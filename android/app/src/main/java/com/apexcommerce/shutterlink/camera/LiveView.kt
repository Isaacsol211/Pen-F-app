package com.apexcommerce.shutterlink.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.os.Process
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.net.InetSocketAddress
import java.net.StandardSocketOptions
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import java.nio.channels.SelectionKey
import java.nio.channels.Selector
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt

// Live view arrives as RTP over UDP (Olympus): after `exec_takemisc.cgi?com=startliveview&port=N`
// the camera streams JPEG frames to port N on the phone that asked. Port of LiveView.swift.
//
//   RTP header (12 bytes): V=2, X=1 on a frame's first packet only, M=1 on its last packet,
//   PT=96, sequence +1 per packet, timestamp = frame number.
//   Extension (first packet only): 2-byte version, 2-byte length in 32-bit words, then fields
//   of [2-byte id][2-byte length in words][data] — AF frame, shutter, F-number, EV, ISO…
//   Payload: JPEG bytes; the first chunk starts FFD8, the last ends FFD9.

private fun u8(b: ByteArray, i: Int) = b[i].toInt() and 0xFF

class RtpFrameAssembler {
    sealed class Output {
        class Frame(val jpeg: ByteArray, val ext: ByteArray?) : Output()
        class InfoOnly(val ext: ByteArray) : Output()
        /** A frame ended but was incomplete (lost packet) or not a JPEG. */
        data object Dropped : Output()
    }

    private val payload = ByteArrayOutputStream(256 * 1024)
    private var ext: ByteArray? = null
    private var lastSeq: Int? = null
    private var broken = false
    private var inFrame = false

    fun push(p: ByteArray, n: Int): Output? {
        if (n < 12 || (u8(p, 0) shr 6) != 2) return null
        val hasPadding = u8(p, 0) and 0x20 != 0
        val hasExtension = u8(p, 0) and 0x10 != 0
        val csrcCount = u8(p, 0) and 0x0F
        val marker = u8(p, 1) and 0x80 != 0
        val seq = (u8(p, 2) shl 8) or u8(p, 3)

        var start = 12 + 4 * csrcCount
        var end = n
        if (hasPadding) end -= u8(p, n - 1)
        if (start > end) return null

        var extData: ByteArray? = null
        if (hasExtension) {
            if (start + 4 > end) return null
            val words = (u8(p, start + 2) shl 8) or u8(p, start + 3)
            val extStart = start + 4
            val extEnd = extStart + 4 * words
            if (extEnd > end) return null
            extData = p.copyOfRange(extStart, extEnd)
            start = extEnd
        }

        if (hasExtension || !inFrame) {
            payload.reset()
            ext = extData
            broken = false
            inFrame = true
        } else if (lastSeq != null && seq != ((lastSeq!! + 1) and 0xFFFF)) {
            broken = true   // lost a packet; drop this frame
        }
        lastSeq = seq

        if (start < end) payload.write(p, start, end - start)
        if (!marker) return null

        inFrame = false
        val bytes = payload.toByteArray()
        if (!broken && bytes.size > 4 && u8(bytes, 0) == 0xFF && u8(bytes, 1) == 0xD8) return Output.Frame(bytes, ext)
        val e = ext
        if (bytes.isEmpty() && e != null) return Output.InfoOnly(e)
        return Output.Dropped
    }
}

object LiveInfoParser {
    fun parse(b: ByteArray, start: LiveInfo): LiveInfo {
        var info = start
        fun u32(o: Int): Long = (u8(b, o).toLong() shl 24) or (u8(b, o + 1).toLong() shl 16) or
            (u8(b, o + 2).toLong() shl 8) or u8(b, o + 3).toLong()
        var i = 0
        while (i + 4 <= b.size) {
            val id = (u8(b, i) shl 8) or u8(b, i + 1)
            val length = ((u8(b, i + 2) shl 8) or u8(b, i + 3)) * 4
            val d = i + 4
            if (d + length > b.size) break
            when {
                id == 2 && length >= 20 -> {   // AF frame: colour, x, y, w, h (signed 16-bit)
                    fun s16(o: Int) = u32(o).toInt().toShort().toDouble()
                    info = info.copy(afState = u32(d).toInt(), afRect = AfRect(s16(d + 4), s16(d + 8), s16(d + 12), s16(d + 16)))
                }
                id == 8 && length >= 24 ->   // shutter (OPC spec): min n/d, max n/d, current n/d as full words
                    info = info.copy(shutter = formatShutter(u32(d + 16), u32(d + 20)))
                id == 8 && length >= 12 -> {   // shutter (PEN-F): min, max, current, each numerator<<16 | denominator
                    val current = u32(d + 8)
                    info = info.copy(shutter = formatShutter(current shr 16, current and 0xFFFF))
                }
                id == 9 && length >= 12 -> {   // F-number ×10: max, min, current
                    val maxF = u32(d) / 10.0
                    val minF = u32(d + 4) / 10.0
                    val v = u32(d + 8)
                    info = info.copy(
                        apertureRange = if (minF > 0 && maxF >= minF) minF..maxF else null,
                        aperture = if (v == 0L) null else if (v >= 100) "F${v / 10}" else fmt("F%.1f", v / 10.0),
                    )
                }
                id == 10 && length >= 12 -> {   // EV ×10, signed: max, min, current
                    val v = u32(d + 8).toInt()
                    info = info.copy(expComp = if (v == 0) "±0.0" else fmt("%+.1f", v / 10.0))
                }
                id == 12 && length >= 8 -> {   // ISO: value, auto flag
                    val v = u32(d)
                    val auto = (u32(d + 4) shr 16) != 0L
                    info = info.copy(iso = "ISO " + (if (v == 0xFFFEL) "LOW" else "$v") + (if (auto) " A" else ""))
                }
                id == 5 && length >= 4 -> info = info.copy(shotsRemaining = u32(d).toInt())
                id == 6 && length >= 4 -> info = info.copy(temperatureWarning = u32(d) != 0L)
                id == 7 && length >= 4 -> {
                    val v = u32(d).toInt()
                    info = info.copy(battery = if (v in 0..100) v else null)
                }
                id == 14 && length >= 4 -> {
                    val v = u32(d)
                    info = info.copy(aspectRatio = if ((v shr 16) > 0 && (v and 0xFFFF) > 0) "${v shr 16}:${v and 0xFFFF}" else null)
                }
                id == 18 && length >= 8 -> {
                    val v = (u32(d + 4) and 0xFFFF).toInt()
                    info = info.copy(focalLength = if (v > 0) v else null)
                }
            }
            i = d + length
        }
        return info
    }

    fun formatShutter(numerator: Long, denominator: Long): String? {
        if (numerator <= 0 || denominator <= 0) return null
        if (numerator >= denominator) {
            val s = numerator.toDouble() / denominator
            return if (s == Math.rint(s)) "${s.toInt()}\"" else fmt("%.1f\"", s)
        }
        val d = denominator.toDouble() / numerator
        return if (d == Math.rint(d)) "1/${d.toInt()}" else fmt("1/%.1f", d)
    }
}

/**
 * A complete JPEG inside a datagram: from the first SOI marker (FF D8 FF) to the last EOI.
 * Used for Panasonic, whose header length varies by model and firmware.
 */
fun jpegInDatagram(p: ByteArray, n: Int): ByteArray? {
    if (n <= 4) return null
    var i = 0
    // LUMIX: a 32-byte header whose last two bytes give the length of a second header.
    if (n > 34) {
        val offset = 32 + ((u8(p, 30) shl 8) or u8(p, 31))
        if (offset + 2 < n && u8(p, offset) == 0xFF && u8(p, offset + 1) == 0xD8) i = offset
    }
    val start = (i until n - 2).firstOrNull { u8(p, it) == 0xFF && u8(p, it + 1) == 0xD8 && u8(p, it + 2) == 0xFF } ?: return null
    val end = (n - 2 downTo start + 1).firstOrNull { u8(p, it) == 0xFF && u8(p, it + 1) == 0xD9 }?.plus(2) ?: n
    return p.copyOfRange(start, end)
}

/**
 * Live-view counters (port of LiveViewStats in LiveView.swift): a detailed line to logcat every couple
 * of seconds, summed into a plain-language line for the Request log. Times are `now()`, in ms.
 */
class LiveViewStats(var since: Long = System.nanoTime() / 1_000_000) {
    var packets = 0
    var completed = 0
    var dropped = 0
    var skippedByUI = 0
    /** Frames passed over because a newer one was already waiting behind them. */
    var stale = 0
    var jpegBytes = 0L
    var frameWidth = 0
    var frameHeight = 0
    var largestDatagram = 0

    fun summary(until: Long = now()): String {
        val seconds = maxOf((until - since) / 1000.0, 0.001)
        val avgKB = if (completed > 0) jpegBytes / completed / 1024 else 0L
        return fmt("LV %.1fs: completed %.1f/s, dropped %.1f/s, skippedByUI %.1f/s, stale %.1f/s, packets %.0f/s, avg %d KB, frame %dx%d, largest datagram %d bytes",
            seconds, completed / seconds, dropped / seconds, skippedByUI / seconds, stale / seconds, packets / seconds,
            avgKB, frameWidth, frameHeight, largestDatagram)
    }

    fun add(other: LiveViewStats) {
        // Time counts from the first frame, not from when the receiver opened.
        if (packets == 0) since = other.since
        packets += other.packets
        completed += other.completed
        dropped += other.dropped
        skippedByUI += other.skippedByUI
        stale += other.stale
        jpegBytes += other.jpegBytes
        largestDatagram = maxOf(largestDatagram, other.largestDatagram)
        if (other.frameWidth != 0) {
            frameWidth = other.frameWidth
            frameHeight = other.frameHeight
        }
    }

    /**
     * For the Request log, e.g. "320×240 · 24.1 frames/s from the camera, 23.9/s shown, 0 unreadable,
     * 0 stale, 9 KB each (last 15 s)".
     */
    fun plainSummary(until: Long): String {
        val seconds = maxOf((until - since) / 1000.0, 0.001)
        fun rate(n: Int) = fmt("%.1f", n / seconds)
        val size = if (frameWidth == 0) "no picture" else "$frameWidth×$frameHeight"
        val kb = if (completed > 0) jpegBytes / completed / 1024 else 0L
        return "$size · ${rate(completed + stale)} frames/s from the camera, ${rate(completed - skippedByUI)}/s shown, " +
            "$dropped unreadable, $stale stale, $kb KB each (last ${Math.round(seconds)} s)"
    }

    companion object {
        /** A clock in ms that doesn't jump when the phone's time is set. */
        fun now(): Long = System.nanoTime() / 1_000_000
    }
}

/**
 * Receives datagrams on a non-blocking channel. Java's DatagramSocket can only wait for the next
 * datagram, not ask whether more are already queued, which the newest-frame skipping below needs.
 */
class DatagramReader(private val channel: DatagramChannel) : Closeable {
    private val selector: Selector = Selector.open()
    /** The datagram the last `receive` returned. */
    var buffer: ByteBuffer = ByteBuffer.allocate(65_536)
        private set
    private var spare: ByteBuffer = ByteBuffer.allocate(65_536)
    /** How many waiting datagrams the last `receive(newest = true)` passed over. */
    var skipped = 0
        private set

    init {
        try {
            channel.configureBlocking(false)
            channel.register(selector, SelectionKey.OP_READ)
        } catch (e: Exception) {
            runCatching { selector.close() }
            throw e
        }
    }

    /**
     * Waits up to `timeoutMs` for a datagram and returns its length (0 when none came); the bytes are
     * in `buffer`. With `newest`, it then reads every datagram already waiting and keeps only the last.
     */
    fun receive(timeoutMs: Long, newest: Boolean): Int {
        skipped = 0
        var count = take(buffer)
        if (count < 0) {
            selector.select(timeoutMs)
            selector.selectedKeys().clear()
            count = take(buffer)
            if (count < 0) return 0
        }
        if (newest && count > 0) {
            while (true) {
                val next = take(spare)
                if (next <= 0) break
                val older = buffer
                buffer = spare
                spare = older
                count = next
                skipped++
            }
        }
        return count
    }

    /** Ends a `receive` that is waiting. */
    fun wakeup() {
        runCatching { selector.wakeup() }
    }

    /** One waiting datagram into `into`: its length, or -1 when none is waiting. */
    private fun take(into: ByteBuffer): Int {
        into.clear()
        return if (channel.receive(into) == null) -1 else into.position()
    }

    override fun close() {
        runCatching { selector.close() }
        runCatching { channel.close() }
    }
}

/**
 * Listens on a UDP port for the whole connection and hands decoded frames to the main thread.
 * Frames that arrive while the UI is still busy with the previous one are dropped, and a LUMIX
 * frame is skipped when a newer one is already waiting, so live view never runs late.
 */
class LiveViewReceiver(val port: Int, val format: LiveViewFormat) {
    /** Called on the main thread: frame (null for metadata only), new metadata, histogram, sharpness. */
    var onFrame: ((Bitmap?, LiveInfo?, FloatArray?, Double?) -> Unit)? = null
    /** Focus-peaking overlays (null clears), on the main thread. */
    var onPeaking: ((Bitmap?) -> Unit)? = null
    /**
     * A plain-language summary while frames are arriving (after 5 s, then every 15 s), on the main
     * thread, so a copied Request log shows how live view ran.
     */
    var onSummary: ((String) -> Unit)? = null

    @Volatile private var running = false
    @Volatile var peakingOn = false
    /** Normalised area to measure sharpness in (the loupe's view), or null when the loupe is closed. */
    @Volatile var meterRegion: RectF? = null

    private var reader: DatagramReader? = null
    private val deliveryPending = AtomicBoolean(false)
    private var info = LiveInfo()
    private var framesSinceHistogram = 0
    private val main = Handler(Looper.getMainLooper())
    /** Pushed frames are decoded one at a time here, like the UDP thread does for its own. */
    private val pushQueue = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "Shutterlink live view (pushed)") }
    private val peaker = FocusPeaker()

    // The counters belong to the thread that receives: the UDP thread, or pushQueue for pushed formats.
    private var stats = LiveViewStats()
    private var logWindow = LiveViewStats()
    private var logWindowEnd = LiveViewStats.now()
    private var summariesSent = 0

    fun start() {
        if (format == LiveViewFormat.PUSHED) {
            running = true
            // The UDP thread checks the counters on every pass; pushed frames need a clock of their own
            // so a pause in frames closes the window instead of stretching it.
            pushQueue.scheduleWithFixedDelay({ if (running) reportStats() }, 1, 1, TimeUnit.SECONDS)
            return
        }
        val channel = DatagramChannel.open()
        val r = try {
            channel.setOption(StandardSocketOptions.SO_REUSEADDR, true)
            channel.setOption(StandardSocketOptions.SO_RCVBUF, 2 * 1024 * 1024)
            channel.bind(InetSocketAddress(port))
            DatagramReader(channel)
        } catch (e: Exception) {
            runCatching { channel.close() }
            throw CameraException("Couldn't listen on UDP port $port (${e.message}).")
        }
        reader = r
        running = true
        Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_DISPLAY)
            run(r)
        }, "Shutterlink live view").start()
    }

    fun stop() {
        running = false
        reader?.wakeup()
        pushQueue.shutdownNow()
        peaker.shutdown()
    }

    /** A complete JPEG fetched by the driver (pushed formats). Dropped if the UI is still busy. */
    fun submit(jpeg: ByteArray) {
        if (!running) return
        // Some cameras put a header before the JPEG: start at the first FF D8.
        val start = (0 until jpeg.size - 1).firstOrNull { u8(jpeg, it) == 0xFF && u8(jpeg, it + 1) == 0xD8 } ?: return
        val frame = if (start == 0) jpeg else jpeg.copyOfRange(start, jpeg.size)
        try {
            pushQueue.execute {
                stats.packets++
                stats.completed++
                stats.jpegBytes += frame.size
                deliver(frame, null)
            }
        } catch (ignored: Exception) {
            // shut down
        }
    }

    /** Every 2 s: the detailed line to logcat, and the totals towards the Request log line. */
    private fun reportStats() {
        val now = LiveViewStats.now()
        if (now - stats.since < 2000) return
        val idle = stats.packets == 0
        if (!idle) {
            debugLog(stats.summary(now))
            logWindow.add(stats)
            logWindowEnd = now
        }
        stats = LiveViewStats(now)
        if (logWindow.packets == 0) {
            logWindow = LiveViewStats(now)
        } else if (idle || now - logWindow.since >= (if (summariesSent == 0) 5000 else 15000)) {
            // Also when frames stop (live view paused, gallery open), so the rates only cover streaming.
            // A frame or two on their own (a single preview fetch) isn't live view: no line for those.
            val window = logWindow
            logWindow = LiveViewStats(now)
            if (window.completed + window.stale < 5) return
            val line = window.plainSummary(logWindowEnd)
            debugLog("LIVE $line")
            summariesSent++
            main.post { onSummary?.invoke(line) }
        }
    }

    private fun run(r: DatagramReader) {
        val assembler = RtpFrameAssembler()
        // One JPEG per datagram (LUMIX): if more are already waiting, this one is old news.
        val newest = format == LiveViewFormat.JPEG_PER_DATAGRAM
        try {
            while (running) {
                val count = try {
                    r.receive(300, newest)
                } catch (e: Exception) {
                    if (running) debugLog("live view socket: $e")
                    break
                }
                val buffer = r.buffer.array()
                if (count > stats.largestDatagram) stats.largestDatagram = count
                if (count > 0 && newest) {
                    // Show the newest so the picture never falls behind the camera (slow bodies like the
                    // GM1, the first seconds after connecting, busy moments); the rest count as stale.
                    stats.packets += 1 + r.skipped
                    stats.stale += r.skipped
                    val jpeg = jpegInDatagram(buffer, count)
                    if (jpeg != null) {
                        stats.completed++
                        stats.jpegBytes += jpeg.size
                        deliver(jpeg, null)
                    } else {
                        stats.dropped++
                    }
                } else if (count > 0) {
                    stats.packets++
                    when (val out = assembler.push(buffer, count)) {
                        is RtpFrameAssembler.Output.Frame -> {
                            stats.completed++
                            stats.jpegBytes += out.jpeg.size
                            deliver(out.jpeg, out.ext)
                        }
                        is RtpFrameAssembler.Output.InfoOnly -> deliver(null, out.ext)
                        RtpFrameAssembler.Output.Dropped -> stats.dropped++
                        null -> {}
                    }
                }
                reportStats()
            }
        } finally {
            r.close()
        }
    }

    private fun deliver(jpeg: ByteArray?, ext: ByteArray?) {
        if (!deliveryPending.compareAndSet(false, true)) {
            stats.skippedByUI++
            return
        }
        var newInfo: LiveInfo? = null
        if (ext != null) {
            info = LiveInfoParser.parse(ext, info)
            newInfo = info
        }
        val image = jpeg?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size) }.getOrNull() }
        image?.prepareToDraw()
        if (image != null) {
            stats.frameWidth = image.width
            stats.frameHeight = image.height
        }

        var histogram: FloatArray? = null
        framesSinceHistogram++
        if (image != null && framesSinceHistogram >= 5) {
            framesSinceHistogram = 0
            histogram = histogram(image)
        }
        val region = meterRegion
        val sharpness = if (image != null && region != null) sharpness(image, region) else null

        if (peakingOn && image != null) {
            peaker.submit(image) { overlay -> main.post { if (peakingOn) onPeaking?.invoke(overlay) } }
        }

        main.post {
            deliveryPending.set(false)
            onFrame?.invoke(image, newInfo, histogram, sharpness)
        }
    }

    companion object {
        /** 64-bin luminance histogram from a small copy of the frame, normalised to 0…1. */
        fun histogram(image: Bitmap, bins: Int = 64): FloatArray {
            val w = 80
            val h = 60
            val small = Bitmap.createScaledBitmap(image, w, h, false)
            val pixels = IntArray(w * h)
            small.getPixels(pixels, 0, w, 0, 0, w, h)
            if (small !== image) small.recycle()
            val counts = FloatArray(bins)
            for (p in pixels) {
                val y = (Color.red(p) * 299 + Color.green(p) * 587 + Color.blue(p) * 114) / 1000
                counts[y.coerceIn(0, 255) * bins / 256] += 1f
            }
            val peak = maxOf(counts.maxOrNull() ?: 1f, 1f)
            for (i in counts.indices) counts[i] /= peak
            return counts
        }

        /** Focus measure: mean squared brightness gradient inside the region; peaks at best focus. */
        fun sharpness(image: Bitmap, region: RectF): Double? {
            val w = image.width
            val h = image.height
            val left = (region.left * w).roundToInt().coerceIn(0, w)
            val top = (region.top * h).roundToInt().coerceIn(0, h)
            val right = (region.right * w).roundToInt().coerceIn(0, w)
            val bottom = (region.bottom * h).roundToInt().coerceIn(0, h)
            if (right - left < 8 || bottom - top < 8) return null
            val crop = Bitmap.createBitmap(image, left, top, right - left, bottom - top)
            val width = minOf(crop.width, 200)
            val height = minOf(crop.height, 150)
            val small = Bitmap.createScaledBitmap(crop, width, height, true)
            val px = IntArray(width * height)
            small.getPixels(px, 0, width, 0, 0, width, height)
            val lum = IntArray(px.size) { (Color.red(px[it]) * 299 + Color.green(px[it]) * 587 + Color.blue(px[it]) * 114) / 1000 }
            var sum = 0.0
            for (y in 0 until height - 1) {
                val row = y * width
                for (x in 0 until width - 1) {
                    val p = lum[row + x].toDouble()
                    val dx = lum[row + x + 1] - p
                    val dy = lum[row + width + x] - p
                    sum += dx * dx + dy * dy
                }
            }
            return sum / ((width - 1) * (height - 1))
        }
    }
}

/**
 * Focus peaking: outlines sharp edges in red. Runs on its own thread at up to 12 fps and skips
 * frames while busy, so live view keeps its frame rate (port of FocusPeaking.swift's idea).
 */
class FocusPeaker {
    private val queue = Executors.newSingleThreadExecutor { r -> Thread(r, "Shutterlink peaking") }
    private val busy = AtomicBoolean(false)
    @Volatile private var lastRun = 0L

    fun submit(image: Bitmap, done: (Bitmap?) -> Unit) {
        val now = System.currentTimeMillis()
        if (now - lastRun < 80 || !busy.compareAndSet(false, true)) return
        lastRun = now
        try {
            queue.execute {
                try {
                    done(overlay(image))
                } finally {
                    busy.set(false)
                }
            }
        } catch (ignored: Exception) {
            busy.set(false)
        }
    }

    fun shutdown() = queue.shutdownNow()

    private fun overlay(image: Bitmap): Bitmap? {
        val w = 320
        val h = (image.height * w / image.width.toFloat()).roundToInt().coerceAtLeast(2)
        val small = Bitmap.createScaledBitmap(image, w, h, true)
        val px = IntArray(w * h)
        small.getPixels(px, 0, w, 0, 0, w, h)
        val lum = IntArray(px.size) { (Color.red(px[it]) * 299 + Color.green(px[it]) * 587 + Color.blue(px[it]) * 114) / 1000 }
        val out = IntArray(px.size)
        val red = Color.argb(255, 255, 40, 40)
        // Sobel magnitude over a fixed threshold, plus a relative one so dark scenes still show edges.
        var maxMag = 1
        val mags = IntArray(px.size)
        for (y in 1 until h - 1) for (x in 1 until w - 1) {
            val i = y * w + x
            val gx = -lum[i - w - 1] - 2 * lum[i - 1] - lum[i + w - 1] + lum[i - w + 1] + 2 * lum[i + 1] + lum[i + w + 1]
            val gy = -lum[i - w - 1] - 2 * lum[i - w] - lum[i - w + 1] + lum[i + w - 1] + 2 * lum[i + w] + lum[i + w + 1]
            val m = kotlin.math.abs(gx) + kotlin.math.abs(gy)
            mags[i] = m
            if (m > maxMag) maxMag = m
        }
        val threshold = maxOf(180, (maxMag * 0.45).toInt())
        for (i in mags.indices) if (mags[i] >= threshold) out[i] = red
        return Bitmap.createBitmap(out, w, h, Bitmap.Config.ARGB_8888)
    }
}

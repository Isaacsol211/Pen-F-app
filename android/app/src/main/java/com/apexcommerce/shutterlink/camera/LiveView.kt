package com.apexcommerce.shutterlink.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.os.Process
import java.io.ByteArrayOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.util.concurrent.Executors
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
                id == 4 && length >= 4 -> info = info.copy(rotation = u8(b, d + 3))
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
    while (i + 2 < n) {
        if (u8(p, i) == 0xFF && u8(p, i + 1) == 0xD8 && u8(p, i + 2) == 0xFF) break
        i++
    }
    if (i + 2 >= n) return null
    var end = n
    var j = n - 2
    while (j > i) {
        if (u8(p, j) == 0xFF && u8(p, j + 1) == 0xD9) {
            end = j + 2
            break
        }
        j--
    }
    return p.copyOfRange(i, end)
}

/**
 * Listens on a UDP port for the whole connection and hands decoded frames to the main thread.
 * Frames that arrive while the UI is still busy with the previous one are dropped.
 */
class LiveViewReceiver(val port: Int, val format: LiveViewFormat) {
    /** Called on the main thread: frame (null for metadata only), new metadata, histogram, sharpness. */
    var onFrame: ((Bitmap?, LiveInfo?, FloatArray?, Double?) -> Unit)? = null
    /** Focus-peaking overlays (null clears), on the main thread. */
    var onPeaking: ((Bitmap?) -> Unit)? = null

    @Volatile private var running = false
    @Volatile var peakingOn = false
    /** Normalised area to measure sharpness in (the loupe's view), or null when the loupe is closed. */
    @Volatile var meterRegion: RectF? = null

    private var socket: DatagramSocket? = null
    private val deliveryPending = AtomicBoolean(false)
    private var info = LiveInfo()
    private var framesSinceHistogram = 0
    private val main = Handler(Looper.getMainLooper())
    private val pushQueue = Executors.newSingleThreadExecutor { r -> Thread(r, "Shutterlink live view (pushed)") }
    private val peaker = FocusPeaker()

    private var statsSince = System.currentTimeMillis()
    private var statsPackets = 0
    private var statsCompleted = 0
    private var statsDropped = 0
    private var statsSkipped = 0
    private var statsMaxBytes = 0

    fun start() {
        if (format == LiveViewFormat.PUSHED) {
            running = true
            return
        }
        val s = DatagramSocket(null)
        try {
            s.reuseAddress = true
            s.receiveBufferSize = 2 * 1024 * 1024
            s.soTimeout = 300
            s.bind(InetSocketAddress(port))
        } catch (e: Exception) {
            s.close()
            throw CameraException("Couldn't listen on UDP port $port (${e.message}).")
        }
        socket = s
        running = true
        Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_DISPLAY)
            run(s)
        }, "Shutterlink live view").start()
    }

    fun stop() {
        running = false
        pushQueue.shutdownNow()
        peaker.shutdown()
    }

    /** A complete JPEG fetched by the driver (pushed formats). Dropped if the UI is still busy. */
    fun submit(jpeg: ByteArray) {
        if (!running) return
        // Some cameras put a header before the JPEG: start at the first FF D8.
        var start = -1
        var k = 0
        while (k < jpeg.size - 1) {
            if (u8(jpeg, k) == 0xFF && u8(jpeg, k + 1) == 0xD8) {
                start = k
                break
            }
            k++
        }
        if (start < 0) return
        val frame = if (start == 0) jpeg else jpeg.copyOfRange(start, jpeg.size)
        try {
            pushQueue.execute {
                statsPackets++
                statsCompleted++
                deliver(frame, null)
            }
        } catch (ignored: Exception) {
            // shut down
        }
    }

    private fun run(s: DatagramSocket) {
        val buffer = ByteArray(65_536)
        val packet = DatagramPacket(buffer, buffer.size)
        val assembler = RtpFrameAssembler()
        while (running) {
            val count = try {
                packet.length = buffer.size
                s.receive(packet)
                packet.length
            } catch (ignored: SocketTimeoutException) {
                0
            } catch (e: Exception) {
                if (running) debugLog("live view socket: $e")
                break
            }
            if (count > statsMaxBytes) statsMaxBytes = count
            if (count > 0 && format == LiveViewFormat.JPEG_PER_DATAGRAM) {
                statsPackets++
                val jpeg = jpegInDatagram(buffer, count)
                if (jpeg != null) {
                    statsCompleted++
                    deliver(jpeg, null)
                } else {
                    statsDropped++
                }
            } else if (count > 0) {
                statsPackets++
                when (val out = assembler.push(buffer, count)) {
                    is RtpFrameAssembler.Output.Frame -> {
                        statsCompleted++
                        deliver(out.jpeg, out.ext)
                    }
                    is RtpFrameAssembler.Output.InfoOnly -> deliver(null, out.ext)
                    RtpFrameAssembler.Output.Dropped -> statsDropped++
                    null -> {}
                }
            }
            val now = System.currentTimeMillis()
            if (now - statsSince >= 2000) {
                if (statsPackets > 0) {
                    val secs = (now - statsSince) / 1000.0
                    debugLog(fmt("LV %.1fs: completed %.1f/s, dropped %.1f/s, skippedByUI %.1f/s, packets %.0f/s, largest datagram %d bytes",
                        secs, statsCompleted / secs, statsDropped / secs, statsSkipped / secs, statsPackets / secs, statsMaxBytes))
                }
                statsSince = now
                statsPackets = 0; statsCompleted = 0; statsDropped = 0; statsSkipped = 0; statsMaxBytes = 0
            }
        }
        s.close()
    }

    private fun deliver(jpeg: ByteArray?, ext: ByteArray?) {
        if (!deliveryPending.compareAndSet(false, true)) {
            statsSkipped++
            return
        }
        var newInfo: LiveInfo? = null
        if (ext != null) {
            info = LiveInfoParser.parse(ext, info)
            newInfo = info
        }
        val image = jpeg?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size) }.getOrNull() }
        image?.prepareToDraw()

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

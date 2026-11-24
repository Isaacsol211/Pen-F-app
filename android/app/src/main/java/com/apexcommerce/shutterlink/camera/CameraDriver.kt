package com.apexcommerce.shutterlink.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import kotlin.math.abs
import kotlin.math.roundToInt

/** What a connected camera can do from the app. The UI hides anything that is false. */
data class CameraCapabilities(
    /** Live-view sizes the user can choose between ("0640x0480"); empty hides the picker. */
    val liveViewSizes: List<String> = emptyList(),
    /** Tap on live view moves the AF point / focuses there. */
    val tapToFocus: Boolean = true,
    /** Movie recording from the shutter button. */
    val movie: Boolean = false,
    /** The camera's photo/video mode can't be read, so the app shows its own Video switch. */
    val videoSwitch: Boolean = false,
    /** A preview of the last shot is fetched after each capture. */
    val lastShotReview: Boolean = false,
    /** The camera's clock can be set from the phone. */
    val clockSync: Boolean = false,
    /** Olympus High Res Shot guide. */
    val highResShot: Boolean = false,
    /** The card can be browsed and photos saved. */
    val cardBrowser: Boolean = true,
    /** The camera can be switched off from the app. */
    val powerOff: Boolean = false,
    /** The lens can be stepped nearer or farther from the app, for focus stacking. */
    val focusDrive: Boolean = false,
)

/** How live-view frames reach the phone. */
enum class LiveViewFormat {
    /** Olympus: RTP, one JPEG split over several packets, metadata in an RTP extension. */
    OLYMPUS_RTP,
    /** Panasonic: one complete JPEG per datagram after a camera-specific header. */
    JPEG_PER_DATAGRAM,
    /** Nikon, Canon, Sony: the driver fetches frames itself and hands them to `submit(jpeg)`. */
    PUSHED,
}

/**
 * One camera brand's protocol (port of CameraDriver.swift). The model owns all state the UI shows;
 * a driver reads and writes it through `camera`, and only talks to the camera in its own way.
 * Every method is called on the main thread; drivers move network work to Dispatchers.IO.
 *
 * Settings use the app's common property names and spellings (the Olympus ones):
 *   focalvalue "5.6" · shutspeedvalue "250" (1/250 s), "2.5\"" (2.5 s), "bulb" ·
 *   isospeedvalue "auto", "400" · expcomp "+0.3", "0.0" · wbvalue "0" (auto), "18" (daylight)… ·
 *   takemode "P", "A", "S", "M", "iAuto", "movie".
 */
interface CameraDriver {
    val capabilities: CameraCapabilities
    val liveViewFormat: LiveViewFormat

    /** Says hello, pairs if needed, reads the camera's name and what it supports. */
    suspend fun connect()
    /** Polite goodbye before the connection is dropped (best effort). */
    suspend fun disconnect() {}
    /** Stops background work and closes sockets; called once the model forgets the camera. */
    fun teardown() {}
    suspend fun powerOff() {}

    /** Shooting mode with live view; also called after browsing the card. */
    suspend fun enterRecMode()
    suspend fun startLiveView()
    suspend fun stopLiveView()

    suspend fun refreshProperties()
    /** Returns false (and reports why, when asked) if the camera refused the value. */
    suspend fun setProperty(name: String, value: String, reportErrors: Boolean): Boolean

    /** `x`, `y` are 0…1 over the live-view frame. */
    suspend fun focus(x: Double, y: Double)
    suspend fun releaseFocus() {}
    suspend fun shutterPressed()
    suspend fun shutterReleased() {}
    /** Bulb / Live modes: the first call opens the shutter, the second closes it. */
    suspend fun toggleOpenExposure() {}
    suspend fun toggleMovie() {}
    suspend fun fetchLastShot() {}
    suspend fun syncClock(): Boolean = false
    /** Steps manual focus nearer or farther (focus stacking). Only called when `capabilities.focusDrive`. */
    suspend fun driveFocus(farther: Boolean, step: FocusStepSize): FocusDriveResult =
        throw CameraException("This camera can't move its focus over Wi-Fi.")

    /** Fills `camera.images` and `camera.cardFolders`. */
    suspend fun openGallery()
    suspend fun thumbnail(image: CameraImage): Bitmap?
    suspend fun preview(image: CameraImage): Bitmap
    suspend fun downloadOriginal(image: CameraImage): ByteArray
}

/** Shared helpers for drivers that map a camera's own values onto the app's spellings. */
object ExposureText {
    /** 1/250 s → "250", 2.5 s → "2.5\"", 1/2.5 s → "2.5", 1 s → "1\"". */
    fun shutter(seconds: Double): String {
        if (seconds <= 0) return ""
        if (seconds >= 1 - 0.001) return clean(seconds) + "\""
        return clean(1 / seconds)
    }

    /** 125.0 → "125", 2.5 → "2.5", 1.333 → "1.3". */
    fun clean(value: Double): String {
        if (value >= 10 || abs(value - Math.rint(value)) < 0.05) return value.roundToInt().toString()
        return fmt("%.1f", value)
    }

    /** f/5.6 → "5.6", f/11 → "11". */
    fun aperture(f: Double): String = if (f >= 10) fmt("%.0f", f) else fmt("%.1f", f)

    /** Thirds of a stop → "+0.3", "-1.0", "0.0". */
    fun ev(thirds: Int): String = if (thirds == 0) "0.0" else fmt("%+.1f", thirds / 3.0)

    /** EV as a number → nearest third ("+0.7" from 0.6667). */
    fun ev(value: Double): String = ev(Math.rint(value * 3).toInt())

    /** Panasonic-style white-balance names → the app's codes (which have labels and icons). */
    val whiteBalanceCodes: Map<String, String> = mapOf(
        "auto" to "0", "daylight" to "18", "sunny" to "18", "shade" to "16", "cloudy" to "17",
        "incandescent" to "20", "tungsten" to "20", "halogen" to "20", "fluorescent" to "35",
        "underwater" to "64", "flash" to "23", "custom" to "256", "preset" to "256",
        "color_temp" to "512", "kelvin" to "512",
    )
}

/** `String.format` with a fixed locale: camera values always use a dot. */
fun fmt(format: String, vararg args: Any?): String = String.format(java.util.Locale.US, format, *args)

// MARK: - Shared by the drivers

const val LOST_CONTACT = "Lost contact with the camera. Check that this phone is still on the camera's Wi-Fi."

/** Runs `block`, giving null instead of an error (cancellation still cancels): for best-effort calls. */
internal inline fun <T> attempt(block: () -> T): T? = try {
    block()
} catch (e: CancellationException) {
    throw e
} catch (e: Throwable) {
    null
}

/** Decodes a photo off the main thread, or null; `maxSide` > 0 subsamples it to about that size. */
suspend fun decodeImage(bytes: ByteArray, maxSide: Int = 0): Bitmap? = withContext(Dispatchers.Default) {
    runCatching {
        if (maxSide <= 0) return@runCatching BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }.getOrNull()
}

/**
 * The first request to a camera, which can be slow right after its Wi-Fi comes up: up to 3 tries while
 * `retry` says the failure is worth another (by default network failures, not answers from the camera).
 */
suspend fun <T> CameraModel.retryConnect(
    retry: (Exception) -> Boolean = { it is IOException && it !is CameraHttpException },
    block: suspend () -> T,
): T {
    for (next in 2..3) {
        try {
            return block()
        } catch (e: Exception) {
            if (e is CancellationException || !retry(e)) throw e
            status = "No answer yet, retrying ($next/3)…"
            delay(1500)
        }
    }
    return block()
}

/** Shows a mode switch in progress while `block` runs. */
inline fun CameraModel.switchingMode(block: () -> Unit) {
    isSwitchingMode = true
    try {
        block()
    } finally {
        isSwitchingMode = false
    }
}

/** Shows `value` at once and sends it, putting the old one back if that fails; then re-reads the settings. */
suspend fun CameraDriver.applySetting(
    camera: CameraModel, name: String, value: String, reportErrors: Boolean, send: suspend () -> Unit,
): Boolean {
    val previous = camera.properties[name]?.value
    camera.updateValue(name, value)
    val ok = try {
        send()
        true
    } catch (e: Exception) {
        if (previous != null) camera.updateValue(name, previous)
        if (reportErrors) camera.report(e)
        false
    }
    // Changing one setting can lock/unlock others (e.g. aperture in P vs A).
    refreshProperties()
    return ok
}

/** Before a shot: the shutter time in seconds (0 when unknown); 1 s and longer get a countdown. */
fun CameraModel.startTimedExposure(): Double {
    val seconds = PropertyFormat.seconds(properties["shutspeedvalue"]?.value ?: "") ?: 0.0
    if (seconds >= 1) {
        exposureStartedAt = System.currentTimeMillis()
        exposureDuration = seconds
    }
    return seconds
}

/** Bulb-style exposures: `stop` (failures ignored) while one runs, else `start`. */
suspend fun CameraModel.toggleBulb(start: suspend () -> Unit, stop: suspend () -> Unit, afterStop: () -> Unit = {}) {
    if (isShooting) {
        runCatching { stop() }
        isShooting = false
        exposureStartedAt = null
        shotCounter++
        afterStop()
        return
    }
    isShooting = true
    exposureStartedAt = System.currentTimeMillis()
    exposureDuration = null
    try {
        start()
    } catch (e: Exception) {
        isShooting = false
        exposureStartedAt = null
        report(e)
    }
}

/** The movie button: `stop` (failures ignored) while recording, else `start`; `failed` runs before reporting. */
suspend fun CameraModel.recordMovie(
    start: suspend () -> Unit, stop: suspend () -> Unit,
    afterStop: suspend () -> Unit = {}, failed: suspend () -> Unit = {},
) {
    if (isRecordingMovie) {
        runCatching { stop() }
        isRecordingMovie = false
        movieStartedAt = null
        shotCounter++
        afterStop()
        return
    }
    try {
        start()
        isRecordingMovie = true
        movieStartedAt = System.currentTimeMillis()
    } catch (e: Exception) {
        failed()
        report(e)
    }
}

/** Asks the camera what changed every 2 s while connected; three failures in a row mean contact is lost. */
fun <T> CameraModel.pollEvents(skip: () -> Boolean = { false }, fetch: suspend () -> T, handle: suspend (T) -> Unit): Job =
    scope.launch {
        var failures = 0
        while (isActive) {
            delay(2000)
            if (phase != ConnectionPhase.CONNECTED || skip()) continue
            try {
                val changes = fetch()
                failures = 0
                handle(changes)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (++failures == 3) lastError = LOST_CONTACT
            }
        }
    }

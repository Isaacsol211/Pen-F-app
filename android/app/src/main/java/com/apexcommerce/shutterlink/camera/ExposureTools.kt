package com.apexcommerce.shutterlink.camera

import android.graphics.Bitmap
import android.graphics.Color
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt

// Exposure tools (port of ExposureTools.swift): frame metering, the ND filter calculator,
// day-to-night ramping, the motion trigger and expose to the right.

// MARK: - Frame measurements

object FrameMeter {
    /** sRGB code value → linear light, so averages and ratios are in stops. */
    private val linear = DoubleArray(256) { (it / 255.0).pow(2.2) }

    /** The frame (or a normalised region of it) as a small greyscale buffer, 0…255 per cell. */
    fun grey(image: Bitmap, region: NRect? = null, width: Int, height: Int): IntArray? = runCatching {
        var source = image
        if (region != null) {
            val w = image.width
            val h = image.height
            val left = (region.x * w).roundToInt().coerceIn(0, w)
            val top = (region.y * h).roundToInt().coerceIn(0, h)
            val right = ((region.x + region.w) * w).roundToInt().coerceIn(0, w)
            val bottom = ((region.y + region.h) * h).roundToInt().coerceIn(0, h)
            if (right - left < 2 || bottom - top < 2) return null
            source = Bitmap.createBitmap(image, left, top, right - left, bottom - top)
        }
        val small = Bitmap.createScaledBitmap(source, width, height, true)
        val px = IntArray(width * height)
        small.getPixels(px, 0, width, 0, 0, width, height)
        IntArray(px.size) { (Color.red(px[it]) * 299 + Color.green(px[it]) * 587 + Color.blue(px[it]) * 114) / 1000 }
    }.getOrNull()

    /** Mean linear brightness, 0…1. */
    fun brightness(image: Bitmap): Double? {
        val pixels = grey(image, width = 32, height = 24) ?: return null
        return pixels.sumOf { linear[it.coerceIn(0, 255)] } / pixels.size
    }

    /** Share of pixels at the very top of the range (blown highlights in the JPEG), 0…1. */
    fun clipped(image: Bitmap): Double? {
        val pixels = grey(image, width = 80, height = 60) ?: return null
        return pixels.count { it >= 250 }.toDouble() / pixels.size
    }
}

/** Seconds for a shutter as shown or as the camera lists it: `1/250`, `2"`, `2.5"`, `250`, `60"`. */
fun secondsFromDisplay(text: String): Double? {
    val t = text.trim()
    if (t.startsWith("1/")) t.drop(2).toDoubleOrNull()?.takeIf { it > 0 }?.let { return 1 / it }
    return PropertyFormat.seconds(t)
}

private fun log2(x: Double) = ln(x) / ln(2.0)

/** The latest live-view frame, if one arrived in the last few seconds. */
val CameraModel.recentFrame: Bitmap?
    get() {
        val at = lastFrameAt ?: return null
        return if (System.currentTimeMillis() - at < 3000) latestBitmap else null
    }

/** One step brighter or darker for `name`: the next EV option, shutter speed or ISO. */
fun CameraModel.adjacentValue(name: String, brighter: Boolean): String? {
    val property = properties[name] ?: return null
    return when (name) {
        "expcomp" -> {
            val values = property.options.mapNotNull { o -> o.toDoubleOrNull()?.let { o to it } }.sortedBy { it.second }
            val current = property.value.toDoubleOrNull() ?: return null
            if (brighter) values.firstOrNull { it.second > current + 0.01 }?.first else values.lastOrNull { it.second < current - 0.01 }?.first
        }
        "shutspeedvalue" -> {
            val values = timedShutters.sortedBy { it.second }
            val current = PropertyFormat.seconds(property.value) ?: return null
            if (brighter) values.firstOrNull { it.second > current * 1.1 }?.first else values.lastOrNull { it.second < current / 1.1 }?.first
        }
        "isospeedvalue" -> {
            val values = property.options.mapNotNull { o -> o.toIntOrNull()?.let { o to it } }.sortedBy { it.second }
            val current = property.value.toIntOrNull() ?: return null
            if (brighter) values.firstOrNull { it.second > current }?.first else values.lastOrNull { it.second < current }?.first
        }
        else -> null
    }
}

// MARK: - ND filter calculator

/** What the camera meters now: what it chose in an auto mode (from live view where reported), or what is set. */
val CameraModel.meteredExposure: NDMeter?
    get() {
        val shown = liveInfo.shutter ?: properties["shutspeedvalue"]?.let { PropertyFormat.display("shutspeedvalue", it.value) }
        val seconds = shown?.let(::secondsFromDisplay) ?: return null
        val apertureNumber = liveInfo.aperture?.filter { it.isDigit() || it == '.' }?.toDoubleOrNull()
        val apertureValue = apertureNumber?.let { aperture(it) } ?: properties["focalvalue"]?.value
        val liveIso = liveInfo.iso?.filter { it.isDigit() }?.toIntOrNull()
        val setIso = properties["isospeedvalue"]?.value?.toIntOrNull()
        val iso = (setIso ?: liveIso)?.let { nearestIso(it) }
        return NDMeter(seconds, apertureValue, iso)
    }

fun ndSeconds(metered: Double, stops: Int): Double = metered * 2.0.pow(stops)

/** Bulb, or the Live mode that works like it, for exposures longer than the camera's timed ones. */
val CameraModel.bulbShutter: String?
    get() {
        val options = properties["shutspeedvalue"]?.options ?: return null
        return listOf("bulb", "livetime", "livebulb").firstNotNullOfOrNull { wanted -> options.firstOrNull { it.lowercase() == wanted } }
    }

/** The shutter the ND exposure needs: a timed speed when the camera has one long enough, else Bulb. */
fun CameraModel.ndShutter(seconds: Double): Pair<String?, Boolean> {
    val longest = timedShutters.maxOfOrNull { it.second } ?: 0.0
    if (seconds <= longest * 1.12) return shutter(seconds) to false
    bulbShutter?.let { return it to true }
    return timedShutters.maxByOrNull { it.second }?.first to false
}

fun CameraModel.ndSteps(meter: NDMeter, stops: Int): List<PresetStep> {
    val target = ndSeconds(meter.seconds, stops)
    val (mode, inM) = modeStep("M", "Keeps the exposure you metered")
    val (shutterValue, timed) = ndShutter(target)
    val shutterDetail = if (timed) "Bulb, stopped by the app after ${CameraModel.durationLabel(target)}"
    else "${CameraModel.durationLabel(target)} through a $stops-stop filter"
    return listOf(
        mode,
        presetStep("Aperture as metered", "Keeps the depth of field you metered at", "focalvalue", meter.aperture, "M", inM),
        presetStep("Shutter", shutterDetail, "shutspeedvalue", shutterValue, "M", inM),
        presetStep("ISO as metered", "Fixed, so the exposure doesn't drift", "isospeedvalue", meter.iso,
            unavailable = "Set a fixed ISO (not Auto) on the camera and meter again"),
        antiShockStep(),
    )
}

/** Shoots the long exposure: a timed shutter as usual, or Bulb stopped by the app. */
suspend fun CameraModel.shootNd(seconds: Double) {
    if (isOpenEndedShutter) {
        toggleOpenExposure()
        if (isShooting) scheduleOpenExposureStop(seconds)
    } else {
        shutterPressed()
        shutterReleased()
    }
}

/** "1/250", "2.5 s", "4 min 10 s". */
fun shutterLabel(seconds: Double): String {
    if (seconds < 0.75) return "1/${(1 / seconds).roundToInt()}"
    if (seconds < 10) return if (seconds == Math.rint(seconds)) fmt("%.0f s", seconds) else fmt("%.1f s", seconds)
    val total = seconds.roundToInt()
    if (total < 60) return "$total s"
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    if (h > 0) return "$h h $m min"
    return if (s == 0) "$m min" else "$m min $s s"
}

// MARK: - Day-to-night ramping

/**
 * Nudges the exposure a third of a stop towards the brightness live view had when the interval
 * started: a longer shutter first (up to what the interval leaves room for), then a higher ISO, and
 * back the other way as it gets lighter. Returns what changed, for the progress card.
 */
suspend fun CameraModel.rampExposure(target: Double, plan: IntervalPlan, baseIso: Int?): String? {
    val frame = recentFrame ?: return null
    val now = FrameMeter.brightness(frame) ?: return null
    if (now <= 0.0002 || target <= 0.0002) return null
    val stops = log2(target / now)          // > 0: darker than at the start
    if (abs(stops) < 0.33) return null
    val longest = maxOf(0.5, plan.seconds - 1.5)
    if (stops > 0) {
        if (settableProperty("shutspeedvalue") != null) {
            val next = adjacentValue("shutspeedvalue", brighter = true)
            val s = next?.let { PropertyFormat.seconds(it) }
            if (next != null && s != null && s <= longest && setProperty("shutspeedvalue", next, reportErrors = false)) {
                return "Darker: shutter ${PropertyFormat.display("shutspeedvalue", next)}"
            }
        }
        if (settableProperty("isospeedvalue") != null) {
            val next = adjacentValue("isospeedvalue", brighter = true)
            if (next != null && (next.toIntOrNull() ?: Int.MAX_VALUE) <= plan.maxISO && setProperty("isospeedvalue", next, reportErrors = false)) {
                return "Darker: ISO $next"
            }
        }
        return "At the limit: ${PropertyFormat.display("shutspeedvalue", properties["shutspeedvalue"]?.value ?: "")}, ISO ${properties["isospeedvalue"]?.value ?: ""}"
    }
    if (settableProperty("isospeedvalue") != null) {
        val next = adjacentValue("isospeedvalue", brighter = false)
        if (next != null && (next.toIntOrNull() ?: 0) >= (baseIso ?: 0) && setProperty("isospeedvalue", next, reportErrors = false)) {
            return "Lighter: ISO $next"
        }
    }
    if (settableProperty("shutspeedvalue") != null) {
        val next = adjacentValue("shutspeedvalue", brighter = false)
        if (next != null && setProperty("shutspeedvalue", next, reportErrors = false)) {
            return "Lighter: shutter ${PropertyFormat.display("shutspeedvalue", next)}"
        }
    }
    return null
}

/** Ramping changes the shutter, so the camera has to let the app set it (M or S). */
val CameraModel.canRampExposure: Boolean get() = settableProperty("shutspeedvalue") != null

// MARK: - Motion trigger

/** Arms or disarms the trigger. It needs a timed shutter: Bulb and Live modes don't end on their own. */
fun CameraModel.armMotion(on: Boolean) {
    motion = motion.copy(armed = on && mode == CameraMode.REC && !isOpenEndedShutter, shots = if (on) 0 else motion.shots)
    motionPrevious = null
    motionLevel = 0.0
}

/** Compares the trigger box with the last frame a few times a second and shoots when it changes. */
fun CameraModel.analyzeMotion(image: Bitmap) {
    val now = System.currentTimeMillis()
    if (now - motionAnalyzedAt < 120) return
    motionAnalyzedAt = now
    val pixels = FrameMeter.grey(image, motion.region, 32, 24) ?: return
    val previous = motionPrevious
    motionPrevious = pixels
    if (previous == null || previous.size != pixels.size) return
    // The share of cells that clearly changed: a small subject counts as much as a big one moving slightly,
    // and JPEG noise (a few levels) doesn't count at all.
    var changed = 0
    for (i in pixels.indices) if (abs(previous[i] - pixels[i]) > 16) changed++
    val change = changed.toDouble() / pixels.size
    if (abs(change - motionLevel) > 0.005) motionLevel = change
    if (!motion.armed || mode != CameraMode.REC || isShooting || bracket.running || interval.running ||
        now < motionQuietUntil || change <= motion.threshold) return
    motion = motion.copy(shots = motion.shots + 1, lastTrigger = now)
    // Live view hiccups around a capture; don't let that count as movement.
    motionQuietUntil = now + (maxOf(1.5, motion.cooldown) * 1000).toLong()
    motionPrevious = null
    scope.launch {
        shutterPressed()
        shutterReleased()
    }
}

// MARK: - Expose to the right

/**
 * Raises the exposure until the brightest parts of live view are about to clip, then stops a step
 * short: the most light the sensor can take without losing highlights. Uses exposure compensation
 * (P, A, S) or the shutter speed (M).
 */
suspend fun CameraModel.exposeToTheRight() {
    if (ettrRunning || mode != CameraMode.REC || isShooting) return
    val name = when {
        settableProperty("expcomp") != null -> "expcomp"
        settableProperty("shutspeedvalue") != null -> {
            if (isOpenEndedShutter) {
                lastError = "Expose to the right needs a timed shutter speed, not Bulb or a Live mode."
                return
            }
            "shutspeedvalue"
        }
        else -> {
            lastError = "Expose to the right needs exposure compensation (P, A or S) or a shutter speed the app can set (M)."
            return
        }
    }
    ettrRunning = true
    try {
        val start = properties[name]?.value
        val limit = 0.004

        suspend fun measure(): Pair<Double, Double>? {
            // Let the change reach live view; after a shot it can take a few seconds to come back.
            delay(900)
            repeat(20) { if (recentFrame == null) delay(200) }
            val frame = recentFrame ?: return null
            val clip = FrameMeter.clipped(frame) ?: return null
            val light = FrameMeter.brightness(frame) ?: return null
            return clip to light
        }
        suspend fun restore() {
            if (start != null && properties[name]?.value != start) setProperty(name, start, reportErrors = false)
        }

        val first = measure()
        if (first == null) {
            lastError = "Expose to the right needs live view."
            return
        }
        val brighter = first.first <= limit
        var steps = 0
        while (steps < 15) {
            val next = adjacentValue(name, brighter) ?: break
            if (!setProperty(name, next, reportErrors = false)) break
            steps++
            val now = measure() ?: break
            // Live view that doesn't follow the exposure can't show clipping.
            if (brighter && steps == 2 && now.second < first.second * 1.08) {
                restore()
                lastError = "Live view doesn't get brighter with the exposure, so the highlights can't be judged. Turn off Live View Boost (or exposure preview) on the camera and try again."
                return
            }
            if (brighter && now.first > limit) {
                adjacentValue(name, brighter = false)?.let { setProperty(name, it, reportErrors = false) }
                break
            }
            if (!brighter && now.first <= limit) break
        }
        val value = PropertyFormat.display(name, properties[name]?.value ?: "")
        showToast(if (steps == 0) "Already at the limit: $value" else "Exposed to the right: $value")
    } finally {
        ettrRunning = false
    }
}

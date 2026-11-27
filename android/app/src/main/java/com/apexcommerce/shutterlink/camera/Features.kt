package com.apexcommerce.shutterlink.camera

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.log2
import kotlin.math.pow

// Interval timer, timed Bulb, exposure bracketing, the Astro preset, stars and RAW download.
// Port of Features.swift, Extras.swift and Astro.swift.

// MARK: - Interval timer

fun CameraModel.startInterval(plan: IntervalPlan) {
    if (interval.running || mode != CameraMode.REC || isOpenEndedShutter) return
    interval = IntervalState(running = true, done = 0, total = plan.count, nextShotAt = System.currentTimeMillis())
    val rampTarget = if (plan.ramp) recentFrame?.let { FrameMeter.brightness(it) } else null
    val baseIso = properties["isospeedvalue"]?.value?.toIntOrNull()
    if (plan.ramp && rampTarget == null) interval = interval.copy(rampNote = "No live view to follow the light: ramping is off")
    intervalJob = scope.launch {
        while (isActive && interval.running && (plan.count == 0 || interval.done < plan.count)) {
            if (rampTarget != null && interval.done > 0) {
                rampExposure(rampTarget, plan, baseIso)?.let { interval = interval.copy(rampNote = it) }
            }
            val shotStart = System.currentTimeMillis()
            interval = interval.copy(nextShotAt = null)
            shutterPressed()
            shutterReleased()
            interval = interval.copy(done = interval.done + 1)
            if (plan.count != 0 && interval.done >= plan.count) break
            // Interval is measured start-to-start; never fire faster than the camera can finish.
            val waitMs = maxOf(500L, (plan.seconds * 1000).toLong() - (System.currentTimeMillis() - shotStart))
            interval = interval.copy(nextShotAt = System.currentTimeMillis() + waitMs)
            delay(waitMs)
        }
        interval = interval.copy(running = false, nextShotAt = null)
    }
}

fun CameraModel.stopInterval() {
    intervalJob?.cancel()
    intervalJob = null
    interval = interval.copy(running = false, nextShotAt = null)
}

// MARK: - Timed bulb

/** Ends the open-ended exposure that just started after `seconds`, showing a countdown meanwhile. */
fun CameraModel.scheduleOpenExposureStop(seconds: Double) {
    exposureDuration = seconds
    val started = exposureStartedAt
    openExposureStopJob?.cancel()
    openExposureStopJob = scope.launch {
        delay((seconds * 1000).toLong())
        if (!isShooting || exposureStartedAt != started) return@launch
        // Clear it first: toggleOpenExposure cancels this job, which would cancel the stop request.
        openExposureStopJob = null
        withContext(NonCancellable) { toggleOpenExposure() }
    }
}

// MARK: - Exposure bracketing

/** The setting a bracket varies: shutter speed in M, exposure compensation in P, A and S. */
fun CameraModel.bracketProperty(target: BracketTarget): String = when (target) {
    BracketTarget.EV -> "expcomp"
    BracketTarget.SHUTTER -> "shutspeedvalue"
    BracketTarget.AUTO -> if (properties["takemode"]?.value?.uppercase() == "M") "shutspeedvalue" else "expcomp"
}

/** Offsets in thirds of a stop, in the usual camera order: 0, −1, +1, −2, +2… */
fun bracketOffsets(frames: Int, thirds: Int): List<Int> = List(maxOf(frames, 1)) { i ->
    val k = (i + 1) / 2
    if (i % 2 == 1) -k * thirds else k * thirds
}

/** What a plan would shoot, or why it can't run with the current settings. */
fun CameraModel.bracketSet(plan: BracketPlan): Result<BracketSet> {
    val inM = properties["takemode"]?.value?.uppercase() == "M"
    var name = bracketProperty(plan.target)
    // Automatic: when that one can't be changed (a compact with a fixed shutter), use the other.
    if (plan.target == BracketTarget.AUTO && properties[name]?.settable != true) {
        val other = if (name == "expcomp") "shutspeedvalue" else "expcomp"
        if (properties[other]?.settable == true) name = other
    }
    val isEv = name == "expcomp"
    val property = properties[name] ?: return Result.failure(CameraException(
        "This camera doesn't offer ${if (isEv) "exposure compensation" else "shutter speed"} over Wi-Fi."))
    if (!property.settable) {
        val mode = PropertyFormat.display("takemode", properties["takemode"]?.value ?: "")
        val noMode = inM || mode.isEmpty()
        return Result.failure(CameraException(when {
            isEv && noMode -> "Exposure compensation can't be changed from the phone here. Bracket the shutter instead."
            isEv -> "Exposure compensation is locked in $mode. Use P, A or S, or bracket the shutter in M."
            noMode -> "This camera doesn't let the phone change the shutter speed. Bracket EV instead."
            else -> "The shutter speed is locked in $mode. Use S or M, or bracket EV instead."
        }))
    }
    val offsets = bracketOffsets(plan.frames, plan.thirds)
    val number: (String) -> Double? = if (isEv) String::toDoubleOrNull else PropertyFormat::seconds
    val options = property.options.mapNotNull { o -> number(o)?.let { o to it } }
    val base = number(property.value)
    if (base == null || options.isEmpty()) return Result.failure(CameraException(if (isEv)
        "Couldn't read the current exposure compensation." else "Bracketing needs a timed shutter speed, not Bulb or Live modes."))
    // How far a value is from a frame's target, in stops. A positive offset means more light: a longer exposure.
    fun miss(value: Double, offset: Int) = abs(if (isEv) value - (base + offset / 3.0) else log2(value / (base * 2.0.pow(offset / 3.0))))
    var clamped = false
    val values = offsets.map { offset ->
        val best = options.minBy { miss(it.second, offset) }
        if (miss(best.second, offset) > 0.17) clamped = true
        best.first
    }
    return Result.success(BracketSet(name, values, offsets, clamped))
}

fun offsetLabel(thirds: Int): String {
    if (thirds == 0) return "±0"
    val whole = abs(thirds) / 3
    return (if (thirds > 0) "+" else "−") + (if (whole > 0) "$whole" else "") + listOf("", "⅓", "⅔")[abs(thirds) % 3]
}

val CameraModel.canBracket: Boolean
    get() = mode == CameraMode.REC && !bracket.running && !interval.running && !isOpenEndedShutter && !isMovieMode && !isShooting

/** Shoots the bracket, then puts the setting back the way it was. */
fun CameraModel.startBracket(plan: BracketPlan) {
    if (!canBracket) return
    val set = bracketSet(plan).getOrElse {
        lastError = it.message
        return
    }
    val name = set.property
    val original = properties[name]?.value
    bracket = BracketState(running = true, done = 0, total = set.values.size)
    bracketJob = scope.launch {
        var completed = false
        try {
            for ((index, value) in set.values.withIndex()) {
                if (!isActive) break
                val offset = "${offsetLabel(set.offsets[index])} EV"
                bracket = bracket.copy(label = if (name == "expcomp") offset else "$offset · ${PropertyFormat.display(name, value)}")
                if (properties[name]?.value != value) {
                    if (!setPropertyWhenReady(name, value)) break
                    delay(250)
                }
                if (!isActive) break
                shutterPressed()
                shutterReleased()
                while (isShooting && isActive) delay(100)
                bracket = bracket.copy(done = index + 1)
            }
            completed = isActive && bracket.done == set.values.size
        } catch (ignored: CancellationException) {
        } finally {
            withContext(NonCancellable) {
                val finished = bracket.done
                // Put the setting back, even after Cancel.
                if (original != null && phase == ConnectionPhase.CONNECTED && properties[name]?.value != original) {
                    setPropertyWhenReady(name, original, reportErrors = false)
                }
                // Finished: the final count stays (not running) so feedback can tell complete from stopped.
                bracket = if (completed) BracketState(done = finished, total = set.values.size) else BracketState()
                bracketJob = null
                if (finished > 0) showToast("Bracket: $finished of ${set.values.size} frames")
            }
        }
    }
}

/**
 * Sets a property between the frames of a series. Right after a shot the camera is still exposing or
 * writing the file and refuses changes (an Olympus answers HTTP 520), so this waits and tries again for
 * a few seconds before giving up. Only the last refusal is shown.
 */
suspend fun CameraModel.setPropertyWhenReady(name: String, value: String, reportErrors: Boolean = true): Boolean {
    val attempts = 12
    for (attempt in 1..attempts) {
        val last = attempt == attempts
        if (setProperty(name, value, reportErrors && last)) return true
        if (last || !currentCoroutineContext().isActive || phase != ConnectionPhase.CONNECTED) break
        delay(500)
    }
    return false
}

// MARK: - Focus stacking

/** Where the user puts focus before starting, and what the lens switch has to be on. */
val CameraModel.focusStackSetup: String
    get() = when (brand) {
        CameraBrand.PANASONIC -> "Set the camera to MF and focus on the nearest thing you want sharp. Each frame moves focus a step farther away."
        // The camera drives the lens's AF motor, so the lens has to stay on AF.
        CameraBrand.NIKON, CameraBrand.CANON -> "Leave the lens on AF, focus on the nearest thing you want sharp, and keep live view on. Each frame moves focus a step farther away."
        else -> "Focus on the nearest thing you want sharp. Each frame moves focus a step farther away."
    }

/** Where to look instead, on cameras the app can't step the focus of. */
val CameraModel.focusStackUnavailable: String
    get() = when (brand) {
        CameraBrand.OLYMPUS -> "Olympus and OM System cameras have no Wi-Fi command to move focus. Use Focus BKT, or Focus Stacking where the body has it, in the camera's Bracketing menu, then press the shutter here."
        CameraBrand.SONY -> "Sony's Camera Remote API has no command to move focus. Use the camera's own Focus Bracket where it has one."
        else -> "This camera doesn't offer a Wi-Fi command to move focus. Use its own focus bracketing from the camera's menu."
    }

val CameraModel.canFocusStack: Boolean get() = capabilities.focusDrive && canBracket

/**
 * Shoots a frame, steps focus farther, and repeats until the frame count or infinity. Uses the
 * bracket's state, so its progress ring and Cancel work for it too.
 */
fun CameraModel.startFocusStack(frames: Int, step: FocusStepSize) {
    val driver = driver ?: return
    if (!canFocusStack || frames <= 0) return
    bracket = BracketState(running = true, done = 0, total = frames, isFocusStack = true)
    bracketJob = scope.launch {
        var reachedEnd = false
        var failure: String? = null
        try {
            for (index in 0 until frames) {
                if (!isActive) break
                bracket = bracket.copy(label = "Focus ${index + 1} of $frames")
                val before = shotCounter
                shutterPressed()
                shutterReleased()
                while (isShooting && isActive) delay(100)
                if (shotCounter <= before) {
                    failure = lastError ?: "The camera didn't take frame ${index + 1}."
                    break
                }
                bracket = bracket.copy(done = index + 1)
                if (index == frames - 1 || !isActive) break
                try {
                    if (driver.driveFocus(farther = true, step = step) == FocusDriveResult.END_OF_TRAVEL) {
                        reachedEnd = true
                        break
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    failure = e.message ?: e.toString()
                    break
                }
                // Let the lens settle before the next frame.
                delay(300)
            }
        } catch (ignored: CancellationException) {
        } finally {
            val shot = bracket.done
            // Finished (every frame, or focus reached infinity): the final count stays (not running) so
            // feedback can tell complete from stopped. Cancelled or failed: cleared.
            val completed = failure == null && isActive && shot > 0 && (shot == frames || reachedEnd)
            bracket = if (completed) BracketState(done = shot, total = frames, isFocusStack = true) else BracketState()
            bracketJob = null
            when {
                failure != null -> lastError = if (shot > 0) "Focus stack stopped after $shot frames: $failure" else failure
                shot > 0 -> showToast(if (reachedEnd) "Focus stack: $shot frames, reached infinity" else "Focus stack: $shot of $frames frames")
            }
        }
    }
}

fun CameraModel.cancelBracket() {
    bracketJob?.cancel()
    if (phase != ConnectionPhase.CONNECTED) {
        bracketJob = null
        bracket = BracketState()
    }
}

// MARK: - Stars and RAW download

private fun starKey(image: CameraImage) = "${image.name}|${image.size}"

fun CameraModel.isStarred(image: CameraImage) = starKey(image) in starred

fun CameraModel.toggleStar(image: CameraImage) {
    val key = starKey(image)
    starred = if (key in starred) starred - key else starred + key
    prefs.edit().putStringSet("stars", starred).apply()
}

/** The RAW file shot together with this JPEG (same name, same folder), or the file itself if it's a RAW. */
fun CameraModel.rawCompanion(image: CameraImage): CameraImage? {
    if (image.fileExtension in MediaSaver.rawExtensions) return image
    return images.firstOrNull {
        it.directory == image.directory && it.fileExtension in MediaSaver.rawExtensions && it.baseName == image.baseName
    }
}

/** Fetches the RAW of every starred photo and saves it to Download/Shutterlink/RAW. */
fun CameraModel.downloadStarredRaws() {
    if (rawImportJob != null) return
    val companions = images.filter { isStarred(it) && !it.isVideo }.map { rawCompanion(it) }
    val raws = companions.filterNotNull().distinct()
    val withoutRaw = companions.count { it == null }
    if (raws.isEmpty()) {
        rawImport = RawImportProgress(message = if (withoutRaw > 0)
            "None of the starred photos has a RAW file next to it. Shoot RAW+JPEG to use this."
        else "Star some photos first: tap and hold a photo, or use the star when viewing it.")
        return
    }
    rawImport = RawImportProgress(done = 0, total = raws.size)
    rawImportJob = scope.launch {
        var saved = 0
        var failed = 0
        var cancelled = false
        for (raw in raws) {
            if (!isActive) {
                cancelled = true
                break
            }
            rawImport = rawImport?.copy(current = raw.name)
            try {
                saveOriginal(raw)
                saved++
            } catch (e: CancellationException) {
                cancelled = true
                break
            } catch (e: Throwable) {
                debugLog("RAW download ${raw.name}: ${e.message}")
                failed++
            }
            rawImport = rawImport?.copy(done = (rawImport?.done ?: 0) + 1)
        }
        var message = if (saved == 0) "No RAW files were saved." else "Saved $saved to Download ▸ Shutterlink ▸ RAW."
        if (failed > 0) message += " $failed couldn't be downloaded."
        if (withoutRaw > 0) message += " $withoutRaw starred photo${if (withoutRaw == 1) " has" else "s have"} no RAW."
        if (cancelled) message = "Stopped. $message"
        rawImport = RawImportProgress(done = saved, total = raws.size, message = message)
        rawImportJob = null
    }
}

fun CameraModel.cancelRawImport() {
    rawImportJob?.cancel()
}

// MARK: - Exposure strip values

/** Prefer the values the camera reports with each frame: they include what auto modes chose. */
fun CameraModel.stripValue(name: String, property: CameraProperty?): String {
    val info = liveInfo
    when (name) {
        "focalvalue" -> info.aperture?.let { return it }
        "shutspeedvalue" -> {
            if (property != null && PropertyFormat.isOpenEnded(property.value)) {
                return when (property.value.lowercase()) {
                    "livecomp" -> "LC"
                    "livetime" -> "LT"
                    "livebulb" -> "LB"
                    else -> PropertyFormat.display(name, property.value)
                }
            }
            info.shutter?.let { return it }
        }
        "isospeedvalue" -> info.iso?.let { return it.replace("ISO ", "").replace(" A", "") }
        "expcomp" -> info.expComp?.let { return it }
        "drivemode" -> return driveShort(property?.value ?: "")
        "wbvalue" -> {
            val raw = property?.value ?: return "–"
            // Short enough for a strip cell, without cutting a word off mid-way ("Fluore").
            val short = mapOf("0" to "AWB", "20" to "Incand.", "35" to "Fluor.", "64" to "Underw.", "256" to "OT 1",
                "257" to "OT 2", "258" to "OT 3", "259" to "OT 4", "512" to "Kelvin", "awb_white" to "AWB W", "awb_ambience" to "AWB A")
            return short[raw] ?: PropertyFormat.whiteBalance[raw] ?: raw
        }
    }
    if (property == null) return "–"
    return PropertyFormat.display(name, property.value)
}

/** Drive in a strip cell: "Single", "Anti-shock", "Cont H", "Burst H", "Timer 2s"… */
fun driveShort(value: String): String {
    val parts = value.split("|", limit = 2)
    if (parts.size == 2) {   // LUMIX: "burst|h", "selftimer|2sec"…
        return when (parts[0]) {
            "burst" -> "Burst ${parts[1].uppercase()}"
            "selftimer" -> "Timer " + parts[1].replace("sec3shot", "s×3").replace("sec", "s")
            "4k_photo" -> "4K"
            "autobracket" -> "Bracket"
            "stopmotion_interval" -> if (parts[1] == "interval") "Interval" else "Stop mo."
            else -> PropertyFormat.display("drivemode", value)
        }
    }
    // Olympus: "lowvib-normal", "silent-continuous-H", "customselftimer"…
    val words = mapOf("normal" to "Single", "lowvib" to "Anti-shock", "silent" to "Silent",
        "continuous" to "Cont", "selftimer" to "Timer", "customselftimer" to "Timer C")
    val tokens = value.split("-").filter { it.isNotEmpty() }.map { words[it] ?: it }.toMutableList()
    if (tokens.size > 1 && tokens.last() == "Single") tokens.removeAt(tokens.size - 1)   // "Anti-shock Single" → "Anti-shock"
    return if (tokens.isEmpty()) "–" else tokens.joinToString(" ")
}

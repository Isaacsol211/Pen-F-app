package com.apexcommerce.shutterlink.camera

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.pow

// Interval timer, timed Bulb, exposure bracketing, the Astro preset, stars and RAW download.
// Port of Features.swift, Extras.swift and Astro.swift.

private fun log2(x: Double) = ln(x) / ln(2.0)

// MARK: - Interval timer

fun CameraModel.startInterval(plan: IntervalPlan) {
    if (interval.running || mode != CameraMode.REC || isOpenEndedShutter) return
    val now = System.currentTimeMillis()
    interval = IntervalState(running = true, done = 0, total = plan.count, nextShotAt = now, startedAt = now)
    intervalJob = scope.launch {
        while (isActive && interval.running && (plan.count == 0 || interval.done < plan.count)) {
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
fun bracketOffsets(frames: Int, thirds: Int): List<Int> {
    val result = mutableListOf(0)
    var k = 1
    while (result.size < frames) {
        result.add(-k * thirds)
        if (result.size < frames) result.add(k * thirds)
        k++
    }
    return result
}

/** What a plan would shoot, or why it can't run with the current settings. */
fun CameraModel.bracketSet(plan: BracketPlan): Result<BracketSet> {
    val name = bracketProperty(plan.target)
    val property = properties[name] ?: return Result.failure(CameraException(
        "This camera doesn't offer ${if (name == "expcomp") "exposure compensation" else "shutter speed"} over Wi-Fi."))
    if (!property.settable) {
        val mode = PropertyFormat.display("takemode", properties["takemode"]?.value ?: "")
        return Result.failure(CameraException(if (name == "expcomp")
            "Exposure compensation is locked in $mode. Use P, A or S, or bracket the shutter in M."
        else "The shutter speed is locked in $mode. Use S or M, or bracket EV instead."))
    }
    val offsets = bracketOffsets(plan.frames, plan.thirds)
    val values = mutableListOf<String>()
    var clamped = false
    if (name == "expcomp") {
        val options = property.options.mapNotNull { o -> o.toDoubleOrNull()?.let { o to it } }
        val base = property.value.toDoubleOrNull()
        if (base == null || options.isEmpty()) return Result.failure(CameraException("Couldn't read the current exposure compensation."))
        for (offset in offsets) {
            val target = base + offset / 3.0
            val best = options.minByOrNull { abs(it.second - target) } ?: continue
            if (abs(best.second - target) > 0.17) clamped = true
            values.add(best.first)
        }
    } else {
        val options = property.options.mapNotNull { o -> PropertyFormat.seconds(o)?.let { o to it } }
        val base = PropertyFormat.seconds(property.value)
        if (base == null || options.isEmpty()) return Result.failure(CameraException("Bracketing needs a timed shutter speed, not Bulb or Live modes."))
        for (offset in offsets) {
            // A positive offset means more light: a longer exposure.
            val target = base * 2.0.pow(offset / 3.0)
            val best = options.minByOrNull { abs(log2(it.second / target)) } ?: continue
            if (abs(log2(best.second / target)) > 0.17) clamped = true
            values.add(best.first)
        }
    }
    return Result.success(BracketSet(name, values, offsets, clamped))
}

fun offsetLabel(thirds: Int): String {
    if (thirds == 0) return "±0"
    val sign = if (thirds > 0) "+" else "−"
    val whole = abs(thirds) / 3
    val rest = abs(thirds) % 3
    val fraction = when (rest) { 0 -> ""; 1 -> "⅓"; else -> "⅔" }
    return "$sign${if (whole > 0) "$whole" else ""}$fraction"
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
        try {
            for ((index, value) in set.values.withIndex()) {
                if (!isActive) break
                val offset = "${offsetLabel(set.offsets[index])} EV"
                bracket = bracket.copy(label = if (name == "expcomp") offset else "$offset · ${PropertyFormat.display(name, value)}")
                if (properties[name]?.value != value) {
                    if (!setProperty(name, value, reportErrors = true)) break
                    delay(250)
                }
                if (!isActive) break
                shutterPressed()
                shutterReleased()
                while (isShooting && isActive) delay(100)
                bracket = bracket.copy(done = index + 1)
            }
        } catch (ignored: CancellationException) {
        } finally {
            withContext(NonCancellable) {
                val finished = bracket.done
                // Put the setting back, even after Cancel.
                if (original != null && phase == ConnectionPhase.CONNECTED && properties[name]?.value != original) {
                    setProperty(name, original, reportErrors = false)
                }
                bracket = BracketState()
                bracketJob = null
                if (finished > 0) showToast("Bracket: $finished of ${set.values.size} frames")
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

// MARK: - Astro preset

/** Slowest available shutter that still keeps stars round (or Live Composite for trails). */
fun CameraModel.astroShutter(plan: AstroPlan): String? {
    val options = properties["shutspeedvalue"]?.options ?: return null
    if (plan.trails) return options.firstOrNull { it.lowercase() == "livecomp" }
    return options.mapNotNull { o -> PropertyFormat.seconds(o)?.let { o to it } }
        .filter { it.second <= plan.maxSeconds }
        .maxByOrNull { it.second }?.first
}

val CameraModel.widestAperture: String?
    get() {
        val property = properties["focalvalue"] ?: return null
        return dialOptions(property).options.mapNotNull { o -> o.toDoubleOrNull()?.let { o to it } }.minByOrNull { it.second }?.first
    }

fun CameraModel.nearestIso(target: Int): String? =
    properties["isospeedvalue"]?.options?.mapNotNull { o -> o.toIntOrNull()?.let { o to it } }
        ?.minByOrNull { abs(it.second - target) }?.first

fun CameraModel.astroSteps(plan: AstroPlan): List<PresetStep> {
    val mode = properties["takemode"]?.options?.firstOrNull { it.uppercase() == "M" }
    val wb = properties["wbvalue"]?.options?.firstOrNull { it == "35" }
    val drive = properties["drivemode"]?.options?.firstOrNull { it == "lowvib-normal" }
    val shutterDetail = if (plan.trails) "Live Composite: stacks only new light, so stars draw trails"
    else fmt("Longest that keeps stars sharp at %d mm (≤ %.1f s)", plan.focalLength.toInt(), plan.maxSeconds)
    return listOf(
        PresetStep("Manual mode", "So aperture and shutter can be set", "takemode", mode),
        PresetStep("Widest aperture", "Gather as much starlight as possible", "focalvalue", widestAperture),
        PresetStep("Shutter", shutterDetail, "shutspeedvalue", astroShutter(plan)),
        PresetStep("ISO", "Bright enough for faint stars without too much noise", "isospeedvalue", nearestIso(plan.iso)),
        PresetStep("White balance ≈ 4000 K", "Neutral-blue night sky (Fluorescent preset)", "wbvalue", wb),
        PresetStep("Anti-shock drive", "Avoids shutter-shock blur on a tripod", "drivemode", drive),
    )
}

/** Applies each step in order and records what the camera accepted. */
suspend fun CameraModel.applyAstro(plan: AstroPlan) {
    if (presetRunning) return
    presetRunning = true
    try {
        presetSteps = astroSteps(plan)
        for (index in presetSteps.indices) {
            val step = presetSteps[index]
            fun update(state: PresetStep.State) {
                presetSteps = presetSteps.toMutableList().also { it[index] = it[index].copy(state = state) }
            }
            val value = step.value
            if (value == null || properties[step.property] == null) {
                update(PresetStep.State.Skipped("Not offered by the camera over Wi-Fi"))
                continue
            }
            update(PresetStep.State.Running)
            val ok = setProperty(step.property, value, reportErrors = false)
            update(if (ok) PresetStep.State.Done else PresetStep.State.Failed("The camera refused ${PropertyFormat.display(step.property, value)}"))
        }
    } finally {
        presetRunning = false
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
    val raws = mutableListOf<CameraImage>()
    var withoutRaw = 0
    for (image in images) {
        if (!isStarred(image) || image.isVideo) continue
        val raw = rawCompanion(image)
        if (raw != null) {
            if (raw !in raws) raws.add(raw)
        } else {
            withoutRaw++
        }
    }
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
                val data = downloadOriginal(raw)
                MediaSaver.save(context, data, raw)
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
        "wbvalue" -> {
            val raw = property?.value ?: return "–"
            return if (raw == "0") "AWB" else PropertyFormat.whiteBalance[raw]?.take(6) ?: raw
        }
    }
    if (property == null) return "–"
    return PropertyFormat.display(name, property.value)
}

fun CameraModel.stripValue(name: String): String = stripValue(name, properties[name]?.let { dialOptions(it) })

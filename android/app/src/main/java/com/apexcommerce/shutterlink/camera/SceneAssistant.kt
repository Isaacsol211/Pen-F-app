package com.apexcommerce.shutterlink.camera

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.location.Location
import android.location.LocationManager
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.roundToInt

// The scene assistant (port of SceneAssistant.swift): every ~1.5 s it labels live view on the phone
// with Google's ML Kit image labeling (bundled model; nothing leaves the phone), adds the frame's
// brightness and blown highlights and where the sun and moon are, and shows one suggestion with one
// button. The rules use the iOS app's scene names (Apple's classifier); ML Kit's labels are mapped
// onto them, so both apps suggest the same things.

/** One suggestion shown over live view. Nothing changes until the user taps its button. */
data class SceneSuggestion(
    /** Stable per kind of suggestion, so "not now" keeps that kind away for a while. */
    val id: String,
    val icon: String,
    val title: String,
    val detail: String,
    val actionTitle: String,
    val action: Action,
) {
    sealed class Action {
        data class Recipe(val recipe: PresetRecipe) : Action()
        /** Sets one property, e.g. exposure compensation or (in M) the shutter speed. */
        data class Setting(val property: String, val value: String) : Action()
        data object ExposeToTheRight : Action()
        data object OpenND : Action()
        data object OpenMotion : Action()
    }
}

/** What the assistant looks at for one frame. */
data class SceneSignals(
    /** Scene labels (the iOS app's names, e.g. "night_sky") with their confidence (0…1). */
    val labels: Map<String, Float> = emptyMap(),
    /** Mean linear brightness of the frame (0…1). */
    val brightness: Double = 0.2,
    /** Share of the frame with blown highlights (0…1). */
    val clipped: Double = 0.0,
    /** From the phone's clock and last known location; null without a location. */
    val sky: Astronomy.Sky? = null,
) {
    fun score(vararg names: String): Float = names.maxOf { labels[it] ?: 0f }
    val isDaylight: Boolean get() = sky?.let { it.sunAltitude > 0 } ?: (brightness > 0.08)
    val isDark: Boolean get() = sky?.let { it.sunAltitude < -6 } ?: (brightness < 0.03)
}

object SceneLabels {
    /**
     * ML Kit's labels → the iOS app's scene names. ML Kit has no "night", "snow", "ocean" or "animal"
     * label, so those come from near neighbours (and a dark frame for the night sky).
     */
    private val map: Map<String, List<String>> = mapOf(
        "Fireworks" to listOf("fireworks"),
        "Aurora" to listOf("aurora"),
        "Star" to listOf("night_sky"),
        "Lightning" to listOf("lightning"),
        "Waterfall" to listOf("waterfall"),
        "Lake" to listOf("water_body"),
        "River" to listOf("waterways"),
        "Canal" to listOf("waterways"),
        "Beach" to listOf("beach", "ocean"),
        "Skyscraper" to listOf("cityscape"),
        "Skyline" to listOf("cityscape"),
        "Car" to listOf("car"),
        "Bird" to listOf("bird"),
        "Dog" to listOf("animal"), "Cat" to listOf("animal"), "Pet" to listOf("animal"), "Bear" to listOf("animal"),
        "Cattle" to listOf("animal"), "Horse" to listOf("animal"), "Butterfly" to listOf("insect"),
        "Sports" to listOf("sport"), "Surfing" to listOf("watersport"), "Skiing" to listOf("winter_sport"),
        "Snowboarding" to listOf("winter_sport", "snow"),
        "Flower" to listOf("flower"), "Insect" to listOf("insect"),
        "Ice" to listOf("snow"), "Glacier" to listOf("snow"), "Icicle" to listOf("snow"),
        "Sunset" to listOf("sunset_sunrise"),
        "Mountain" to listOf("mountain"), "Forest" to listOf("forest"), "Hill" to listOf("hill"),
    )

    /** Maps one frame's ML Kit labels (text → confidence) onto scene names. */
    fun fromMlKit(labels: Map<String, Float>, brightness: Double): Map<String, Float> {
        val out = HashMap<String, Float>()
        fun put(name: String, confidence: Float) {
            if (confidence > (out[name] ?: 0f)) out[name] = confidence
        }
        for ((text, confidence) in labels) {
            map[text]?.forEach { put(it, confidence) }
            // A dark frame of sky is a night sky; a bright one, a blue sky.
            if (text == "Sky") put(if (brightness < 0.03) "night_sky" else "blue_sky", confidence)
            // ML Kit also calls a low sun a "Moon": only count it when the frame is dark, as a moon shot is.
            if (text == "Moon" && brightness < 0.1) put("moon", confidence)
        }
        return out
    }
}

/** The suggestions that fit a frame, most useful first. Pure: reads the camera's settings, changes nothing. */
fun CameraModel.sceneSuggestions(s: SceneSignals): List<SceneSuggestion> {
    val out = mutableListOf<SceneSuggestion>()
    val liveComposite = option("shutspeedvalue", listOf("livecomp")) != null
    fun recipe(r: PresetRecipe, id: String, icon: String, title: String, detail: String) {
        out.add(SceneSuggestion(id, icon, title, detail, r.title, SceneSuggestion.Action.Recipe(r)))
    }
    fun setting(id: String, icon: String, title: String, detail: String, change: Triple<String, String, String>) {
        out.add(SceneSuggestion(id, icon, title, detail, change.third, SceneSuggestion.Action.Setting(change.first, change.second)))
    }

    if (s.score("fireworks") >= 0.3f) {
        recipe(PresetRecipe.FIREWORKS, "fireworks", "fireworks", "Fireworks",
            if (liveComposite) "Live Composite adds each burst without washing out the sky" else "M, f/8 and a 4 s exposure per burst")
    }
    if (s.score("moon") >= 0.3f && (s.sky?.moonAltitude ?: 1.0) > -2) {
        recipe(PresetRecipe.MOON, "moon", "moon", "The moon", "Auto exposure burns it out: M, f/8, 1/250 s keeps the craters")
    }
    if (s.score("aurora") >= 0.3f) {
        recipe(PresetRecipe.ASTRO, "aurora", "astro", "Aurora", "Astro settings, then try 2–5 s so the curtains stay sharp")
    }
    val darkNight = (s.sky?.let { it.sunAltitude < -12 } ?: false) && s.brightness < 0.01
    if (s.score("night_sky") >= 0.3f || darkNight) {
        var detail = "Astro sets M, the widest aperture and the longest shutter that keeps stars round"
        val sky = s.sky
        if (sky != null && sky.moonAltitude > 0 && sky.moonIllumination > 0.5) {
            detail = "The moon is ${(sky.moonIllumination * 100).toInt()}% full and up: expect fewer faint stars. $detail"
        }
        recipe(PresetRecipe.ASTRO, "astro", "astro", "Night sky", detail)
    }
    if (s.score("lightning") >= 0.3f && liveComposite) {
        recipe(PresetRecipe.FIREWORKS, "lightning", "lightning", "Lightning", "Live Composite catches each strike as it happens")
    }
    if (s.score("waterfall", "ocean", "water_body", "waterways") >= 0.35f) {
        if (s.isDaylight || s.brightness > 0.12) {
            out.add(SceneSuggestion("water-nd", "nd", "Silky water", "In daylight a long exposure needs an ND filter: work it out here",
                "ND filter", SceneSuggestion.Action.OpenND))
        } else {
            recipe(PresetRecipe.TRAILS, "water", "water", "Silky water", "M, f/11 and 15 s smooths the water")
        }
    }
    if (s.score("cityscape", "car", "traffic_light") >= 0.3f && (s.isDark || s.brightness < 0.04)) {
        recipe(PresetRecipe.TRAILS, "trails", "car", "Light trails", "M, f/11 and 15 s draws car lights into lines")
    }
    if (s.score("bird") >= 0.35f) {
        recipe(PresetRecipe.ACTION, "bird", "bird", "Bird", "1/1000 s freezes wings. For a feeder, the Motion trigger can wait for it")
    } else if (s.score("animal", "sport", "motorsport", "watersport", "winter_sport") >= 0.35f) {
        recipe(PresetRecipe.ACTION, "action", "action", "Movement", "1/1000 s and fast bursts freeze the action")
    }
    if (s.score("flower", "insect") >= 0.35f) {
        recipe(PresetRecipe.MACRO, "macro", "macro", "Close-up",
            if (capabilities.focusDrive) "f/8 and steady, then a focus stack for more depth" else "f/8 and steady for more depth")
    }

    // Exposure, from the frame itself.
    if (s.clipped > 0.02) exposureChange(-2)?.let {
        setting("clipping", "warning", "Highlights clipping", "${(s.clipped * 100).roundToInt()}% of the picture is blown out", it)
    }
    if (s.score("snow") >= 0.4f && s.clipped < 0.01) exposureChange(2)?.let {
        setting("snow", "snow", "Snow", "Snow fools the meter into grey: brighten it", it)
    }
    val goldenHour = s.sky?.let { it.sunAltitude in -4.0..6.0 } ?: false
    if ((s.score("sunset_sunrise") >= 0.3f || goldenHour) && s.clipped > 0.003) exposureChange(-1)?.let {
        setting("golden", "sunset", "Golden hour", "A little less exposure keeps the colour in the sky", it)
    }
    if (s.isDaylight && s.score("mountain", "beach", "forest", "hill", "land", "blue_sky", "snow") >= 0.35f) {
        recipe(PresetRecipe.LANDSCAPE, "landscape", "landscape", "Landscape", "f/8 and the lowest ISO for front-to-back sharpness")
    }
    val nightLabels = s.score("night_sky", "moon", "fireworks", "aurora", "lightning") >= 0.3f
    if (s.brightness < 0.02 && s.clipped < 0.001 && !nightLabels && !s.isDark) {
        out.add(SceneSuggestion("dark", "bright", "Underexposed", "There's room to brighten without losing highlights",
            "Expose right", SceneSuggestion.Action.ExposeToTheRight))
    }
    return out
}

/** A change of `thirds` of a stop: exposure compensation in P/A/S, else the shutter in M. (property, value, label) */
fun CameraModel.exposureChange(thirds: Int): Triple<String, String, String>? {
    val ev = settableProperty("expcomp")
    val current = ev?.value?.toDoubleOrNull()
    if (ev != null && current != null) {
        val target = current + thirds / 3.0
        val best = ev.options.mapNotNull { o -> o.toDoubleOrNull()?.let { o to it } }.minByOrNull { abs(it.second - target) } ?: return null
        if (abs(best.second - current) <= 0.1) return null
        return Triple("expcomp", best.first, "EV ${PropertyFormat.display("expcomp", best.first)}")
    }
    // In M: shutter speeds are a third of a stop apart, so step along the list.
    if (settableProperty("shutspeedvalue") != null && !isOpenEndedShutter) {
        val now = PropertyFormat.seconds(properties["shutspeedvalue"]?.value ?: "") ?: return null
        val sorted = timedShutters.sortedBy { it.second }
        val index = sorted.indices.minByOrNull { abs(ln(sorted[it].second / now)) } ?: return null
        val target = (index + thirds).coerceIn(0, sorted.size - 1)
        if (target == index) return null
        val value = sorted[target].first
        return Triple("shutspeedvalue", value, PropertyFormat.display("shutspeedvalue", value))
    }
    return null
}

// MARK: - Running it

private val labeler by lazy {
    ImageLabeling.getClient(ImageLabelerOptions.Builder().setConfidenceThreshold(0.1f).build())
}
@Volatile private var classifyFailureLogged = false

/** ML Kit's on-device labels (text → confidence), off the main thread. */
suspend fun classifyScene(frame: Bitmap): Map<String, Float> = withContext(Dispatchers.Default) {
    suspendCancellableCoroutine { cont ->
        try {
            labeler.process(InputImage.fromBitmap(frame, 0))
                .addOnSuccessListener { labels -> if (cont.isActive) cont.resume(labels.associate { it.text to it.confidence }) }
                .addOnFailureListener { e ->
                    if (!classifyFailureLogged) {
                        classifyFailureLogged = true
                        debugLog("Scene labeling unavailable: ${e.message}")
                    }
                    if (cont.isActive) cont.resume(emptyMap())
                }
        } catch (e: Exception) {
            if (cont.isActive) cont.resume(emptyMap())
        }
    }
}

/** Roughly where the phone is, without asking for anything: the last fix when location is already allowed. */
fun CameraModel.lastKnownLocation(): Location? {
    val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    if (!granted) return null
    val manager = context.getSystemService(LocationManager::class.java) ?: return null
    return runCatching {
        manager.getProviders(true).mapNotNull { manager.getLastKnownLocation(it) }.maxByOrNull { it.time }
    }.getOrNull()
}

/**
 * Looks at live view every ~1.5 s while the remote screen is up, and keeps `sceneSuggestion` current.
 * Paused while shooting, bracketing, running an interval or a preset, or with the motion trigger armed.
 */
suspend fun CameraModel.runSceneAssistant() {
    while (coroutineContext.isActive) {
        delay(1500)
        val frame = recentFrame
        if (!sceneAssistantOn || phase != ConnectionPhase.CONNECTED || mode != CameraMode.REC || !liveViewRunning || isShooting ||
            bracket.running || interval.running || presetRunning || motion.armed || frame == null) {
            if (!sceneAssistantOn) sceneSuggestion = null
            continue
        }
        try {
            val brightness = withContext(Dispatchers.Default) { FrameMeter.brightness(frame) } ?: 0.2
            val clipped = withContext(Dispatchers.Default) { FrameMeter.clipped(frame) } ?: 0.0
            val override = sceneLabelOverride
            val raw = if (override != null) emptyMap() else classifyScene(frame)
            val labels = override ?: SceneLabels.fromMlKit(raw, brightness)
            val location = lastKnownLocation()
            val sky = location?.let { Astronomy.sky(System.currentTimeMillis(), it.latitude, it.longitude) }
            val signals = SceneSignals(labels, brightness, clipped, sky)
            sceneSignals = signals
            sceneRawLabels = raw
            showBest(sceneSuggestions(signals))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            debugLog("scene assistant: $e")
        }
    }
}

/** Shows a suggestion once it has topped two looks in a row (no flicker), and hides it after two without. */
private fun CameraModel.showBest(suggestions: List<SceneSuggestion>) {
    val now = System.currentTimeMillis()
    sceneSnoozed = sceneSnoozed.filterValues { it > now }
    val best = suggestions.firstOrNull { it.id !in sceneSnoozed }
    if (best != null && best.id == sceneSuggestion?.id) {
        sceneSuggestion = best
        sceneMisses = 0
        return
    }
    if (best != null && best.id == sceneCandidate) {
        sceneSuggestion = best
        sceneMisses = 0
    } else {
        sceneCandidate = best?.id
        sceneMisses++
        if (sceneMisses >= 2) sceneSuggestion = null
    }
}

/** "Not now": that kind of suggestion stays away for ten minutes. */
fun CameraModel.dismissSceneSuggestion() {
    val suggestion = sceneSuggestion ?: return
    sceneSnoozed = sceneSnoozed + (suggestion.id to System.currentTimeMillis() + 600_000)
    sceneSuggestion = null
    sceneCandidate = null
}

/** Runs a suggestion's action. Panels (ND, Motion) are opened by the screen. */
suspend fun CameraModel.applySceneSuggestion(suggestion: SceneSuggestion) {
    sceneSuggestion = null
    sceneCandidate = null
    fun snooze(ms: Long) {
        sceneSnoozed = sceneSnoozed + (suggestion.id to System.currentTimeMillis() + ms)
    }
    when (val action = suggestion.action) {
        is SceneSuggestion.Action.Recipe -> {
            snooze(600_000)
            apply(action.recipe)
        }
        is SceneSuggestion.Action.Setting -> {
            // Give the new exposure time to reach live view before judging it again.
            snooze(20_000)
            if (setProperty(action.property, action.value)) {
                showToast("${PropertyFormat.title(action.property)} ${PropertyFormat.display(action.property, action.value)}")
            }
        }
        SceneSuggestion.Action.ExposeToTheRight -> {
            snooze(120_000)
            exposeToTheRight()
        }
        SceneSuggestion.Action.OpenND, SceneSuggestion.Action.OpenMotion -> snooze(600_000)
    }
}

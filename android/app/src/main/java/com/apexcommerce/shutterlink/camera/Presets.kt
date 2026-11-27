package com.apexcommerce.shutterlink.camera

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.ln

// Presets (port of Presets.swift and Astro.swift): a shared engine that applies settings in order
// (mode first), works each step out again as the mode changes, and says what to do on the camera for
// anything it can't set. Astro runs on it, as do the one-tap recipes, Undo and My presets.

/** "My presets", stored as JSON in the app's preferences. */
object SavedPresets {
    private const val KEY = "presets.saved"

    fun load(prefs: SharedPreferences): List<SavedPreset> = runCatching {
        val array = JSONArray(prefs.getString(KEY, null) ?: return emptyList())
        (0 until array.length()).map { i ->
            val o = array.getJSONObject(i)
            val values = o.getJSONObject("values")
            SavedPreset(o.getString("id"), o.getString("name"), o.getString("brand"),
                values.keys().asSequence().associateWith { values.getString(it) }, o.optLong("created"))
        }
    }.getOrDefault(emptyList())

    fun store(prefs: SharedPreferences, presets: List<SavedPreset>) {
        val array = JSONArray(presets.map { p ->
            JSONObject().put("id", p.id).put("name", p.name).put("brand", p.brand).put("values", JSONObject(p.values)).put("created", p.created)
        })
        prefs.edit().putString(KEY, array.toString()).apply()
    }
}

/** Properties a preset may change, in the order they're applied: the mode first, because it decides the rest. */
val presetOrder = listOf("takemode", "focalvalue", "shutspeedvalue", "isospeedvalue", "expcomp", "wbvalue", "drivemode")

/** Which exposure settings a mode lets you set. */
fun modeAllows(mode: String, name: String): Boolean = when (name) {
    "focalvalue" -> mode in setOf("A", "M")
    "shutspeedvalue" -> mode in setOf("S", "M")
    "expcomp" -> mode in setOf("P", "A", "S")
    else -> true
}

// MARK: - Engine

/** A property the app can change right now. */
fun CameraModel.settableProperty(name: String): CameraProperty? = properties[name]?.takeIf { it.settable }

/** The mode step, and whether the camera will be in that mode once it has run. */
fun CameraModel.modeStep(target: String, why: String): Pair<PresetStep, Boolean> {
    val option = settableProperty("takemode")?.options?.firstOrNull { it.uppercase() == target }
    val current = properties["takemode"]?.value
    val already = current?.uppercase() == target
    val names = mapOf("M" to "Manual", "A" to "Aperture priority", "S" to "Shutter priority", "P" to "Program")
    val step = PresetStep("${names[target] ?: target} mode", why, "takemode", option ?: if (already) current else null,
        unavailable = "Turn the camera's mode dial to $target: the app can't change the mode on this camera")
    return step to (option != null || already)
}

/** A step for one setting, with nothing to set when the camera doesn't offer it. */
fun CameraModel.presetStep(
    title: String, detail: String, name: String, value: String?, mode: String? = null, inMode: Boolean = false,
    unavailable: String = "Not offered by the camera over Wi-Fi",
): PresetStep {
    // The camera offers it now, or will once it's in `mode`.
    val available = settableProperty(name) != null || (mode != null && inMode && modeAllows(mode, name) && name in properties)
    val onCamera = when {
        mode != null && !inMode && name in setOf("focalvalue", "shutspeedvalue", "expcomp") ->
            "Turn the camera's mode dial to $mode, then apply again."
        // Several bodies have a drive dial the phone can't turn (or say OK and ignore the change).
        name == "drivemode" -> unavailable
        else -> null
    }
    return PresetStep(title, detail, name, if (available) value else null, unavailable = unavailable, onCamera = onCamera)
}

// MARK: - Values

/** The apertures the mounted lens can do, with their f-number. */
private val CameraModel.apertures: List<Pair<String, Double>>
    get() = properties["focalvalue"]?.let { p -> dialOptions(p).options.mapNotNull { o -> o.toDoubleOrNull()?.let { o to it } } } ?: emptyList()

fun CameraModel.aperture(near: Double): String? = apertures.minByOrNull { abs(ln(it.second / near)) }?.first

/** The camera's timed shutter speeds with their length in seconds (Bulb and Live modes excluded). */
val CameraModel.timedShutters: List<Pair<String, Double>>
    get() = (properties["shutspeedvalue"]?.options ?: emptyList()).mapNotNull { o -> PropertyFormat.seconds(o)?.let { o to it } }

/** The timed shutter speed closest to `seconds`. */
fun CameraModel.shutter(near: Double): String? = timedShutters.minByOrNull { abs(ln(it.second / near)) }?.first

val CameraModel.lowestIso: String?
    get() = properties["isospeedvalue"]?.options?.mapNotNull { o -> o.toIntOrNull()?.let { o to it } }?.minByOrNull { it.second }?.first

val CameraModel.autoIso: String? get() = properties["isospeedvalue"]?.options?.firstOrNull { it.lowercase() == "auto" }

val CameraModel.zeroEv: String? get() = properties["expcomp"]?.options?.firstOrNull { it.toDoubleOrNull() == 0.0 }

/** The first of `preferred` the camera offers for `name`. */
fun CameraModel.option(name: String, preferred: List<String>): String? {
    val options = properties[name]?.options ?: emptyList()
    return preferred.firstOrNull { it in options }
}

/**
 * Keeps a tripod shot steady: anti-shock drive where the camera has it, else a 2 s self-timer, else
 * what to set on the camera, so the step never just says "not offered".
 */
fun CameraModel.antiShockStep(detail: String = "Avoids shutter-shock blur on a tripod"): PresetStep {
    val onCamera = if (brand == CameraBrand.PANASONIC)
        "Set it on the camera: turn the drive dial to the self-timer and choose 2 s in MENU ▸ Rec ▸ Self Timer, " +
            "or choose ESHTR (electronic shutter) in MENU ▸ Rec ▸ Shutter Type."
    else "Set it on the camera: a 2 s self-timer, or the electronic (silent) shutter."
    val antiShock = option("drivemode", listOf("lowvib-normal"))
    val timer = option("drivemode", listOf("selftimer|2sec"))
    val step = if (timer != null && antiShock == null)
        presetStep("2 s self-timer", "$detail: the camera waits 2 s after the press", "drivemode", timer)
    else presetStep("Anti-shock drive", detail, "drivemode", antiShock, unavailable = onCamera)
    return step.copy(onCamera = onCamera)
}

/**
 * Runs steps in order and records what the camera accepted. They're worked out again before each one,
 * because changing the mode changes what the camera offers. What they change is remembered so Undo can
 * put it back. Returns false if the camera refused any of them.
 */
suspend fun CameraModel.runPreset(id: String, title: String, make: () -> List<PresetStep>): Boolean {
    if (presetRunning) return false
    presetRunning = true
    try {
        presetResultsFor = id
        val before = presetOrder.mapNotNull { name -> properties[name]?.let { name to it.value } }.toMap()
        presetSteps = make()
        var changed = false
        for (index in presetSteps.indices) {
            val fresh = make()
            if (index >= fresh.size) break
            fun update(f: (PresetStep) -> PresetStep) {
                presetSteps = presetSteps.toMutableList().also { it[index] = f(it[index]) }
            }
            update { it.copy(value = fresh[index].value, unavailable = fresh[index].unavailable, onCamera = fresh[index].onCamera) }
            val step = presetSteps[index]
            val value = step.value
            val property = properties[step.property]
            if (value == null || property == null) {
                update { it.copy(state = PresetStep.State.Skipped(step.unavailable)) }
                continue
            }
            if (property.value == value) {
                update { it.copy(state = PresetStep.State.Done) }
                continue
            }
            update { it.copy(state = PresetStep.State.Running) }
            val onCamera = step.onCamera
            if (setProperty(step.property, value, reportErrors = false)) {
                changed = true
                update { it.copy(state = PresetStep.State.Done) }
            } else if (onCamera != null) {
                // A dial or mode the phone can't turn: say what to do, not "refused".
                update { it.copy(state = PresetStep.State.Skipped("Couldn't set ${PropertyFormat.display(step.property, value)} from the phone. $onCamera")) }
            } else {
                update { it.copy(state = PresetStep.State.Failed("The camera refused ${PropertyFormat.display(step.property, value)}")) }
            }
        }
        val failed = presetSteps.any { it.state is PresetStep.State.Failed }
        // The setup stays on (even when the camera was already set that way) until it's turned off,
        // which puts back the settings from just before it.
        if (changed || !failed) {
            presetUndo = SettingsSnapshot(id, title, before)
            savePresetUndo()
        }
        return !failed
    } finally {
        presetRunning = false
    }
}

/** The setup (recipe or saved preset) is on: applied, and not yet turned off. */
fun CameraModel.isPresetOn(id: String): Boolean = presetUndo?.id == id

/** A setup that's on is kept per camera, so after a restart it still shows and can be turned off. */
private val CameraModel.presetUndoKey: String? get() = savedCameras.firstOrNull()?.let { "presetOn.${it.id}" }

fun CameraModel.savePresetUndo() {
    val key = presetUndoKey ?: return
    val snapshot = presetUndo
    if (snapshot == null) {
        prefs.edit().remove(key).apply()
        return
    }
    val json = JSONObject().put("id", snapshot.id).put("title", snapshot.title).put("values", JSONObject(snapshot.values))
    prefs.edit().putString(key, json.toString()).apply()
}

/** After connecting: the setup that was on for this camera, so it can still be turned off. */
fun CameraModel.restorePresetUndo() {
    val key = presetUndoKey ?: return
    val text = prefs.getString(key, null) ?: return
    presetUndo = runCatching {
        val o = JSONObject(text)
        val values = o.getJSONObject("values")
        SettingsSnapshot(o.getString("id"), o.getString("title"), values.keys().asSequence().associateWith { values.getString(it) })
    }.getOrNull()
}

/**
 * Turns the setup off: puts back the settings from before it, the mode first, then whatever it lets
 * the app set (in A, for example, the camera picks the shutter itself again).
 */
suspend fun CameraModel.undoPreset() {
    val snapshot = presetUndo ?: return
    if (presetRunning) return
    presetRunning = true
    val missed = mutableListOf<String>()
    try {
        for (name in presetOrder) {
            val value = snapshot.values[name] ?: continue
            val property = properties[name] ?: continue
            if (property.value == value || !property.settable) continue
            if (!setProperty(name, value, reportErrors = false)) missed.add(PropertyFormat.title(name))
        }
    } finally {
        presetRunning = false
    }
    presetUndo = null
    savePresetUndo()
    presetSteps = emptyList()
    presetResultsFor = null
    if (missed.isEmpty()) showToast("Settings from before ${snapshot.title} are back")
    else lastError = "Couldn't put back: ${missed.joinToString(", ")}."
}

// MARK: - Astro

/** The sensor's crop factor, from the brand and model, for the 300/500 rules. */
val CameraModel.cropFactor: Double get() = cropFactor(brand, cameraName ?: "")

fun cropFactor(brand: CameraBrand, model: String): Double {
    val m = model.uppercase().replace(" ", "").replace("-", "")
    return when (brand) {
        CameraBrand.OLYMPUS -> 2.0
        // LUMIX S bodies (DC-S1, S1R, S1H, S5, S5 II, S9) are full frame; G, GH, GX, GF are Four Thirds.
        CameraBrand.PANASONIC -> if (listOf("DCS", "S1", "S5", "S9", "LUMIXS").any { m.startsWith(it) }) 1.0 else 2.0
        CameraBrand.NIKON -> {
            // Full frame: Z5, Z6 (II, III), Z7, Z8, Z9, Zf and the FX DSLRs. Z50, Z30, Zfc and D3xxx–D7xxx are DX.
            val name = m.replace("NIKON", "")
            val fullFrame = listOf("Z5", "Z6", "Z7", "Z8", "Z9", "ZF", "D3", "D4", "D5", "D6", "D600", "D610", "D700",
                "D750", "D780", "D800", "D810", "D850", "DF")
            val isFullFrame = fullFrame.any { body ->
                listOf("", "_", "II", "S", "X", "E", "H").any { suffix ->
                    name == body + suffix || (suffix.isNotEmpty() && name.startsWith(body + suffix) && suffix != "S")
                }
            }
            if (isFullFrame) 1.0 else 1.5
        }
        CameraBrand.CANON -> {
            val name = m.replace("CANON", "").replace("EOS", "")
            when {
                // Full frame: R, RP, and R1, R3, R5 (II, C), R6 (II, "R6m2"), R8, but not R10, R50, R100 or R7.
                name in setOf("R", "RP") || Regex("^R[13568](?![0-9])").containsMatchIn(name) ||
                    name.startsWith("5D") || name.startsWith("6D") || name.startsWith("1D") -> 1.0
                name.startsWith("POWERSHOT") || name.startsWith("G") || name.startsWith("SX") -> 2.7
                else -> 1.6
            }
        }
        CameraBrand.SONY -> {
            // a7 / a9 / a1 (ILCE-7…, -9, -1) and RX1 are full frame; RX100 and RX10 have 1-inch sensors.
            val name = m.replace("SONY", "")
            val rx10 = listOf("DSCRX10", "RX10").any { name.startsWith(it) }
            when {
                listOf("ILCE7", "ILCE9", "ILCE1", "A7", "A9", "A1", "DSCRX1", "RX1").any { name.startsWith(it) } && !rx10 -> 1.0
                rx10 -> 2.7
                // ZV-E1 is full frame, ZV-E10 APS-C.
                name.startsWith("ZVE1") && !name.startsWith("ZVE10") -> 1.0
                else -> 1.5
            }
        }
    }
}

/**
 * Slowest available shutter that still keeps stars round. For trails, Live Composite where the camera
 * has it, else 30 s frames for the interval timer to shoot back to back.
 */
fun CameraModel.astroShutter(plan: AstroPlan): String? {
    if (plan.trails && hasLiveComposite) return properties["shutspeedvalue"]?.options?.firstOrNull { it.lowercase() == "livecomp" }
    val longest = if (plan.trails) 30.0 else plan.maxSeconds
    return timedShutters.filter { it.second <= longest }.maxByOrNull { it.second }?.first
}

/** Star trails without Live Composite: about an hour of back-to-back frames, to stack afterwards. */
fun CameraModel.trailsSeries(plan: AstroPlan): IntervalPlan? {
    if (!plan.trails || hasLiveComposite) return null
    val frame = astroShutter(plan)?.let { PropertyFormat.seconds(it) } ?: 30.0
    val every = Math.rint(frame + 3)   // a few seconds to save each frame
    return IntervalPlan(count = Math.round(3600 / every).toInt(), seconds = every)
}

/** Starts the star-trail series, and leaves the same plan in the Interval panel. */
fun CameraModel.startTrailsSeries(series: IntervalPlan) {
    prefs.edit().putInt("interval.count", series.count).putFloat("interval.seconds", series.seconds.toFloat())
        .putBoolean("interval.ramp", false).apply()
    startInterval(series)
}

val CameraModel.widestAperture: String? get() = apertures.minByOrNull { it.second }?.first

fun CameraModel.nearestIso(target: Int): String? =
    properties["isospeedvalue"]?.options?.mapNotNull { o -> o.toIntOrNull()?.let { o to it } }
        ?.minByOrNull { abs(it.second - target) }?.first

val CameraModel.hasLiveComposite: Boolean
    get() = properties["shutspeedvalue"]?.options?.any { it.lowercase() == "livecomp" } == true

fun CameraModel.astroSteps(plan: AstroPlan): List<PresetStep> {
    // In A, S or P the camera locks aperture or shutter; once the preset has switched to M they open up.
    val (mode, inM) = modeStep("M", "So aperture and shutter can be set")
    val shutterDetail = when {
        !plan.trails -> fmt("Longest that keeps stars sharp at %d mm (≤ %.1f s)", plan.focalLength.toInt(), plan.maxSeconds)
        hasLiveComposite -> "Live Composite: stacks only new light, so stars draw trails"
        else -> "One frame of the series: the interval timer shoots them back to back, then stack them"
    }
    // About 4000 K keeps the night sky a neutral blue. Fluorescent is the nearest preset on most bodies;
    // LUMIX has none, so it falls back to Incandescent (about 3200 K, a cooler blue).
    val wbOptions = settableProperty("wbvalue")?.options ?: emptyList()
    val wbStep = when {
        "35" in wbOptions -> PresetStep("White balance ≈ 4000 K", "Neutral-blue night sky (Fluorescent preset)", "wbvalue", "35")
        "20" in wbOptions -> PresetStep("White balance ≈ 3200 K",
            "Cool-blue night sky (Incandescent: this camera has no 4000 K preset)", "wbvalue", "20")
        else -> PresetStep("White balance ≈ 4000 K", "Neutral-blue night sky", "wbvalue", null,
            unavailable = "Set about 4000 K on the camera, or shoot RAW and set it afterwards")
    }
    return listOf(
        mode,
        presetStep("Widest aperture", "Gather as much starlight as possible", "focalvalue", widestAperture, "M", inM),
        presetStep("Shutter", shutterDetail, "shutspeedvalue", astroShutter(plan), "M", inM),
        presetStep("ISO", "Bright enough for faint stars without too much noise", "isospeedvalue", nearestIso(plan.iso)),
        wbStep,
        antiShockStep(),
    )
}

/** Applies the night-sky settings; Undo in Presets puts the old ones back. */
suspend fun CameraModel.applyAstro(plan: AstroPlan): Boolean = runPreset(PresetRecipe.ASTRO.id, "Astro") { astroSteps(plan) }

// MARK: - Recipes

fun CameraModel.steps(recipe: PresetRecipe): List<PresetStep> = when (recipe) {
    PresetRecipe.ASTRO -> astroSteps(AstroPlan(cropFactor = cropFactor))
    PresetRecipe.MOON -> {
        val (mode, inM) = modeStep("M", "The moon is as bright as daylight: auto exposure burns it out")
        listOf(
            mode,
            presetStep("Aperture f/8", "Sharpest on most lenses", "focalvalue", aperture(8.0), "M", inM),
            presetStep("Shutter 1/250 s", "Freezes the moon's movement", "shutspeedvalue", shutter(1.0 / 250), "M", inM),
            presetStep("ISO 200", "Low noise: the moon is bright", "isospeedvalue", nearestIso(200)),
            presetStep("Daylight white balance", "The moon is lit by the sun", "wbvalue", option("wbvalue", listOf("18"))),
            antiShockStep(),
        )
    }
    PresetRecipe.FIREWORKS -> {
        val (mode, inM) = modeStep("M", "Auto exposure is fooled by a dark sky")
        val liveComposite = option("shutspeedvalue", listOf("livecomp"))
        val shutterStep = if (liveComposite != null)
            presetStep("Live Composite", "Each burst adds up without washing out the sky", "shutspeedvalue", liveComposite, "M", inM)
        else presetStep("Shutter 4 s", "Long enough for a whole burst", "shutspeedvalue", shutter(4.0), "M", inM)
        listOf(
            mode,
            presetStep("Aperture f/8", "Crisp, colourful trails", "focalvalue", aperture(8.0), "M", inM),
            shutterStep,
            presetStep("Lowest ISO", "Fireworks are bright; keep the sky black", "isospeedvalue", lowestIso),
            presetStep("Daylight white balance", "True firework colours", "wbvalue", option("wbvalue", listOf("18"))),
            antiShockStep(),
        )
    }
    PresetRecipe.LANDSCAPE -> {
        val (mode, inA) = modeStep("A", "You pick the depth of field, the camera the shutter")
        listOf(
            mode,
            presetStep("Aperture f/8", "Front-to-back sharpness on most lenses", "focalvalue", aperture(8.0), "A", inA),
            presetStep("Lowest ISO", "The cleanest files", "isospeedvalue", lowestIso),
            presetStep("Exposure ±0", "Start from the camera's metering", "expcomp", zeroEv, "A", inA),
            antiShockStep(),
        )
    }
    PresetRecipe.ACTION -> {
        val (mode, inS) = modeStep("S", "You pick the shutter, the camera the aperture")
        listOf(
            mode,
            presetStep("Shutter 1/1000 s", "Freezes running, sport and birds", "shutspeedvalue", shutter(1.0 / 1000), "S", inS),
            presetStep("Auto ISO", "Keeps the fast shutter as the light changes", "isospeedvalue", autoIso,
                unavailable = "Set Auto ISO on the camera"),
            presetStep("Exposure ±0", "Start from the camera's metering", "expcomp", zeroEv, "S", inS),
            presetStep("Fast continuous drive", "Hold the shutter for a burst", "drivemode",
                option("drivemode", listOf("continuous-H", "silent-continuous-H")),
                unavailable = "Set continuous shooting on the camera"),
        )
    }
    PresetRecipe.MACRO -> {
        val (mode, inA) = modeStep("A", "You pick the depth of field, the camera the shutter")
        listOf(
            mode,
            presetStep("Aperture f/8", "More depth without softening from diffraction", "focalvalue", aperture(8.0), "A", inA),
            presetStep("Lowest ISO", "The cleanest files", "isospeedvalue", lowestIso),
            presetStep("Exposure ±0", "Start from the camera's metering", "expcomp", zeroEv, "A", inA),
            antiShockStep("Close up, the smallest shake shows"),
        )
    }
    PresetRecipe.TRAILS -> {
        val (mode, inM) = modeStep("M", "The exposure stays fixed while the lights move")
        listOf(
            mode,
            presetStep("Aperture f/11", "Lets the shutter stay open longer", "focalvalue", aperture(11.0), "M", inM),
            presetStep("Shutter 15 s", "Long enough to draw trails and smooth water", "shutspeedvalue", shutter(15.0), "M", inM),
            presetStep("Lowest ISO", "The cleanest files, and the longest exposure", "isospeedvalue", lowestIso),
            antiShockStep(),
        )
    }
}

suspend fun CameraModel.apply(recipe: PresetRecipe): Boolean {
    val ok = runPreset(recipe.id, recipe.title) { steps(recipe) }
    if (ok && recipe != PresetRecipe.ASTRO) showToast("${recipe.title} settings applied")
    return ok
}

// MARK: - Saved presets

/** Saves what the app can set right now under `name`, for this camera brand. */
fun CameraModel.saveCurrentSettings(name: String) {
    val values = presetOrder.mapNotNull { key -> settableProperty(key)?.let { key to it.value } }.toMap()
    val saved = SavedPreset(name = name.trim().ifEmpty { "My preset" }, brand = brand.id, values = values)
    savedPresets = listOf(saved) + savedPresets
    SavedPresets.store(prefs, savedPresets)
    showToast("Saved \"${saved.name}\"")
}

val CameraModel.savedPresetsForCamera: List<SavedPreset> get() = savedPresets.filter { it.brand == brand.id }

fun CameraModel.steps(saved: SavedPreset): List<PresetStep> = buildList {
    var target: String? = null
    var inMode = false
    saved.values["takemode"]?.let { mode ->
        val option = settableProperty("takemode")?.options?.firstOrNull { it == mode }
        val already = properties["takemode"]?.value == mode
        target = mode.uppercase()
        inMode = option != null || already
        add(PresetStep("Mode", "As saved", "takemode", option ?: if (already) mode else null,
            unavailable = "Turn the camera's mode dial to ${PropertyFormat.display("takemode", mode)}"))
    }
    for (name in presetOrder.drop(1)) {
        val value = saved.values[name] ?: continue
        val offered = properties[name]?.options?.contains(value) == true
        add(presetStep(PropertyFormat.title(name), "As saved", name, if (offered) value else null, target, inMode,
            unavailable = if (offered) "Not settable in this mode" else "Not offered by the camera now"))
    }
}

suspend fun CameraModel.apply(saved: SavedPreset) {
    if (runPreset(saved.id, saved.name) { steps(saved) }) showToast("${saved.name} applied")
}

fun CameraModel.deleteSavedPreset(saved: SavedPreset) {
    savedPresets = savedPresets.filter { it.id != saved.id }
    SavedPresets.store(prefs, savedPresets)
}

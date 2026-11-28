package com.apexcommerce.shutterlink.camera

import android.graphics.Bitmap
import android.graphics.Color
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.net.InetAddress
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import kotlin.math.abs

/**
 * Debug builds only (port of SelfTest.swift): launched with the `selfTest` extra, runs one driver
 * through the whole flow against a mock camera and logs "SELFTEST PASS/FAIL …" lines (logcat tag
 * Shutterlink). It takes pictures and changes settings, so MainActivity only starts it for the Mac
 * running the mocks (10.0.2.2 from the emulator, or loopback).
 *
 *     adb shell am start -n com.apexcommerce.shutterlink/.MainActivity --es selfTest lumix --es host 10.0.2.2:8082
 */
object DriverSelfTest {
    private var failures = 0
    private lateinit var camera: CameraModel

    /** Logs one result and clears the camera's error, so each check sees only its own. */
    private fun check(name: String, ok: Boolean, detail: String = "") {
        if (!ok) failures++
        debugLog("SELFTEST ${if (ok) "PASS" else "FAIL"} $name $detail")
        camera.lastError = null
    }

    private suspend fun waitFor(seconds: Double, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + (seconds * 1000).toLong()
        while (!condition() && System.currentTimeMillis() < deadline) delay(100)
    }

    /** Starts a run that should take [count] pictures and stop by itself; checks it did, without an error. */
    private suspend fun shoots(name: String, count: Int, also: () -> Boolean = { true }, start: () -> Unit) {
        val before = camera.shotCounter
        start()
        waitFor(30.0) { !camera.interval.running && !camera.bracket.running }
        check(name, camera.shotCounter == before + count && camera.lastError == null && also(),
            "shots=${camera.shotCounter - before} ${camera.lastError ?: ""}")
    }

    /** A quick timed exposure: the settings test leaves 30 s shutters and −5 EV, ND leaves Bulb. */
    private suspend fun quickExposure() {
        if (camera.settableProperty("shutspeedvalue") != null) camera.shutter(1.0 / 250)?.let { camera.setProperty("shutspeedvalue", it) }
        if (camera.settableProperty("expcomp") != null) camera.zeroEv?.let { camera.setProperty("expcomp", it) }
        camera.lastError = null
    }

    /** The last preset's steps: "property=value", ":skip", or ":FAILED(why)" where the camera refused. */
    private fun presetSummary() = camera.presetSteps.joinToString(" ") { step ->
        when (val st = step.state) {
            PresetStep.State.Done -> "${step.property}=${step.value?.let { PropertyFormat.display(step.property, it) } ?: "-"}"
            is PresetStep.State.Skipped -> "${step.property}:skip"
            is PresetStep.State.Failed -> "${step.property}:FAILED(${st.reason})"
            else -> "${step.property}:${step.state}"
        }
    }

    suspend fun run(camera: CameraModel, brand: String, host: String) {
        this.camera = camera
        failures = 0
        camera.selectBrand(CameraBrand.fromId(if (brand == "lumix") "panasonic" else brand))   // null (for "auto") = auto-detect
        camera.host = host
        camera.connect()
        check("connect", camera.phase == ConnectionPhase.CONNECTED,
            "brand=${camera.brand.id} name=${camera.cameraName ?: "-"} error=${camera.lastError ?: "-"}")
        if (camera.phase != ConnectionPhase.CONNECTED) return finish()
        debugLog("SELFTEST INFO profile=${camera.profile?.name ?: "none"} support=${camera.profile?.support?.text ?: "-"} crop=${camera.cropFactor} note=${camera.cameraNote ?: "-"}")

        waitFor(8.0) { camera.liveFrame != null && camera.fps > 2 }
        check("live view", camera.liveFrame != null, "fps=${camera.fps} frame=${camera.frameWidth}x${camera.frameHeight}")

        val props = camera.properties.values.sortedBy { it.name }
        check("settings read", props.isNotEmpty(),
            props.joinToString(" ") { "${it.name}=${it.value}${if (it.settable) "" else "(ro)"}[${it.options.size}]" })
        if (camera.brand == CameraBrand.PANASONIC) {
            // The extra settings from the camera's own menu, with its names, and the mode dial.
            val drive = camera.properties["drivemode"]
            check("lumix menu settings", drive != null && camera.properties["colormode"] != null &&
                PropertyFormat.title("colormode") == "Photo Style" && camera.properties["takemode"] != null,
                "drive=${drive?.let { "${PropertyFormat.display("drivemode", it.value)} of ${it.options.size}" } ?: "-"} " +
                    "mode=${camera.properties["takemode"]?.value ?: "-"} " +
                    "extras=${LumixMenu.wanted.count { camera.properties[it.name] != null }} kelvin=${camera.properties[LumixMenu.KELVIN_NAME]?.options?.size ?: 0}")
        }
        val extras = if (camera.brand == CameraBrand.PANASONIC) listOf("drivemode", "colormode", "afmode", LumixMenu.KELVIN_NAME) else emptyList()
        for (name in listOf("expcomp", "focalvalue", "shutspeedvalue", "isospeedvalue", "wbvalue") + extras) {
            val p = camera.settableProperty(name) ?: continue
            val target = p.options.firstOrNull { it != p.value && !PropertyFormat.isOpenEnded(it) && it != "auto" } ?: continue
            val ok = camera.setProperty(name, target)
            check("set $name", ok && camera.properties[name]?.value == target,
                "${p.value} → $target, now ${camera.properties[name]?.value ?: "-"} ${camera.lastError ?: ""}")
        }

        if (camera.capabilities.tapToFocus) {
            camera.tapFocus(0.4, 0.6)
            check("tap focus", camera.lastError == null, "afState=${camera.liveInfo.afState} ${camera.lastError ?: ""}")
        }

        // This shot is also saved to the gallery (auto-save on just for it; LUMIX saves it when the card opens).
        val autoSaveWas = camera.autoSaveNewPhotos
        camera.changeAutoSave(true)
        val shots = camera.shotCounter
        camera.lastShot = null
        camera.shutterPressed()
        camera.shutterReleased()
        check("shoot", camera.shotCounter == shots + 1 && camera.lastError == null, camera.lastError ?: "")
        if (camera.capabilities.lastShotReview) {
            waitFor(5.0) { camera.lastShot != null }
            check("last-shot review", camera.lastShot != null)
        }
        waitFor(20.0) { camera.autoSavedCount > 0 || camera.autoSavePending > 0 }
        camera.autoSaveChain?.join()
        check("auto-save", camera.autoSavedCount > 0 || camera.autoSavePending > 0,
            "saved=${camera.autoSavedCount} pending=${camera.autoSavePending} ${camera.toast ?: ""}")
        val autoSavePending = camera.autoSavePending
        camera.changeAutoSave(false)

        if (camera.capabilities.movie) {
            if (camera.capabilities.videoSwitch) camera.videoMode = true
            camera.toggleMovie()
            val started = camera.isRecordingMovie
            delay(1000)
            camera.toggleMovie()
            check("movie", started && !camera.isRecordingMovie, camera.lastError ?: "")
            camera.videoMode = false
        }

        check("battery", camera.liveInfo.battery != null, "${camera.liveInfo.battery ?: "-"}%")

        quickExposure()
        shoots("interval", 2) { camera.startInterval(IntervalPlan(count = 2, seconds = 1.5)) }
        val plan = BracketPlan()
        camera.bracketSet(plan).onSuccess { set ->
            val original = camera.properties[set.property]?.value
            shoots("bracket", set.values.size, { camera.properties[set.property]?.value == original }) { camera.startBracket(plan) }
        }.onFailure { check("bracket", false, it.message ?: "") }
        if (camera.capabilities.focusDrive) shoots("focus stack", 3) { camera.startFocusStack(3, FocusStepSize.MEDIUM) }
        sceneChecks()
        wifiChecks()
        lumixChecks()
        liveViewChecks()
        shootingTools()

        if (camera.capabilities.cardBrowser) {
            if (autoSavePending > 0) camera.changeAutoSave(true)
            val savedBefore = camera.autoSavedCount
            camera.openGallery()
            check("card list", camera.images.isNotEmpty() && camera.galleryError == null,
                "${camera.images.size} files in ${camera.cardFolders.map { it.name }} ${camera.galleryError ?: ""}")
            if (autoSavePending > 0) {
                check("auto-save from card", camera.autoSavedCount > savedBefore && camera.autoSavePending == 0,
                    "saved=${camera.autoSavedCount - savedBefore} of $autoSavePending")
            }
            camera.images.firstOrNull { it.fileExtension in setOf("JPG", "JPEG") }?.let { first ->
                check("thumbnail", camera.thumbnail(first) != null, first.name)
                try {
                    val preview = camera.preview(first)
                    check("preview", preview.width > 0, "${preview.width}x${preview.height}")
                    val data = camera.downloadOriginal(first)
                    check("download", data.isNotEmpty(), "${first.name} ${data.size} bytes")
                } catch (e: Exception) {
                    check("preview/download", false, e.message ?: e.toString())
                }
            }
            camera.images.firstOrNull { it.fileExtension in MediaSaver.rawExtensions }?.let { raw ->
                val data = runCatching { camera.downloadOriginal(raw) }.getOrNull()
                check("download RAW", (data?.size ?: 0) > 100_000, "${raw.name} ${data?.size ?: 0} bytes")
            }
            camera.closeGallery()
            waitFor(8.0) { camera.liveViewRunning && camera.fps > 2 }
            check("live view after card", camera.liveViewRunning && camera.fps > 0, "fps=${camera.fps}")
        }
        camera.changeAutoSave(autoSaveWas)

        // After 5 s of live view the Request log has a LIVE line with the frame rates.
        val live = camera.log.lastOrNull { it.note && it.method == "LIVE" }
        check("live view log", live != null, live?.path ?: "no LIVE line")

        camera.disconnect()
        finish()
    }

    private fun finish() {
        debugLog("SELFTEST DONE failures=$failures")
    }

    /** Every preset, Undo, a saved preset, ND, the motion trigger and ETTR. */
    private suspend fun shootingTools() {
        // One-tap recipes (Astro with this body's crop factor): every step applies or says why it can't.
        for (recipe in PresetRecipe.entries) {
            val ok = camera.apply(recipe)
            check("preset ${recipe.id}", ok, presetSummary())
        }
        // Undo puts the mode back.
        camera.settableProperty("takemode")?.let { mode ->
            val before = mode.value
            camera.apply(PresetRecipe.MOON)
            camera.undoPreset()
            check("preset undo", camera.properties["takemode"]?.value == before && camera.lastError == null,
                "mode $before → ${camera.properties["takemode"]?.value} ${camera.lastError ?: ""}")
        }
        // A setup that's on is kept with the camera, so it can still be turned off after a restart.
        val undoWas = camera.presetUndo
        camera.presetUndo = SettingsSnapshot("selftest", "Self-test", mapOf("isospeedvalue" to "200"))
        camera.savePresetUndo()
        camera.presetUndo = null
        camera.restorePresetUndo()
        val restored = camera.isPresetOn("selftest") && camera.presetUndo?.values?.get("isospeedvalue") == "200"
        camera.presetUndo = undoWas
        camera.savePresetUndo()
        check("preset stays on", restored, "restored ${camera.savedCameras.firstOrNull()?.id ?: "no saved camera"}")

        camera.saveCurrentSettings("Self-test")
        camera.savedPresetsForCamera.firstOrNull()?.let { saved ->
            val ok = camera.runPreset(saved.id, saved.name) { camera.steps(saved) }
            check("saved preset", ok && saved.values.isNotEmpty(), "${saved.values.size} values: ${presetSummary()}")
            camera.deleteSavedPreset(saved)
        }

        // ND calculator: meter, 6 stops, set up.
        val meter = camera.meteredExposure
        if (meter != null) {
            val ok = camera.runPreset("nd", "ND filter") { camera.ndSteps(meter, 6) }
            check("nd setup", ok, "metered ${meter.seconds}s → ${ndSeconds(meter.seconds, 6)}s, shutter now ${camera.properties["shutspeedvalue"]?.value}")
        } else {
            check("nd setup", false, "no metered exposure")
        }

        // Motion trigger: the mock's frame number (bottom left) changes every frame, so a box over it must fire.
        quickExposure()
        waitFor(8.0) { camera.recentFrame != null }
        camera.motion = camera.motion.copy(region = NRect(0.17, 0.86, 0.18, 0.13), sensitivity = 1.0, cooldown = 1.0)
        val beforeMotion = camera.shotCounter
        var peak = 0.0
        camera.armMotion(true)
        waitFor(12.0) { peak = maxOf(peak, camera.motionLevel); camera.shotCounter != beforeMotion }
        camera.armMotion(false)
        waitFor(5.0) { !camera.isShooting }
        check("motion trigger", camera.shotCounter > beforeMotion,
            "shots=${camera.shotCounter - beforeMotion} peak=${fmt("%.4f", peak)} threshold=${camera.motion.threshold}")

        // Expose to the right: finishes, and leaves the setting as it found it if live view can't judge it.
        val evBefore = camera.properties["expcomp"]?.value
        camera.exposeToTheRight()
        check("ettr", !camera.ettrRunning,
            "ev ${evBefore ?: "-"} → ${camera.properties["expcomp"]?.value ?: "-"} ${camera.lastError ?: camera.toast ?: ""}")
    }

    /** Scene assistant: sky positions, the rules on made-up signals against this camera's settings, and ML Kit live. */
    private suspend fun sceneChecks() {
        fun utc(text: String) = java.time.Instant.parse(text).toEpochMilli()
        val noon = Astronomy.sky(utc("2026-06-21T12:00:00Z"), 51.48, 0.0)
        val fullMoon = Astronomy.sky(utc("2026-11-24T15:00:00Z"), 51.48, 0.0)
        val newMoon = Astronomy.sky(utc("2026-11-09T12:00:00Z"), 51.48, 0.0)
        check("sky positions", abs(noon.sunAltitude - 62) < 1.5 && fullMoon.moonIllumination > 0.95 && newMoon.moonIllumination < 0.05,
            fmt("sun %.1f° (≈62), full %.2f, new %.2f", noon.sunAltitude, fullMoon.moonIllumination, newMoon.moonIllumination))
        fun top(s: SceneSignals) = camera.sceneSuggestions(s).firstOrNull()?.id ?: "-"
        val night = top(SceneSignals(mapOf("night_sky" to 0.97f, "sky" to 0.97f), brightness = 0.004))
        val moon = top(SceneSignals(mapOf("moon" to 0.8f), brightness = 0.01))
        val water = top(SceneSignals(mapOf("waterfall" to 0.8f), brightness = 0.3))
        val bird = top(SceneSignals(mapOf("bird" to 0.7f), brightness = 0.25))
        val clipping = camera.sceneSuggestions(SceneSignals(brightness = 0.4, clipped = 0.06)).map { it.id }
        check("scene rules", night == "astro" && moon == "moon" && water == "water-nd" && bird == "bird" &&
            ("clipping" in clipping || camera.exposureChange(-2) == null),
            "night=$night moon=$moon water=$water bird=$bird clipping=$clipping")
        // ML Kit's labels map onto the same names (a dark "Sky" is a night sky), and say indoor or outdoor.
        val mapped = SceneLabels.fromMlKit(mapOf("Sky" to 0.9f, "Star" to 0.6f, "Waterfall" to 0.7f, "Bird" to 0.8f), brightness = 0.01)
        val daylightMoon = SceneLabels.fromMlKit(mapOf("Moon" to 0.6f, "Sky" to 0.9f), brightness = 0.3)
        val rooms = SceneLabels.fromMlKit(mapOf("Couch" to 0.7f, "Lampshade" to 0.5f), brightness = 0.1)
        val outside = SceneLabels.fromMlKit(mapOf("Mountain" to 0.8f, "Road" to 0.4f), brightness = 0.3)
        check("scene labels", mapped["night_sky"] == 0.9f && mapped["waterfall"] == 0.7f && mapped["bird"] == 0.8f &&
            "moon" !in daylightMoon && daylightMoon["blue_sky"] == 0.9f &&
            rooms["room"] == 0.7f && "outdoor" !in rooms && outside["outdoor"] == 0.8f && outside["mountain"] == 0.8f,
            "$mapped; daylight $daylightMoon; $rooms; $outside")
        waitFor(10.0) { camera.sceneSignals != null }
        check("scene analysis", camera.sceneSignals != null,
            "ML Kit: " + camera.sceneRawLabels.entries.sortedByDescending { it.value }.take(4).joinToString { "${it.key} ${fmt("%.2f", it.value)}" } +
                " → ${camera.sceneSignals?.labels?.keys} suggestion=${camera.sceneSuggestion?.id ?: "-"}")

        // Blur: movement at a slow shutter, not when still or already fast.
        val moving = camera.sceneSuggestions(SceneSignals(brightness = 0.2, motion = 0.1, shutter = 1.0 / 60)).map { it.id }
        val still = camera.sceneSuggestions(SceneSignals(brightness = 0.2, motion = 0.01, shutter = 1.0 / 60)).map { it.id }
        val fast = camera.sceneSuggestions(SceneSignals(brightness = 0.2, motion = 0.1, shutter = 1.0 / 1000)).map { it.id }
        check("scene movement", ("motion" in moving || camera.isOpenEndedShutter) && "motion" !in still && "motion" !in fast,
            "moving=$moving still=$still fast=$fast")
        // Camera shake is only suggested in P and A (the camera picks the shutter there).
        val modeWas = camera.properties["takemode"]?.value
        camera.settableProperty("takemode")?.options?.firstOrNull { it.uppercase() == "A" }?.let { camera.setProperty("takemode", it) }
        val shakeSignals = SceneSignals(brightness = 0.2, shutter = 1.0 / 15, focal35 = 100.0, iso = 200)
        val raised = camera.isoForSteadyShutter(1.0 / 15, 100.0, 200)
        val pa = camera.properties["takemode"]?.value?.uppercase() in setOf("P", "A")
        val shake = camera.sceneSuggestions(shakeSignals).firstOrNull { it.id == "shake" }
        check("scene shake", if (pa && raised != null) shake?.actionTitle == "ISO ${raised.second}" else shake == null,
            "mode=${camera.properties["takemode"]?.value ?: "-"} raised=${raised?.second ?: "-"} → ${shake?.detail ?: "none"}")
        if (modeWas != null && camera.properties["takemode"]?.value != modeWas) camera.setProperty("takemode", modeWas)
        // White balance: Auto for the lamp/tube/shade/cloud rules, then an indoor setting outdoors.
        val wbWas = camera.properties["wbvalue"]?.value
        camera.whiteBalanceOption(listOf("auto"))?.let { camera.setProperty("wbvalue", it) }
        val wb = camera.settableProperty("wbvalue")
        val wbAuto = wb != null && PropertyFormat.display("wbvalue", wb.value).contains("auto", ignoreCase = true)
        fun wbTop(s: SceneSignals) = camera.whiteBalanceSuggestions(s).firstOrNull()?.id ?: "-"
        fun expected(id: String, vararg keywords: String) = if (wbAuto && camera.whiteBalanceOption(keywords.toList()) != null) id else "-"
        val lamps = wbTop(SceneSignals(mapOf("room" to 0.8f), brightness = 0.1, cast = ColourCast(225.0, 200.0, 175.0)))
        val tubes = wbTop(SceneSignals(mapOf("room" to 0.8f), brightness = 0.1, cast = ColourCast(205.0, 210.0, 185.0)))
        val cloudy = wbTop(SceneSignals(mapOf("outdoor" to 0.8f), brightness = 0.3, cast = ColourCast(180.0, 190.0, 215.0)))
        // Shade needs the sun's position (from a location): without one, a frame this dark doesn't count as daytime.
        val shade = wbTop(SceneSignals(mapOf("outdoor" to 0.8f), brightness = 0.1, sky = noon, cast = ColourCast(180.0, 190.0, 215.0)))
        val neutral = wbTop(SceneSignals(mapOf("room" to 0.8f), brightness = 0.1, cast = ColourCast(200.0, 200.0, 200.0)))
        check("scene white balance", lamps == expected("wb-lamps", "incandescent", "tungsten") && tubes == expected("wb-tubes", "fluorescent") &&
            cloudy == expected("wb-cloudy", "cloudy", "overcast") && shade == expected("wb-shade", "shade") && neutral == "-",
            "wb=${wb?.let { PropertyFormat.display("wbvalue", it.value) } ?: "not settable"} lamps=$lamps tubes=$tubes cloudy=$cloudy shade=$shade neutral=$neutral")
        camera.whiteBalanceOption(listOf("fluorescent"))?.let { tube ->
            camera.setProperty("wbvalue", tube)
            val outdoors = wbTop(SceneSignals(mapOf("outdoor" to 0.8f), brightness = 0.3))
            check("scene white balance outdoors", outdoors == "wb-outdoors", "on ${PropertyFormat.display("wbvalue", tube)}: $outdoors")
        }
        if (wbWas != null && camera.properties["wbvalue"]?.value != wbWas) camera.setProperty("wbvalue", wbWas)
        fun frame(r: Int, g: Int, b: Int) = Bitmap.createBitmap(80, 60, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.rgb(r, g, b)) }
        val lampCast = FrameMeter.neutralCast(frame(225, 200, 175))
        check("colour cast", lampCast != null && abs(lampCast.red - 225) < 2 && lampCast.warmth > 0.08 && lampCast.orange > 0.04 &&
            FrameMeter.neutralCast(frame(250, 40, 40)) == null, "lamp=$lampCast")
    }

    /** The LUMIX menu reader, drive names and the other tables, on made-up input (no camera needed). */
    private fun lumixChecks() {
        val menu = MiniXml.parse("""<camrply><result>ok</result><menuset model="G7"><photosettings><menu>
            <item id="menu_item_id_ph_sty" title_id="title_ph_sty" func_type="select"><group>
            <item id="menu_item_id_ph_sty_standard" title_id="title_ph_sty_standard" cmd_mode="setsetting" cmd_type="colormode" cmd_value="standard" cmd_value2="__value__"/>
            <item id="menu_item_id_ph_sty_vivid" title_id="title_ph_sty_vivid" cmd_mode="setsetting" cmd_type="colormode" cmd_value="vivid" cmd_value2="__value__"/>
            </group></item></menu></photosettings><qmenu2><menu>
            <item id="menu_item_id_whitebalance" title_id="title_whitebalance" func_type="sp_embeded_whitebalance"><group>
            <item id="menu_item_id_whitebalance_auto" cmd_mode="setsetting" cmd_type="whitebalance" cmd_value="auto"/>
            <item id="menu_item_id_whitebalance_color_temp" min_val="2500" max_val="10000" step_val="100" cmd_mode="setsetting" cmd_type="whitebalance" cmd_value="color_temp" cmd_value2="__value__"/>
            </group></item>
            <item id="menu_item_id_1shoot" title_id="title_1shoot" cmd_mode="setsetting" cmd_type="drivemode" cmd_value="normal"/>
            <item id="menu_item_id_burst" title_id="title_burst" func_type="select" cmd_mode="setsetting" cmd_type="drivemode" cmd_value="burst"><group>
            <item id="menu_item_id_burst_h" title_id="title_burst_h" cmd_mode="setsetting" cmd_type="drivemode" cmd_value="burst" cmd_value2="h"/>
            </group></item>
            <item id="menu_item_id_selftimer" title_id="title_selftimer" func_type="select" cmd_mode="setsetting" cmd_type="drivemode" cmd_value="selftimer"><group>
            <item id="menu_item_id_selftimer_2sec" title_id="title_selftimer_2sec" cmd_mode="setsetting" cmd_type="drivemode" cmd_value="selftimer" cmd_value2="2sec"/>
            </group></item></menu></qmenu2>
            <titlelist><language code="en" default="yes"><title id="title_ph_sty">Photo Style</title>
            <title id="title_ph_sty_standard">Standard</title><title id="title_ph_sty_vivid">Vivid</title>
            <title id="title_1shoot">Single</title><title id="title_burst">Burst Shooting</title><title id="title_burst_h">H</title>
            <title id="title_selftimer">Self Timer</title><title id="title_selftimer_2sec">2sec.</title>
            </language></titlelist></menuset></camrply>""")
        val parsed = menu?.let { LumixMenu.parse(it) }
        val drive = parsed?.settings?.firstOrNull { it.name == "drivemode" }
        val style = parsed?.settings?.firstOrNull { it.name == "colormode" }
        val kelvin = parsed?.kelvin
        check("lumix menu", parsed != null && drive != null && style != null && kelvin != null &&
            parsed.settings.map { it.name } == listOf("drivemode", "colormode") &&
            drive.options == listOf("normal", "burst|h", "selftimer|2sec") &&
            drive.labels["burst|h"] == "Burst H" && drive.labels["burst"] == "Burst" && drive.labels["selftimer|2sec"] == "Self-timer 2 s" &&
            drive.optionItems["burst|h"] == listOf("menu_item_id_burst_h", "menu_item_id_burst") &&
            style.options == listOf("standard", "vivid") && style.labels["vivid"] == "Vivid" &&
            style.headingItems == listOf("menu_item_id_ph_sty") &&
            kelvin.options.size == 76 && kelvin.itemId == "menu_item_id_whitebalance_color_temp",
            "settings=${parsed?.settings?.map { "${it.name}${it.options}" }} labels=${drive?.labels} kelvin=${parsed?.kelvin}")

        val state = MiniXml.parse("""<camrply><result>ok</result><menuinfo><item id="menu_item_id_recmode" enable="yes" value="manual_exposure" />
            <item id="menu_item_id_crtv_ctrl" enable="no" /></menuinfo></camrply>""")?.let { LumixMenu.parseState(it) } ?: emptyMap()
        check("lumix curmenu", state["menu_item_id_crtv_ctrl"]?.enabled == false && state["menu_item_id_recmode"]?.enabled == true &&
            state["menu_item_id_recmode"]?.value?.let { PanasonicDriver.lumixMode(it) } == "M" &&
            PanasonicDriver.lumixMode("aperture_ae") == "A" && PanasonicDriver.lumixMode("custom_1") == "Custom 1",
            "$state")
        val keys = listOf(
            PanasonicDriver.optionKey("burst", "h", listOf("normal", "burst|h")),
            PanasonicDriver.optionKey("burst", null, listOf("burst|h")),
            PanasonicDriver.optionKey("selftimer", "10sec", listOf("selftimer|2sec")),
        )
        val labels = listOf(LumixMenu.driveLabel("autobracket|3shot_1/3ev"), LumixMenu.driveLabel("4k_photo|pre_burst"), LumixMenu.driveLabel("odd|thing"))
        val strip = listOf("burst|h", "selftimer|10sec3shot", "lowvib-normal", "silent-continuous-H", "normal", "").map { driveShort(it) }
        check("drive names", keys == listOf("burst|h", "burst", "selftimer|10sec") &&
            labels == listOf("Bracket 3 × 1/3 EV", "4K Pre-Burst", null) &&
            strip == listOf("Burst H", "Timer 10s×3", "Anti-shock", "Silent Cont H", "Single", "–"),
            "keys=$keys labels=$labels strip=$strip")

        // Crop factors for the bodies the tables used to get wrong, and Sony's newer bodies.
        val crops = listOf(cropFactor(CameraBrand.CANON, "Canon EOS R6m2"), cropFactor(CameraBrand.CANON, "Canon EOS R10"),
            cropFactor(CameraBrand.CANON, "EOS R50"), cropFactor(CameraBrand.CANON, "EOS R8"), cropFactor(CameraBrand.CANON, "EOS R7"),
            cropFactor(CameraBrand.SONY, "ZV-E1"), cropFactor(CameraBrand.SONY, "ZV-E10"))
        check("crop factors", crops == listOf(1.0, 1.6, 1.6, 1.0, 1.6, 1.0, 1.5) &&
            SonyDriver.isNewerBody("ILCE-7M4") && !SonyDriver.isNewerBody("ILCE-6000"), "$crops")
    }

    /** Live view's skip-to-newest and its Request log line, without a camera. */
    private suspend fun liveViewChecks() {
        val stats = LiveViewStats(since = 0).apply {
            completed = 48; stale = 2; dropped = 1; jpegBytes = 48L * 9 * 1024; frameWidth = 320; frameHeight = 240
        }
        val line = stats.plainSummary(until = 2000)
        check("live view summary", line == "320×240 · 25.0 frames/s from the camera, 24.0/s shown, 1 unreadable, 2 stale, 9 KB each (last 2 s)", line)

        // Three datagrams already waiting: the reader returns the third and counts two as passed over.
        val newest = withContext(Dispatchers.IO) {
            runCatching {
                val channel = DatagramChannel.open().bind(InetSocketAddress(InetAddress.getLoopbackAddress(), 0))
                DatagramReader(channel).use { reader ->
                    DatagramChannel.open().use { sender ->
                        for (i in 1..3) sender.send(ByteBuffer.wrap(byteArrayOf(i.toByte(), 0x55)), channel.localAddress)
                    }
                    Thread.sleep(150)
                    val count = reader.receive(300, newest = true)
                    Triple(count, reader.buffer.array()[0].toInt(), reader.skipped)
                }
            }.getOrElse { e -> debugLog("SELFTEST live view reader: $e"); null }
        }
        check("live view newest datagram", newest == Triple(2, 3, 2), "length, first byte, skipped = $newest")
    }

    /**
     * One-tap Wi-Fi joining without a camera: the QR formats (the Olympus example is a real PEN-F's code
     * and the name and password it shows) and the Keystore password store.
     */
    private fun wifiChecks() {
        val penf = WifiQrCode.parse("OIS1,GRI1Q1G1UOIV-YZW%,\$/Y/*Z\$/")
        val std = WifiQrCode.parse("WIFI:S:My\\;Cam;T:WPA;P:pass:word;;")
        val sony = WifiQrCode.parse("W01:S:AbCd;P:secret12;C:ILCE-6000;M:00AABBCCDDEE;")
        check("wifi qr", penf == WifiCredentials("PEN-F-P-BHNA17694", "50703650") &&
            WifiQrCode.brand("OIS1,GRI1Q1G1UOIV-YZW%,x") == CameraBrand.OLYMPUS &&
            std == WifiCredentials("My;Cam", "pass:word") && WifiQrCode.brand("WIFI:S:x;;") == null &&
            sony == WifiCredentials("DIRECT-AbCd", "secret12") && WifiQrCode.brand("W01:S:x;P:y;") == CameraBrand.SONY &&
            WifiQrCode.parse("https://example.com") == null,
            "penf=$penf std=$std sony=$sony")
        val ssid = "SELFTEST-NETWORK"
        CameraWifiPasswords.save(camera, "p@ss word 123", ssid)
        val stored = CameraWifiPasswords.password(camera, ssid)
        val plain = camera.prefs.all.values.any { it.toString().contains("p@ss word 123") }
        CameraWifiPasswords.delete(camera, ssid)
        check("wifi password store", stored == "p@ss word 123" && !plain && CameraWifiPasswords.password(camera, ssid) == null,
            "round trip ${stored == "p@ss word 123"}, stored in plain text $plain")
    }
}

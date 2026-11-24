package com.apexcommerce.shutterlink.camera

import kotlinx.coroutines.delay
import kotlin.math.abs

/**
 * Debug builds only (port of SelfTest.swift): launched with the `selfTest` extra, runs one driver
 * through the whole flow against a mock camera and logs "SELFTEST PASS/FAIL …" lines (logcat tag
 * Shutterlink). It takes pictures and changes settings, so it refuses anything but the Mac running
 * the mocks (10.0.2.2 from the emulator, or loopback).
 *
 *     adb shell am start -n com.apexcommerce.shutterlink/.MainActivity --es selfTest lumix --es host 10.0.2.2:8082
 */
object DriverSelfTest {
    private var failures = 0

    private fun check(name: String, ok: Boolean, detail: String = "") {
        if (!ok) failures++
        debugLog("SELFTEST ${if (ok) "PASS" else "FAIL"} $name $detail")
    }

    private suspend fun waitFor(seconds: Double, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + (seconds * 1000).toLong()
        while (!condition() && System.currentTimeMillis() < deadline) delay(100)
    }

    suspend fun run(camera: CameraModel, brand: String, host: String) {
        if (!CameraNetwork.isLocalTestHost(host)) {
            debugLog("SELFTEST refused: $host is not the Mac running the mocks")
            return
        }
        failures = 0
        val wanted = CameraBrand.fromId(if (brand == "lumix") "panasonic" else brand)
        camera.selectBrand(wanted)   // null (for "auto") = auto-detect
        camera.host = host
        camera.connect()
        check("connect", camera.phase == ConnectionPhase.CONNECTED,
            "brand=${camera.brand.id} name=${camera.cameraName ?: "-"} error=${camera.lastError ?: "-"}")
        if (camera.phase != ConnectionPhase.CONNECTED) return finish()
        if (wanted != null) check("brand", camera.brand == wanted, camera.brand.id)
        debugLog("SELFTEST INFO profile=${camera.profile?.name ?: "none"} support=${camera.profile?.support?.text ?: "-"} note=${camera.cameraNote ?: "-"}")

        waitFor(8.0) { camera.liveFrame != null && camera.fps > 2 }
        check("live view", camera.liveFrame != null, "fps=${camera.fps} frame=${camera.frameWidth}x${camera.frameHeight}")

        val props = camera.properties.values.sortedBy { it.name }
        check("settings read", props.isNotEmpty(),
            props.joinToString(" ") { "${it.name}=${it.value}${if (it.settable) "" else "(ro)"}[${it.options.size}]" })
        for (name in listOf("expcomp", "focalvalue", "shutspeedvalue", "isospeedvalue", "wbvalue")) {
            val p = camera.properties[name] ?: continue
            if (!p.settable) continue
            val target = p.options.firstOrNull { it != p.value && !PropertyFormat.isOpenEnded(it) && it != "auto" } ?: continue
            val ok = camera.setProperty(name, target)
            check("set $name", ok && camera.properties[name]?.value == target,
                "${p.value} → $target, now ${camera.properties[name]?.value ?: "-"} ${camera.lastError ?: ""}")
            camera.lastError = null
        }

        if (camera.capabilities.tapToFocus) {
            camera.tapFocus(0.4, 0.6)
            check("tap focus", camera.lastError == null, "afState=${camera.liveInfo.afState} ${camera.lastError ?: ""}")
            camera.lastError = null
        }

        // This shot is also saved to the gallery (auto-save on just for it; LUMIX saves it when the card opens).
        val autoSaveWas = camera.autoSaveNewPhotos
        camera.changeAutoSave(true)
        val shots = camera.shotCounter
        camera.lastShot = null
        camera.shutterPressed()
        camera.shutterReleased()
        check("shoot", camera.shotCounter == shots + 1 && camera.lastError == null, camera.lastError ?: "")
        camera.lastError = null
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
            camera.lastError = null
            camera.videoMode = false
        }

        check("battery", camera.liveInfo.battery != null, "${camera.liveInfo.battery ?: "-"}%")

        shootingTools(camera)

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

        camera.disconnect()
        check("disconnect", camera.phase == ConnectionPhase.DISCONNECTED)
        finish()
    }

    /** Interval, bracket, focus stack, presets, Undo, a saved preset, ND, the motion trigger and ETTR. */
    private suspend fun shootingTools(camera: CameraModel) {
        // The settings test leaves values at the ends of their ranges (30 s shutters, −5 EV).
        // Put back a quick exposure so the interval and bracket frames don't each take half a minute.
        camera.settableProperty("shutspeedvalue")?.let { _ -> camera.shutter(1.0 / 250)?.let { camera.setProperty("shutspeedvalue", it) } }
        camera.settableProperty("expcomp")?.let { _ -> camera.zeroEv?.let { camera.setProperty("expcomp", it) } }
        camera.lastError = null

        // Interval timer: two frames, then it stops by itself.
        val beforeInterval = camera.shotCounter
        camera.startInterval(IntervalPlan(count = 2, seconds = 1.5))
        waitFor(20.0) { !camera.interval.running }
        check("interval", camera.shotCounter == beforeInterval + 2 && camera.lastError == null,
            "shots=${camera.shotCounter - beforeInterval} running=${camera.interval.running} ${camera.lastError ?: ""}")
        camera.lastError = null

        // Exposure bracket: three frames, then the setting goes back.
        val beforeBracket = camera.shotCounter
        val plan = BracketPlan()
        camera.bracketSet(plan).onSuccess { set ->
            val original = camera.properties[set.property]?.value
            camera.startBracket(plan)
            waitFor(30.0) { !camera.bracket.running }
            check("bracket", camera.shotCounter == beforeBracket + set.values.size && camera.lastError == null &&
                camera.properties[set.property]?.value == original,
                "${set.property} ${set.values} shots=${camera.shotCounter - beforeBracket} now=${camera.properties[set.property]?.value} ${camera.lastError ?: ""}")
        }.onFailure { check("bracket", false, it.message ?: "") }
        camera.lastError = null

        // Focus stack: three frames with the focus stepped farther between them, where the camera can.
        if (camera.capabilities.focusDrive) {
            val beforeStack = camera.shotCounter
            camera.startFocusStack(3, FocusStepSize.MEDIUM)
            waitFor(30.0) { !camera.bracket.running }
            check("focus stack", camera.shotCounter == beforeStack + 3 && camera.lastError == null,
                "shots=${camera.shotCounter - beforeStack} ${camera.lastError ?: ""}")
            camera.lastError = null
        } else {
            debugLog("SELFTEST INFO focus stack not offered by this camera")
        }

        // Astro preset: every step either takes or says why it was skipped; none is refused.
        camera.applyAstro(AstroPlan(cropFactor = camera.cropFactor))
        debugLog("SELFTEST INFO astro crop factor ${camera.cropFactor} for ${camera.cameraName}")
        camera.presetSteps.forEach { step ->
            debugLog("SELFTEST INFO astro ${step.title} → ${step.value?.let { PropertyFormat.display(step.property, it) } ?: "-"} ${step.state}")
        }
        val refused = camera.presetSteps.filter { it.state is PresetStep.State.Failed }
        check("astro preset", refused.isEmpty(), refused.joinToString { it.title })

        // Scene assistant: sky positions against known dates, rules against known scenes, and live analysis.
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
        // ML Kit's labels map onto the same names (a dark "Sky" is a night sky).
        val mapped = SceneLabels.fromMlKit(mapOf("Sky" to 0.9f, "Star" to 0.6f, "Waterfall" to 0.7f, "Bird" to 0.8f), brightness = 0.01)
        val daylightMoon = SceneLabels.fromMlKit(mapOf("Moon" to 0.6f, "Sky" to 0.9f), brightness = 0.3)
        check("scene labels", mapped["night_sky"] == 0.9f && mapped["waterfall"] == 0.7f && mapped["bird"] == 0.8f &&
            "moon" !in daylightMoon && daylightMoon["blue_sky"] == 0.9f, "$mapped; daylight $daylightMoon")
        waitFor(10.0) { camera.sceneSignals != null }
        check("scene analysis", camera.sceneSignals != null,
            "ML Kit: " + camera.sceneRawLabels.entries.sortedByDescending { it.value }.take(4).joinToString { "${it.key} ${fmt("%.2f", it.value)}" } +
                " → ${camera.sceneSignals?.labels?.keys} suggestion=${camera.sceneSuggestion?.id ?: "-"}")
        camera.sceneSignals?.let { live ->
            debugLog("SELFTEST INFO scene live motion=${fmt("%.3f", live.motion)} cast=${live.cast?.let { fmt("%.0f/%.0f/%.0f warmth %.2f", it.red, it.green, it.blue, it.warmth) } ?: "-"}" +
                " shutter=${live.shutter?.let(::shutterText) ?: "-"} focal35=${live.focal35 ?: "-"} iso=${live.iso ?: "-"}")
        }

        // Blur and white balance (port of today's iOS rules), on made-up signals against this camera's settings.
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
        val lampFrame = android.graphics.Bitmap.createBitmap(80, 60, android.graphics.Bitmap.Config.ARGB_8888).apply {
            eraseColor(android.graphics.Color.rgb(225, 200, 175))
        }
        val redFrame = android.graphics.Bitmap.createBitmap(80, 60, android.graphics.Bitmap.Config.ARGB_8888).apply {
            eraseColor(android.graphics.Color.rgb(250, 40, 40))
        }
        val lampCast = FrameMeter.neutralCast(lampFrame)
        check("colour cast", lampCast != null && abs(lampCast.red - 225) < 2 && lampCast.warmth > 0.08 && lampCast.orange > 0.04 &&
            FrameMeter.neutralCast(redFrame) == null, "lamp=$lampCast")
        val rooms = SceneLabels.fromMlKit(mapOf("Couch" to 0.7f, "Lampshade" to 0.5f), brightness = 0.1)
        val outside = SceneLabels.fromMlKit(mapOf("Mountain" to 0.8f, "Road" to 0.4f), brightness = 0.3)
        check("indoor/outdoor labels", rooms["room"] == 0.7f && "outdoor" !in rooms && outside["outdoor"] == 0.8f && outside["mountain"] == 0.8f,
            "$rooms; $outside")
        wifiChecks(camera)

        // One-tap recipes: every step applies or says why it can't; none is refused.
        for (recipe in PresetRecipe.entries.filter { it != PresetRecipe.ASTRO }) {
            val ok = camera.apply(recipe)
            val summary = camera.presetSteps.joinToString(" ") { step ->
                val value = step.value?.let { PropertyFormat.display(step.property, it) } ?: "-"
                when (val st = step.state) {
                    PresetStep.State.Done -> "${step.property}=$value"
                    is PresetStep.State.Skipped -> "${step.property}:skip"
                    is PresetStep.State.Failed -> "${step.property}:FAILED(${st.reason})"
                    else -> "${step.property}:${step.state}"
                }
            }
            check("preset ${recipe.id}", ok, summary)
        }

        // Undo puts the mode back.
        camera.properties["takemode"]?.takeIf { it.settable }?.let { mode ->
            val before = mode.value
            camera.apply(PresetRecipe.MOON)
            camera.undoPreset()
            check("preset undo", camera.properties["takemode"]?.value == before && camera.lastError == null,
                "mode $before → ${camera.properties["takemode"]?.value} ${camera.lastError ?: ""}")
            camera.lastError = null
        }

        // Saved preset round trip.
        camera.saveCurrentSettings("Self-test")
        camera.savedPresetsForCamera.firstOrNull()?.let { saved ->
            camera.apply(saved)
            val refusedSaved = camera.presetSteps.filter { it.state is PresetStep.State.Failed }
            check("saved preset", refusedSaved.isEmpty() && saved.values.isNotEmpty(),
                "${saved.values.size} values, refused: ${refusedSaved.map { it.property }}")
            camera.deleteSavedPreset(saved)
        }

        // ND calculator: meter, 6 stops, set up.
        val meter = camera.meteredExposure
        if (meter != null) {
            val ok = camera.runPreset("nd", "ND filter") { camera.ndSteps(meter, 6) }
            check("nd setup", ok, "metered ${meter.seconds}s → ${ndSeconds(meter.seconds, 6)}s, shutter now ${camera.properties["shutspeedvalue"]?.value}")
        } else {
            check("nd meter", false, "no metered exposure")
        }

        // The ND step may have left a Bulb shutter; the trigger needs a timed one.
        if (camera.settableProperty("shutspeedvalue") != null) camera.shutter(1.0 / 250)?.let { camera.setProperty("shutspeedvalue", it) }
        waitFor(8.0) { camera.recentFrame != null }

        // Motion trigger: the mock's frame number (bottom left) changes every frame, so a box over it must fire.
        camera.motion = camera.motion.copy(region = NRect(0.17, 0.86, 0.18, 0.13), sensitivity = 1.0, cooldown = 1.0)
        val beforeMotion = camera.shotCounter
        camera.armMotion(true)
        var peak = 0.0
        val deadline = System.currentTimeMillis() + 12_000
        while (camera.shotCounter == beforeMotion && System.currentTimeMillis() < deadline) {
            peak = maxOf(peak, camera.motionLevel)
            delay(100)
        }
        camera.armMotion(false)
        waitFor(5.0) { !camera.isShooting }
        check("motion trigger", camera.shotCounter > beforeMotion,
            "shots=${camera.shotCounter - beforeMotion} peak=${fmt("%.4f", peak)} threshold=${camera.motion.threshold}")

        // Expose to the right: finishes, and leaves the setting as it found it if live view can't judge it.
        val evBefore = camera.properties["expcomp"]?.value
        camera.exposeToTheRight()
        debugLog("SELFTEST INFO ettr ev ${evBefore ?: "-"} → ${camera.properties["expcomp"]?.value ?: "-"} ${camera.lastError ?: camera.toast ?: ""}")
        check("ettr", !camera.ettrRunning)
        camera.lastError = null
    }

    private fun finish() {
        debugLog("SELFTEST DONE failures=$failures")
    }

    /**
     * One-tap Wi-Fi joining without a camera: the QR formats (the Olympus example is a real PEN-F's code
     * and the name and password it shows) and the Keystore password store.
     */
    private fun wifiChecks(camera: CameraModel) {
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

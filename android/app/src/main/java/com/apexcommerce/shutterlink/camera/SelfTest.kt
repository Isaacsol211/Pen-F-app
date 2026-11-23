package com.apexcommerce.shutterlink.camera

import kotlinx.coroutines.delay

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

        if (camera.capabilities.cardBrowser) {
            camera.openGallery()
            check("card list", camera.images.isNotEmpty() && camera.galleryError == null,
                "${camera.images.size} files in ${camera.cardFolders.map { it.name }} ${camera.galleryError ?: ""}")
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

        camera.disconnect()
        check("disconnect", camera.phase == ConnectionPhase.DISCONNECTED)
        finish()
    }

    private fun finish() {
        debugLog("SELFTEST DONE failures=$failures")
    }
}

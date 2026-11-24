package com.apexcommerce.shutterlink.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.IOException
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs

// Olympus / OM System over the camera's own Wi-Fi (the OI.Share / OM Image Share protocol); port of
// OlympusDriver.swift. Same HTTP commands across OM-D, PEN, TG and OM System bodies; what differs per
// model is listed by the camera itself in get_commandlist.cgi and in the property list (desclist).

class OlympusDriver(private val camera: CameraModel) : CameraDriver {
    val client = camera.makeHttpClient(camera.userAgent)
    private var loggedDescList = false

    override val liveViewFormat get() = LiveViewFormat.OLYMPUS_RTP

    override val capabilities: CameraCapabilities
        get() = CameraCapabilities(
            liveViewSizes = liveViewSizes, tapToFocus = true, openEndedExposure = true, movie = true,
            videoSwitch = false, lastShotReview = true, clockSync = true,
            highResShot = camera.profile?.highResShot ?: camera.cameraName?.let(::hasHighResShot) ?: true,
            cardBrowser = true, powerOff = true, userAgentChoice = true,
        )

    private val commands get() = camera.commands

    val liveViewSizes: List<String>
        get() = commands.liveViewSizes.ifEmpty { CameraBrand.OLYMPUS.defaultLiveViewSizes }

    companion object {
        /** For bodies missing from ModelProfiles: High Res Shot is on the PEN-F, E-M5 II/III, E-M1 II/III/X and OM bodies. */
        fun hasHighResShot(model: String): Boolean {
            val m = model.uppercase().replace(" ", "").replace("-", "")
            if (m.contains("EM10") || m.contains("EPL") || m.contains("EP5") || m.contains("EP7") || m.startsWith("TG") ||
                m.startsWith("SH") || m.startsWith("STYLUS") || m == "EM1") return false
            return true
        }

        fun decode(data: ByteArray): Bitmap? = runCatching { BitmapFactory.decodeByteArray(data, 0, data.size) }.getOrNull()
    }

    // MARK: - Connect

    override suspend fun connect() {
        // The camera can be slow right after its Wi-Fi comes up, so retry a little.
        var reply: ByteArray? = null
        var failure: Exception? = null
        for (attempt in 1..3) {
            try {
                reply = client.get("get_connectmode", timeout = 5.0)
                break
            } catch (e: Exception) {
                failure = e
                if (attempt >= 3 || e !is IOException || e is CameraHttpException) break
                camera.status = "No answer yet, retrying (${attempt + 1}/3)…"
                delay(1500)
            }
        }
        if (reply == null) throw failure ?: CameraException("No reply from the camera.")
        camera.connectMode = MiniXml.parse(reply)?.trimmedText

        camera.status = "Reading camera info…"
        runCatching { client.get("get_caminfo") }.getOrNull()?.let { info ->
            val reported = MiniXml.parse(info)?.value("model")
            camera.profile = ModelProfiles.find(CameraBrand.OLYMPUS, reported)
            camera.cameraName = camera.profile?.name ?: reported
            debugLog("Olympus model ${reported ?: "?"} → ${camera.profile?.name ?: "not in the model table"}")
            camera.profile?.unsupportedReason?.let { throw CameraException(it) }
        }
        runCatching { client.get("get_commandlist") }.getOrNull()?.let { list ->
            camera.rawCommandList = String(list)
            camera.commands = CommandList(MiniXml.parse(list))
        }
        loggedDescList = false
        // A saved size this body doesn't offer (e.g. 1280×960 on an E-M10) would be refused.
        val sizes = commands.liveViewSizes
        if (sizes.isNotEmpty() && camera.liveViewQuality !in sizes) {
            camera.liveViewQuality = if ("0640x0480" in sizes) "0640x0480" else sizes.first()
        }
    }

    override fun teardown() {}

    override suspend fun powerOff() {
        runCatching { client.get("switch_cammode", listOf("mode" to "play")) }
        runCatching { client.get("exec_pwoff") }
    }

    // MARK: - Modes & live view

    override suspend fun enterRecMode() {
        camera.isSwitchingMode = true
        try {
            // The PEN-F ignores a new live-view size while it's already in recording mode,
            // so go through playback first.
            if (camera.mode != CameraMode.PLAY) {
                client.get("switch_cammode", listOf("mode" to "play"))
                delay(300)
            }
            val params = mutableListOf("mode" to "rec")
            if (commands.liveViewSizes.isEmpty() || camera.liveViewQuality in commands.liveViewSizes) {
                params.add("lvqty" to camera.liveViewQuality)
            }
            client.get("switch_cammode", params)
            camera.mode = CameraMode.REC
            delay(400)
            camera.isSwitchingMode = false
            camera.refreshProperties()
            camera.startLiveView()
        } catch (e: Exception) {
            camera.report(e)
        } finally {
            camera.isSwitchingMode = false
        }
    }

    override suspend fun startLiveView() {
        try {
            val port = fmt("%05d", camera.udpPort)
            val reply = client.get("exec_takemisc", listOf("com" to "startliveview", "port" to port))
            debugLog("STARTLIVEVIEW reply: ${String(reply)}")
        } catch (e: Exception) {
            camera.liveViewRunning = false
            camera.report(e)
        }
    }

    override suspend fun stopLiveView() {
        runCatching { client.get("exec_takemisc", listOf("com" to "stopliveview")) }
    }

    // MARK: - Settings

    override suspend fun refreshProperties() {
        try {
            val data = client.get("get_camprop", listOf("com" to "desc", "propname" to "desclist"))
            camera.rawDescList = String(data)
            if (!loggedDescList) {
                loggedDescList = true
                debugLog("DESCLIST\n${camera.rawDescList.take(4000)}")
            }
            val root = MiniXml.parse(data) ?: return
            val result = LinkedHashMap<String, CameraProperty>()
            for (desc in root.descendants("desc")) {
                val name = desc.value("propname")?.takeIf { it.isNotEmpty() } ?: continue
                val options = (desc.value("enum") ?: "").split(" ").filter { it.isNotEmpty() }
                result[name] = CameraProperty(name, desc.value("attribute") == "getset", desc.value("value") ?: "", options)
            }
            camera.properties = result
        } catch (e: Exception) {
            camera.report(e)
        }
    }

    override suspend fun setProperty(name: String, value: String, reportErrors: Boolean): Boolean {
        // Sent verbatim (the camera's parser is simple; shutter values contain a literal ").
        val body = "<?xml version=\"1.0\"?>\r\n<set>\r\n<value>$value</value>\r\n</set>\r\n"
        val previous = camera.properties[name]?.value
        camera.updateValue(name, value)
        var ok = true
        try {
            client.post("set_camprop", listOf("com" to "set", "propname" to name), body)
            if (name == "takemode") delay(300)
        } catch (e: Exception) {
            ok = false
            if (previous != null) camera.updateValue(name, previous)
            if (reportErrors) camera.report(e)
        }
        // Changing one setting can lock/unlock others (e.g. aperture in P vs A).
        refreshProperties()
        return ok
    }

    // MARK: - Focus & shooting

    override suspend fun focus(x: Double, y: Double) {
        val (px, py) = camera.pixelPoint(x, y)
        val point = CameraModel.pointString(px, py)
        // assignafframe moves the AF target; takeready is a half-press (AF) at that point.
        try {
            val reply = client.get("exec_takemotion", listOf("com" to "assignafframe", "point" to point))
            debugLog("assignafframe reply: ${String(reply)}")
        } catch (e: Exception) {
            debugLog("assignafframe failed: $e")
        }
        if (!commands.supports("exec_takemotion", "takeready")) return
        try {
            client.get("exec_takemotion", listOf("com" to "takeready", "point" to point))
        } catch (e: Exception) {
            camera.report(e)
        }
    }

    override suspend fun releaseFocus() {
        runCatching { client.get("exec_takemotion", listOf("com" to "releaseafframe")) }
    }

    /** Bodies whose command list has exec_shutter but no starttake shoot with a full press + release. */
    private val usesShutterPush: Boolean
        get() = !commands.isEmpty && "starttake" !in commands.subcommands("exec_takemotion") &&
            "1st2ndpush" in commands.subcommands("exec_shutter")

    /** Press = start taking. In continuous drive the camera keeps shooting until release. */
    override suspend fun shutterPressed() {
        if (usesShutterPush) {
            camera.isShooting = true
            try {
                client.get("exec_shutter", listOf("com" to "1st2ndpush"), timeout = 60.0)
                client.get("exec_shutter", listOf("com" to "2nd1strelease"), timeout = 30.0)
                camera.shotCounter++
                camera.scope.launch { camera.fetchLastShot() }
            } catch (e: Exception) {
                camera.report(e)
            } finally {
                camera.isShooting = false
            }
            return
        }
        camera.isShooting = true
        val params = mutableListOf("com" to "starttake")
        camera.focusPoint?.let { (fx, fy) ->
            val (px, py) = camera.pixelPoint(fx, fy)
            params.add("point" to CameraModel.pointString(px, py))
        }
        // Long exposures: the reply can take the exposure time plus the same again for noise reduction.
        val seconds = PropertyFormat.seconds(camera.properties["shutspeedvalue"]?.value ?: "") ?: 0.0
        if (seconds >= 1) {
            camera.exposureStartedAt = System.currentTimeMillis()
            camera.exposureDuration = seconds
        }
        try {
            val reply = client.get("exec_takemotion", params, timeout = maxOf(60.0, seconds * 2 + 30))
            debugLog("starttake reply: ${String(reply)}")
            camera.shotCounter++
            camera.scope.launch { camera.fetchLastShot() }
        } catch (e: Exception) {
            camera.isShooting = false
            camera.report(e)
            return
        } finally {
            camera.exposureStartedAt = null
            camera.exposureDuration = null
        }
        if (!camera.isContinuousDrive) camera.isShooting = false
    }

    override suspend fun shutterReleased() {
        if (!camera.isShooting || !camera.isContinuousDrive) return
        runCatching { client.getUrgent("exec_takemotion", listOf("com" to "stoptake")) }
        camera.isShooting = false
    }

    override suspend fun toggleOpenExposure() {
        if (camera.isShooting) {
            runCatching { client.getUrgent("exec_takemotion", listOf("com" to "stoptake")) }
            camera.isShooting = false
            camera.exposureStartedAt = null
            camera.shotCounter++
            // Give the camera a moment to write the composite, then grab the review image.
            camera.scope.launch {
                delay(1500)
                camera.fetchLastShot()
            }
            return
        }
        camera.isShooting = true
        camera.exposureStartedAt = System.currentTimeMillis()
        camera.exposureDuration = null
        // Don't wait here: the camera may hold this reply until the exposure is stopped.
        camera.scope.launch {
            try {
                val reply = client.get("exec_takemotion", listOf("com" to "starttake"), timeout = 4 * 3600.0)
                debugLog("starttake (open-ended) reply: ${String(reply)}")
            } catch (e: Exception) {
                camera.isShooting = false
                camera.exposureStartedAt = null
                camera.report(e)
            }
        }
    }

    override suspend fun toggleMovie() {
        if (camera.isRecordingMovie) {
            runCatching { client.getUrgent("exec_takemotion", listOf("com" to "stopmovietake")) }
            camera.isRecordingMovie = false
            camera.movieStartedAt = null
            camera.shotCounter++
        } else {
            try {
                client.get("exec_takemotion", listOf("com" to "startmovietake"), timeout = 15.0)
                camera.isRecordingMovie = true
                camera.movieStartedAt = System.currentTimeMillis()
            } catch (e: Exception) {
                camera.report(e)
            }
        }
    }

    /** The PEN-F lists both `getrecview` and `getlastjpg`; try the first, fall back to the second. */
    override suspend fun fetchLastShot() {
        for (command in listOf("getrecview", "getlastjpg")) {
            if (!commands.supports("exec_takemisc", command)) continue
            val data = runCatching { client.get("exec_takemisc", listOf("com" to command), timeout = 8.0) }.getOrNull()
            val image = data?.let(::decode)
            if (image == null) {
                debugLog("$command: no image")
                continue
            }
            camera.lastShot = image.asImageBitmap()
            return
        }
    }

    /** Sets the camera's clock and time zone from the phone (needs playback mode, so live view blinks). */
    override suspend fun syncClock(): Boolean {
        val wasLive = camera.liveViewRunning
        camera.stopLiveView()
        val utc = java.text.SimpleDateFormat("yyyyMMdd'T'HHmmss", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        val offset = TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 1000
        val diff = fmt("%s%02d%02d", if (offset >= 0) "%2B" else "-", abs(offset) / 3600, abs(offset) % 3600 / 60)
        var ok = false
        try {
            client.get("switch_cammode", listOf("mode" to "play"))
            camera.mode = CameraMode.PLAY
            client.get("set_utctimediff", listOf("utctime" to utc.format(Date()), "diff" to diff))
            ok = true
        } catch (e: Exception) {
            camera.report(e)
        }
        if (wasLive || camera.mode == CameraMode.PLAY) camera.enterRecMode()
        return ok
    }

    // MARK: - Card

    override suspend fun openGallery() {
        try {
            if (camera.mode != CameraMode.PLAY) {
                client.get("switch_cammode", listOf("mode" to "play"))
                camera.mode = CameraMode.PLAY
                delay(300)
            }
            val found = mutableListOf<CameraImage>()
            val folders = mutableListOf<CardFolder>()
            for (folder in listDirectory("/DCIM").filter { it.isDirectory }) {
                var files = listDirectory(folder.path).filter { !it.isDirectory }
                // The PEN-F's photo list skips another camera's folder; its built-in web page may not.
                if (files.isEmpty()) files = webListedFiles(folder)
                found += files
                folders.add(CardFolder(folder.path, folder.name, files.size))
            }
            camera.cardFolders = folders.sortedByDescending { it.name }
            camera.images = found.sortedWith(compareByDescending<CameraImage> { it.date }.thenByDescending { it.name })
        } catch (e: Exception) {
            camera.galleryError = camera.describe(e, camera.connectionHost)
        }
    }

    /** Reads the camera's built-in web page for a folder and pulls out any file names it links to. */
    private suspend fun webListedFiles(folder: CameraImage): List<CameraImage> {
        val data = runCatching { client.download(folder.path + "/") }.getOrNull() ?: return emptyList()
        val html = String(data)
        val regex = Regex("""[A-Za-z0-9_\-]+\.(?:jpe?g|rw2|orf|mp4|mov|cr2|cr3|nef|arw|raf|heic|dng)\b""", RegexOption.IGNORE_CASE)
        val names = regex.findAll(html).map { it.value }.distinct().toList()
        debugLog("WEBLIST ${folder.path}: ${names.size} files")
        return names.map { CameraImage(folder.path, it, 0, 0, 0) }
    }

    private suspend fun listDirectory(directory: String): List<CameraImage> = try {
        ImageListParser.parse(String(client.get("get_imglist", listOf("DIR" to directory))))
    } catch (e: CameraHttpException) {
        if (e.status == 404) emptyList() else throw e   // 404 = empty folder
    }

    override suspend fun thumbnail(image: CameraImage): Bitmap? {
        val data = runCatching { client.get("get_thumbnail", listOf("DIR" to image.path), log = false) }.getOrNull() ?: return null
        return decode(data)
    }

    override suspend fun preview(image: CameraImage): Bitmap {
        if (image.fileExtension == "JPG") {
            runCatching { client.get("get_resizeimg", listOf("DIR" to image.path, "size" to "1600")) }.getOrNull()
                ?.let(::decode)?.let { return it }
        }
        runCatching { client.get("get_thumbnail", listOf("DIR" to image.path)) }.getOrNull()?.let(::decode)?.let { return it }
        // Files the camera doesn't index (another camera's) have no preview: fetch the file itself.
        if (image.fileExtension !in setOf("JPG", "JPEG")) {
            throw CameraException("The camera has no preview for this ${image.fileExtension} file. Save it to view it.")
        }
        val data = client.download(image.path)
        return decode(data) ?: throw CameraException("Couldn't decode the photo.")
    }

    override suspend fun downloadOriginal(image: CameraImage): ByteArray = client.download(image.path)
}

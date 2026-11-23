package com.apexcommerce.shutterlink.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException

// Canon Camera Control API (CCAPI): REST + JSON over HTTP on port 8080, built into recent EOS R,
// EOS M, DSLR and PowerShot bodies (port of Canon.swift). Canon keeps it switched off until the
// camera has been activated once with Canon's CCAPI activation tool (free, needs a Canon developer
// account). After that the camera offers a CCAPI Wi-Fi connection the phone can join.
//
//   GET /ccapi → the APIs this camera offers, per version: {"ver100": [{"path": …, "get": true, …}], …}
//   Settings: GET /ccapi/ver100/shooting/settings/<tv|av|iso|exposure|wb|shootingmode…>
//             → {"value": "1/125", "ability": ["30\"", …, "1/8000"]}; PUT {"value": "1/250"}.
//   Live view: POST …/shooting/liveview {"liveviewsize": "small", "cameradisplay": "on"},
//              then GET …/shooting/liveview/flip returns the latest JPEG.
//   Shutter: POST …/shooting/control/shutterbutton {"af": true};
//            …/shutterbutton/manual {"action": "half_press" | "full_press" | "release", "af": …}.
//   Events: GET …/event/polling?continue=off → what changed since last time (settings, battery,
//           "addedcontents" after a shot).
//   Card: GET …/contents → storages → folders → files (?kind=number, ?page=n), each file ?kind=
//         thumbnail | display, plain GET for the original.

class CanonDriver(private val camera: CameraModel) : CameraDriver {
    private val client = camera.makeHttpClient("Shutterlink", 200..204)
    /** Feature path ("shooting/settings/tv") → full path in the oldest version that has it (ver100
     *  payloads are the ones this driver speaks; ver110 changed some, e.g. recbutton). */
    private var api: Map<String, String> = emptyMap()
    private var methods: Map<String, Set<String>> = emptyMap()
    private var liveJob: Job? = null
    private var eventJob: Job? = null
    /** UI value → Canon value, per property. */
    private var valueMap: Map<String, Map<String, String>> = emptyMap()

    override val liveViewFormat: LiveViewFormat get() = LiveViewFormat.PUSHED

    override val capabilities: CameraCapabilities
        get() = CameraCapabilities(
            liveViewSizes = emptyList(),
            tapToFocus = has("shooting/liveview/afframeposition"),
            openEndedExposure = has("shooting/control/shutterbutton/manual"),
            movie = has("shooting/control/recbutton"),
            videoSwitch = true,
            lastShotReview = has("event/polling"),
            clockSync = false,
            highResShot = false,
            cardBrowser = has("contents"),
            powerOff = false,
        )

    private fun has(feature: String, method: String? = null): Boolean {
        if (api[feature] == null) return false
        if (method == null) return true
        return methods[feature]?.contains(method) ?: false
    }

    private fun path(feature: String): String = api[feature] ?: "/ccapi/ver100/$feature"

    /** Runs `block`, giving null instead of an error (cancellation still cancels). */
    private inline fun <T> attempt(block: () -> T): T? = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Throwable) {
        null
    }

    private suspend fun decode(bytes: ByteArray): Bitmap? = withContext(Dispatchers.Default) {
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    }

    // MARK: - Connect

    override suspend fun connect() {
        var root = JSONObject()
        var failure: Throwable? = null
        for (tryNumber in 1..3) {
            try {
                root = client.requestJson("GET", "/ccapi", timeout = 5.0)
                failure = null
                break
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                failure = e
                // Only network failures are worth another try, not an answer from the camera.
                if (tryNumber >= 3 || e !is IOException || e is CameraHttpException) break
                camera.status = "No answer yet, retrying (${tryNumber + 1}/3)…"
                delay(1500)
            }
        }
        failure?.let { throw it }
        parseApiList(root)
        if (api.isEmpty()) {
            throw CameraException("The camera answered but lists no CCAPI functions. Check that CCAPI is activated on it.")
        }
        camera.rawCommandList = api.keys.sorted().joinToString("\n") { feature ->
            "$feature  ${methods[feature]?.sorted()?.joinToString(",") ?: ""}"
        }

        camera.status = "Reading camera info…"
        attempt { client.requestJson("GET", path("deviceinformation")) }?.let { info ->
            (info.opt("productname") as? String)?.let { camera.cameraName = it.replace("Canon ", "") }
            camera.rawDescList = info.toString()
        }
        if (camera.cameraName == null) camera.cameraName = "Canon"
        readBattery()
        // Start from a clean slate so the first poll only reports what changes from now on.
        if (has("event/polling")) attempt { client.request("GET", path("event/polling") + "?continue=off", log = false) }
        startEvents()
    }

    /** {"ver100": [{"path": "/ccapi/ver100/shooting/settings/tv", "get": true, "put": true, …}], "ver110": …} */
    private fun parseApiList(root: JSONObject) {
        val paths = HashMap<String, String>()
        val verbs = HashMap<String, Set<String>>()
        for (version in root.keys().asSequence().sorted()) {   // ver100 < ver110 < ver120: the first one wins
            val entries = root.optJSONArray(version) ?: continue
            for (i in 0 until entries.length()) {
                val entry = entries.optJSONObject(i) ?: continue
                val full = entry.opt("path") as? String ?: continue
                val marker = "/$version/"
                val at = full.indexOf(marker)
                if (at < 0) continue
                val feature = full.substring(at + marker.length)
                if (paths.containsKey(feature)) continue
                paths[feature] = full
                verbs[feature] = listOf("get", "put", "post", "delete").filter { entry.optBoolean(it, false) }.toSet()
            }
        }
        api = paths
        methods = verbs
    }

    private suspend fun readBattery() {
        var reply: JSONObject? = null
        if (has("devicestatus/batterylist")) {
            reply = attempt { client.requestJson("GET", path("devicestatus/batterylist"), log = false) }
                ?.optJSONArray("batterylist")?.optJSONObject(0)
        }
        if (reply == null) reply = attempt { client.requestJson("GET", path("devicestatus/battery"), log = false) }
        val level = reply?.opt("level") as? String ?: return
        batteryPercent(level)?.let { camera.liveInfo = camera.liveInfo.copy(battery = it) }
    }

    override fun teardown() {
        liveJob?.cancel()
        liveJob = null
        eventJob?.cancel()
        eventJob = null
    }

    /** Polls for changes every 2 s: settings turned on the camera, battery, new pictures. */
    private fun startEvents() {
        if (!has("event/polling")) return
        eventJob?.cancel()
        eventJob = camera.scope.launch {
            var failures = 0
            while (isActive) {
                delay(2000)
                if (camera.phase != ConnectionPhase.CONNECTED || camera.isShooting) continue
                try {
                    val changes = client.requestJson("GET", path("event/polling") + "?continue=off", timeout = 5.0, log = false)
                    failures = 0
                    applyChanges(changes)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    failures++
                    if (failures == 3) {
                        camera.lastError = "Lost contact with the camera. Check that this phone is still on the camera's Wi-Fi."
                    }
                }
            }
        }
    }

    private suspend fun applyChanges(changes: JSONObject) {
        val level = changes.optJSONObject("battery")?.opt("level") as? String
        level?.let { batteryPercent(it) }?.let { camera.liveInfo = camera.liveInfo.copy(battery = it) }
        changes.stringList("addedcontents").lastOrNull()?.let { showLastShot(it) }
        val settingKeys = listOf("tv", "av", "iso", "exposure", "wb", "shootingmode", "shootingmodedial")
        if (settingKeys.any { changes.has(it) }) refreshProperties()
    }

    // MARK: - Live view

    override suspend fun enterRecMode() {
        camera.isSwitchingMode = true
        try {
            camera.mode = CameraMode.REC
            camera.refreshProperties()
            camera.startLiveView()
        } finally {
            camera.isSwitchingMode = false
        }
    }

    override suspend fun startLiveView() {
        try {
            client.request("POST", path("shooting/liveview"), json = mapOf("liveviewsize" to "small", "cameradisplay" to "on"))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            camera.liveViewRunning = false
            camera.report(e)
            return
        }
        val flip = path("shooting/liveview/flip")
        liveJob?.cancel()
        liveJob = camera.pullLiveView(everyMs = 20) {
            // 503 while the camera is busy (e.g. writing a shot): skip a frame.
            try {
                client.request("GET", flip, timeout = 5.0, log = false)
            } catch (e: CameraHttpException) {
                if (e.status != 503) throw e
                delay(200)
                null
            }
        }
    }

    override suspend fun stopLiveView() {
        liveJob?.cancel()
        liveJob = null
        attempt {
            client.request("POST", path("shooting/liveview"), json = mapOf("liveviewsize" to "off", "cameradisplay" to "on"), timeout = 3.0)
        }
    }

    // MARK: - Settings

    override suspend fun refreshProperties() {
        var all = JSONObject()
        if (has("shooting/settings")) {
            attempt { client.requestJson("GET", path("shooting/settings"), log = false) }?.let { all = it }
        }
        val result = LinkedHashMap<String, CameraProperty>()
        val maps = HashMap<String, Map<String, String>>()
        for ((ui, canon) in SETTINGS) {
            if (result.containsKey(ui)) continue
            var setting = all.optJSONObject(canon)
            if (setting == null && all.length() == 0 && has("shooting/settings/$canon")) {
                setting = attempt { client.requestJson("GET", path("shooting/settings/$canon"), log = false) }
            }
            if (setting == null) continue
            val current = setting.opt("value") as? String
            if (current.isNullOrEmpty()) continue
            val ability = setting.stringList("ability")
            val map = LinkedHashMap<String, String>()
            val options = mutableListOf<String>()
            for (value in ability) {
                val text = uiValue(ui, value)
                if (!map.containsKey(text)) {
                    map[text] = value
                    options.add(text)
                }
            }
            maps[ui] = map
            val value = uiValue(ui, current)
            if (value !in options) options.add(value)
            val settable = ability.isNotEmpty() && (methods["shooting/settings/$canon"]?.contains("put") ?: true) &&
                canon != "shootingmodedial"
            result[ui] = CameraProperty(ui, settable, value, options)
        }
        valueMap = maps
        camera.properties = result
    }

    override suspend fun setProperty(name: String, value: String, reportErrors: Boolean): Boolean {
        val canonName = SETTINGS.firstOrNull { (ui, canon) ->
            ui == name && api["shooting/settings/$canon"] != null && canon != "shootingmodedial"
        }?.second
        val canonValue = valueMap[name]?.get(value)
        if (canonName == null || canonValue == null) {
            if (reportErrors) camera.lastError = "This setting can't be changed on this Canon from the app."
            return false
        }
        val previous = camera.properties[name]?.value
        camera.updateValue(name, value)
        try {
            client.request("PUT", path("shooting/settings/$canonName"), json = mapOf("value" to canonValue))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (previous != null) camera.updateValue(name, previous)
            if (reportErrors) camera.report(e)
            refreshProperties()
            return false
        }
        refreshProperties()
        return true
    }

    // MARK: - Focus & shooting

    override suspend fun focus(x: Double, y: Double) {
        // The AF frame position is in live-view pixels.
        val (px, py) = camera.pixelPoint(x, y)
        try {
            client.request("PUT", path("shooting/liveview/afframeposition"),
                json = mapOf("positionx" to px.toInt(), "positiony" to py.toInt()))
            if (has("shooting/control/shutterbutton/manual")) {
                val manual = path("shooting/control/shutterbutton/manual")
                client.request("POST", manual, json = mapOf("action" to "half_press", "af" to true), timeout = 10.0)
                attempt { client.request("POST", manual, json = mapOf("action" to "release", "af" to true), timeout = 5.0) }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            camera.report(e)
        }
    }

    override suspend fun shutterPressed() {
        camera.isShooting = true
        val seconds = PropertyFormat.seconds(camera.properties["shutspeedvalue"]?.value ?: "") ?: 0.0
        if (seconds >= 1) {
            camera.exposureStartedAt = System.currentTimeMillis()
            camera.exposureDuration = seconds
        }
        try {
            client.request("POST", path("shooting/control/shutterbutton"), json = mapOf("af" to true),
                timeout = maxOf(30.0, seconds * 2 + 20))
            camera.shotCounter++
            // The new file shows up in the next event poll; ask now so the thumbnail comes quickly.
            if (seconds >= 1) delay((seconds * 1000).toLong())
            delay(600)
            attempt { client.requestJson("GET", path("event/polling") + "?continue=off", log = false) }?.let { applyChanges(it) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            camera.report(e)
        } finally {
            camera.isShooting = false
            camera.exposureStartedAt = null
            camera.exposureDuration = null
        }
    }

    /** Bulb: hold the shutter fully pressed until the second tap. */
    override suspend fun toggleOpenExposure() {
        val manual = path("shooting/control/shutterbutton/manual")
        if (camera.isShooting) {
            attempt { client.request("POST", manual, json = mapOf("action" to "release", "af" to false), urgent = true) }
            camera.isShooting = false
            camera.exposureStartedAt = null
            camera.shotCounter++
            return
        }
        camera.isShooting = true
        camera.exposureStartedAt = System.currentTimeMillis()
        camera.exposureDuration = null
        try {
            client.request("POST", manual, json = mapOf("action" to "full_press", "af" to false))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            camera.isShooting = false
            camera.exposureStartedAt = null
            camera.report(e)
        }
    }

    override suspend fun toggleMovie() {
        if (camera.isRecordingMovie) {
            attempt { client.request("POST", path("shooting/control/recbutton"), json = mapOf("action" to "stop")) }
            camera.isRecordingMovie = false
            camera.movieStartedAt = null
            camera.shotCounter++
            if (has("shooting/control/moviemode")) {
                attempt { client.request("POST", path("shooting/control/moviemode"), json = mapOf("action" to "off")) }
            }
            return
        }
        try {
            if (has("shooting/control/moviemode")) {
                client.request("POST", path("shooting/control/moviemode"), json = mapOf("action" to "on"))
            }
            client.request("POST", path("shooting/control/recbutton"), json = mapOf("action" to "start"))
            camera.isRecordingMovie = true
            camera.movieStartedAt = System.currentTimeMillis()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            camera.report(e)
        }
    }

    private suspend fun showLastShot(file: String) {
        // kind=display is a screen-sized JPEG, also for RAW and HEIF files.
        val data = attempt { client.request("GET", "$file?kind=display", timeout = 10.0, log = false) } ?: return
        decode(data)?.let { camera.lastShot = it.asImageBitmap() }
    }

    // MARK: - Card

    override suspend fun openGallery() {
        try {
            camera.mode = CameraMode.PLAY
            val found = mutableListOf<CameraImage>()
            val folders = mutableListOf<CardFolder>()
            val storages = client.requestJson("GET", path("contents")).stringList("path")
            for (storage in storages) {
                val dirs = client.requestJson("GET", storage).stringList("path")
                for (dir in dirs) {
                    val pages = client.requestJson("GET", "$dir?kind=number").optInt("pagenumber", 1)
                    val files = mutableListOf<CameraImage>()
                    for (page in 1..maxOf(pages, 1)) {
                        for (file in client.requestJson("GET", "$dir?page=$page").stringList("path")) {
                            files.add(CameraImage(dir, file.trimEnd('/').substringAfterLast('/'), 0, 0, 0))
                        }
                    }
                    found += files
                    val name = dir.trimEnd('/').substringAfterLast('/')
                    folders.add(CardFolder(dir, name, files.size, isForeign = !name.uppercase().endsWith("CANON")))
                }
            }
            camera.cardFolders = folders.sortedByDescending { it.name }
            // No dates without asking for each file's info; newest folder and highest number first.
            camera.images = found.sortedWith(compareByDescending<CameraImage> { it.directory }.thenByDescending { it.name })
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            camera.galleryError = camera.describe(e, camera.connectionHost)
        }
    }

    override suspend fun thumbnail(image: CameraImage): Bitmap? {
        val data = attempt { client.request("GET", image.path + "?kind=thumbnail", log = false) } ?: return null
        return decode(data)
    }

    override suspend fun preview(image: CameraImage): Bitmap {
        val data = client.request("GET", image.path + "?kind=display", timeout = 30.0)
        return decode(data) ?: throw CameraException("Couldn't decode the preview.")
    }

    override suspend fun downloadOriginal(image: CameraImage): ByteArray =
        client.request("GET", image.path, timeout = 300.0)

    companion object {
        private val SETTINGS: List<Pair<String, String>> = listOf(
            "takemode" to "shootingmodedial", "takemode" to "shootingmode", "focalvalue" to "av",
            "shutspeedvalue" to "tv", "isospeedvalue" to "iso", "expcomp" to "exposure", "wbvalue" to "wb",
        )

        fun batteryPercent(level: String): Int? {
            level.toIntOrNull()?.let { return it }
            return mapOf("full" to 100, "high" to 75, "half" to 50, "quarter" to 25, "low" to 10, "empty" to 0)[level.lowercase()]
        }

        /**
         * Canon spelling → the app's: "f5.6" → "5.6", "1/125" → "125", "0\"5" → "0.5\"",
         * "+1_1/3" → "+1.3", "av" → "A", "daylight" → "18".
         */
        fun uiValue(name: String, canon: String): String = when (name) {
            "focalvalue" -> if (canon.startsWith("f")) canon.drop(1) else canon
            "shutspeedvalue" -> when {
                canon.lowercase() == "bulb" -> "bulb"
                canon.startsWith("1/") -> canon.drop(2)
                canon.contains("\"") -> {
                    val parts = canon.split("\"")
                    val whole = parts.firstOrNull() ?: "0"
                    val fraction = parts.getOrNull(1) ?: ""
                    (if (fraction.isEmpty()) whole else "$whole.$fraction") + "\""
                }
                else -> canon
            }
            "isospeedvalue" -> if (canon.lowercase() == "auto") "auto" else canon
            "expcomp" -> ExposureText.ev(evValue(canon))
            "wbvalue" -> mapOf(
                "auto" to "0", "daylight" to "18", "shade" to "16", "cloudy" to "17", "tungsten" to "20",
                "whitefluorescent" to "35", "flash" to "23", "custom" to "256", "colortemp" to "512",
                "awbwhite" to "awb_white", "awbambience" to "awb_ambience",
            )[canon.lowercase()] ?: canon
            "takemode" -> mapOf(
                "m" to "M", "av" to "A", "tv" to "S", "p" to "P", "a+" to "iAuto", "auto" to "iAuto", "fv" to "Fv",
                "bulb" to "B", "movie" to "movie",
            )[canon.lowercase()] ?: canon.uppercase()
            else -> canon
        }

        /** "+1_1/3" → 1.333, "-0_2/3" → -0.667, "+2" → 2, "0" → 0. */
        fun evValue(canon: String): Double {
            var text = canon.trim()
            var sign = 1.0
            if (text.startsWith("-")) {
                sign = -1.0
                text = text.drop(1)
            } else if (text.startsWith("+")) {
                text = text.drop(1)
            }
            val parts = text.split("_")
            var value = parts.firstOrNull()?.toDoubleOrNull() ?: 0.0
            if (parts.size > 1) {
                val fraction = parts[1].split("/").mapNotNull { it.toDoubleOrNull() }
                if (fraction.size == 2 && fraction[1] != 0.0) value += fraction[0] / fraction[1]
            }
            return sign * value
        }
    }
}

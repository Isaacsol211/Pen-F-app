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
import okio.Buffer
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.time.Instant
import java.time.OffsetDateTime

// Sony Camera Remote API (JSON-RPC over HTTP), as used by PlayMemories Mobile with the
// "Smart Remote Control" / "Smart Remote Embedded" app on the camera (port of Sony.swift). Bodies up
// to about 2019 (a5000–a6500, a7 II/III family, RX100 III–VI, RX10 II–IV, a9…) have it; Sony dropped
// it from bodies released after mid-2020 (a7 IV, a7S III, ZV-E10, a6700…).
//
//   Camera at 192.168.122.1; API at http://192.168.122.1:8080/sony/camera (some bodies :10000).
//   POST {"method": "...", "params": [...], "id": n, "version": "1.0"} → {"result": [...]} or
//   {"error": [code, "message"]}. getAvailableApiList says what the camera allows right now.
//   Live view: startLiveview → URL of an endless HTTP stream of packets:
//     8-byte common header (FF, type 01 = JPEG, sequence, timestamp) +
//     128-byte payload header (24 35 68 79, 3-byte JPEG size, 1-byte padding) + JPEG + padding.
//   Settings: getAvailableX → [current, [choices]], setX [value].
//   Card: setCameraFunction "Contents Transfer", then avContent getContentList.

class SonyException(val code: Int, val reason: String, val method: String) : Exception() {
    override val message: String
        get() = when (code) {
            40401 -> "The camera isn't ready ($method). Try again in a moment."
            40403 -> "The camera is still taking the picture."
            12, 403 -> "The camera doesn't allow $method right now."
            3 -> "The camera didn't accept that value ($method)."
            else -> "The camera answered error $code $reason to $method."
        }
}

class SonyDriver(private val camera: CameraModel) : CameraDriver {
    private val client = camera.makeHttpClient("Shutterlink")
    private var apis: Set<String> = emptySet()
    private var rpcId = 0
    private var stream: HttpStreamReader? = null
    private var eventJob: Job? = null
    /** UI value → Sony value, per property. */
    private var valueMap: Map<String, Map<String, String>> = emptyMap()
    /** Exposure compensation index step: 1 = ⅓ EV, 2 = ½ EV. */
    private var evStep = 1

    override val liveViewFormat: LiveViewFormat get() = LiveViewFormat.PUSHED

    override val capabilities: CameraCapabilities
        get() = CameraCapabilities(
            liveViewSizes = emptyList(),
            tapToFocus = "setTouchAFPosition" in apis || apis.isEmpty(),
            openEndedExposure = "startBulbShooting" in apis,
            movie = "startMovieRec" in apis || "setShootMode" in apis,
            videoSwitch = true,
            lastShotReview = true,
            clockSync = false,
            highResShot = false,
            cardBrowser = "setCameraFunction" in apis,
            powerOff = false,
        )

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

    // MARK: - JSON-RPC

    /** Calls `method` and returns its result array (JSONObject / JSONArray / String / Number / Boolean / null). */
    suspend fun call(
        method: String, params: List<Any?> = emptyList(), service: String = "camera", version: String = "1.0",
        timeout: Double = 10.0, log: Boolean = true,
    ): List<Any?> {
        rpcId++
        val body = JSONObject()
            .put("method", method)
            .put("params", JSONArray(params))
            .put("id", rpcId)
            .put("version", version)
        val reply = client.requestJson("POST", "/sony/$service", json = body, timeout = timeout, log = log)
        reply.optJSONArray("error")?.let { error ->
            throw SonyException(error.optInt(0, -1), error.opt(1) as? String ?: "", method)
        }
        return (reply.optJSONArray("result") ?: reply.optJSONArray("results"))?.toList() ?: emptyList()
    }

    // MARK: - Connect

    override suspend fun connect() {
        var failure: Throwable? = null
        for (tryNumber in 1..3) {
            try {
                call("getVersions", timeout = 5.0)
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

        camera.status = "Reading camera info…"
        camera.cameraName = deviceName() ?: "Sony"
        attempt { call("getApplicationInfo") }?.let { info ->
            camera.rawCommandList = "Application: ${info.joinToString(" ")}\n"
        }
        refreshApis()
        // Bodies with a separate remote-shooting mode list startRecMode until it has run.
        if ("startRecMode" in apis) {
            camera.status = "Starting remote shooting…"
            attempt { call("startRecMode", timeout = 15.0) }
            var waited = 0
            while (waited < 10 && "actTakePicture" !in apis) {
                delay(500)
                attempt { refreshApis() }
                waited++
            }
        }
        camera.rawCommandList += apis.sorted().joinToString("\n")
        startEvents()
    }

    private suspend fun refreshApis() {
        (call("getAvailableApiList").firstOrNull() as? JSONArray)?.let { list ->
            apis = list.toList().filterIsInstance<String>().toSet()
        }
    }

    /** The model name from the camera's UPnP description (e.g. "ILCE-6000"), if it serves one. */
    private suspend fun deviceName(): String? {
        val ip = camera.connectionHost.substringBefore(':')
        val data = attempt { client.fetch("http://$ip:64321/DmsRmtDesc.xml", timeout = 3.0, log = false) } ?: return null
        val root = MiniXml.parse(data) ?: return null
        return root.firstDescendant("modelName")?.trimmedText ?: root.firstDescendant("friendlyName")?.trimmedText
    }

    override suspend fun disconnect() {
        if ("stopRecMode" in apis) attempt { call("stopRecMode", timeout = 3.0) }
    }

    override fun teardown() {
        stream?.stop()
        stream = null
        eventJob?.cancel()
        eventJob = null
    }

    /** Polls getEvent every 2 s for battery, card space and settings changed on the camera. */
    private fun startEvents() {
        eventJob?.cancel()
        eventJob = camera.scope.launch {
            var failures = 0
            while (isActive) {
                delay(2000)
                if (camera.phase != ConnectionPhase.CONNECTED) continue
                try {
                    val result = call("getEvent", listOf(false), timeout = 5.0, log = false)
                    failures = 0
                    applyEvent(result)
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

    /** getEvent's result is a fixed-position array of objects (or arrays of objects) with a "type". */
    private fun applyEvent(result: List<Any?>) {
        val objects = mutableListOf<JSONObject>()
        for (item in result) {
            when (item) {
                is JSONObject -> objects.add(item)
                is JSONArray -> objects.addAll(item.toList().filterIsInstance<JSONObject>())
            }
        }
        var info = camera.liveInfo
        var settingsChanged = false
        for (o in objects) {
            when (o.opt("type") as? String) {
                "availableApiList" -> o.optJSONArray("names")?.let { names ->
                    apis = names.toList().filterIsInstance<String>().toSet()
                }
                "storageInformation" -> {
                    val n = (o.opt("numberOfRecordableImages") as? Number)?.toInt()
                    if (n != null && n >= 0) info = info.copy(shotsRemaining = n)
                }
                "batteryInfo" -> {
                    val battery = o.optJSONArray("batteryInfo")?.optJSONObject(0)
                    val numer = (battery?.opt("levelNumer") as? Number)?.toInt()
                    val denom = (battery?.opt("levelDenom") as? Number)?.toInt()
                    if (numer != null && denom != null && denom > 0) info = info.copy(battery = numer * 100 / denom)
                }
                "fNumber", "shutterSpeed", "isoSpeedRate", "exposureCompensation", "whiteBalance", "exposureMode" ->
                    settingsChanged = true
            }
        }
        if (info != camera.liveInfo) camera.liveInfo = info
        if (settingsChanged && !camera.isShooting) camera.scope.launch { refreshProperties() }
    }

    // MARK: - Live view

    override suspend fun enterRecMode() {
        camera.isSwitchingMode = true
        try {
            if (camera.mode == CameraMode.PLAY && "setCameraFunction" in apis) {
                attempt { call("setCameraFunction", listOf("Remote Shooting")) }
                delay(1000)
                attempt { refreshApis() }
            }
            camera.mode = CameraMode.REC
            camera.refreshProperties()
            camera.startLiveView()
        } finally {
            camera.isSwitchingMode = false
        }
    }

    override suspend fun startLiveView() {
        try {
            val address = call("startLiveview").firstOrNull() as? String
                ?: throw CameraException("The camera gave no live-view address.")
            val reader = HttpStreamReader(address) { parseLiveViewPackets(it) }
            reader.onFrame = { jpeg -> camera.scope.launch { camera.submitLiveViewJpeg(jpeg) } }
            reader.onEnd = { error ->
                camera.scope.launch {
                    if (camera.liveViewRunning && stream === reader) {
                        debugLog("Sony live view ended: ${error?.message ?: "closed"}")
                        camera.liveViewRunning = false
                    }
                }
            }
            stream?.stop()
            stream = reader
            reader.start(camera.scope)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            camera.liveViewRunning = false
            camera.report(e)
        }
    }

    override suspend fun stopLiveView() {
        stream?.stop()
        stream = null
        attempt { call("stopLiveview", timeout = 3.0) }
    }

    // MARK: - Settings

    override suspend fun refreshProperties() {
        val result = LinkedHashMap<String, CameraProperty>()
        val maps = HashMap<String, Map<String, String>>()

        // [current, [choices]] for the simple string settings.
        suspend fun available(method: String): Pair<String, List<String>>? {
            if (apis.isNotEmpty() && method !in apis) return null
            val reply = attempt { call(method, log = false) } ?: return null
            val current = reply.firstOrNull() as? String ?: return null
            val choices = (reply.getOrNull(1) as? JSONArray)?.toList()?.filterIsInstance<String>() ?: listOf(current)
            return current to choices
        }

        fun add(name: String, current: String, choices: List<String>, settable: Boolean, ui: (String) -> String?) {
            val map = LinkedHashMap<String, String>()
            val options = mutableListOf<String>()
            for (choice in choices) {
                val label = ui(choice) ?: continue
                if (map.containsKey(label)) continue
                map[label] = choice
                options.add(label)
            }
            maps[name] = map
            val value = ui(current) ?: current
            result[name] = CameraProperty(name, settable && options.size > 1, value,
                if (value in options) options else options + value)
        }

        val mode = available("getAvailableExposureMode")
        if (mode != null) {
            add("takemode", mode.first, mode.second, "setExposureMode" in apis) { modeLabel(it) }
        } else {
            val current = attempt { call("getExposureMode", log = false) }?.firstOrNull() as? String
            if (current != null) add("takemode", current, listOf(current), false) { modeLabel(it) }
        }
        available("getAvailableFNumber")?.takeIf { it.first != "--" }?.let { (current, choices) ->
            add("focalvalue", current, choices, "setFNumber" in apis) { if (it == "--") null else it }
        }
        available("getAvailableShutterSpeed")?.takeIf { it.first != "--" }?.let { (current, choices) ->
            add("shutspeedvalue", current, choices, "setShutterSpeed" in apis) { shutterLabel(it) }
        }
        available("getAvailableIsoSpeedRate")?.let { (current, choices) ->
            add("isospeedvalue", current, choices, "setIsoSpeedRate" in apis) {
                when {
                    it.uppercase() == "AUTO" -> "auto"
                    it.toIntOrNull() != null -> it
                    else -> null
                }
            }
        }
        if (apis.isEmpty() || "getAvailableExposureCompensation" in apis) {
            val reply = attempt { call("getAvailableExposureCompensation", log = false) }
            if (reply != null && reply.size >= 4) {
                val current = (reply[0] as? Number)?.toInt()
                val maxIndex = (reply[1] as? Number)?.toInt()
                val minIndex = (reply[2] as? Number)?.toInt()
                val step = (reply[3] as? Number)?.toInt()
                if (current != null && maxIndex != null && minIndex != null && step != null && maxIndex > minIndex) {
                    evStep = if (step == 2) 2 else 1
                    val label = { i: Int ->
                        if (evStep == 2) (if (i == 0) "0.0" else fmt("%+.1f", i / 2.0)) else ExposureText.ev(i)
                    }
                    val map = LinkedHashMap<String, String>()
                    val options = (minIndex..maxIndex).map { i -> label(i).also { map[it] = i.toString() } }
                    maps["expcomp"] = map
                    result["expcomp"] = CameraProperty("expcomp", "setExposureCompensation" in apis, label(current), options)
                }
            }
        }
        if (apis.isEmpty() || "getAvailableWhiteBalance" in apis) {
            val reply = attempt { call("getAvailableWhiteBalance", log = false) }
            val current = (reply?.firstOrNull() as? JSONObject)?.opt("whiteBalanceMode") as? String
            if (reply != null && current != null) {
                val modes = (reply.getOrNull(1) as? JSONArray)?.toList()
                    ?.mapNotNull { (it as? JSONObject)?.opt("whiteBalanceMode") as? String } ?: emptyList()
                add("wbvalue", current, modes.ifEmpty { listOf(current) }, "setWhiteBalance" in apis) { whiteBalanceCode(it) }
            }
        }
        valueMap = maps
        camera.properties = result
    }

    override suspend fun setProperty(name: String, value: String, reportErrors: Boolean): Boolean {
        val sony = valueMap[name]?.get(value) ?: value
        val request: Pair<String, List<Any?>>? = when (name) {
            "takemode" -> "setExposureMode" to listOf(sony)
            "focalvalue" -> "setFNumber" to listOf(sony)
            "shutspeedvalue" -> "setShutterSpeed" to listOf(sony)
            "isospeedvalue" -> "setIsoSpeedRate" to listOf(sony)
            "expcomp" -> "setExposureCompensation" to listOf(sony.toIntOrNull() ?: 0)
            "wbvalue" -> "setWhiteBalance" to listOf(sony, false, -1)
            else -> null
        }
        if (request == null) {
            if (reportErrors) camera.lastError = "This setting can't be changed on a Sony camera from the app."
            return false
        }
        val previous = camera.properties[name]?.value
        camera.updateValue(name, value)
        try {
            call(request.first, request.second)
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
        if ("setTouchAFPosition" !in apis) return
        try {
            val result = call("setTouchAFPosition", listOf(x * 100, y * 100))
            // [0, {"AFResult": true, "AFType": "Touch"}]
            val focused = result.filterIsInstance<JSONObject>().firstOrNull()?.optBoolean("AFResult", false) ?: false
            camera.showAfResult(focused, x, y)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            camera.report(e)
        }
    }

    override suspend fun releaseFocus() {
        if ("cancelTouchAFPosition" in apis) attempt { call("cancelTouchAFPosition", timeout = 3.0) }
    }

    override suspend fun shutterPressed() {
        camera.isShooting = true
        val seconds = PropertyFormat.seconds(camera.properties["shutspeedvalue"]?.value ?: "") ?: 0.0
        if (seconds >= 1) {
            camera.exposureStartedAt = System.currentTimeMillis()
            camera.exposureDuration = seconds
        }
        val timeout = maxOf(30.0, seconds * 2 + 20)
        try {
            val result = try {
                call("actTakePicture", timeout = timeout)
            } catch (e: SonyException) {
                if (e.code != 40403) throw e
                call("awaitTakePicture", timeout = timeout)
            }
            camera.shotCounter++
            // [["http://…/postview.jpg"]]
            val address = (result.firstOrNull() as? JSONArray)?.toList()?.firstOrNull() as? String
            if (address != null) {
                camera.scope.launch {
                    val data = attempt { client.fetch(address, timeout = 10.0, log = false) } ?: return@launch
                    decode(data)?.let { camera.lastShot = it.asImageBitmap() }
                }
            }
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

    override suspend fun toggleOpenExposure() {
        if (camera.isShooting) {
            attempt { call("stopBulbShooting") }
            camera.isShooting = false
            camera.exposureStartedAt = null
            camera.shotCounter++
            return
        }
        try {
            camera.isShooting = true
            camera.exposureStartedAt = System.currentTimeMillis()
            camera.exposureDuration = null
            call("startBulbShooting")
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
            attempt { call("stopMovieRec") }
            camera.isRecordingMovie = false
            camera.movieStartedAt = null
            camera.shotCounter++
            if ("setShootMode" in apis || "getShootMode" in apis) attempt { call("setShootMode", listOf("still")) }
            return
        }
        try {
            attempt { call("setShootMode", listOf("movie")) }
            call("startMovieRec", timeout = 15.0)
            camera.isRecordingMovie = true
            camera.movieStartedAt = System.currentTimeMillis()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            attempt { call("setShootMode", listOf("still")) }
            camera.report(e)
        }
    }

    // MARK: - Card (avContent, in Contents Transfer mode)

    override suspend fun openGallery() {
        if ("setCameraFunction" !in apis) {
            camera.galleryError = "This camera can't show its card over Wi-Fi in remote mode. Use Sony's own app, or the camera's Send to Smartphone."
            return
        }
        try {
            call("setCameraFunction", listOf("Contents Transfer"))
            camera.mode = CameraMode.PLAY
            // The switch takes a moment; avContent answers "not ready" until it's done.
            var sources: List<Any?> = emptyList()
            var tries = 0
            while (tries < 10) {
                tries++
                delay(700)
                val reply = attempt { call("getSourceList", listOf(mapOf("scheme" to "storage")), service = "avContent") }
                if (reply != null) {
                    sources = reply
                    break
                }
            }
            val source = ((sources.firstOrNull() as? JSONArray)?.optJSONObject(0)?.opt("source") as? String)
                ?: "storage:memoryCard1"
            val found = mutableListOf<CameraImage>()
            var start = 0
            while (true) {
                val page = call(
                    "getContentList",
                    listOf(mapOf("uri" to source, "stIdx" to start, "cnt" to 100, "view" to "flat", "sort" to "descending")),
                    service = "avContent", version = "1.3", timeout = 20.0,
                )
                val items = (page.firstOrNull() as? JSONArray)?.toList()?.filterIsInstance<JSONObject>() ?: emptyList()
                for (item in items) found += images(item)
                start += items.size
                if (items.size < 100) break
            }
            camera.images = found.sortedWith(compareByDescending<CameraImage> { it.date }.thenByDescending { it.name })
            camera.cardFolders = listOf(CardFolder("SONY", camera.cameraName ?: "Sony", camera.images.size, isForeign = false))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            camera.galleryError = camera.describe(e, camera.connectionHost)
        }
    }

    override suspend fun thumbnail(image: CameraImage): Bitmap? {
        val urls = image.urls ?: return null
        val data = attempt { client.fetch(urls.thumbnail ?: urls.preview ?: urls.original, log = false) } ?: return null
        return decode(data)
    }

    override suspend fun preview(image: CameraImage): Bitmap {
        val urls = image.urls ?: throw CameraException("The camera gave no address for this file.")
        val data = client.fetch(urls.preview ?: urls.thumbnail ?: urls.original)
        return decode(data) ?: throw CameraException("Couldn't decode the preview.")
    }

    override suspend fun downloadOriginal(image: CameraImage): ByteArray {
        val urls = image.urls ?: throw CameraException("The camera gave no address for this file.")
        return client.fetch(urls.original, timeout = 300.0)
    }

    companion object {
        fun modeLabel(sony: String): String = when (sony) {
            "Program Auto" -> "P"
            "Aperture" -> "A"
            "Shutter" -> "S"
            "Manual" -> "M"
            "Intelligent Auto", "Superior Auto" -> "iAuto"
            else -> sony
        }

        /** "1/125" → "125", "2.5\"" → "2.5\"", "BULB" → "bulb". */
        fun shutterLabel(sony: String): String? = when {
            sony.uppercase() == "BULB" -> "bulb"
            sony.startsWith("1/") -> sony.drop(2)
            sony.endsWith("\"") -> sony
            else -> null
        }

        fun whiteBalanceCode(sony: String): String {
            val lower = sony.lowercase()
            return when {
                lower.startsWith("auto") -> "0"
                lower.startsWith("fluorescent") -> if (lower.contains("warm") || lower.contains("(-1)")) "35" else sony
                lower.startsWith("custom") -> if (lower.endsWith("1") || lower == "custom") "256" else sony
                lower.startsWith("color temperature") -> "512"
                else -> ExposureText.whiteBalanceCodes[lower] ?: sony
            }
        }

        /** Pulls complete JPEG packets off the front of the stream buffer. */
        fun parseLiveViewPackets(buffer: Buffer): List<ByteArray> {
            val frames = mutableListOf<ByteArray>()
            fun u(i: Long) = buffer[i].toInt() and 0xFF
            while (buffer.size >= 136) {
                // Resync on the common header's start byte and the payload header's start code.
                if (u(0) != 0xFF || u(8) != 0x24 || u(9) != 0x35 || u(10) != 0x68 || u(11) != 0x79) {
                    val next = buffer.indexOf(0xFF.toByte(), 1)
                    if (next >= 0) {
                        buffer.skip(next)
                        continue
                    }
                    buffer.clear()
                    break
                }
                val type = u(1)
                val size = (u(12) shl 16) or (u(13) shl 8) or u(14)
                val padding = u(15)
                val total = 136L + size + padding
                if (buffer.size < total) break
                buffer.skip(136)
                if (type == 0x01 && size > 0) frames.add(buffer.readByteArray(size.toLong())) else buffer.skip(size.toLong())
                buffer.skip(padding.toLong())
            }
            return frames
        }

        /** Sony's ISO 8601 times ("2014-08-25T14:22:21+09:00") → ms since 1970; 0 when unknown. */
        fun parseDate(text: String?): Long {
            if (text.isNullOrEmpty()) return 0
            runCatching { return OffsetDateTime.parse(text).toInstant().toEpochMilli() }
            runCatching { return Instant.parse(text).toEpochMilli() }
            return 0
        }

        fun images(item: JSONObject): List<CameraImage> {
            val content = item.optJSONObject("content") ?: return emptyList()
            val originals = content.optJSONArray("original")?.toList()?.filterIsInstance<JSONObject>() ?: emptyList()
            val thumb = content.opt("thumbnailUrl") as? String
            val large = (content.opt("largeUrl") as? String) ?: (content.opt("smallUrl") as? String)
            val date = parseDate(item.opt("createdTime") as? String)
            return originals.mapNotNull { original ->
                val name = original.opt("fileName") as? String ?: return@mapNotNull null
                val url = original.opt("url") as? String ?: return@mapNotNull null
                CameraImage("SONY", name, 0, 0, date, MediaUrls(thumb, large ?: thumb, url))
            }
        }
    }
}

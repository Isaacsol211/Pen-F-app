package com.apexcommerce.shutterlink.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.IOException
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt

// Panasonic LUMIX (GH5, G9, GH4, S-series…) over the camera's own Wi-Fi, as used by Image App /
// LUMIX Sync; port of Panasonic.swift. Summary of the protocol:
//
//   Camera at 192.168.54.1. Commands are GET /cam.cgi?mode=…; replies are XML
//   (<camrply><result>ok</result>…) or CSV ("ok,…"); errors start with "err_".
//   Pairing: mode=accctrl&type=req_acc&value=<uuid>&value2=<name>. While the camera asks the
//   user it answers "ok_under_research"; resend every second until it says ok.
//   Live view: mode=startstream&value=<udp port>; each datagram is one JPEG after a header.
//   The camera stops unless polled with mode=getstate (we poll every second).
//   Exposure values are APEX × 256 written "n/256": f-number = 2^(n/512), time = 2^(-n/256).
//   Photos: UPnP ContentDirectory on port 60606; files on port 50001.

class PanasonicException(val code: String, val command: String) : Exception() {
    override val message: String
        get() = when (code) {
            "err_user_refused" -> "The camera said No to this phone. Start Remote Shooting & View on the camera again and choose Yes."
            "err_others_requesting", "err_already_connected" -> "Another phone or app is connected to the camera. Close Image App or LUMIX Sync on other devices, then try again."
            "err_unsuitable_app" -> "The camera won't accept this app in its current Wi-Fi mode. On the camera use New Connection ▸ Remote Shooting & View."
            "err_busy" -> "The camera is busy (probably still writing to the card). Try again in a moment."
            "err_reject" -> "The camera refused $command in its current mode. Check the mode dial."
            "err_param", "err_non_support" -> "This camera doesn't support $command."
            else -> "The camera answered $code to $command."
        }
}

/** What the mounted lens and body allow, from mode=getinfo&type=lens. */
data class LumixLens(
    val maxFNumber: Double? = null,
    val minFNumber: Double? = null,
    val minFNumberCode: Int? = null,
    /** Shutter codes (APEX × 256): fastest (e.g. 3328 = 1/8000) and slowest (e.g. -1536 = 60 s). */
    val fastestShutter: Int? = null,
    val slowestShutter: Int? = null,
    val focalMax: Int? = null,
    val focalMin: Int? = null,
)

class PanasonicDriver(private val camera: CameraModel) : CameraDriver {
    val client = camera.makeHttpClient("LUMIX Sync")

    // Per-connection LUMIX state.
    private var lens = LumixLens()
    /** Allowed values per setting type, from getinfo&type=allmenu. */
    private var menu: Map<String, List<String>> = emptyMap()
    /** UI value → camera code, built with each option list. */
    private var apertureCodes: Map<String, Int> = emptyMap()
    private var shutterCodes: Map<String, Int> = emptyMap()
    private var whiteBalanceCodes: Map<String, String> = emptyMap()
    private var contentDirectory: String? = null
    private var lastStreamKick = 0L
    /** The camera stops streaming unless it hears from the app regularly. */
    private var keepAlive: Job? = null

    override val liveViewFormat get() = LiveViewFormat.JPEG_PER_DATAGRAM

    override val capabilities: CameraCapabilities
        get() = CameraCapabilities(
            liveViewSizes = CameraBrand.PANASONIC.defaultLiveViewSizes, tapToFocus = true,
            openEndedExposure = !(camera.profile?.fixedExposure ?: false),
            movie = !(camera.profile?.noVideo ?: false), videoSwitch = true, lastShotReview = false,
            clockSync = false, highResShot = false, cardBrowser = true, powerOff = true, focusDrive = true,
        )

    /**
     * `camctrl&type=focus`: "wide-…" steps nearer, "tele-…" farther, "-fast" in bigger steps. The camera
     * has to be in MF (it answers err_reject otherwise) and replies "ok,<position>,<end>".
     */
    override suspend fun driveFocus(farther: Boolean, step: FocusStepSize): FocusDriveResult {
        val direction = if (farther) "tele" else "wide"
        val (speed, repeats) = when (step) {
            FocusStepSize.FINE -> "normal" to 1
            FocusStepSize.MEDIUM -> "normal" to 3
            FocusStepSize.COARSE -> "fast" to 1
        }
        var reply = ""
        repeat(repeats) {
            reply = try {
                lumixCommand(listOf("mode" to "camctrl", "type" to "focus", "value" to "$direction-$speed"), timeout = 5.0)
            } catch (e: PanasonicException) {
                if (e.code == "err_reject") throw CameraException("The camera won't move focus: switch it to MF (manual focus) and try again.")
                throw e
            }
        }
        // Community notes read the two numbers as position and end of travel; unconfirmed on a real body.
        val numbers = reply.split(",").drop(1).mapNotNull { it.trim().toIntOrNull() }
        if (numbers.size >= 2 && numbers[1] > 0 && (if (farther) numbers[0] >= numbers[1] else numbers[0] <= 0)) {
            return FocusDriveResult.END_OF_TRAVEL
        }
        return FocusDriveResult.MOVED
    }

    companion object {
        const val DEVICE_NAME = "Shutterlink"
        const val BULB_CODE = 16384

        val fNumbers = listOf("1.0", "1.1", "1.2", "1.4", "1.6", "1.8", "2.0", "2.2", "2.5", "2.8", "3.2", "3.5",
            "4.0", "4.5", "5.0", "5.6", "6.3", "7.1", "8.0", "9.0", "10", "11", "13", "14", "16", "18", "20", "22")
        val shutterLabels = listOf("60\"", "50\"", "40\"", "30\"", "25\"", "20\"", "15\"", "13\"", "10\"", "8\"",
            "6\"", "5\"", "4\"", "3.2\"", "2.5\"", "2\"", "1.6\"", "1.3\"", "1\"", "1.3",
            "1.6", "2", "2.5", "3", "4", "5", "6", "8", "10", "13", "15", "20", "25", "30", "40",
            "50", "60", "80", "100", "125", "160", "200", "250", "320", "400", "500", "640",
            "800", "1000", "1250", "1600", "2000", "2500", "3200", "4000", "5000", "6400", "8000")
        val isoFallback = listOf("auto", "i_iso", "100", "125", "160", "200", "250", "320", "400", "500", "640", "800",
            "1000", "1250", "1600", "2000", "2500", "3200", "4000", "5000", "6400", "8000", "10000", "12800",
            "16000", "20000", "25600")
        val whiteBalanceFallback = listOf("auto", "daylight", "cloudy", "shade", "halogen", "flash",
            "white_set1", "white_set2", "white_set3", "white_set4")
        /** Panasonic white-balance names → the codes the UI already has names and icons for. */
        val whiteBalanceToUi = mapOf("auto" to "0", "daylight" to "18", "shade" to "16", "cloudy" to "17",
            "halogen" to "20", "incandescent" to "20", "flash" to "23", "white_set1" to "256", "white_set2" to "257",
            "white_set3" to "258", "white_set4" to "259", "color_temp" to "512", "color_temp1" to "512")

        fun lumixResult(text: String): String {
            val start = text.indexOf("<result>")
            if (start >= 0) {
                val end = text.indexOf("</result>", start)
                if (end > start) return text.substring(start + 8, end).trim()
            }
            return text.split(",", limit = 2).firstOrNull()?.trim() ?: ""
        }

        /** "1280/256" → 1280 (codes are APEX × 256). */
        fun lumixCode(fraction: String): Int? {
            val parts = fraction.split("/").mapNotNull { it.trim().toDoubleOrNull() }
            if (parts.size == 2 && parts[1] != 0.0) return (parts[0] * 256 / parts[1]).roundToInt()
            if (parts.size == 1) return parts[0].toInt()
            return null
        }

        fun fLabel(f: Double): String = if (f >= 10) fmt("%.0f", f) else fmt("%.1f", f)
        fun evLabel(thirds: Int): String = if (thirds == 0) "0.0" else fmt("%+.1f", thirds / 3.0)

        /** "-1/3" → -0.333, "2" → 2. */
        fun lumixFraction(text: String): Double {
            val parts = text.split("/").mapNotNull { it.trim().toDoubleOrNull() }
            if (parts.size == 2 && parts[1] != 0.0) return parts[0] / parts[1]
            return parts.firstOrNull() ?: 0.0
        }

        fun lumixDate(text: String): Long? {
            runCatching { return OffsetDateTime.parse(text).toInstant().toEpochMilli() }
            runCatching { return LocalDateTime.parse(text).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli() }
            runCatching { return LocalDate.parse(text).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli() }
            return null
        }

        private fun log2(x: Double) = ln(x) / ln(2.0)
        private fun decode(data: ByteArray): Bitmap? = runCatching { BitmapFactory.decodeByteArray(data, 0, data.size) }.getOrNull()
    }

    /** Stable per-install id; the camera remembers approved phones by it. */
    private val uuid: String
        get() {
            camera.prefs.getString("lumix.uuid", null)?.let { return it }
            val hex = (0 until 12).joinToString("") { "%X".format((0..15).random()) }
            val id = "4D454930-0100-1000-8001-$hex"
            camera.prefs.edit().putString("lumix.uuid", id).apply()
            return id
        }

    override fun teardown() {
        keepAlive?.cancel()
        keepAlive = null
    }

    // MARK: - Commands

    /** Sends cam.cgi and returns the raw reply; throws PanasonicException for "err_…" answers. */
    suspend fun lumixCommand(params: List<Pair<String, String>>, timeout: Double = 8.0, log: Boolean = true): String {
        val text = String(client.get("cam", params, timeout, log))
        val result = lumixResult(text)
        if (result.startsWith("err")) {
            val what = params.firstOrNull { it.first == "value" || it.first == "type" }?.second ?: params.firstOrNull()?.second ?: "cam.cgi"
            throw PanasonicException(result, what)
        }
        return text
    }

    // MARK: - Connect

    override suspend fun connect() {
        val uuid = uuid
        lens = LumixLens()
        menu = emptyMap()
        // Newer bodies (S5IIX, G9II…) say in their UPnP description that they want the newer pairing.
        val description = readDeviceDescription()
        camera.profile = ModelProfiles.find(CameraBrand.PANASONIC, description.model)
        camera.profile?.unsupportedReason?.let { throw CameraException(it) }
        var pairing = if (description.encrypted) LumixPairing.NEWER else (camera.profile?.pairing ?: LumixPairing.STANDARD)
        debugLog("LUMIX model ${description.model ?: "?"} → ${camera.profile?.name ?: "not in the model table"}, pairing $pairing")
        if (pairing == LumixPairing.NEWER) {
            val udn = description.udn
            if (udn != null) {
                try {
                    encryptedPairing(udn)
                } catch (e: PanasonicException) {
                    if (e.code !in setOf("err_param", "err_non_support")) throw e
                    // e.g. the original S5 answers req_acc_g with err_param: it wants the usual pairing.
                    debugLog("LUMIX: newer pairing refused (${e.code}); trying the usual one")
                    pairing = LumixPairing.STANDARD
                }
            } else {
                pairing = LumixPairing.STANDARD
            }
        }
        var attempt = 0
        val deadline = System.currentTimeMillis() + 90_000
        while (pairing == LumixPairing.STANDARD) {
            attempt++
            try {
                val reply = lumixCommand(listOf("mode" to "accctrl", "type" to "req_acc", "value" to uuid, "value2" to DEVICE_NAME), timeout = 5.0)
                if (lumixResult(reply).startsWith("ok_under_research")) {
                    camera.status = "On the camera, choose Yes to allow this phone…"
                    if (System.currentTimeMillis() > deadline) {
                        throw CameraException("The camera is still waiting. Choose Yes on the camera's screen, then tap Connect again.")
                    }
                    delay(1000)
                    continue
                }
                val fields = reply.split(",").map { it.trim() }
                if (fields.size > 1 && fields[1].isNotEmpty()) camera.cameraName = fields[1]
                break
            } catch (e: PanasonicException) {
                if (e.code in setOf("err_non_support", "err_param")) break   // older bodies (GH4) don't pair
                throw e
            } catch (e: IOException) {
                if (e is CameraHttpException || attempt >= 3) throw e
                camera.status = "No answer yet, retrying (${attempt + 1}/3)…"
                delay(1500)
            }
        }

        camera.status = "Reading camera info…"
        runCatching { lumixCommand(listOf("mode" to "setsetting", "type" to "device_name", "value" to DEVICE_NAME)) }
        val info = StringBuilder()
        runCatching { lumixCommand(listOf("mode" to "getinfo", "type" to "capability")) }.getOrNull()?.let { capability ->
            info.append("CAPABILITY\n$capability\n\n")
            if (camera.profile == null) {
                MiniXml.parse(capability)?.firstDescendant("model_name")?.trimmedText?.let {
                    camera.profile = ModelProfiles.find(CameraBrand.PANASONIC, it)
                }
            }
        }
        runCatching { lumixCommand(listOf("mode" to "getinfo", "type" to "lens")) }.getOrNull()?.let {
            info.append("LENS\n$it\n\n")
            applyLumixLens(it)
        }
        runCatching { lumixCommand(listOf("mode" to "getinfo", "type" to "allmenu"), timeout = 15.0) }.getOrNull()?.let {
            camera.rawCommandList = it
            parseLumixMenu(it)
        }
        runCatching { lumixCommand(listOf("mode" to "getstate")) }.getOrNull()?.let {
            info.append("STATE\n$it\n")
            applyLumixState(it)
        }
        camera.rawDescList = info.toString()
        camera.profile?.name?.let { camera.cameraName = it }
        if (camera.cameraName == null) camera.cameraName = "LUMIX"
        startKeepAlive()
    }

    private data class Description(val udn: String?, val encrypted: Boolean, val model: String?)

    private val hostIp: String get() = camera.connectionHost.substringBefore(':')

    /**
     * Reads the camera's UPnP device description on port 60606: its UDN, whether it advertises the
     * newer encrypted pairing (X_CamCapability ending in 1), and the card's ContentDirectory URL.
     */
    private suspend fun readDeviceDescription(): Description {
        val base = "http://$hostIp:60606"
        for (path in listOf("/Server0/ddd", "/Lumix/Server0/ddd")) {
            val data = runCatching { client.fetch(base + path, timeout = 3.0, log = false) }.getOrNull() ?: continue
            val root = MiniXml.parse(data) ?: continue
            rememberContentDirectory(root, base)
            val udn = root.firstDescendant("UDN")?.trimmedText?.replace("uuid:", "")
            val capability = root.firstDescendant("pana:X_CamCapability", "X_CamCapability")?.trimmedText ?: ""
            // modelName is always "LUMIX"; modelNumber is the body, e.g. "DC-GH5".
            val model = root.firstDescendant("modelNumber")?.trimmedText
            debugLog("LUMIX ddd $path: udn=$udn model=$model X_CamCapability=$capability")
            return Description(udn, capability.endsWith("1"), model)
        }
        return Description(null, false, null)
    }

    /**
     * The newer LUMIX pairing (S5IIX, G9II…), as the open-source liblumix does it: req_acc_g, then
     * req_acc_e with the camera's UDN and our name as lowercase hex until the camera says ok; the
     * reply's last field is a session id that goes in an X-SESSION_ID header from then on. Unverified.
     */
    private suspend fun encryptedPairing(udn: String) {
        camera.status = "Pairing with the camera…"
        lumixCommand(listOf("mode" to "accctrl", "type" to "req_acc_g"), timeout = 5.0)
        fun hex(text: String) = text.toByteArray().joinToString("") { "%02x".format(it) }
        val deadline = System.currentTimeMillis() + 90_000
        while (true) {
            val reply = lumixCommand(listOf("mode" to "accctrl", "type" to "req_acc_e", "value" to hex(udn), "value2" to hex(DEVICE_NAME)), timeout = 5.0)
            val fields = reply.split(",").map { it.trim() }
            if (fields.firstOrNull() == "ok") {
                if (fields.size > 1 && fields[1].isNotEmpty()) camera.cameraName = fields[1]
                val session = fields.lastOrNull()
                if (fields.size >= 5 && !session.isNullOrEmpty()) client.extraHeaders = client.extraHeaders + ("X-SESSION_ID" to session)
                return
            }
            if (System.currentTimeMillis() > deadline) {
                throw CameraException("The camera didn't accept this phone. Choose Yes on the camera's screen if it asks, then tap Connect again. (Newer LUMIX pairing is experimental in this app.)")
            }
            if (fields.firstOrNull()?.startsWith("ok_under_research") == true) camera.status = "On the camera, choose Yes to allow this phone…"
            delay(1000)
        }
    }

    private fun rememberContentDirectory(root: XmlNode, base: String) {
        for (service in root.descendants("service")) {
            if (service.value("serviceType")?.contains("ContentDirectory") != true) continue
            val control = service.value("controlURL") ?: continue
            contentDirectory = if (control.startsWith("http")) control else base + (if (control.startsWith("/")) control else "/$control")
            return
        }
    }

    private fun applyLumixLens(reply: String) {
        // ok,<smallest aperture>,<widest aperture>,<fastest shutter>,<slowest shutter>,…,<focal max>,<focal min>
        val f = reply.split(",")
        fun code(i: Int) = f.getOrNull(i)?.let(::lumixCode)
        val l = LumixLens(
            maxFNumber = code(1)?.let { 2.0.pow(it / 512.0) },
            minFNumber = code(2)?.let { 2.0.pow(it / 512.0) },
            minFNumberCode = code(2),
            fastestShutter = code(3),
            slowestShutter = code(4),
            focalMax = f.getOrNull(7)?.trim()?.toIntOrNull(),
            focalMin = f.getOrNull(8)?.trim()?.toIntOrNull(),
        )
        lens = l
        var info = camera.liveInfo
        if (l.minFNumber != null && l.maxFNumber != null && l.minFNumber > 0 && l.maxFNumber >= l.minFNumber) {
            info = info.copy(apertureRange = l.minFNumber..l.maxFNumber)
        }
        // A prime lens reports one focal length: the Astro preset can use it.
        if (l.focalMax != null && l.focalMax == l.focalMin && l.focalMax > 0) info = info.copy(focalLength = l.focalMax)
        camera.liveInfo = info
    }

    private fun parseLumixMenu(xml: String) {
        val root = MiniXml.parse(xml) ?: return
        val result = LinkedHashMap<String, MutableList<String>>()
        for (item in root.descendants("item")) {
            val type = item.attributes["cmd_type"] ?: continue
            val value = item.attributes["cmd_value"] ?: continue
            val list = result.getOrPut(type) { mutableListOf() }
            if (value !in list) list.add(value)
        }
        menu = result
        debugLog("LUMIX menu types: ${result.keys.sorted()}")
    }

    fun applyLumixState(reply: String) {
        val state = MiniXml.parse(reply)?.firstDescendant("state") ?: return
        var info = camera.liveInfo
        state.value("batt")?.let { batt ->
            val parts = batt.replace("%", "").split("/").mapNotNull { it.trim().toDoubleOrNull() }
            if (parts.size == 2 && parts[1] > 0) info = info.copy(battery = (parts[0] / parts[1] * 100).roundToInt())
            else if (parts.size == 1) info = info.copy(battery = parts[0].toInt())
        }
        state.value("remaincapacity")?.toIntOrNull()?.let { info = info.copy(shotsRemaining = it) }
        state.value("temperature")?.let { info = info.copy(temperatureWarning = it.lowercase() !in setOf("", "normal", "off")) }
        if (info != camera.liveInfo) camera.liveInfo = info
    }

    /** Polls getstate every second: keeps live view and the connection alive, refreshes battery. */
    private fun startKeepAlive() {
        keepAlive?.cancel()
        keepAlive = camera.scope.launch {
            var failures = 0
            while (isActive) {
                delay(1000)
                if (camera.phase == ConnectionPhase.DISCONNECTED) return@launch
                try {
                    val reply = lumixCommand(listOf("mode" to "getstate"), timeout = 3.0, log = false)
                    if (failures >= 3) camera.lastError = null
                    failures = 0
                    applyLumixState(reply)
                    // If frames stop, ask again (the camera can drop the stream after a hiccup).
                    if (camera.liveViewRunning && camera.mode == CameraMode.REC && camera.isLiveViewStalled(System.currentTimeMillis()) &&
                        System.currentTimeMillis() - lastStreamKick > 3000) {
                        lastStreamKick = System.currentTimeMillis()
                        runCatching { lumixCommand(listOf("mode" to "startstream", "value" to camera.udpPort.toString())) }
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (ignored: Exception) {
                    failures++
                    if (failures == 3) camera.lastError = "Lost contact with the camera. Check that this phone is still on the camera's Wi-Fi."
                }
            }
        }
    }

    override suspend fun powerOff() {
        runCatching { lumixCommand(listOf("mode" to "camcmd", "value" to "recmode"), timeout = 3.0) }
        runCatching { lumixCommand(listOf("mode" to "camcmd", "value" to "poweroff"), timeout = 3.0) }
    }

    // MARK: - Live view

    override suspend fun enterRecMode() {
        camera.isSwitchingMode = true
        try {
            runCatching { lumixCommand(listOf("mode" to "stopstream"), timeout = 3.0) }
            lumixCommand(listOf("mode" to "camcmd", "value" to "recmode"), timeout = 5.0)
            camera.mode = CameraMode.REC
            // The new size only applies to the next startstream.
            val size = if (camera.liveViewQuality == "0320x0240") "qvga" else "vga"
            runCatching { lumixCommand(listOf("mode" to "setsetting", "type" to "liveviewsize", "value" to size)) }
            delay(300)
            camera.isSwitchingMode = false
            camera.refreshProperties()
            camera.startLiveView()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            camera.report(e)
        } finally {
            camera.isSwitchingMode = false
        }
    }

    override suspend fun startLiveView() {
        try {
            lastStreamKick = System.currentTimeMillis()
            lumixCommand(listOf("mode" to "startstream", "value" to camera.udpPort.toString()))
        } catch (e: Exception) {
            camera.liveViewRunning = false
            camera.report(e)
        }
    }

    override suspend fun stopLiveView() {
        runCatching { lumixCommand(listOf("mode" to "stopstream"), timeout = 3.0) }
    }

    // MARK: - Settings

    override suspend fun refreshProperties() {
        val result = LinkedHashMap<String, CameraProperty>()
        suspend fun current(type: String): String? {
            val reply = runCatching { lumixCommand(listOf("mode" to "getsetting", "type" to type), log = false) }.getOrNull() ?: return null
            return MiniXml.parse(reply)?.firstDescendant("settingvalue")?.attributes?.get(type)
        }

        // Aperture: third stops within the lens's range, plus its exact widest value.
        val apertures = apertureOptions()
        current("focal")?.let(::lumixCode)?.let { code ->
            result["focalvalue"] = CameraProperty("focalvalue", true, nearest(code, apertureCodes) ?: apertures.firstOrNull() ?: "", apertures)
        }
        val shutters = shutterOptions()
        current("shtrspeed")?.let(::lumixCode)?.let { code ->
            val value = if (code == BULB_CODE) "bulb" else nearest(code, shutterCodes) ?: ""
            result["shutspeedvalue"] = CameraProperty("shutspeedvalue", true, value, shutters)
        }
        current("iso")?.let { raw ->
            val options = menu["iso"] ?: isoFallback
            result["isospeedvalue"] = CameraProperty("isospeedvalue", true, raw, if (raw in options) options else options + raw)
        }
        current("exposure")?.let { raw ->
            val options = (-15..15).map(::evLabel)
            result["expcomp"] = CameraProperty("expcomp", true, evLabel((lumixFraction(raw) * 3).roundToInt()), options)
        }
        current("whitebalance")?.let { raw ->
            val names = menu["whitebalance"] ?: whiteBalanceFallback
            val codes = LinkedHashMap<String, String>()
            val options = mutableListOf<String>()
            for (name in names + raw) {
                val ui = whiteBalanceToUi[name] ?: name
                if (ui !in codes) {
                    codes[ui] = name
                    options.add(ui)
                }
            }
            whiteBalanceCodes = codes
            result["wbvalue"] = CameraProperty("wbvalue", true, whiteBalanceToUi[raw] ?: raw, options)
        }
        // Bodies whose controls are physical or fixed: show the values, don't offer to change them.
        camera.profile?.let { profile ->
            fun lock(name: String) { result[name]?.let { result[name] = it.copy(settable = false) } }
            if (profile.fixedExposure) { lock("focalvalue"); lock("shutspeedvalue") }
            if (profile.noExposureComp) lock("expcomp")
            if (profile.noISO) lock("isospeedvalue")
        }
        camera.properties = result
    }

    override suspend fun setProperty(name: String, value: String, reportErrors: Boolean): Boolean {
        val setting: Pair<String, String>? = when (name) {
            "focalvalue" -> apertureCodes[value]?.let { "focal" to "$it/256" }
            "shutspeedvalue" -> if (value == "bulb") "shtrspeed" to "$BULB_CODE/256" else shutterCodes[value]?.let { "shtrspeed" to "$it/256" }
            "isospeedvalue" -> "iso" to value
            "expcomp" -> {
                val thirds = ((value.toDoubleOrNull() ?: 0.0) * 3).roundToInt()
                "exposure" to (if (thirds % 3 == 0) "${thirds / 3}" else "$thirds/3")
            }
            "wbvalue" -> "whitebalance" to (whiteBalanceCodes[value] ?: value)
            else -> null
        }
        if (setting == null) {
            if (reportErrors) camera.lastError = "This setting can't be changed on a LUMIX camera from the app."
            return false
        }
        val previous = camera.properties[name]?.value
        camera.updateValue(name, value)
        try {
            lumixCommand(listOf("mode" to "setsetting", "type" to setting.first, "value" to setting.second))
        } catch (e: Exception) {
            if (previous != null) camera.updateValue(name, previous)
            if (reportErrors) camera.report(e)
            refreshProperties()
            return false
        }
        refreshProperties()
        return true
    }

    private fun apertureOptions(): List<String> {
        val codes = LinkedHashMap<String, Int>()
        val options = mutableListOf<String>()
        val widest = lens.minFNumber
        val widestCode = lens.minFNumberCode
        if (widest != null && widestCode != null) {
            val label = fLabel(widest)
            options.add(label)
            codes[label] = widestCode
        }
        for (label in fNumbers) {
            val f = label.toDoubleOrNull() ?: continue
            if (label in codes) continue
            val lo = lens.minFNumber
            if (lo != null && f < lo + 0.05) continue
            val hi = lens.maxFNumber
            if (hi != null && f > hi + 0.05) continue
            // Third-stop grid: Av = 2·log2(N) rounded to thirds, × 256.
            val thirds = Math.rint(2 * log2(f) * 3)
            codes[label] = (256 * thirds / 3).roundToInt()
            options.add(label)
        }
        apertureCodes = codes
        return options
    }

    private fun shutterOptions(): List<String> {
        val codes = LinkedHashMap<String, Int>()
        val options = mutableListOf<String>()
        val fast = lens.fastestShutter ?: 3328     // 1/8000
        val slow = lens.slowestShutter ?: -1536    // 60 s
        for (label in shutterLabels) {
            val seconds = PropertyFormat.seconds(label) ?: continue
            val thirds = Math.rint(-log2(seconds) * 3)
            val code = (256 * thirds / 3).roundToInt()
            if (code < minOf(slow, fast) || code > maxOf(slow, fast)) continue
            codes[label] = code
            options.add(label)
        }
        shutterCodes = codes
        return listOf("bulb") + options
    }

    private fun nearest(code: Int, table: Map<String, Int>): String? = table.minByOrNull { abs(it.value - code) }?.key

    // MARK: - Focus & shooting

    override suspend fun focus(x: Double, y: Double) {
        // Touch AF in a 0–1000 grid over the live-view frame.
        val gx = (x * 1000).roundToInt()
        val gy = (y * 1000).roundToInt()
        try {
            lumixCommand(listOf("mode" to "camctrl", "type" to "touch", "value" to "$gx/$gy", "value2" to "on"))
        } catch (e: PanasonicException) {
            if (e.code == "err_param") {
                // Older bodies use touchaf.
                runCatching { lumixCommand(listOf("mode" to "camctrl", "type" to "touchaf", "value" to "$gx/$gy")) }
            } else {
                camera.report(e)
            }
        } catch (e: Exception) {
            camera.report(e)
        }
    }

    override suspend fun releaseFocus() {
        runCatching { lumixCommand(listOf("mode" to "camctrl", "type" to "touch", "value" to "0/0", "value2" to "off")) }
    }

    override suspend fun shutterPressed() {
        camera.isShooting = true
        val seconds = PropertyFormat.seconds(camera.properties["shutspeedvalue"]?.value ?: "") ?: 0.0
        if (seconds >= 1) {
            camera.exposureStartedAt = System.currentTimeMillis()
            camera.exposureDuration = seconds
        }
        try {
            lumixCommand(listOf("mode" to "camcmd", "value" to "capture"), timeout = 10.0)
            // capture returns straight away; keep the countdown honest for long exposures.
            if (seconds >= 1) delay(((seconds + 0.5) * 1000).toLong())
            camera.shotCounter++
            runCatching { lumixCommand(listOf("mode" to "camcmd", "value" to "autoreviewunlock"), timeout = 3.0, log = false) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            camera.report(e)
        } finally {
            camera.exposureStartedAt = null
            camera.exposureDuration = null
            camera.isShooting = false
        }
    }

    /** Bulb: first tap opens the shutter, second tap closes it. */
    override suspend fun toggleOpenExposure() {
        if (camera.isShooting) {
            runCatching { lumixCommand(listOf("mode" to "camcmd", "value" to "capture_cancel")) }
            camera.isShooting = false
            camera.exposureStartedAt = null
            camera.shotCounter++
            return
        }
        camera.isShooting = true
        camera.exposureStartedAt = System.currentTimeMillis()
        camera.exposureDuration = null
        try {
            lumixCommand(listOf("mode" to "camcmd", "value" to "capture"), timeout = 10.0)
        } catch (e: Exception) {
            camera.isShooting = false
            camera.exposureStartedAt = null
            camera.report(e)
        }
    }

    override suspend fun toggleMovie() {
        if (camera.isRecordingMovie) {
            runCatching { lumixCommand(listOf("mode" to "camcmd", "value" to "video_recstop")) }
            camera.isRecordingMovie = false
            camera.movieStartedAt = null
            camera.shotCounter++
        } else {
            try {
                lumixCommand(listOf("mode" to "camcmd", "value" to "video_recstart"))
                camera.isRecordingMovie = true
                camera.movieStartedAt = System.currentTimeMillis()
            } catch (e: Exception) {
                camera.report(e)
            }
        }
    }

    // LUMIX review images need playback mode, which would stop live view, so there's no quick review,
    // and the clock can't be set over Wi-Fi: both are off in `capabilities`.

    // MARK: - Card (UPnP ContentDirectory)

    override suspend fun openGallery() {
        try {
            lumixCommand(listOf("mode" to "camcmd", "value" to "playmode"), timeout = 5.0)
            camera.mode = CameraMode.PLAY
            delay(1000)
            val control = contentDirectoryUrl()
            val found = mutableListOf<CameraImage>()
            for (entry in browse(control, "0")) {
                when (entry) {
                    is Entry.Item -> found += entry.images
                    is Entry.Container -> browse(control, entry.id).filterIsInstance<Entry.Item>().forEach { found += it.images }
                }
            }
            camera.images = found.sortedWith(compareByDescending<CameraImage> { it.date }.thenByDescending { it.name })
            camera.cardFolders = listOf(CardFolder("LUMIX", camera.cameraName ?: "LUMIX", camera.images.size, isForeign = false))
        } catch (e: Exception) {
            camera.galleryError = camera.describe(e, camera.connectionHost)
        }
    }

    override suspend fun thumbnail(image: CameraImage): Bitmap? {
        val urls = image.urls ?: return null
        val data = runCatching { client.fetch(urls.thumbnail ?: urls.preview ?: urls.original, log = false) }.getOrNull() ?: return null
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

    /** Finds the ContentDirectory control URL from the camera's UPnP device description. */
    private suspend fun contentDirectoryUrl(): String {
        contentDirectory?.let { return it }
        val base = "http://$hostIp:60606"
        for (path in listOf("/Server0/ddd", "/Lumix/Server0/ddd")) {
            val data = runCatching { client.fetch(base + path, timeout = 5.0) }.getOrNull() ?: continue
            val root = MiniXml.parse(data) ?: continue
            rememberContentDirectory(root, base)
            contentDirectory?.let { return it }
        }
        // Fall back to the usual control path.
        return "$base/Server0/CDS_control".also { contentDirectory = it }
    }

    private sealed class Entry {
        class Item(val images: List<CameraImage>) : Entry()
        class Container(val id: String) : Entry()
    }

    private suspend fun browse(control: String, objectId: String): List<Entry> {
        val entries = mutableListOf<Entry>()
        var start = 0
        while (true) {
            val body = """<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1" xmlns:pana="urn:schemas-panasonic-com:pana">
<ObjectID>$objectId</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter>
<StartingIndex>$start</StartingIndex><RequestedCount>50</RequestedCount><SortCriteria></SortCriteria>
<pana:X_FromCP>LumixLink2.0</pana:X_FromCP></u:Browse></s:Body></s:Envelope>"""
            val data = client.soap(control, "urn:schemas-upnp-org:service:ContentDirectory:1#Browse", body)
            val response = MiniXml.parse(data) ?: break
            val didl = response.firstDescendant("Result")?.trimmedText ?: break
            val root = MiniXml.parse(didl) ?: break
            val returned = response.firstDescendant("NumberReturned")?.trimmedText?.toIntOrNull() ?: 0
            val total = response.firstDescendant("TotalMatches")?.trimmedText?.toIntOrNull() ?: 0
            for (node in root.children) {
                val id = node.attributes["id"]
                if (node.name == "container" && id != null) entries.add(Entry.Container(id))
                else if (node.name == "item") entries.add(Entry.Item(lumixImages(node)))
            }
            start += returned
            if (returned == 0 || start >= total) break
        }
        return entries
    }

    /** One UPnP item → its JPEG/MP4 and (if present) its RAW file. */
    private fun lumixImages(item: XmlNode): List<CameraImage> {
        var original: String? = null
        var raw: String? = null
        var thumb: String? = null
        var large: String? = null
        var size = 0L
        var rawSize = 0L
        for (res in item.children("res")) {
            val kind = res.attributes["protocolInfo"] ?: ""
            val url = res.trimmedText
            val bytes = res.attributes["size"]?.toLongOrNull() ?: 0
            when {
                kind.contains("CAM_RAW") -> { raw = url; rawSize = bytes }
                kind.contains("CAM_LRGTN") -> large = url
                kind.contains("CAM_TN") -> thumb = url
                kind.contains("CAM_ORG") -> { original = url; size = bytes }
            }
        }
        val title = item.value("dc:title") ?: item.attributes["id"] ?: "photo"
        val date = item.value("dc:date")?.let(::lumixDate) ?: 0L
        val result = mutableListOf<CameraImage>()
        original?.let {
            val ext = it.substringAfterLast('/').substringAfterLast('.', "").uppercase().ifEmpty { "JPG" }
            result.add(CameraImage("LUMIX", "$title.$ext", size, 0, date, MediaUrls(thumb, large ?: thumb, it)))
        }
        raw?.let {
            result.add(CameraImage("LUMIX", "$title.RW2", rawSize, 0, date, MediaUrls(thumb, large ?: thumb, it)))
        }
        return result
    }
}

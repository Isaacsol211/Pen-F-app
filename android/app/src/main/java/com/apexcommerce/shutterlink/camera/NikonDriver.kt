package com.apexcommerce.shutterlink.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import kotlin.random.Random

// Nikon over the camera's own Wi-Fi: PTP/IP on TCP 15740 (see PtpIp.kt), with Nikon's vendor
// operations, the same ones Nikon's apps and libgphoto2 use over USB. Port of Nikon.swift.
//
//   Session: OpenSession, GetDeviceInfo (model, supported operations and properties).
//   Live view: StartLiveView 0x9201, poll DeviceReady 0x90C8 until it stops answering Busy, then
//              GetLiveViewImg 0x9203 in a loop (a model-specific header, then the JPEG).
//   Shooting: InitiateCaptureRecInMedia 0x9207 (to the card, live view stays on) or
//             InitiateCapture 0x100E on older bodies.
//   Settings: GetDevicePropDesc / SetDevicePropValue on FNumber 0x5007 (f × 100),
//             ExposureTime 0x500D, ExposureIndex 0x500F (ISO), ExposureBiasCompensation 0x5010
//             (1/1000 EV), WhiteBalance 0x5005, ExposureProgramMode 0x500E, Nikon auto ISO 0xD054.
//   Card: GetStorageIDs, GetObjectHandles, GetObjectInfo, GetThumb, GetPartialObject.

object PtpOp {
    const val GET_DEVICE_INFO = 0x1001
    const val OPEN_SESSION = 0x1002
    const val CLOSE_SESSION = 0x1003
    const val GET_STORAGE_IDS = 0x1004
    const val GET_OBJECT_HANDLES = 0x1007
    const val GET_OBJECT_INFO = 0x1008
    const val GET_OBJECT = 0x1009
    const val GET_THUMB = 0x100A
    const val INITIATE_CAPTURE = 0x100E
    const val GET_PARTIAL_OBJECT = 0x101B
    const val GET_DEVICE_PROP_DESC = 0x1014
    const val GET_DEVICE_PROP_VALUE = 0x1015
    const val SET_DEVICE_PROP_VALUE = 0x1016

    const val NIKON_CAPTURE_TO_SDRAM = 0x90C0
    const val NIKON_AF_DRIVE = 0x90C1
    const val NIKON_CHANGE_CAMERA_MODE = 0x90C2
    const val NIKON_GET_LARGE_THUMB = 0x90C4
    const val NIKON_GET_EVENT = 0x90C7
    const val NIKON_DEVICE_READY = 0x90C8
    const val NIKON_START_LIVE_VIEW = 0x9201
    const val NIKON_END_LIVE_VIEW = 0x9202
    const val NIKON_GET_LIVE_VIEW_IMAGE = 0x9203
    const val NIKON_MF_DRIVE = 0x9204
    const val NIKON_CHANGE_AF_AREA = 0x9205
    const val NIKON_CAPTURE_TO_CARD = 0x9207
    const val NIKON_START_MOVIE = 0x920A
    const val NIKON_END_MOVIE = 0x920B
    const val NIKON_GET_EVENT_EX = 0x941C
    const val NIKON_GET_LIVE_VIEW_IMAGE_EX = 0x9428
}

object PtpProp {
    const val BATTERY_LEVEL = 0x5001
    const val WHITE_BALANCE = 0x5005
    const val F_NUMBER = 0x5007
    const val FOCAL_LENGTH = 0x5008
    const val EXPOSURE_TIME = 0x500D
    const val EXPOSURE_PROGRAM = 0x500E
    const val ISO = 0x500F
    const val EXPOSURE_BIAS = 0x5010
    const val NIKON_AUTO_ISO = 0xD054
    /** Nikon's own exposure time, numerator << 16 | denominator (0x500D is in 1/10000 s). */
    const val NIKON_EXPOSURE_TIME = 0xD100
}

object NikonResponse {
    const val OUT_OF_FOCUS = 0xA002
    const val CHANGE_CAMERA_MODE_FAILED = 0xA003
    const val INVALID_STATUS = 0xA004
    const val NOT_LIVE_VIEW = 0xA00B
    const val MF_DRIVE_STEP_END = 0xA00C
    const val MF_DRIVE_STEP_INSUFFICIENCY = 0xA00E
    const val BULB_RELEASE_BUSY = 0xA200
    const val SILENT_RELEASE_BUSY = 0xA201
    const val MEDIA_FULL = 0xA207

    /** Answers that mean "not yet, ask again". */
    fun isBusy(code: Int): Boolean =
        code == PtpException.DEVICE_BUSY || code == INVALID_STATUS || code == BULB_RELEASE_BUSY || code == MEDIA_FULL
}

class NikonDriver(private val camera: CameraModel) : CameraDriver {
    private val ptp: PtpIpClient
    private var info: PtpDeviceInfo? = null
    private val descs = HashMap<Int, PtpPropDesc>()
    /** UI value → raw camera value, per property name. */
    private var valueMap: Map<String, Map<String, Long>> = emptyMap()
    private var liveJob: Job? = null
    private var statusJob: Job? = null
    /** Object handles by path, so previews and downloads can find them again. */
    private val handles = HashMap<String, Long>()

    init {
        val (host, port) = splitHost(camera.connectionHost, 15740)
        ptp = PtpIpClient(host, port)
    }

    override val liveViewFormat: LiveViewFormat get() = LiveViewFormat.PUSHED

    private fun supports(op: Int): Boolean = info?.operations?.contains(op) ?: false
    private fun hasProperty(code: Int): Boolean = info?.properties?.contains(code) ?: false

    override val capabilities: CameraCapabilities
        get() = CameraCapabilities(
            liveViewSizes = emptyList(), tapToFocus = supports(PtpOp.NIKON_AF_DRIVE),
            openEndedExposure = false,
            movie = supports(PtpOp.NIKON_START_MOVIE), videoSwitch = true,
            lastShotReview = supports(PtpOp.NIKON_GET_EVENT) || supports(PtpOp.NIKON_GET_EVENT_EX),
            clockSync = false, highResShot = false, cardBrowser = supports(PtpOp.GET_OBJECT_HANDLES),
            powerOff = false, focusDrive = supports(PtpOp.NIKON_MF_DRIVE),
        )

    /**
     * MfDrive (0x9204): direction 1 = towards the closest point, 2 = towards infinity, then an amount
     * (1–32767). Only works in live view and with the lens's AF/MF switch on AF (the camera drives it).
     */
    override suspend fun driveFocus(farther: Boolean, step: FocusStepSize): FocusDriveResult {
        val amount = when (step) {
            FocusStepSize.FINE -> 40L
            FocusStepSize.MEDIUM -> 120L
            FocusStepSize.COARSE -> 400L
        }
        for (attempt in 0 until 2) {
            val response = ptp.transaction(PtpOp.NIKON_MF_DRIVE, listOf(if (farther) 2L else 1L, amount), timeout = 10.0)
            when (response.code) {
                PtpException.OK -> {
                    waitUntilReady()
                    return FocusDriveResult.MOVED
                }
                NikonResponse.MF_DRIVE_STEP_END, NikonResponse.MF_DRIVE_STEP_INSUFFICIENCY -> return FocusDriveResult.END_OF_TRAVEL
                NikonResponse.NOT_LIVE_VIEW ->
                    // Live view pauses around each capture; give it a moment to come back.
                    if (attempt == 0) delay(800) else throw CameraException("The camera only moves focus while live view is on.")
                else -> throw PtpException(response.code, PtpOp.NIKON_MF_DRIVE)
            }
        }
        return FocusDriveResult.MOVED
    }

    /** Stable per-install id: cameras that remember paired devices know us by it. */
    private fun guid(): ByteArray {
        val key = "nikon.guid"
        val saved = camera.prefs.getString(key, null)?.chunked(2)?.mapNotNull { it.toIntOrNull(16)?.toByte() }
        if (saved != null && saved.size == 16) return saved.toByteArray()
        val fresh = Random.nextBytes(16)
        camera.prefs.edit().putString(key, fresh.joinToString("") { fmt("%02x", it.toInt() and 0xFF) }).apply()
        return fresh
    }

    private val deviceName: String get() = "Shutterlink (" + android.os.Build.MODEL + ")"

    // MARK: - Connect

    override suspend fun connect() {
        ptp.logger = { line ->
            debugLog(line)
            camera.scope.launch { camera.appendLog(LogEntry(System.currentTimeMillis(), "PTP", line, 200, 0, "")) }
        }
        camera.status = "Connecting (PTP/IP)…"
        var failure: Exception? = null
        for (attempt in 1..3) {
            try {
                ptp.connect(guid(), deviceName)
                failure = null
                break
            } catch (e: CancellationException) {
                withContext(Dispatchers.IO) { ptp.close() }
                throw e
            } catch (e: Exception) {
                failure = e
                withContext(Dispatchers.IO) { ptp.close() }
                if (attempt >= 3 || e is CameraException) break
                camera.status = "No answer yet, retrying (${attempt + 1}/3)…"
                delay(1500)
            }
        }
        failure?.let { throw it }

        ptp.run(PtpOp.OPEN_SESSION, listOf(1L))
        camera.status = "Reading camera info…"
        val deviceInfo = PtpDeviceInfo(ptp.run(PtpOp.GET_DEVICE_INFO).data)
        info = deviceInfo
        val name = ptp.cameraName
        camera.cameraName = if (deviceInfo.model.isEmpty()) name.ifEmpty { "Nikon" } else displayName(deviceInfo.model)
        camera.rawCommandList = "Model: ${deviceInfo.model} ${deviceInfo.version}\nOperations: " +
            deviceInfo.operations.sorted().joinToString(" ") { fmt("0x%04X", it) } +
            "\nProperties: " + deviceInfo.properties.sorted().joinToString(" ") { fmt("0x%04X", it) }
        debugLog("NIKON ${camera.rawCommandList}")
        // Don't touch RecordingMedia (0xD10B): writing it hung a D600 over Wi-Fi (libgphoto2 bug 959).
        startStatus()
    }

    override suspend fun disconnect() {
        ptpOrNull { ptp.transaction(PtpOp.CLOSE_SESSION, timeout = 3.0) }
    }

    override fun teardown() {
        liveJob?.cancel()
        liveJob = null
        statusJob?.cancel()
        statusJob = null
        val ptp = ptp
        camera.scope.launch(Dispatchers.IO) { ptp.close() }
    }

    /**
     * Battery every few seconds; also keeps the session alive (Nikon drops one idle for ~30 s)
     * and notices when the camera has gone.
     */
    private fun startStatus() {
        statusJob?.cancel()
        statusJob = camera.scope.launch {
            var failures = 0
            while (isActive) {
                val level = ptpOrNull { readRaw(PtpProp.BATTERY_LEVEL) }
                if (level != null) {
                    failures = 0
                    if (camera.liveInfo.battery != level.toInt()) camera.liveInfo = camera.liveInfo.copy(battery = level.toInt())
                } else if (hasProperty(PtpProp.BATTERY_LEVEL)) {
                    failures++
                    if (failures == 3) {
                        camera.lastError = "Lost contact with the camera. Check that this phone is still on the camera's Wi-Fi."
                    }
                }
                delay(5000)
            }
        }
    }

    // MARK: - Helpers

    private suspend fun readRaw(code: Int): Long {
        if (!hasProperty(code)) throw CameraException("No such property.")
        val desc = PtpPropDesc(ptp.run(PtpOp.GET_DEVICE_PROP_DESC, listOf(code.toLong()), timeout = 5.0).data)
        descs[code] = desc
        return desc.current
    }

    private suspend fun setRaw(code: Int, value: Long) {
        val desc = descs[code] ?: PtpPropDesc(ptp.run(PtpOp.GET_DEVICE_PROP_DESC, listOf(code.toLong())).data).also {
            descs[code] = it
        }
        ptp.run(PtpOp.SET_DEVICE_PROP_VALUE, listOf(code.toLong()), dataOut = desc.encode(value))
    }

    /** Polls DeviceReady until the camera stops answering Busy (after live view start, capture, AF). */
    private suspend fun waitUntilReady(timeout: Double = 10.0): Int {
        if (!supports(PtpOp.NIKON_DEVICE_READY)) {
            delay(500)
            return PtpException.OK
        }
        val deadline = System.currentTimeMillis() + (timeout * 1000).toLong()
        while (System.currentTimeMillis() < deadline) {
            val response = ptpOrNull { ptp.transaction(PtpOp.NIKON_DEVICE_READY, timeout = 5.0) } ?: break
            if (response.code == NikonResponse.SILENT_RELEASE_BUSY) return PtpException.OK
            if (response.code != PtpException.DEVICE_BUSY && response.code != NikonResponse.BULB_RELEASE_BUSY) return response.code
            delay(100)
        }
        return PtpException.DEVICE_BUSY
    }

    private suspend fun decode(bytes: ByteArray, maxSide: Int = 0): Bitmap? = withContext(Dispatchers.Default) {
        if (maxSide <= 0) return@withContext BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
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

    private val liveViewOp: Int
        get() = if (supports(PtpOp.NIKON_GET_LIVE_VIEW_IMAGE) || !supports(PtpOp.NIKON_GET_LIVE_VIEW_IMAGE_EX))
            PtpOp.NIKON_GET_LIVE_VIEW_IMAGE else PtpOp.NIKON_GET_LIVE_VIEW_IMAGE_EX

    override suspend fun startLiveView() {
        if (!supports(PtpOp.NIKON_START_LIVE_VIEW)) {
            camera.liveViewRunning = false
            camera.lastError = "This Nikon doesn't offer live view over Wi-Fi. You can still change settings and shoot."
            return
        }
        try {
            // Remote ("PC") mode first, as libgphoto2 does; bodies that are already there say 0xA003.
            if (supports(PtpOp.NIKON_CHANGE_CAMERA_MODE)) {
                ptpOrNull { ptp.transaction(PtpOp.NIKON_CHANGE_CAMERA_MODE, listOf(1L)) }
            }
            ptp.run(PtpOp.NIKON_START_LIVE_VIEW)
            waitUntilReady(5.0)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            camera.liveViewRunning = false
            camera.report(e)
            return
        }
        val ptp = ptp
        val op = liveViewOp
        liveJob?.cancel()
        liveJob = camera.pullLiveView(everyMs = 15) {
            // A header (128 or 384 bytes, by model) comes before the JPEG; the receiver finds FF D8.
            val response = ptp.transaction(op, timeout = 5.0)
            when (response.code) {
                PtpException.OK -> response.data
                PtpException.DEVICE_BUSY, NikonResponse.INVALID_STATUS -> {
                    delay(30)
                    null
                }
                NikonResponse.NOT_LIVE_VIEW -> {
                    // The camera left live view (e.g. after a shot or on its own): start it again.
                    ptpOrNull { ptp.transaction(PtpOp.NIKON_START_LIVE_VIEW) }
                    delay(300)
                    null
                }
                else -> throw PtpException(response.code, op)
            }
        }
    }

    override suspend fun stopLiveView() {
        liveJob?.cancel()
        liveJob = null
        ptpOrNull { ptp.transaction(PtpOp.NIKON_END_LIVE_VIEW, timeout = 5.0) }
    }

    // MARK: - Settings

    override suspend fun refreshProperties() {
        val result = LinkedHashMap<String, CameraProperty>()
        val newMap = HashMap<String, Map<String, Long>>()

        suspend fun desc(code: Int): PtpPropDesc? {
            if (!hasProperty(code)) return null
            val data = ptpOrNull { ptp.run(PtpOp.GET_DEVICE_PROP_DESC, listOf(code.toLong()), timeout = 5.0).data } ?: return null
            return PtpPropDesc(data).also { descs[code] = it }
        }

        fun add(name: String, d: PtpPropDesc, label: (Long) -> String?) {
            val map = LinkedHashMap<String, Long>()
            val options = mutableListOf<String>()
            for (raw in d.allowed) {
                val text = label(raw) ?: continue
                if (text in map) continue
                map[text] = raw
                options.add(text)
            }
            val value = label(d.current) ?: d.current.toString()
            if (value !in map) map[value] = d.current
            newMap[name] = map
            if (value !in options) options.add(value)
            result[name] = CameraProperty(name, d.settable && options.size > 1, value, options)
        }

        desc(PtpProp.EXPOSURE_PROGRAM)?.let { d -> add("takemode", d) { modeLabel(it) } }
        val fNumber = desc(PtpProp.F_NUMBER)
        if (fNumber != null && fNumber.current > 0) {
            add("focalvalue", fNumber) { if (it > 0) ExposureText.aperture(it / 100.0) else null }
            val fs = fNumber.allowed.filter { it > 0 }.map { it / 100.0 }
            val lo = fs.minOrNull()
            val hi = fs.maxOrNull()
            if (lo != null && hi != null && hi > lo) camera.liveInfo = camera.liveInfo.copy(apertureRange = lo..hi)
        }
        val nikonShutter = if (hasProperty(PtpProp.NIKON_EXPOSURE_TIME)) desc(PtpProp.NIKON_EXPOSURE_TIME) else null
        if (nikonShutter != null) {
            add("shutspeedvalue", nikonShutter) { shutterLabel(it, packed = true) }
        } else {
            desc(PtpProp.EXPOSURE_TIME)?.let { d -> add("shutspeedvalue", d) { shutterLabel(it, packed = false) } }
        }
        val isoDesc = desc(PtpProp.ISO)
        if (isoDesc != null) {
            val auto = desc(PtpProp.NIKON_AUTO_ISO)
            add("isospeedvalue", isoDesc) { if (it > 0) it.toString() else null }
            val iso = result["isospeedvalue"]
            if (auto != null && auto.settable && iso != null) {
                // Nikon's auto ISO is a separate on/off switch; show it as one more ISO choice.
                result["isospeedvalue"] = iso.copy(
                    options = listOf("auto") + iso.options,
                    value = if (auto.current != 0L) "auto" else iso.value,
                    settable = true,
                )
            }
        }
        desc(PtpProp.EXPOSURE_BIAS)?.let { d -> add("expcomp", d) { ExposureText.ev(it / 1000.0) } }
        desc(PtpProp.WHITE_BALANCE)?.let { d -> add("wbvalue", d) { whiteBalanceCode(it) } }
        val focal = desc(PtpProp.FOCAL_LENGTH)
        if (focal != null && focal.current > 0) {
            camera.liveInfo = camera.liveInfo.copy(focalLength = (focal.current / 100).toInt())
        }
        valueMap = newMap
        camera.properties = result
    }

    override suspend fun setProperty(name: String, value: String, reportErrors: Boolean): Boolean {
        val code = when (name) {
            "takemode" -> PtpProp.EXPOSURE_PROGRAM
            "focalvalue" -> PtpProp.F_NUMBER
            "shutspeedvalue" -> if (hasProperty(PtpProp.NIKON_EXPOSURE_TIME)) PtpProp.NIKON_EXPOSURE_TIME else PtpProp.EXPOSURE_TIME
            "isospeedvalue" -> PtpProp.ISO
            "expcomp" -> PtpProp.EXPOSURE_BIAS
            "wbvalue" -> PtpProp.WHITE_BALANCE
            else -> null
        }
        if (code == null) {
            if (reportErrors) camera.lastError = "This setting can't be changed on a Nikon from the app."
            return false
        }
        val previous = camera.properties[name]?.value
        camera.updateValue(name, value)
        try {
            if (name == "isospeedvalue" && hasProperty(PtpProp.NIKON_AUTO_ISO)) {
                setRaw(PtpProp.NIKON_AUTO_ISO, if (value == "auto") 1L else 0L)
                if (value == "auto") {
                    refreshProperties()
                    return true
                }
            }
            val raw = valueMap[name]?.get(value) ?: throw CameraException("The camera doesn't offer $value.")
            setRaw(code, raw)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (previous != null) camera.updateValue(name, previous)
            if (reportErrors) camera.report(e)
            refreshProperties()
            return false
        }
        refreshProperties()
        return true
    }

    companion object {
        /** Nikon reports Mark II/III bodies as "Z 6_2", "Z 7_3": show them as people write them. */
        fun displayName(model: String): String = model.replace("_2", " II").replace("_3", " III")

        fun modeLabel(raw: Long): String = when (raw) {
            1L -> "M"
            2L -> "P"
            3L -> "A"
            4L -> "S"
            0x8010L, 0x8012L -> "iAuto"
            0x8050L -> "U1"
            0x8051L -> "U2"
            0x8052L -> "U3"
            in 0x8011L..0x804FL -> "SCN"
            else -> fmt("0x%X", raw)
        }

        /**
         * Exposure time: Nikon's 0xD100 packs numerator << 16 | denominator (0x00010FA0 = 1/4000 s,
         * 0x001E0001 = 30 s); PTP's 0x500D is in 1/10000 s. Bulb and Time are 0xFFFFFFFF / 0xFFFFFFFD.
         */
        fun shutterSeconds(raw: Long, packed: Boolean): Double? {
            val value = raw and 0xFFFF_FFFFL
            if (value >= 0xFFFF_FFFCL || value == 0L) return null
            if (packed) {
                val numerator = (value shr 16).toDouble()
                val denominator = (value and 0xFFFF).toDouble()
                return if (denominator > 0) numerator / denominator else null
            }
            return value / 10000.0
        }

        fun shutterLabel(raw: Long, packed: Boolean): String? {
            val value = raw and 0xFFFF_FFFFL
            if (value == 0xFFFF_FFFFL) return "bulb"
            if (value == 0xFFFF_FFFDL) return "time"
            if (value == 0xFFFF_FFFEL || value == 0xFFFF_FFFCL) return null   // flash sync / auto: not offered
            return shutterSeconds(raw, packed)?.let { ExposureText.shutter(it) }
        }

        fun whiteBalanceCode(raw: Long): String = when (raw) {
            2L -> "0"              // auto
            4L -> "18"             // daylight
            5L -> "35"             // fluorescent
            6L -> "20"             // incandescent
            7L -> "23"             // flash
            0x8010L -> "17"        // cloudy
            0x8011L -> "16"        // shade
            0x8012L -> "512"       // colour temperature
            0x8013L -> "256"       // preset manual
            0x8016L -> "natural_light_auto"
            else -> "wb_$raw"
        }
    }

    // MARK: - Focus & shooting

    override suspend fun focus(x: Double, y: Double) {
        val (px, py) = camera.pixelPoint(x, y)
        if (supports(PtpOp.NIKON_CHANGE_AF_AREA)) {
            ptpOrNull { ptp.transaction(PtpOp.NIKON_CHANGE_AF_AREA, listOf(maxOf(0.0, px).toLong(), maxOf(0.0, py).toLong())) }
        }
        try {
            ptp.run(PtpOp.NIKON_AF_DRIVE)
            val result = waitUntilReady(6.0)
            camera.showAfResult(result == PtpException.OK, x, y)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            camera.showAfResult(false, x, y)
            debugLog("Nikon AF: ${e.message}")
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
            // 0x9207 (0xFFFFFFFF = no AF in live view, 0 = to the card) keeps live view running;
            // older bodies fall back to PTP's InitiateCapture, which also saves to the card.
            val toCard = supports(PtpOp.NIKON_CAPTURE_TO_CARD)
            val op = if (toCard) PtpOp.NIKON_CAPTURE_TO_CARD else PtpOp.INITIATE_CAPTURE
            val params = if (toCard) listOf(0xFFFF_FFFFL, 0L) else listOf(0L, 0L)
            var attempts = 0
            while (true) {
                val response = ptp.transaction(op, params, timeout = maxOf(30.0, seconds + 20))
                if (response.code == PtpException.OK) break
                attempts++
                if (!NikonResponse.isBusy(response.code) || attempts >= 20) throw PtpException(response.code, op)
                delay(150)
            }
            waitUntilReady(seconds * 2 + 20)
            camera.shotCounter++
            showNewestCapture()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            camera.report(e)
        } finally {
            camera.isShooting = false
            camera.exposureStartedAt = null
            camera.exposureDuration = null
        }
    }

    /** Bulb and Time need the shutter held, which Nikon's Wi-Fi commands don't offer. */
    override suspend fun toggleOpenExposure() {
        camera.lastError = "Bulb and Time can't be run from the app on a Nikon. Pick a shutter speed (up to 30 s) or use the camera's own interval timer."
    }

    override suspend fun toggleMovie() {
        if (camera.isRecordingMovie) {
            ptpOrNull { ptp.transaction(PtpOp.NIKON_END_MOVIE) }
            camera.isRecordingMovie = false
            camera.movieStartedAt = null
            camera.shotCounter++
            return
        }
        try {
            ptp.run(PtpOp.NIKON_START_MOVIE)
            camera.isRecordingMovie = true
            camera.movieStartedAt = System.currentTimeMillis()
        } catch (e: PtpException) {
            camera.lastError = if (e.code == 0xA00B || e.code == 0xA002)
                "The camera won't record now. Set its photo/video switch to video, then try again."
            else e.message
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            camera.report(e)
        }
    }

    /**
     * ObjectAdded handles from Nikon's event queue: GetEventEx (Z bodies: u16 count, then from
     * offset 4 entries of u16 code, u16 parameter count, u32 parameters) or GetEvent (u16 count,
     * then u16 code + u32 parameter).
     */
    private suspend fun addedObjects(): List<Long>? {
        val added = mutableListOf<Long>()
        if (supports(PtpOp.NIKON_GET_EVENT_EX)) {
            val data = ptpOrNull { ptp.run(PtpOp.NIKON_GET_EVENT_EX, timeout = 5.0).data } ?: return null
            val r = PtpReader(data)
            val count = r.u16()
            r.offset = 4
            repeat(minOf(count, 512)) {
                val code = r.u16()
                val n = r.u16()
                val params = List(minOf(n, maxOf(0, r.remaining / 4))) { r.u32() }
                if (code == 0x4002 && params.isNotEmpty()) added.add(params[0])   // ObjectAdded
            }
            return added
        }
        if (!supports(PtpOp.NIKON_GET_EVENT)) return null
        val data = ptpOrNull { ptp.run(PtpOp.NIKON_GET_EVENT, timeout = 5.0).data } ?: return null
        val r = PtpReader(data)
        val count = r.u16()
        repeat(minOf(count, 512)) {
            val code = r.u16()
            val param = r.u32()
            if (code == 0x4002) added.add(param)   // ObjectAdded
        }
        return added
    }

    /** Shows the thumbnail of the picture just taken. */
    private suspend fun showNewestCapture() {
        repeat(10) {
            val objects = addedObjects() ?: return
            val handle = objects.lastOrNull()
            if (handle != null) {
                val op = if (supports(PtpOp.NIKON_GET_LARGE_THUMB)) PtpOp.NIKON_GET_LARGE_THUMB else PtpOp.GET_THUMB
                val thumb = ptpOrNull { ptp.run(op, listOf(handle), timeout = 10.0).data }
                val image = thumb?.let { decode(it) }
                if (image != null) camera.lastShot = image.asImageBitmap()
                return
            }
            delay(300)
        }
    }

    // MARK: - Card

    override suspend fun openGallery() {
        try {
            camera.mode = CameraMode.PLAY
            handles.clear()
            val found = mutableListOf<CameraImage>()
            val folderCounts = LinkedHashMap<String, Int>()
            val storages = PtpReader(ptp.run(PtpOp.GET_STORAGE_IDS).data).u32Array()
            for (storage in storages) {
                if (storage and 0xFFFF == 0L) continue   // skip empty slots
                val all = PtpReader(ptp.run(PtpOp.GET_OBJECT_HANDLES, listOf(storage, 0L, 0L), timeout = 30.0).data).u32Array()
                // Over Wi-Fi each file's info is a round trip; show the newest 300.
                val list = all.sorted().takeLast(300)
                val folders = HashMap<Long, String>()
                for (handle in list.asReversed()) {
                    val data = ptpOrNull { ptp.run(PtpOp.GET_OBJECT_INFO, listOf(handle), timeout = 5.0).data } ?: continue
                    val obj = PtpObjectInfo(data)
                    if (obj.isFolder) {
                        folders[handle] = obj.filename
                        continue
                    }
                    val folderPath = folders[obj.parent] ?: folderName(obj.parent) ?: "DCIM"
                    folders[obj.parent] = folderPath
                    val image = CameraImage(folderPath, obj.filename, obj.size, 0, obj.date)
                    handles[image.path] = handle
                    found.add(image)
                    folderCounts[folderPath] = (folderCounts[folderPath] ?: 0) + 1
                }
            }
            camera.images = found.sortedWith(compareByDescending<CameraImage> { it.date }.thenByDescending { it.name })
            camera.cardFolders = folderCounts.map { (path, count) ->
                val upper = path.uppercase()
                CardFolder(path, path, count, isForeign = !upper.contains("NIKON") && !upper.contains("NZ"))
            }.sortedByDescending { it.name }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            camera.galleryError = camera.describe(e, camera.connectionHost)
        }
    }

    private suspend fun folderName(handle: Long): String? {
        if (handle == 0L || handle == 0xFFFF_FFFFL) return null
        val data = ptpOrNull { ptp.run(PtpOp.GET_OBJECT_INFO, listOf(handle), timeout = 5.0).data } ?: return null
        return PtpObjectInfo(data).filename
    }

    override suspend fun thumbnail(image: CameraImage): Bitmap? {
        val handle = handles[image.path] ?: return null
        val data = ptpOrNull { ptp.run(PtpOp.GET_THUMB, listOf(handle), timeout = 10.0).data } ?: return null
        return decode(data)
    }

    override suspend fun preview(image: CameraImage): Bitmap {
        val handle = handles[image.path] ?: throw CameraException("The camera no longer lists this file.")
        if (supports(PtpOp.NIKON_GET_LARGE_THUMB)) {
            val data = ptpOrNull { ptp.run(PtpOp.NIKON_GET_LARGE_THUMB, listOf(handle), timeout = 20.0).data }
            data?.let { decode(it) }?.let { return it }
        }
        if (image.fileExtension == "JPG" || image.fileExtension == "JPEG") {
            val data = ptp.run(PtpOp.GET_OBJECT, listOf(handle), timeout = 120.0).data
            decode(data, maxSide = 2000)?.let { return it }
        }
        val data = ptp.run(PtpOp.GET_THUMB, listOf(handle), timeout = 10.0).data
        return decode(data) ?: throw CameraException("Couldn't decode the preview.")
    }

    /** Big transfers stall Nikon's Wi-Fi, so originals come in 1 MB pieces when the size is known. */
    override suspend fun downloadOriginal(image: CameraImage): ByteArray {
        val handle = handles[image.path] ?: throw CameraException("The camera no longer lists this file.")
        if (!supports(PtpOp.GET_PARTIAL_OBJECT) || image.size <= 0) {
            return ptp.run(PtpOp.GET_OBJECT, listOf(handle), timeout = 600.0).data
        }
        val chunk = 1L shl 20
        val data = ByteArrayOutputStream(image.size.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
        while (data.size() < image.size) {
            currentCoroutineContext().ensureActive()
            val piece = ptp.run(PtpOp.GET_PARTIAL_OBJECT, listOf(handle, data.size().toLong(), chunk), timeout = 60.0).data
            if (piece.isEmpty()) break
            data.write(piece)
        }
        return data.toByteArray()
    }
}

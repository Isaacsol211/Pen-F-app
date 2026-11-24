package com.apexcommerce.shutterlink.camera

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.RectF
import android.util.LruCache
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.IOException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.abs

/**
 * The connection/mode state machine; forwards everything to the driver (port of CameraModel.swift).
 * All state is Compose state and is only changed on the main thread.
 */
class CameraModel private constructor(val context: Context) {
    companion object {
        @Volatile private var instance: CameraModel? = null

        fun get(context: Context): CameraModel = instance ?: synchronized(this) {
            instance ?: CameraModel(context.applicationContext).also {
                instance = it
                CameraNetwork.init(context.applicationContext)
            }
        }

        val userAgents = listOf("OI.Share v2", "OlympusCameraKit")

        /** The camera Wi-Fi name to mention in connection errors (set per brand on connect). */
        var ssidHint = "PEN-F-P-…"

        fun liveViewLabel(quality: String): String {
            val size = quality.split("x").mapNotNull { it.toIntOrNull() }.joinToString("×")
            return when (quality) {
                "0320x0240" -> "$size · fastest, blurry"
                "0640x0480" -> "$size · smooth (~30 fps)"
                "1280x0960" -> "$size · sharp (~9 fps)"
                else -> size
            }
        }

        fun pointString(x: Double, y: Double): String = fmt("%04dx%04d", Math.round(x), Math.round(y))

        fun durationLabel(seconds: Double): String {
            val total = Math.round(seconds).toInt()
            if (total < 60) return "$total s"
            val m = total / 60
            val s = total % 60
            return if (s == 0) "$m min" else fmt("%d:%02d", m, s)
        }
    }

    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val prefs: SharedPreferences = context.getSharedPreferences("shutterlink", Context.MODE_PRIVATE)

    // MARK: Settings (saved between launches)

    /** The brand picked on the Connect screen, or the one auto-detect found for this connection. */
    var brand by mutableStateOf(CameraBrand.OLYMPUS)
    /** Find the brand by itself at connect (from the Wi-Fi network and by asking the camera). */
    var autoDetectBrand by mutableStateOf(true)
    /** Bodies whose photo/video mode can't be read get the app's own Video switch. */
    var videoMode by mutableStateOf(false)
    var host by mutableStateOf("")
    var userAgent by mutableStateOf("OI.Share v2")
    var liveViewQuality by mutableStateOf("0640x0480")
    var touchShutter by mutableStateOf(false)

    // MARK: Connection

    var phase by mutableStateOf(ConnectionPhase.DISCONNECTED)
    var status by mutableStateOf<String?>(null)
    var lastError by mutableStateOf<String?>(null)
    var cameraName by mutableStateOf<String?>(null)
    var connectMode: String? = null
    var commands = CommandList()
    var rawCommandList by mutableStateOf("")
    var rawDescList by mutableStateOf("")
    var mode by mutableStateOf(CameraMode.UNKNOWN)
    var isSwitchingMode by mutableStateOf(false)

    // MARK: Settings on the camera

    var properties by mutableStateOf<Map<String, CameraProperty>>(emptyMap())

    /** Changes one property's value in place (if the camera has it). */
    fun updateValue(name: String, value: String) {
        val p = properties[name] ?: return
        properties = properties + (name to p.copy(value = value))
    }

    // MARK: Live view

    var liveFrame by mutableStateOf<ImageBitmap?>(null)
    /** Pixel size of the arriving frames (the camera's AF coordinate space); changes rarely. */
    var frameWidth by mutableStateOf(0)
    var frameHeight by mutableStateOf(0)
    var liveInfo by mutableStateOf(LiveInfo())
    var histogram by mutableStateOf<FloatArray?>(null)
    var focusScore by mutableStateOf<Double?>(null)
    var focusPeak by mutableStateOf(0.0)
    var focusFloor by mutableStateOf(Double.POSITIVE_INFINITY)

    // MARK: Last shot, movie, sequences

    var lastShot by mutableStateOf<ImageBitmap?>(null)
    var isRecordingMovie by mutableStateOf(false)
    var movieStartedAt by mutableStateOf<Long?>(null)
    var interval by mutableStateOf(IntervalState())
    var toast by mutableStateOf<String?>(null)
    var intervalJob: Job? = null
    var liveViewRunning by mutableStateOf(false)
    var liveViewStartedAt: Long? = null
    var lastFrameAt by mutableStateOf<Long?>(null)
    var fps by mutableStateOf(0)
    /** Where the user last tapped, normalised 0…1 so it survives live-view size changes. */
    var focusPoint by mutableStateOf<Pair<Double, Double>?>(null)
    var isShooting by mutableStateOf(false)
    var shotCounter by mutableStateOf(0)
    /** Set while a timed (≥ 1 s) or open-ended exposure is running (ms since 1970). */
    var exposureStartedAt by mutableStateOf<Long?>(null)
    /** Length of the timed exposure, null when open-ended. */
    var exposureDuration by mutableStateOf<Double?>(null)

    // MARK: Presets

    var presetSteps by mutableStateOf<List<PresetStep>>(emptyList())
    var presetRunning by mutableStateOf(false)
    /** Which preset `presetSteps` belong to (a recipe id or a saved preset's id). */
    var presetResultsFor by mutableStateOf<String?>(null)
    /** Settings from before the last preset, for Undo. */
    var presetUndo by mutableStateOf<SettingsSnapshot?>(null)
    /** "My presets", for every brand (each remembers the brand it was saved on). */
    var savedPresets by mutableStateOf(SavedPresets.load(prefs))

    // MARK: Motion trigger, exposing to the right

    var motion by mutableStateOf(MotionTrigger())
    /** How much the trigger box changed between the last two frames analysed (0…1). */
    var motionLevel by mutableStateOf(0.0)
    var motionPrevious: IntArray? = null
    var motionAnalyzedAt = 0L
    var motionQuietUntil = 0L
    var ettrRunning by mutableStateOf(false)

    // MARK: Scene assistant

    /** "Scene suggestions" in the ··· menu; on by default. */
    var sceneAssistantOn by mutableStateOf(true)
    var sceneSuggestion by mutableStateOf<SceneSuggestion?>(null)
    /** What the last look saw (scene names), for the self-test. */
    var sceneSignals: SceneSignals? = null
    /** ML Kit's own labels from the last look. */
    var sceneRawLabels: Map<String, Float> = emptyMap()
    /** Suggestion id → time (ms) until which it stays away. */
    var sceneSnoozed: Map<String, Long> = emptyMap()
    var sceneCandidate: String? = null
    var sceneMisses = 0
    /** Debug: scene labels that stand in for ML Kit's ("night_sky:0.97,sky:0.9"), to try the suggestions. */
    var sceneLabelOverride: Map<String, Float>? = null

    fun changeSceneAssistant(on: Boolean) {
        sceneAssistantOn = on
        prefs.edit().putBoolean("assistant.on", on).apply()
        if (!on) sceneSuggestion = null
    }
    /** The latest live-view frame as a Bitmap, for metering (ETTR, ramping, ND). */
    var latestBitmap: Bitmap? = null

    // MARK: Card browser

    var images by mutableStateOf<List<CameraImage>>(emptyList())
    var cardFolders by mutableStateOf<List<CardFolder>>(emptyList())
    var galleryLoading by mutableStateOf(false)
    var galleryError by mutableStateOf<String?>(null)

    // MARK: Extras

    var focusPeaking by mutableStateOf(false)
    var peakingOverlay by mutableStateOf<ImageBitmap?>(null)
    /** Stop Bulb / Live Time / Live Composite automatically after this many seconds (0 = off). */
    var bulbTimer by mutableStateOf(0.0)
    var openExposureStopJob: Job? = null
    var bracket by mutableStateOf(BracketState())
    var bracketJob: Job? = null
    /** Starred card files, keyed by name and size so a reused file name on a new card doesn't match. */
    var starred by mutableStateOf<Set<String>>(emptySet())
    var rawImport by mutableStateOf<RawImportProgress?>(null)
    var rawImportJob: Job? = null

    // MARK: Request log

    val log = mutableStateListOf<LogEntry>()

    /** The connected camera's protocol; null while disconnected. */
    var driver: CameraDriver? = null
    /** What the connected camera can do (the selected brand's defaults while disconnected). */
    var capabilities by mutableStateOf(CameraCapabilities())
    /** What the app knows about this body from its model table (null for one not in it). */
    var profile: ModelProfile? = null
    /** Advice for this body (e.g. "set Wi-Fi to Private"), shown until dismissed once per model. */
    var cameraNote by mutableStateOf<String?>(null)
    /** Cameras this phone has connected to, most recent first (the home screen's cards). */
    var savedCameras by mutableStateOf(SavedCameras.load(prefs))
    var receiver: LiveViewReceiver? = null
    var udpPort = 40000
        private set
    private val frameTimes = ArrayDeque<Long>()
    private var fpsUpdatedAt = 0L
    private val thumbnailCache = LruCache<String, Bitmap>(300)
    private var resumeLiveViewWhenActive = false
    /** Live-view size to go back to when the focus loupe closes. */
    var liveViewBeforeLoupe: String? = null
    /** Where the connected camera is (the detected address when auto-detecting). */
    var activeHost: String? = null
    /** Debug: bind to Wi-Fi even for the mocks' address, to test the binding in the emulator. */
    var forceWifiBinding = false

    init {
        val savedBrand = CameraBrand.fromId(prefs.getString("brand", null))
        val startBrand = savedBrand ?: CameraBrand.OLYMPUS
        val auto = if (prefs.contains("autoBrand")) prefs.getBoolean("autoBrand", true) else savedBrand == null
        brand = startBrand
        autoDetectBrand = auto
        host = prefs.getString("host", null) ?: if (auto) "" else startBrand.defaultHost
        userAgent = prefs.getString("userAgent", null) ?: "OI.Share v2"
        liveViewQuality = prefs.getString("lvqty", null) ?: "0640x0480"
        focusPeaking = prefs.getBoolean("ui.peaking", false)
        sceneAssistantOn = prefs.getBoolean("assistant.on", true)
        bulbTimer = prefs.getFloat("bulbTimer", 0f).toDouble()
        starred = prefs.getStringSet("stars", emptySet())?.toSet() ?: emptySet()
        fitLiveViewQualityToBrand()
        capabilities = brand.defaultCapabilities
    }

    /** LUMIX streams only 320×240 or 640×480; fall back to 640×480 if a bigger Olympus size was saved. */
    private fun fitLiveViewQualityToBrand() {
        val sizes = availableLiveViewSizes
        if (sizes.isNotEmpty() && liveViewQuality !in sizes) liveViewQuality = "0640x0480"
    }

    fun saveSettings() {
        prefs.edit()
            .putString("brand", brand.id)
            .putBoolean("autoBrand", autoDetectBrand)
            .putString("host", host)
            .putString("userAgent", userAgent)
            .putString("lvqty", liveViewQuality)
            .apply()
    }

    fun setPeaking(on: Boolean) {
        focusPeaking = on
        prefs.edit().putBoolean("ui.peaking", on).apply()
        receiver?.peakingOn = on
        if (!on) peakingOverlay = null
    }

    fun changeBulbTimer(seconds: Double) {
        bulbTimer = seconds
        prefs.edit().putFloat("bulbTimer", seconds.toFloat()).apply()
    }

    /** Switches camera family (null = auto-detect), moving the address to its default unless customised. */
    fun selectBrand(newBrand: CameraBrand?) {
        if (phase != ConnectionPhase.DISCONNECTED) return
        val hostIsDefault = host.isEmpty() || CameraBrand.entries.any { it.defaultHost == host }
        if (newBrand != null) {
            if (hostIsDefault) host = newBrand.defaultHost
            brand = newBrand
            autoDetectBrand = false
        } else {
            if (hostIsDefault) host = ""
            autoDetectBrand = true
        }
        capabilities = brand.defaultCapabilities
        fitLiveViewQualityToBrand()
        saveSettings()
    }

    /** An HTTP client for the camera whose requests show up in the Request log. */
    fun makeHttpClient(userAgent: String, allowedStatus: IntRange = 200..202): CameraHttpClient =
        CameraHttpClient(connectionHost, userAgent, allowedStatus) { entry -> scope.launch { appendLog(entry) } }

    /** Pixel size of the live-view frames actually arriving (the camera's AF coordinate space). */
    val frameSpace: Pair<Double, Double>
        get() = if (frameWidth == 0) liveViewSize else frameWidth.toDouble() to frameHeight.toDouble()

    val liveViewSize: Pair<Double, Double>
        get() {
            val parts = liveViewQuality.split("x").mapNotNull { it.toDoubleOrNull() }
            return if (parts.size == 2) parts[0] to parts[1] else 640.0 to 480.0
        }

    /** The dial only offers what the mounted lens can do (the camera lists F1.0–F91 regardless). */
    fun dialOptions(property: CameraProperty): CameraProperty {
        val range = liveInfo.apertureRange
        if (property.name != "focalvalue" || range == null) return property
        val options = property.options.filter { o -> o.toDoubleOrNull()?.let { it in range } ?: true }
        if (options.isEmpty()) return property
        var value = property.value
        // The camera can report a value the lens can't do (e.g. "1.0"); show the nearest real stop.
        val current = value.toDoubleOrNull()
        if (value !in options && current != null) {
            value = options.minByOrNull { abs((it.toDoubleOrNull() ?: 0.0) - current) } ?: value
        }
        return property.copy(options = options, value = value)
    }

    /** Live-view sizes this camera offers; empty when it has only one. */
    val availableLiveViewSizes: List<String> get() = capabilities.liveViewSizes

    /** The shutter records video (a movie mode on the dial, or the app's Video switch). */
    val isMovieMode: Boolean
        get() = if (capabilities.videoSwitch) videoMode else properties["takemode"]?.value?.lowercase() == "movie"

    val isContinuousDrive: Boolean
        get() = properties["drivemode"]?.value?.contains("continuous", ignoreCase = true) == true

    fun isLiveViewStalled(now: Long): Boolean {
        if (!liveViewRunning) return false
        val since = lastFrameAt ?: liveViewStartedAt ?: return false
        return now - since > 3000
    }

    // MARK: - Connect / disconnect

    /** Connects; with a deadline, keeps trying until then (e.g. while the phone joins the camera's Wi-Fi). */
    suspend fun connect(waitUntil: Long? = null) {
        if (phase != ConnectionPhase.DISCONNECTED) return
        while (true) {
            connectOnce()
            if (phase != ConnectionPhase.DISCONNECTED || waitUntil == null || System.currentTimeMillis() >= waitUntil) return
            val failure = lastError
            lastError = null
            phase = ConnectionPhase.CONNECTING
            status = "Waiting for the camera's Wi-Fi…"
            delay(2000)
            phase = ConnectionPhase.DISCONNECTED
            status = null
            if (System.currentTimeMillis() >= waitUntil) {
                lastError = failure
                return
            }
        }
    }

    fun connectInBackground() {
        scope.launch { connect() }
    }

    private suspend fun connectOnce() {
        if (phase != ConnectionPhase.DISCONNECTED) return
        host = host.trim()
        saveSettings()
        phase = ConnectionPhase.CONNECTING
        lastError = null
        status = "Looking for the camera…"

        try {
            // Use the camera's Wi-Fi even though it has no internet (see CameraNetwork).
            val target0 = if (host.isEmpty()) brand.defaultHost else host
            if (forceWifiBinding || !CameraNetwork.isLocalTestHost(if (autoDetectBrand && host.isEmpty()) "192.168.0.1" else target0)) {
                status = "Holding on to the camera's Wi-Fi…"
                CameraNetwork.acquireWifi()
            }
            debugLog("connect: brand=${if (autoDetectBrand) "auto" else brand.id} host=$host wifi=${CameraNetwork.wifiAddress() ?: "none"} ua=$userAgent")
            var target = brand to target0
            if (autoDetectBrand) {
                status = "Finding out which camera this is…"
                val found = BrandDetector.detect(host) ?: throw CameraException(BrandDetector.notFoundMessage(CameraNetwork.wifiAddress()))
                debugLog("auto-detect: ${found.first.id} at ${found.second}")
                target = found
                brand = found.first
            }
            ssidHint = brand.ssidHint
            // The driver talks to the detected address; the saved setting stays as the user left it.
            activeHost = target.second
            val driver = brand.makeDriver(this)
            this.driver = driver
            capabilities = driver.capabilities
            driver.connect()
            capabilities = driver.capabilities
            fitLiveViewQualityToBrand()
            val p = profile
            if (p != null && p.notes.isNotEmpty() && p.name !in (prefs.getStringSet("dismissedNotes", emptySet()) ?: emptySet())) {
                cameraNote = p.notes.joinToString("\n\n")
            }
            startReceiver(driver.liveViewFormat)
            phase = ConnectionPhase.CONNECTED
            prefs.edit().putBoolean("hasConnected", true).apply()
            rememberConnectedCamera()
            status = null
            enterRecMode()
        } catch (e: CancellationException) {
            teardown()
            throw e
        } catch (e: Throwable) {
            debugLog("connect failed: $e")
            lastError = describe(e, connectionHost)
            teardown()
        }
    }

    /** The address drivers talk to: the connected one, else the setting, else the brand's default. */
    val connectionHost: String
        get() = activeHost ?: if (host.isEmpty()) brand.defaultHost else host

    /** Hides the camera note, and keeps it hidden for this model from now on. */
    fun dismissCameraNote() {
        profile?.name?.let { name ->
            val dismissed = (prefs.getStringSet("dismissedNotes", emptySet()) ?: emptySet()) + name
            prefs.edit().putStringSet("dismissedNotes", dismissed).apply()
        }
        cameraNote = null
    }

    suspend fun disconnect() {
        stopLiveView()
        runCatching { driver?.disconnect() }
        teardown()
    }

    suspend fun powerOff() {
        val driver = driver ?: return
        stopLiveView()
        runCatching { driver.powerOff() }
        teardown()
    }

    private fun teardown() {
        driver?.teardown()
        driver = null
        activeHost = null
        profile = null
        cameraNote = null
        stopInterval()
        cancelBracket()
        // Undo and the motion trigger belong to this camera's session.
        presetUndo = null
        presetSteps = emptyList()
        presetResultsFor = null
        armMotion(false)
        latestBitmap = null
        sceneSuggestion = null
        sceneCandidate = null
        sceneSignals = null
        openExposureStopJob?.cancel()
        openExposureStopJob = null
        rawImportJob?.cancel()
        peakingOverlay = null
        receiver?.stop()
        receiver = null
        phase = ConnectionPhase.DISCONNECTED
        status = null
        mode = CameraMode.UNKNOWN
        liveViewRunning = false
        liveFrame = null
        frameWidth = 0
        frameHeight = 0
        liveInfo = LiveInfo()
        focusPoint = null
        isShooting = false
        isRecordingMovie = false
        movieStartedAt = null
        exposureStartedAt = null
        exposureDuration = null
        properties = emptyMap()
        images = emptyList()
        thumbnailCache.evictAll()
        fps = 0
        capabilities = brand.defaultCapabilities
        CameraNetwork.release()
    }

    private fun startReceiver(format: LiveViewFormat) {
        var lastFailure: Exception? = null
        for (port in 40000..40010) {
            val r = LiveViewReceiver(port, format)
            r.onFrame = { image, info, histogram, sharpness ->
                handleFrame(image, info)
                if (histogram != null) this.histogram = histogram
                if (sharpness != null) updateFocusMeter(sharpness)
            }
            r.onPeaking = { overlay -> if (focusPeaking) peakingOverlay = overlay?.asImageBitmap() }
            r.peakingOn = focusPeaking
            try {
                r.start()
                receiver = r
                udpPort = port
                return
            } catch (e: Exception) {
                lastFailure = e
            }
        }
        throw lastFailure ?: CameraException("Couldn't open a UDP port for live view.")
    }

    /** The app went to the background (true) or came back (false). */
    fun appBackgrounded(background: Boolean) {
        if (phase != ConnectionPhase.CONNECTED) return
        if (background) {
            if (liveViewRunning && !isBusyExposing) {
                resumeLiveViewWhenActive = true
                scope.launch { stopLiveView() }
            }
        } else if (resumeLiveViewWhenActive) {
            resumeLiveViewWhenActive = false
            scope.launch { startLiveView() }
        }
    }

    // MARK: - Modes & live view

    /** Recording mode: required for live view, shooting and reading/changing settings. */
    suspend fun enterRecMode() {
        driver?.enterRecMode()
    }

    suspend fun startLiveView() {
        val driver = driver ?: return
        if (mode != CameraMode.REC || liveViewRunning) return
        liveViewRunning = true
        liveViewStartedAt = System.currentTimeMillis()
        lastFrameAt = null
        driver.startLiveView()
    }

    suspend fun stopLiveView() {
        val driver = driver ?: return
        if (!liveViewRunning) return
        liveViewRunning = false
        fps = 0
        driver.stopLiveView()
    }

    suspend fun restartLiveView() {
        stopLiveView()
        enterRecMode()
    }

    suspend fun changeLiveViewQuality(quality: String) {
        if (quality == liveViewQuality) return
        liveViewQuality = quality
        saveSettings()
        liveFrame = null
        frameWidth = 0
        frameHeight = 0
        restartLiveView()
    }

    /** Pull-based drivers (Nikon, Canon, Sony) hand each live-view JPEG over here. */
    fun submitLiveViewJpeg(jpeg: ByteArray) {
        receiver?.submit(jpeg)
    }

    private fun handleFrame(image: Bitmap?, info: LiveInfo?) {
        if (!liveViewRunning) return
        if (image != null) {
            liveFrame = image.asImageBitmap()
            latestBitmap = image
            if (image.width != frameWidth || image.height != frameHeight) {
                frameWidth = image.width
                frameHeight = image.height
            }
            val now = System.currentTimeMillis()
            // Only touch these a couple of times a second: each change recomposes what reads them.
            if (lastFrameAt.let { it == null || now - it > 500 }) lastFrameAt = now
            frameTimes.addLast(now)
            while (frameTimes.isNotEmpty() && now - frameTimes.first() > 1000) frameTimes.removeFirst()
            if (now - fpsUpdatedAt > 500) {
                fpsUpdatedAt = now
                if (fps != frameTimes.size) fps = frameTimes.size
            }
            if (motion.armed || motion.editing) analyzeMotion(image)
        }
        if (info != null && info != liveInfo) {
            // The receiver only knows what the stream says; keep what drivers learned by polling.
            liveInfo = info.copy(
                battery = info.battery ?: liveInfo.battery,
                shotsRemaining = info.shotsRemaining ?: liveInfo.shotsRemaining,
                apertureRange = info.apertureRange ?: liveInfo.apertureRange,
                focalLength = info.focalLength ?: liveInfo.focalLength,
            )
        }
    }

    // MARK: - Settings

    suspend fun refreshProperties() {
        driver?.refreshProperties()
    }

    /** Returns false (and reports why) if the camera refused the value. */
    suspend fun setProperty(name: String, value: String, reportErrors: Boolean = true): Boolean {
        val driver = driver ?: return false
        return driver.setProperty(name, value, reportErrors)
    }

    // MARK: - Focus & shooting

    suspend fun tapFocus(x: Double, y: Double) {
        val driver = driver ?: return
        if (mode != CameraMode.REC) return
        val nx = x.coerceIn(0.0, 1.0)
        val ny = y.coerceIn(0.0, 1.0)
        focusPoint = nx to ny
        if (touchShutter) {
            shutterPressed()
            shutterReleased()
            return
        }
        if (!capabilities.tapToFocus) return
        driver.focus(nx, ny)
    }

    suspend fun clearFocus() {
        focusPoint = null
        liveInfo = liveInfo.copy(afState = 0)
        driver?.releaseFocus()
    }

    /** Live Composite / Live Time / Bulb: the exposure runs until told to stop. */
    val isOpenEndedShutter: Boolean
        get() = PropertyFormat.isOpenEnded(properties["shutspeedvalue"]?.value ?: "")

    /** Press = start taking. In continuous drive the camera keeps shooting until release. */
    suspend fun shutterPressed() {
        val driver = driver ?: return
        if (mode != CameraMode.REC || isShooting) return
        driver.shutterPressed()
    }

    suspend fun shutterReleased() {
        driver?.shutterReleased()
    }

    /** Open-ended exposures: first tap starts, second tap stops. */
    suspend fun toggleOpenExposure() {
        val driver = driver ?: return
        if (mode != CameraMode.REC) return
        val starting = !isShooting
        if (!starting) {
            openExposureStopJob?.cancel()
            openExposureStopJob = null
            exposureDuration = null
        }
        driver.toggleOpenExposure()
        if (starting && isShooting && bulbTimer > 0) scheduleOpenExposureStop(bulbTimer)
    }

    suspend fun toggleMovie() {
        val driver = driver ?: return
        if (mode != CameraMode.REC) return
        driver.toggleMovie()
    }

    /** Grabs a preview of the capture that just finished, for the review thumbnail. */
    suspend fun fetchLastShot() {
        val driver = driver ?: return
        if (mode != CameraMode.REC || !capabilities.lastShotReview) return
        driver.fetchLastShot()
    }

    /** Sets the camera's clock and time zone from the phone. */
    suspend fun syncClock(): Boolean {
        val driver = driver ?: return false
        if (!capabilities.clockSync) return false
        return driver.syncClock()
    }

    /** A normalised point in the camera's AF space: the pixels of the frames actually arriving. */
    fun pixelPoint(x: Double, y: Double): Pair<Double, Double> {
        val (w, h) = frameSpace
        return x * (w - 1) to y * (h - 1)
    }

    /** Long or open exposure / movie in progress: anything that switches modes would ruin it. */
    val isBusyExposing: Boolean
        get() = isRecordingMovie || (isShooting && (isOpenEndedShutter || exposureStartedAt != null))

    /** Shows the AF result box around a tapped point (for cameras that only say focused / not). */
    fun showAfResult(focused: Boolean, x: Double, y: Double, size: Double = 0.14) {
        val (w, h) = frameSpace
        val side = minOf(w, h) * size
        liveInfo = liveInfo.copy(afRect = AfRect(x * w - side / 2, y * h - side / 2, side, side), afState = if (focused) 1 else 2)
    }

    /**
     * Repeatedly fetches one live-view frame and hands it over, for cameras that only offer
     * frame-by-frame live view (Nikon, Canon). Stops when live view stops or after repeated failures.
     */
    fun pullLiveView(everyMs: Long = 30, maxFailures: Int = 15, fetch: suspend () -> ByteArray?): Job = scope.launch {
        var failures = 0
        while (isActive && liveViewRunning) {
            try {
                val jpeg = fetch()
                if (jpeg != null) {
                    submitLiveViewJpeg(jpeg)
                    failures = 0
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                failures++
                debugLog("live view fetch failed ($failures): ${e.message}")
                if (failures >= maxFailures) {
                    liveViewRunning = false
                    report(e)
                    return@launch
                }
                delay(200L * minOf(failures, 5))
            }
            delay(everyMs)
        }
    }

    // MARK: - Card browser

    suspend fun openGallery() {
        val driver = driver ?: return
        galleryLoading = true
        galleryError = null
        try {
            stopLiveView()
            driver.openGallery()
        } finally {
            galleryLoading = false
        }
    }

    suspend fun closeGallery() {
        enterRecMode()
    }

    suspend fun thumbnail(image: CameraImage): Bitmap? {
        thumbnailCache.get(image.path)?.let { return it }
        val driver = driver ?: return null
        val thumb = runCatching { driver.thumbnail(image) }.getOrNull() ?: return null
        thumbnailCache.put(image.path, thumb)
        return thumb
    }

    suspend fun preview(image: CameraImage): Bitmap {
        val driver = driver ?: throw CameraException("Not connected.")
        return driver.preview(image)
    }

    suspend fun downloadOriginal(image: CameraImage): ByteArray {
        val driver = driver ?: throw CameraException("Not connected.")
        return driver.downloadOriginal(image)
    }

    /** Saves the original to the phone's gallery (Pictures/Shutterlink; RAWs to Downloads). */
    suspend fun saveOriginal(image: CameraImage): String {
        val data = downloadOriginal(image)
        return MediaSaver.save(context, data, image)
    }

    // MARK: - Log & errors

    fun appendLog(entry: LogEntry) {
        log.add(entry)
        while (log.size > 400) log.removeAt(0)
    }

    fun clearLog() = log.clear()

    fun report(error: Throwable) {
        if (error is CancellationException) return
        lastError = describe(error, connectionHost)
    }

    fun showToast(text: String) {
        toast = text
        scope.launch {
            delay(2200)
            if (toast == text) toast = null
        }
    }

    fun describe(error: Throwable, host: String): String {
        val network = error is IOException && error !is CameraHttpException
        if (!network) return error.message ?: error.javaClass.simpleName
        val reason = when (error) {
            is SocketTimeoutException -> "No reply from $host (timed out)."
            is InterruptedIOException -> "No reply from $host (timed out)."
            is ConnectException -> "$host refused the connection."
            is NoRouteToHostException -> "There's no network route to $host."
            is UnknownHostException -> "Can't find $host."
            else -> "The connection to $host dropped (${error.message ?: error.javaClass.simpleName})."
        }
        if (CameraNetwork.isLocalTestHost(host)) {
            return "$reason Is the mock camera running on the Mac? In the emulator the Mac is 10.0.2.2."
        }
        val wifi = CameraNetwork.wifiAddress()
        val hint = if (wifi != null) {
            val ssid = CameraNetwork.wifiSsid()
            "This phone is on Wi-Fi${ssid?.let { " \"$it\"" } ?: ""} ($wifi), but probably not the camera's network: home routers often use 192.168.0.x too. Open Settings ▸ Wi-Fi and check it's $ssidHint. Android may say the network has no internet: stay connected anyway."
        } else {
            "This phone isn't on Wi-Fi. Join $ssidHint in Settings ▸ Wi-Fi."
        }
        return "$reason $hint"
    }

    // MARK: - Focus loupe and meter

    /** The loupe needs detail: switch to 1280×960 while it's open, then go back. */
    suspend fun setLoupe(on: Boolean) {
        val sharp = "1280x0960"
        if (on && liveViewQuality != sharp && sharp in availableLiveViewSizes) {
            liveViewBeforeLoupe = liveViewQuality
            changeLiveViewQuality(sharp)
        } else if (!on) {
            val previous = liveViewBeforeLoupe ?: return
            liveViewBeforeLoupe = null
            changeLiveViewQuality(previous)
        }
    }

    /** Measure sharpness inside this normalised region (the loupe's view); null stops measuring. */
    fun setFocusMeterRegion(region: RectF?) {
        receiver?.meterRegion = region
        focusScore = null
        focusPeak = 0.0
        focusFloor = Double.POSITIVE_INFINITY
    }

    fun updateFocusMeter(value: Double) {
        val smoothed = focusScore?.let { it * 0.55 + value * 0.45 } ?: value
        focusScore = smoothed
        focusPeak = maxOf(focusPeak, smoothed)
        focusFloor = minOf(focusFloor, smoothed)
    }
}

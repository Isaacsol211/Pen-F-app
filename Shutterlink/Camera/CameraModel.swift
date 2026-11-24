import Photos
import SwiftUI

enum ConnectionPhase: Equatable {
    case disconnected, connecting, connected
}

/// The camera's operating mode. Shooting, live view and settings need `rec`;
/// browsing the card needs `play`.
enum CameraMode: String {
    case unknown, rec, play
}

struct CameraProperty: Identifiable, Hashable {
    var id: String { name }
    let name: String
    var settable: Bool
    var value: String
    var options: [String]
}

struct CardFolder: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let count: Int
    /// A folder made by a different camera brand, which this camera may not list.
    var isForeign: Bool

    init(path: String, name: String, count: Int, isForeign: Bool? = nil) {
        self.path = path
        self.name = name
        self.count = count
        // Olympus names its folders 100OLYMP…; anything else came from another camera.
        self.isForeign = isForeign ?? !name.uppercased().hasSuffix("OLYMP")
    }
}

/// Where a photo can be fetched when the camera serves files by URL (Panasonic, via UPnP).
struct MediaURLs: Hashable {
    var thumbnail: URL?
    var preview: URL?
    var original: URL
}

struct CameraImage: Identifiable, Hashable {
    var id: String { path }
    let directory: String
    let name: String
    let size: Int
    let attributes: Int
    let date: Date
    var urls: MediaURLs? = nil

    var path: String { directory + "/" + name }
    var isDirectory: Bool { attributes & 16 != 0 }
    var fileExtension: String { (name as NSString).pathExtension.uppercased() }
    var isVideo: Bool { ["MOV", "MP4", "AVI"].contains(fileExtension) }
}

@MainActor
@Observable
final class CameraModel {
    /// The one model the app and its Shortcuts actions share.
    static let shared = CameraModel()

    // MARK: Settings (saved between launches)

    /// The brand picked on the Connect screen, or the one auto-detect found for this connection.
    var brand: CameraBrand
    /// Find the brand by itself at connect (from the Wi-Fi network and by asking the camera).
    var autoDetectBrand: Bool
    /// Some bodies (LUMIX…) record video from any mode and the app can't read a photo/video switch,
    /// so it keeps its own Photo/Video switch for them.
    var videoMode = false
    var host: String
    var userAgent: String
    var liveViewQuality: String
    var touchShutter = false

    static let userAgents = ["OI.Share v2", "OlympusCameraKit"]

    // MARK: Connection

    var phase: ConnectionPhase = .disconnected
    var status: String?
    var lastError: String?
    var cameraName: String?
    var connectMode: String?
    var commands = CommandList()
    var rawCommandList = ""
    var rawDescList = ""
    var mode: CameraMode = .unknown
    var isSwitchingMode = false

    // MARK: Exposure & other settings

    var properties: [String: CameraProperty] = [:]

    // MARK: Live view

    var liveFrame: UIImage?
    /// Pixel size of the arriving frames; changes rarely, so views that only need the
    /// geometry don't redraw on every frame.
    var frameSize: CGSize = .zero
    @ObservationIgnored private var fpsUpdatedAt: CFTimeInterval = 0
    /// Same as liveFrame but updated a few times a second, for the blurred background.
    var ambientFrame: UIImage?
    @ObservationIgnored private var ambientUpdatedAt: CFTimeInterval = 0
    var liveInfo = LiveInfo()
    /// Live luminance histogram (64 bins, 0…1), refreshed a few times a second.
    var histogram: [Float] = []
    /// Loupe focus meter: smoothed sharpness, and the best seen since the loupe moved.
    var focusScore: Double?
    var focusPeak: Double = 0
    var focusFloor: Double = .infinity

    // MARK: Last shot, movie, interval timer

    /// Preview of the most recent capture, fetched right after shooting.
    var lastShot: UIImage?
    var isRecordingMovie = false
    var movieStartedAt: Date?
    var interval = IntervalState()
    /// Short confirmation shown as a floating glass capsule ("Clock synced", …).
    var toast: String?
    @ObservationIgnored var intervalTask: Task<Void, Never>?
    var liveViewRunning = false
    var liveViewStartedAt: Date?
    var lastFrameAt: Date?
    var fps = 0
    /// Where the user last tapped, in live-view coordinates.
    /// Where the user last tapped, normalised 0…1 so it survives live-view size changes.
    var focusPoint: CGPoint?
    var isShooting = false
    var shotCounter = 0
    /// Set while a timed (≥ 1 s) or open-ended exposure is running.
    var exposureStartedAt: Date?
    /// Length of the timed exposure, nil when open-ended.
    var exposureDuration: Double?

    // MARK: Presets

    var presetSteps: [PresetStep] = []
    var presetRunning = false
    /// Which preset `presetSteps` belong to (a recipe id or a saved preset's UUID).
    var presetResultsFor: String?
    /// Settings from before the last preset, for Undo.
    var presetUndo: SettingsSnapshot?
    var savedPresets: [SavedPreset] = SavedPreset.load() {
        didSet { SavedPreset.store(savedPresets) }
    }

    // MARK: Motion trigger, exposing to the right

    var motion = MotionTrigger()
    /// How much the trigger box changed between the last two frames analysed (0…1).
    var motionLevel: Double = 0
    @ObservationIgnored var motionPrevious: [UInt8]?
    @ObservationIgnored var motionAnalyzedAt: CFTimeInterval = 0
    @ObservationIgnored var motionQuietUntil: CFTimeInterval = 0
    var ettrRunning = false

    // MARK: Scene assistant

    /// Suggestions from what live view shows (on by default; ⋯ menu).
    var sceneAssistantOn = UserDefaults.standard.object(forKey: "assistant.on") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(sceneAssistantOn, forKey: "assistant.on")
            if !sceneAssistantOn { sceneSuggestion = nil }
        }
    }
    var sceneSuggestion: SceneSuggestion?
    /// What the last look saw (for the request log and the self-test).
    var sceneSignals: SceneSignals?
    @ObservationIgnored var sceneSnoozed: [String: Date] = [:]
    @ObservationIgnored var sceneCandidate: String?
    @ObservationIgnored var sceneMisses = 0

    // MARK: Card browser

    var images: [CameraImage] = []
    /// Every folder in /DCIM with how many files the camera lists in it.
    var cardFolders: [CardFolder] = []
    var galleryLoading = false
    var galleryError: String?

    // MARK: Extras (peaking, timed bulb, bracketing, geotagging, smart import)

    /// Focus peaking overlay on live view; computed off the main thread a few times a second.
    var focusPeaking = UserDefaults.standard.bool(forKey: "ui.peaking") {
        didSet {
            UserDefaults.standard.set(focusPeaking, forKey: "ui.peaking")
            receiver?.setPeaking(focusPeaking)
            if !focusPeaking { peakingOverlay = nil }
        }
    }
    var peakingOverlay: UIImage?
    /// Stop Bulb / Live Time / Live Composite automatically after this many seconds (0 = off).
    var bulbTimer: Double = UserDefaults.standard.double(forKey: "bulbTimer") {
        didSet { UserDefaults.standard.set(bulbTimer, forKey: "bulbTimer") }
    }
    @ObservationIgnored var openExposureStopTask: Task<Void, Never>?
    var bracket = BracketState()
    @ObservationIgnored var bracketTask: Task<Void, Never>?
    /// Log where the phone is while connected, and add it to photos saved to Photos.
    var geotagging = UserDefaults.standard.bool(forKey: "geotag") {
        didSet {
            UserDefaults.standard.set(geotagging, forKey: "geotag")
            updateLocationLogging()
        }
    }
    @ObservationIgnored let locationLog = LocationLog()
    /// Starred card files, keyed by name and size so a reused file name on a new card doesn't match.
    var starred: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "stars") ?? []) {
        didSet { UserDefaults.standard.set(Array(starred), forKey: "stars") }
    }
    var rawImport: RawImportProgress?
    @ObservationIgnored var rawImportTask: Task<Void, Never>?

    // MARK: Camera Wi-Fi and auto-save (CameraWiFi.swift, AutoSave.swift)

    /// The camera's network as typed or scanned in Add a camera; Shutterlink joins it before connecting.
    var wifiSSID = ""
    var wifiPassword = ""
    /// The network joined for this connection, remembered with the camera once it answers.
    @ObservationIgnored var joinedNetwork: CameraNetwork?
    /// Save each new photo to Photos as it's taken.
    var autoSaveNewPhotos = UserDefaults.standard.bool(forKey: "autoSave") {
        didSet { UserDefaults.standard.set(autoSaveNewPhotos, forKey: "autoSave") }
    }
    /// Photos taken while auto-save was on that the camera couldn't send during live view (LUMIX);
    /// they're saved from the card the next time it's opened.
    var autoSavePending = 0
    /// Saved by auto-save during this connection.
    var autoSavedCount = 0
    @ObservationIgnored var autoSaveChain: Task<Void, Never>?

    // MARK: Request log

    var log: [LogEntry] = []

    /// The connected camera's protocol; nil while disconnected.
    @ObservationIgnored var driver: CameraDriver?
    /// What the connected camera can do (the selected brand's defaults while disconnected).
    var capabilities = CameraCapabilities()
    /// What the app knows about this body from its model table (nil for one not in it).
    var profile: ModelProfile?
    /// Advice for this body (e.g. "set Wi-Fi to Private"), shown until dismissed once per model.
    var cameraNote: String?
    /// Cameras this iPhone has connected to, most recent first (the home screen's cards).
    var savedCameras: [SavedCamera] = SavedCamera.load()
    @ObservationIgnored var receiver: LiveViewReceiver?
    @ObservationIgnored private(set) var udpPort: UInt16 = 40000
    @ObservationIgnored private var frameTimes: [CFTimeInterval] = []
    @ObservationIgnored private var thumbnailCache: [String: UIImage] = [:]
    @ObservationIgnored private var resumeLiveViewWhenActive = false
    /// Live-view size to go back to when the focus loupe closes.
    @ObservationIgnored var liveViewBeforeLoupe: String?

    init() {
        let defaults = UserDefaults.standard
        let savedBrand = defaults.string(forKey: "brand").flatMap(CameraBrand.init(rawValue:))
        let startBrand = savedBrand ?? .olympus
        // Existing installs keep the brand they picked; new ones start on auto-detect.
        let auto = defaults.object(forKey: "autoBrand") as? Bool ?? (savedBrand == nil)
        brand = startBrand
        autoDetectBrand = auto
        host = defaults.string(forKey: "host") ?? (auto ? "" : startBrand.defaultHost)
        userAgent = defaults.string(forKey: "userAgent") ?? "OI.Share v2"
        liveViewQuality = defaults.string(forKey: "lvqty") ?? "0640x0480"
        // 1280×960 tops out around 9 fps over the camera's Wi-Fi; start everyone on the smooth size once.
        if !defaults.bool(forKey: "lvqtyResetTo640") {
            liveViewQuality = "0640x0480"
            defaults.set(true, forKey: "lvqtyResetTo640")
        }
        fitLiveViewQualityToBrand()
        capabilities = brand.defaultCapabilities
    }

    /// LUMIX streams only 320×240 or 640×480; fall back to 640×480 if a bigger Olympus size was saved.
    private func fitLiveViewQualityToBrand() {
        let sizes = availableLiveViewSizes
        if !sizes.isEmpty, !sizes.contains(liveViewQuality) { liveViewQuality = "0640x0480" }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(brand.rawValue, forKey: "brand")
        defaults.set(autoDetectBrand, forKey: "autoBrand")
        defaults.set(host, forKey: "host")
        defaults.set(userAgent, forKey: "userAgent")
        defaults.set(liveViewQuality, forKey: "lvqty")
    }

    /// Switches camera family (nil = auto-detect), moving the address to the new family's default
    /// unless it was customised.
    func setBrand(_ newBrand: CameraBrand?) {
        guard phase == .disconnected else { return }
        let hostIsDefault = host.isEmpty || CameraBrand.allCases.contains { $0.defaultHost == host }
        if let newBrand {
            if hostIsDefault { host = newBrand.defaultHost }
            brand = newBrand
            autoDetectBrand = false
        } else {
            if hostIsDefault { host = "" }
            autoDetectBrand = true
        }
        capabilities = brand.defaultCapabilities
        fitLiveViewQualityToBrand()
        saveSettings()
    }

    /// An HTTP client for `host` whose requests show up in the Request log.
    func makeHTTPClient(userAgent: String, allowedStatus: ClosedRange<Int> = 200...202) -> CameraHTTPClient {
        let client = CameraHTTPClient(host: connectionHost, userAgent: userAgent, allowedStatus: allowedStatus)
        client.onLog = { [weak self] entry in
            Task { @MainActor in self?.appendLog(entry) }
        }
        return client
    }

    /// Pixel size of the live-view frames actually arriving (the camera's AF coordinate space).
    var frameSpace: CGSize { frameSize == .zero ? liveViewSize : frameSize }

    var liveViewSize: CGSize {
        let parts = liveViewQuality.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : CGSize(width: 640, height: 480)
    }

    static func liveViewLabel(_ quality: String) -> String {
        let size = quality.split(separator: "x").compactMap { Int($0) }.map(String.init).joined(separator: "×")
        switch quality {
        case "0320x0240": return "\(size) · fastest, blurry"
        case "0640x0480": return "\(size) · smooth (~30 fps)"
        case "1280x0960": return "\(size) · sharp (~9 fps)"
        default: return size
        }
    }

    /// The dial only offers what the mounted lens can do (the camera lists F1.0–F91 regardless).
    func dialOptions(for property: CameraProperty) -> CameraProperty {
        guard property.name == "focalvalue", let range = liveInfo.apertureRange else { return property }
        var filtered = property
        filtered.options = property.options.filter { Double($0).map(range.contains) ?? true }
        guard !filtered.options.isEmpty else { return property }
        // The camera can report a value the lens can't do (e.g. "1.0"); show the nearest real stop.
        if !filtered.options.contains(property.value), let current = Double(property.value) {
            filtered.value = filtered.options.min {
                abs((Double($0) ?? 0) - current) < abs((Double($1) ?? 0) - current)
            } ?? property.value
        }
        return filtered
    }

    /// Live-view sizes this camera offers; empty when it has only one.
    var availableLiveViewSizes: [String] { capabilities.liveViewSizes }

    /// The shutter records video (a movie mode on the dial, or the app's Video switch).
    var isMovieMode: Bool {
        capabilities.videoSwitch ? videoMode : properties["takemode"]?.value.lowercased() == "movie"
    }

    var isContinuousDrive: Bool {
        properties["drivemode"]?.value.localizedCaseInsensitiveContains("continuous") ?? false
    }

    func isLiveViewStalled(at now: Date) -> Bool {
        guard liveViewRunning, let since = lastFrameAt ?? liveViewStartedAt else { return false }
        return now.timeIntervalSince(since) > 3
    }

    // MARK: - Connect / disconnect

    /// Connects; with a deadline, keeps trying until then (e.g. while iOS joins the camera's Wi-Fi
    /// after a Shortcut or the Action button opened the app).
    func connect(waitingUntil deadline: Date? = nil) async {
        guard phase == .disconnected else { return }
        while true {
            await connectOnce()
            guard phase == .disconnected, let deadline, Date() < deadline, !Task.isCancelled else { return }
            let failure = lastError
            lastError = nil
            phase = .connecting
            status = "Waiting for the camera's Wi-Fi…"
            try? await Task.sleep(for: .seconds(2))
            phase = .disconnected
            status = nil
            if Date() >= deadline {
                lastError = failure
                return
            }
        }
    }

    private func connectOnce() async {
        guard phase == .disconnected else { return }
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        saveSettings()
        phase = .connecting
        lastError = nil
        status = "Looking for the camera…"
        debugLog("connect: brand=\(autoDetectBrand ? "auto" : brand.rawValue) host=\(host) wifi=\(NetworkInfo.wifiAddress() ?? "none") ua=\(userAgent)")

        do {
            var target = (brand: brand, host: host.isEmpty ? brand.defaultHost : host)
            if autoDetectBrand {
                status = "Finding out which camera this is…"
                guard let found = await BrandDetector.detect(host: host) else {
                    throw CameraError(BrandDetector.notFoundMessage(wifi: NetworkInfo.wifiAddress()))
                }
                debugLog("auto-detect: \(found.brand.rawValue) at \(found.host)")
                target = found
                brand = found.brand
            }
            Self.ssidHint = brand.ssidHint
            // The driver talks to the detected address; the saved setting stays as the user left it.
            activeHost = target.host
            let driver = brand.makeDriver(for: self)
            self.driver = driver
            capabilities = driver.capabilities
            try await driver.connect()
            capabilities = driver.capabilities
            fitLiveViewQualityToBrand()
            if let profile, !profile.notes.isEmpty,
               !(UserDefaults.standard.stringArray(forKey: "dismissedNotes") ?? []).contains(profile.name) {
                cameraNote = profile.notes.joined(separator: "\n\n")
            }

            try startReceiver(format: driver.liveViewFormat)
            phase = .connected
            UserDefaults.standard.set(true, forKey: "hasConnected")
            rememberConnectedCamera()
            KeepAwake.set(true)
            status = nil
            updateLocationLogging()
            await enterRecMode()
        } catch {
            lastError = Self.describe(error, host: connectionHost)
            teardown()
        }
    }

    /// Where the connected camera is (the detected address when auto-detecting).
    var activeHost: String?

    /// The address drivers talk to: the connected one, else the setting, else the brand's default.
    var connectionHost: String {
        if let activeHost { return activeHost }
        return host.isEmpty ? brand.defaultHost : host
    }

    /// Hides the camera note, and keeps it hidden for this model from now on.
    func dismissCameraNote() {
        if let name = profile?.name {
            var dismissed = UserDefaults.standard.stringArray(forKey: "dismissedNotes") ?? []
            if !dismissed.contains(name) { dismissed.append(name) }
            UserDefaults.standard.set(dismissed, forKey: "dismissedNotes")
        }
        cameraNote = nil
    }

    func disconnect() async {
        await stopLiveView()
        await driver?.disconnect()
        teardown()
    }

    func powerOff() async {
        guard let driver else { return }
        await stopLiveView()
        await driver.powerOff()
        teardown()
    }

    private func teardown() {
        KeepAwake.set(false)
        driver?.teardown()
        driver = nil
        activeHost = nil
        profile = nil
        cameraNote = nil
        stopInterval()
        cancelBracket()
        // Undo and the motion trigger belong to this camera's session.
        presetUndo = nil
        presetSteps = []
        presetResultsFor = nil
        armMotion(false)
        sceneSuggestion = nil
        sceneCandidate = nil
        openExposureStopTask?.cancel()
        openExposureStopTask = nil
        rawImportTask?.cancel()
        autoSaveChain?.cancel()
        autoSaveChain = nil
        autoSavePending = 0
        autoSavedCount = 0
        joinedNetwork = nil
        peakingOverlay = nil
        receiver?.stop()
        receiver = nil
        phase = .disconnected
        status = nil
        mode = .unknown
        liveViewRunning = false
        liveFrame = nil
        frameSize = .zero
        liveInfo = LiveInfo()
        focusPoint = nil
        isShooting = false
        isRecordingMovie = false
        movieStartedAt = nil
        properties = [:]
        images = []
        thumbnailCache = [:]
        fps = 0
        capabilities = brand.defaultCapabilities
        updateLocationLogging()
    }

    private func startReceiver(format: LiveViewFormat) throws {
        var lastFailure: Error?
        for port in UInt16(40000)...UInt16(40010) {
            let receiver = LiveViewReceiver(port: port, format: format)
            receiver.onFrame = { [weak self] image, info, histogram, sharpness in
                self?.handleFrame(image, info)
                if let histogram { self?.histogram = histogram }
                if let sharpness { self?.updateFocusMeter(sharpness) }
            }
            receiver.onPeaking = { [weak self] overlay in
                guard let self, self.focusPeaking else { return }
                self.peakingOverlay = overlay.map { UIImage(cgImage: $0) }
            }
            receiver.setPeaking(focusPeaking)
            do {
                try receiver.start()
                self.receiver = receiver
                udpPort = port
                return
            } catch {
                lastFailure = error
            }
        }
        throw lastFailure ?? CameraError("Couldn't open a UDP port for live view.")
    }

    func scenePhaseChanged(_ scenePhase: ScenePhase) {
        guard phase == .connected else { return }
        switch scenePhase {
        case .background:
            if liveViewRunning {
                resumeLiveViewWhenActive = true
                Task { await stopLiveView() }
            }
        case .active:
            if resumeLiveViewWhenActive {
                resumeLiveViewWhenActive = false
                Task { await startLiveView() }
            }
        default:
            break
        }
    }

    // MARK: - Modes & live view

    /// Recording mode: required for live view, shooting and reading/changing settings.
    func enterRecMode() async {
        await driver?.enterRecMode()
    }

    func startLiveView() async {
        guard let driver, mode == .rec, !liveViewRunning else { return }
        liveViewRunning = true
        liveViewStartedAt = Date()
        lastFrameAt = nil
        await driver.startLiveView()
    }

    func stopLiveView() async {
        guard let driver, liveViewRunning else { return }
        liveViewRunning = false
        fps = 0
        await driver.stopLiveView()
    }

    func restartLiveView() async {
        await stopLiveView()
        await enterRecMode()
    }

    func changeLiveViewQuality(_ quality: String) async {
        guard quality != liveViewQuality else { return }
        liveViewQuality = quality
        saveSettings()
        liveFrame = nil
        frameSize = .zero
        await restartLiveView()
    }

    /// Pull-based drivers (Nikon, Canon, Sony) hand each live-view JPEG over here; it goes through
    /// the same decoding, histogram, peaking and focus meter as UDP frames.
    func submitLiveViewJPEG(_ jpeg: Data) {
        receiver?.submit(jpeg: jpeg)
    }

    private func handleFrame(_ image: UIImage?, _ info: LiveInfo?) {
        guard liveViewRunning else { return }
        if let image {
            liveFrame = image
            // The loupe's mini-map only needs a few updates a second.
            if CACurrentMediaTime() - ambientUpdatedAt > 0.5 {
                ambientFrame = image
                ambientUpdatedAt = CACurrentMediaTime()
            }
            if image.size != frameSize { frameSize = image.size }
            let now = CACurrentMediaTime()
            // Only touch these a couple of times a second: each change redraws views that read them.
            if lastFrameAt.map({ Date().timeIntervalSince($0) > 0.5 }) ?? true { lastFrameAt = Date() }
            frameTimes.append(now)
            frameTimes.removeAll { now - $0 > 1 }
            if now - fpsUpdatedAt > 0.5 {
                fpsUpdatedAt = now
                if fps != frameTimes.count { fps = frameTimes.count }
            }
            if motion.armed || motion.editing { analyzeMotion(image) }
        }
        if let info, info != liveInfo { liveInfo = info }
    }

    // MARK: - Settings

    func refreshProperties() async {
        await driver?.refreshProperties()
    }

    /// Returns false (and reports why) if the camera refused the value.
    @discardableResult
    func setProperty(_ name: String, to value: String, reportErrors: Bool = true) async -> Bool {
        guard let driver else { return false }
        return await driver.setProperty(name, to: value, reportErrors: reportErrors)
    }

    // MARK: - Focus & shooting

    func tapFocus(normalized point: CGPoint) async {
        guard let driver, mode == .rec else { return }
        let normalized = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        focusPoint = normalized

        if touchShutter {
            await shutterPressed()
            await shutterReleased()
            return
        }
        guard capabilities.tapToFocus else { return }
        await driver.focus(at: normalized)
    }

    func clearFocus() async {
        focusPoint = nil
        liveInfo.afState = 0
        await driver?.releaseFocus()
    }

    /// Live Composite / Live Time / Bulb: the exposure runs until told to stop.
    var isOpenEndedShutter: Bool {
        PropertyFormat.isOpenEnded(shutter: properties["shutspeedvalue"]?.value ?? "")
    }

    /// Press = start taking. In continuous drive the camera keeps shooting until release.
    func shutterPressed() async {
        guard let driver, mode == .rec, !isShooting else { return }
        await driver.shutterPressed()
    }

    func shutterReleased() async {
        await driver?.shutterReleased()
    }

    /// Open-ended exposures: first tap starts, second tap stops.
    func toggleOpenExposure() async {
        guard let driver, mode == .rec else { return }
        let starting = !isShooting
        if !starting {
            openExposureStopTask?.cancel()
            openExposureStopTask = nil
            exposureDuration = nil
        }
        await driver.toggleOpenExposure()
        if starting, isShooting, bulbTimer > 0 { scheduleOpenExposureStop(after: bulbTimer) }
    }

    func toggleMovie() async {
        guard let driver, mode == .rec else { return }
        await driver.toggleMovie()
    }

    /// Grabs a preview of the capture that just finished, for the review thumbnail.
    func fetchLastShot() async {
        guard let driver, mode == .rec, capabilities.lastShotReview else { return }
        await driver.fetchLastShot()
    }

    /// Sets the camera's clock and time zone from the phone.
    @discardableResult
    func syncClock() async -> Bool {
        guard let driver, capabilities.clockSync else { return false }
        return await driver.syncClock()
    }

    /// A normalised point in the camera's AF space: the pixels of the frames actually arriving.
    func pixelPoint(_ normalized: CGPoint) -> CGPoint {
        let size = frameSpace
        return CGPoint(x: normalized.x * (size.width - 1), y: normalized.y * (size.height - 1))
    }

    /// Long or open exposure / movie in progress: anything that switches modes would ruin it.
    var isBusyExposing: Bool {
        isRecordingMovie || (isShooting && (isOpenEndedShutter || exposureStartedAt != nil))
    }

    static func pointString(_ p: CGPoint) -> String {
        String(format: "%04dx%04d", Int(p.x.rounded()), Int(p.y.rounded()))
    }

    // MARK: - Card browser

    func openGallery() async {
        guard let driver else { return }
        galleryLoading = true
        galleryError = nil
        defer { galleryLoading = false }
        await stopLiveView()
        await driver.openGallery()
        // Photos auto-save couldn't fetch during live view (LUMIX).
        await savePendingAutoSaves()
    }

    func closeGallery() async {
        await enterRecMode()
    }

    func thumbnail(for image: CameraImage) async -> UIImage? {
        if let cached = thumbnailCache[image.path] { return cached }
        guard let driver, let thumb = await driver.thumbnail(for: image) else { return nil }
        thumbnailCache[image.path] = thumb
        return thumb
    }

    func preview(for image: CameraImage) async throws -> UIImage {
        guard let driver else { throw CameraError("Not connected.") }
        return try await driver.preview(for: image)
    }

    func downloadOriginal(_ image: CameraImage) async throws -> Data {
        guard let driver else { throw CameraError("Not connected.") }
        return try await driver.downloadOriginal(image)
    }

    /// Returns whether the photo was geotagged.
    @discardableResult
    func saveOriginalToPhotos(_ image: CameraImage) async throws -> Bool {
        let data = try await downloadOriginal(image)
        let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard access == .authorized || access == .limited else {
            throw CameraError("Photos access is off. Turn it on in \(Platform.photosSettings).")
        }
        return try await addToPhotos(data, for: image)
    }

    /// Adds a downloaded file to Photos, with the logged location nearest its capture time when
    /// geotagging is on. Returns whether a location was added.
    @discardableResult
    func addToPhotos(_ data: Data, for image: CameraImage) async throws -> Bool {
        let type: PHAssetResourceType = image.isVideo ? .video : .photo
        let filename = image.name
        let location = geotagging ? locationLog.location(near: image.date) : nil
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = filename
            request.addResource(with: type, data: data, options: options)
            if let location { request.location = location }
        }
        if let location {
            debugLog("geotag \(filename): \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
        return location != nil
    }

    // MARK: - Log & errors

    func appendLog(_ entry: LogEntry) {
        log.append(entry)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    func clearLog() { log.removeAll() }

    func report(_ error: Error) {
        lastError = Self.describe(error, host: connectionHost)
    }

    /// The camera Wi-Fi name to mention in connection errors (set per brand on connect).
    static var ssidHint = "PEN-F-P-…"

    static func describe(_ error: Error, host: String) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }

        // iOS reports a denied Local Network permission inside the error's network-path details.
        let details = "\(urlError) \((urlError as NSError).userInfo)"
        if details.localizedCaseInsensitiveContains("local network prohibited") {
            return "\(Platform.os) is blocking Local Network access for Shutterlink. Turn it on in \(Platform.settings) ▸ Privacy & Security ▸ Local Network, then \(Platform.tap) Connect again."
        }

        let reason: String
        switch urlError.code {
        case .timedOut: reason = "No reply from \(host) (timed out)."
        case .cannotConnectToHost: reason = "\(host) refused the connection."
        case .notConnectedToInternet, .dataNotAllowed: reason = "\(Platform.os) says there is no network route to \(host)."
        case .networkConnectionLost: reason = "The connection to \(host) dropped."
        case .cannotFindHost: reason = "Can't find \(host)."
        default: reason = urlError.localizedDescription
        }

        let network: String
        if let wifi = NetworkInfo.wifiAddress() {
            network = "This \(Platform.device) is on Wi-Fi (\(wifi)), but probably not the camera's network: home routers often use 192.168.0.x too. Open \(Platform.settings) ▸ Wi-Fi and check it says \(ssidHint); \(Platform.os) likes to switch back to a network with internet. Also check Local Network is on for Shutterlink in \(Platform.settings) ▸ Privacy & Security."
        } else {
            network = "This \(Platform.device) isn't on Wi-Fi. Join \(ssidHint) in \(Platform.settings) ▸ Wi-Fi."
        }
        return "\(reason) \(network) [code \(urlError.code.rawValue)]"
    }
}

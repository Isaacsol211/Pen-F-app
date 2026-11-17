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
    // MARK: Settings (saved between launches)

    var brand: CameraBrand
    /// LUMIX bodies record video from any mode (their red button works anywhere), so the app keeps
    /// its own Photo/Video switch for them instead of reading a mode dial.
    var lumixVideoMode = false
    var host: String
    var userAgent: String
    var liveViewQuality: String
    var touchShutter = false

    static let userAgents = ["OI.Share v2", "OlympusCameraKit"]
    static let defaultLiveViewSizes = ["0320x0240", "0640x0480", "0800x0600", "1024x0768", "1280x0960"]

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

    // MARK: Card browser

    var images: [CameraImage] = []
    /// Every folder in /DCIM with how many files the camera lists in it.
    var cardFolders: [CardFolder] = []
    var galleryLoading = false
    var galleryError: String?

    // MARK: Request log

    var log: [LogEntry] = []

    @ObservationIgnored var client: OlympusClient?
    @ObservationIgnored var receiver: LiveViewReceiver?
    @ObservationIgnored private(set) var udpPort: UInt16 = 40000
    @ObservationIgnored private var frameTimes: [CFTimeInterval] = []
    @ObservationIgnored private var thumbnailCache: [String: UIImage] = [:]
    @ObservationIgnored private var resumeLiveViewWhenActive = false
    @ObservationIgnored private var loggedDescList = false
    /// Live-view size to go back to when the focus loupe closes.
    @ObservationIgnored var liveViewBeforeLoupe: String?
    /// Panasonic stops streaming unless it hears from the app regularly.
    @ObservationIgnored var panasonicKeepAlive: Task<Void, Never>?
    /// Per-connection LUMIX state (lens limits, value tables, UPnP address).
    @ObservationIgnored var lumix = PanasonicSession()

    init() {
        let defaults = UserDefaults.standard
        brand = CameraBrand(rawValue: defaults.string(forKey: "brand") ?? "") ?? .olympus
        host = defaults.string(forKey: "host") ?? "192.168.0.10"
        userAgent = defaults.string(forKey: "userAgent") ?? "OI.Share v2"
        liveViewQuality = defaults.string(forKey: "lvqty") ?? "0640x0480"
        // 1280×960 tops out around 9 fps over the camera's Wi-Fi; start everyone on the smooth size once.
        if !defaults.bool(forKey: "lvqtyResetTo640") {
            liveViewQuality = "0640x0480"
            defaults.set(true, forKey: "lvqtyResetTo640")
        }
        fitLiveViewQualityToBrand()
    }

    /// LUMIX streams only 320×240 or 640×480; fall back to 640×480 if a bigger Olympus size was saved.
    private func fitLiveViewQualityToBrand() {
        if brand == .panasonic, !availableLiveViewSizes.contains(liveViewQuality) { liveViewQuality = "0640x0480" }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(brand.rawValue, forKey: "brand")
        defaults.set(host, forKey: "host")
        defaults.set(userAgent, forKey: "userAgent")
        defaults.set(liveViewQuality, forKey: "lvqty")
    }

    /// Switches camera family, moving the address to the new family's default unless it was customised.
    func setBrand(_ newBrand: CameraBrand) {
        guard newBrand != brand, phase == .disconnected else { return }
        if CameraBrand.allCases.map(\.defaultHost).contains(host) { host = newBrand.defaultHost }
        brand = newBrand
        fitLiveViewQualityToBrand()
        saveSettings()
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

    var availableLiveViewSizes: [String] {
        if brand == .panasonic { return ["0320x0240", "0640x0480"] }   // LUMIX: qvga or vga
        let fromCamera = commands.liveViewSizes
        return fromCamera.isEmpty ? Self.defaultLiveViewSizes : fromCamera
    }

    var isContinuousDrive: Bool {
        properties["drivemode"]?.value.localizedCaseInsensitiveContains("continuous") ?? false
    }

    func isLiveViewStalled(at now: Date) -> Bool {
        guard liveViewRunning, let since = lastFrameAt ?? liveViewStartedAt else { return false }
        return now.timeIntervalSince(since) > 3
    }

    // MARK: - Connect / disconnect

    func connect() async {
        guard phase == .disconnected else { return }
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        saveSettings()
        phase = .connecting
        lastError = nil
        status = "Looking for the camera…"

        let client = OlympusClient(host: host, userAgent: userAgent)
        client.onLog = { [weak self] entry in
            Task { @MainActor in self?.appendLog(entry) }
        }
        self.client = client

        debugLog("connect: brand=\(brand.rawValue) host=\(host) wifi=\(NetworkInfo.wifiAddress() ?? "none") ua=\(userAgent)")
        Self.ssidHint = brand.ssidHint
        do {
          if brand == .panasonic {
            try await panasonicHandshake()
          } else {
            // The first request can fail while iOS shows the Local Network prompt,
            // and the camera can be slow right after its Wi-Fi comes up, so retry a little.
            var reply: Data?
            var failure: Error?
            for attempt in 1...3 {
                do {
                    reply = try await client.get("get_connectmode", timeout: 5)
                    break
                } catch {
                    failure = error
                    guard attempt < 3, error is URLError else { break }
                    status = "No answer yet, retrying (\(attempt + 1)/3)…"
                    try? await Task.sleep(for: .milliseconds(1500))
                }
            }
            guard let reply else { throw failure ?? CameraError("No reply from the camera.") }
            self.connectMode = MiniXML.parse(reply)?.trimmedText

            status = "Reading camera info…"
            if let info = try? await client.get("get_caminfo") {
                cameraName = MiniXML.parse(info)?.value("model")
            }
            if let list = try? await client.get("get_commandlist") {
                rawCommandList = String(decoding: list, as: UTF8.self)
                commands = CommandList(root: MiniXML.parse(list))
                debugLog("COMMANDLIST\n\(rawCommandList)")
            }
            loggedDescList = false
          }

            try startReceiver()
            phase = .connected
            UIApplication.shared.isIdleTimerDisabled = true
            status = nil
            await enterRecMode()
        } catch {
            lastError = Self.describe(error, host: host)
            teardown()
        }
    }

    func disconnect() async {
        await stopLiveView()
        teardown()
    }

    func powerOff() async {
        guard let client else { return }
        await stopLiveView()
        if brand == .panasonic {
            await panasonicPowerOff()
            teardown()
            return
        }
        _ = try? await client.get("switch_cammode", [("mode", "play")])
        _ = try? await client.get("exec_pwoff")
        teardown()
    }

    private func teardown() {
        UIApplication.shared.isIdleTimerDisabled = false
        panasonicKeepAlive?.cancel()
        panasonicKeepAlive = nil
        stopInterval()
        receiver?.stop()
        receiver = nil
        client = nil
        phase = .disconnected
        status = nil
        mode = .unknown
        liveViewRunning = false
        liveFrame = nil
        frameSize = .zero
        liveInfo = LiveInfo()
        focusPoint = nil
        isShooting = false
        properties = [:]
        images = []
        thumbnailCache = [:]
        fps = 0
    }

    private func startReceiver() throws {
        var lastFailure: Error?
        for port in UInt16(40000)...UInt16(40010) {
            let receiver = LiveViewReceiver(port: port, format: brand.liveViewFormat)
            receiver.onFrame = { [weak self] image, info, histogram, sharpness in
                self?.handleFrame(image, info)
                if let histogram { self?.histogram = histogram }
                if let sharpness { self?.updateFocusMeter(sharpness) }
            }
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
        guard let client else { return }
        if brand == .panasonic { await panasonicEnterRecMode(); return }
        isSwitchingMode = true
        defer { isSwitchingMode = false }
        do {
            // The PEN-F ignores a new live-view size while it's already in recording mode,
            // so go through playback first.
            if mode != .play {
                _ = try await client.get("switch_cammode", [("mode", "play")])
                try? await Task.sleep(for: .milliseconds(300))
            }
            var params: [(String, String)] = [("mode", "rec")]
            if commands.liveViewSizes.isEmpty || commands.liveViewSizes.contains(liveViewQuality) {
                params.append(("lvqty", liveViewQuality))
            }
            _ = try await client.get("switch_cammode", params)
            mode = .rec
            try? await Task.sleep(for: .milliseconds(400))
            await refreshProperties()
            await startLiveView()
        } catch {
            report(error)
        }
    }

    func startLiveView() async {
        guard let client, mode == .rec, !liveViewRunning else { return }
        liveViewRunning = true
        liveViewStartedAt = Date()
        lastFrameAt = nil
        if brand == .panasonic { await panasonicStartLiveView(); return }
        do {
            let reply = try await client.get("exec_takemisc", [("com", "startliveview"), ("port", String(format: "%05d", Int(udpPort)))])
            debugLog("STARTLIVEVIEW reply: \(String(decoding: reply, as: UTF8.self))")
        } catch {
            liveViewRunning = false
            report(error)
        }
    }

    func stopLiveView() async {
        guard let client, liveViewRunning else { return }
        liveViewRunning = false
        fps = 0
        if brand == .panasonic { await panasonicStopLiveView(); return }
        _ = try? await client.get("exec_takemisc", [("com", "stopliveview")])
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

    private func handleFrame(_ image: UIImage?, _ info: LiveInfo?) {
        guard liveViewRunning else { return }
        if let image {
            liveFrame = image
            // The blurred background glow only needs a few updates a second.
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
        }
        if let info, info != liveInfo { liveInfo = info }
    }

    // MARK: - Settings

    func refreshProperties() async {
        guard let client else { return }
        if brand == .panasonic { await panasonicRefreshProperties(); return }
        do {
            let data = try await client.get("get_camprop", [("com", "desc"), ("propname", "desclist")])
            rawDescList = String(decoding: data, as: UTF8.self)
            if !loggedDescList {
                loggedDescList = true
                debugLog("DESCLIST\n\(rawDescList)")
            }
            guard let root = MiniXML.parse(data) else { return }
            var result: [String: CameraProperty] = [:]
            for desc in root.descendants(named: "desc") {
                guard let name = desc.value("propname"), !name.isEmpty else { continue }
                let options = (desc.value("enum") ?? "").split(separator: " ").map(String.init)
                result[name] = CameraProperty(name: name,
                                              settable: desc.value("attribute") == "getset",
                                              value: desc.value("value") ?? "",
                                              options: options)
            }
            properties = result
        } catch {
            report(error)
        }
    }

    /// Returns false (and reports why) if the camera refused the value.
    @discardableResult
    func setProperty(_ name: String, to value: String, reportErrors: Bool = true) async -> Bool {
        guard let client else { return false }
        if brand == .panasonic { return await panasonicSetProperty(name, to: value, reportErrors: reportErrors) }
        // Sent verbatim (the camera's parser is simple; shutter values contain a literal ").
        let body = "<?xml version=\"1.0\"?>\r\n<set>\r\n<value>\(value)</value>\r\n</set>\r\n"
        let previous = properties[name]?.value
        properties[name]?.value = value
        var ok = true
        do {
            _ = try await client.post("set_camprop", [("com", "set"), ("propname", name)], xml: body)
            if name == "takemode" { try? await Task.sleep(for: .milliseconds(300)) }
        } catch {
            ok = false
            if let previous { properties[name]?.value = previous }
            if reportErrors { report(error) }
        }
        // Changing one setting can lock/unlock others (e.g. aperture in P vs A).
        await refreshProperties()
        return ok
    }

    // MARK: - Focus & shooting

    func tapFocus(normalized point: CGPoint) async {
        guard let client, mode == .rec else { return }
        // AF points are in the pixel space of the frames the camera actually sends.
        let normalized = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        focusPoint = normalized
        let p = pixelPoint(normalized)

        if touchShutter {
            await shutterPressed()
            await shutterReleased()
            return
        }

        if brand == .panasonic { await panasonicFocus(at: normalized); return }
        let pointValue = Self.pointString(p)
        debugLog("tap: normalized=(\(String(format: "%.3f, %.3f", point.x, point.y))) point=\(pointValue) lvqty=\(liveViewQuality) frame=\(liveFrame.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "none") focusmode=\(properties["focusmode"]?.value ?? "?")")
        // assignafframe moves the AF target; takeready is a half-press (AF) at that point.
        do {
            let reply = try await client.get("exec_takemotion", [("com", "assignafframe"), ("point", pointValue)])
            debugLog("assignafframe reply: \(String(decoding: reply, as: UTF8.self))")
        } catch {
            debugLog("assignafframe failed: \(error)")
        }
        guard commands.supports("exec_takemotion", "takeready") else { return }
        do {
            let reply = try await client.get("exec_takemotion", [("com", "takeready"), ("point", pointValue)])
            debugLog("takeready reply: \(String(decoding: reply, as: UTF8.self))")
        } catch {
            report(error)
        }
    }

    func clearFocus() async {
        focusPoint = nil
        liveInfo.afState = 0
        if brand == .panasonic { await panasonicReleaseFocus(); return }
        _ = try? await client?.get("exec_takemotion", [("com", "releaseafframe")])
    }

    /// Live Composite / Live Time / Bulb: the exposure runs until told to stop.
    var isOpenEndedShutter: Bool {
        PropertyFormat.isOpenEnded(shutter: properties["shutspeedvalue"]?.value ?? "")
    }

    /// Press = start taking. In continuous drive the camera keeps shooting until release.
    func shutterPressed() async {
        guard let client, mode == .rec, !isShooting else { return }
        if brand == .panasonic { await panasonicShutterPressed(); return }
        isShooting = true
        var params: [(String, String)] = [("com", "starttake")]
        if let focusPoint { params.append(("point", Self.pointString(pixelPoint(focusPoint)))) }
        // Long exposures: the reply can take the exposure time plus the same again for noise reduction.
        let seconds = PropertyFormat.seconds(fromShutter: properties["shutspeedvalue"]?.value ?? "") ?? 0
        if seconds >= 1 {
            exposureStartedAt = Date()
            exposureDuration = seconds
        }
        defer {
            exposureStartedAt = nil
            exposureDuration = nil
        }
        do {
            let reply = try await client.get("exec_takemotion", params, timeout: max(60, seconds * 2 + 30))
            debugLog("starttake reply: \(String(decoding: reply, as: UTF8.self))")
            shotCounter += 1
            Task { await fetchLastShot() }
        } catch {
            isShooting = false
            report(error)
            return
        }
        if !isContinuousDrive { isShooting = false }
    }

    func shutterReleased() async {
        if brand == .panasonic { await panasonicShutterReleased(); return }
        guard let client, isShooting, isContinuousDrive else { return }
        _ = try? await client.getUrgent("exec_takemotion", [("com", "stoptake")])
        isShooting = false
    }

    /// Open-ended exposures: first tap starts, second tap stops.
    func toggleOpenExposure() async {
        guard let client, mode == .rec else { return }
        if brand == .panasonic { await panasonicToggleBulb(); return }
        if isShooting {
            _ = try? await client.getUrgent("exec_takemotion", [("com", "stoptake")])
            isShooting = false
            exposureStartedAt = nil
            shotCounter += 1
            // Give the camera a moment to write the composite, then grab the review image.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await fetchLastShot()
            }
            return
        }
        isShooting = true
        exposureStartedAt = Date()
        exposureDuration = nil
        // Don't await here: the camera may hold this reply until the exposure is stopped.
        Task {
            do {
                let reply = try await client.get("exec_takemotion", [("com", "starttake")], timeout: 4 * 3600)
                debugLog("starttake (open-ended) reply: \(String(decoding: reply, as: UTF8.self))")
            } catch {
                isShooting = false
                exposureStartedAt = nil
                report(error)
            }
        }
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
        guard let client else { return }
        galleryLoading = true
        galleryError = nil
        defer { galleryLoading = false }
        await stopLiveView()
        if brand == .panasonic { await panasonicOpenGallery(); return }
        do {
            if mode != .play {
                _ = try await client.get("switch_cammode", [("mode", "play")])
                mode = .play
                try? await Task.sleep(for: .milliseconds(300))
            }
            var found: [CameraImage] = []
            var folders: [CardFolder] = []
            for folder in try await listDirectory("/DCIM") where folder.isDirectory {
                var files = try await listDirectory(folder.path).filter { !$0.isDirectory }
                // The PEN-F's photo list skips another camera's folder; its built-in web page may not.
                if files.isEmpty { files = await webListedFiles(folder) }
                found += files
                folders.append(CardFolder(path: folder.path, name: folder.name, count: files.count))
            }
            cardFolders = folders.sorted { $0.name > $1.name }
            images = found.sorted { ($0.date, $0.name) > ($1.date, $1.name) }
        } catch {
            galleryError = Self.describe(error, host: host)
        }
    }

    /// Reads the camera's built-in web page for a folder and pulls out any file names it links to.
    private func webListedFiles(_ folder: CameraImage) async -> [CameraImage] {
        guard let client, let data = try? await client.download(path: folder.path + "/") else { return [] }
        let html = String(decoding: data, as: UTF8.self)
        debugLog("WEBLIST \(folder.path) (\(data.count) bytes)\n\(html.prefix(6000))")
        let pattern = #"[A-Za-z0-9_\-]+\.(?:jpe?g|rw2|orf|mp4|mov|cr2|cr3|nef|arw|raf|heic|dng)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        var names: [String] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let name = String(html[range])
            if !names.contains(name) { names.append(name) }
        }
        debugLog("WEBLIST \(folder.path): \(names.count) files \(names.prefix(10))")
        return names.map { CameraImage(directory: folder.path, name: $0, size: 0, attributes: 0, date: .distantPast) }
    }

    func closeGallery() async {
        await enterRecMode()
    }

    private func listDirectory(_ directory: String) async throws -> [CameraImage] {
        guard let client else { return [] }
        do {
            let data = try await client.get("get_imglist", [("DIR", directory)])
            return ImageListParser.parse(String(decoding: data, as: UTF8.self))
        } catch let error as CameraHTTPError where error.status == 404 {
            return [] // empty folder
        }
    }

    func thumbnail(for image: CameraImage) async -> UIImage? {
        if let cached = thumbnailCache[image.path] { return cached }
        if let urls = image.urls {
            guard let data = try? await client?.fetch(urls.thumbnail ?? urls.preview ?? urls.original, log: false),
                  let thumb = UIImage(data: data) else { return nil }
            thumbnailCache[image.path] = thumb
            return thumb
        }
        guard let client,
              let data = try? await client.get("get_thumbnail", [("DIR", image.path)], log: false),
              let thumb = UIImage(data: data) else { return nil }
        thumbnailCache[image.path] = thumb
        return thumb
    }

    func preview(for image: CameraImage) async throws -> UIImage {
        guard let client else { throw CameraError("Not connected.") }
        if let urls = image.urls {
            let data = try await client.fetch(urls.preview ?? urls.thumbnail ?? urls.original)
            guard let picture = UIImage(data: data) else { throw CameraError("Couldn't decode the preview.") }
            return picture
        }
        if image.fileExtension == "JPG",
           let data = try? await client.get("get_resizeimg", [("DIR", image.path), ("size", "1600")]),
           let resized = UIImage(data: data) {
            return resized
        }
        if let data = try? await client.get("get_thumbnail", [("DIR", image.path)]), let thumb = UIImage(data: data) {
            return thumb
        }
        // Files the camera doesn't index (another camera's) have no preview: fetch the file itself.
        guard ["JPG", "JPEG"].contains(image.fileExtension) else {
            throw CameraError("The camera has no preview for this \(image.fileExtension) file. Save it to Photos to view it.")
        }
        let data = try await client.download(path: image.path)
        guard let full = UIImage(data: data) else { throw CameraError("Couldn't decode the photo.") }
        return full.preparingThumbnail(of: CGSize(width: 2000, height: 2000)) ?? full
    }

    func saveOriginalToPhotos(_ image: CameraImage) async throws {
        guard let client else { throw CameraError("Not connected.") }
        let data: Data
        if let urls = image.urls {
            data = try await client.fetch(urls.original, timeout: 300)
        } else {
            data = try await client.download(path: image.path)
        }
        let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard access == .authorized || access == .limited else {
            throw CameraError("Photos access is off. Turn it on in Settings ▸ PEN-F Remote ▸ Photos.")
        }
        let type: PHAssetResourceType = image.isVideo ? .video : .photo
        let filename = image.name
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = filename
            request.addResource(with: type, data: data, options: options)
        }
    }

    // MARK: - Log & errors

    private func appendLog(_ entry: LogEntry) {
        log.append(entry)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    func clearLog() { log.removeAll() }

    private func report(_ error: Error) {
        lastError = Self.describe(error, host: host)
    }

    /// The camera Wi-Fi name to mention in connection errors (set per brand on connect).
    static var ssidHint = "PEN-F-P-…"

    static func describe(_ error: Error, host: String) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }

        // iOS reports a denied Local Network permission inside the error's network-path details.
        let details = "\(urlError) \((urlError as NSError).userInfo)"
        if details.localizedCaseInsensitiveContains("local network prohibited") {
            return "iOS is blocking Local Network access for PEN-F Remote. Turn it on in Settings ▸ Privacy & Security ▸ Local Network, then tap Connect again."
        }

        let reason: String
        switch urlError.code {
        case .timedOut: reason = "No reply from \(host) (timed out)."
        case .cannotConnectToHost: reason = "\(host) refused the connection."
        case .notConnectedToInternet, .dataNotAllowed: reason = "iOS says there is no network route to \(host)."
        case .networkConnectionLost: reason = "The connection to \(host) dropped."
        case .cannotFindHost: reason = "Can't find \(host)."
        default: reason = urlError.localizedDescription
        }

        let network: String
        if let wifi = NetworkInfo.wifiAddress() {
            network = "This iPhone is on Wi-Fi (\(wifi)), but probably not the camera's network: home routers often use 192.168.0.x too. Open Settings ▸ Wi-Fi and check it says \(ssidHint); iOS likes to switch back to a network with internet. Also check Local Network is on for PEN-F Remote in Settings ▸ Privacy & Security."
        } else {
            network = "This iPhone isn't on Wi-Fi. Join \(ssidHint) in Settings ▸ Wi-Fi."
        }
        return "\(reason) \(network) [code \(urlError.code.rawValue)]"
    }
}

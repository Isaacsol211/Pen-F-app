import UIKit

// Sony Camera Remote API (JSON-RPC over HTTP), as used by PlayMemories Mobile with the
// "Smart Remote Control" / "Smart Remote Embedded" app on the camera. Bodies up to about 2019
// (a5000–a6500, a7 II/III family, RX100 III–VI, RX10 II–IV, a9…) have it; Sony dropped it from
// bodies released after mid-2020 (a7 IV, a7S III, ZV-E10, a6700…), which this app can't control.
//
//   Camera at 192.168.122.1; API at http://192.168.122.1:8080/sony/camera (some bodies :10000).
//   POST {"method": "...", "params": [...], "id": n, "version": "1.0"} → {"result": [...]} or
//   {"error": [code, "message"]}. getAvailableApiList says what the camera allows right now.
//   Live view: startLiveview → URL of an endless HTTP stream of packets:
//     8-byte common header (FF, type 01 = JPEG, sequence, timestamp) +
//     128-byte payload header (24 35 68 79, 3-byte JPEG size, 1-byte padding) + JPEG + padding.
//   Settings: getAvailableX → [current, [choices]], setX [value].
//   Card: setCameraFunction "Contents Transfer", then avContent getContentList.

struct SonyError: LocalizedError {
    let code: Int
    let message: String
    let method: String

    var errorDescription: String? {
        switch code {
        case 40401: "The camera isn't ready (\(method)). Try again in a moment."
        case 40403: "The camera is still taking the picture."
        case 12, 403: "The camera doesn't allow \(method) right now."
        case 3: "The camera didn't accept that value (\(method))."
        default: "The camera answered error \(code) \(message) to \(method)."
        }
    }
}

@MainActor
final class SonyDriver: CameraDriver {
    unowned let camera: CameraModel
    let client: CameraHTTPClient
    private var apis: Set<String> = []
    private var rpcID = 0
    private var stream: HTTPStreamReader?
    /// Times live view was reopened since the last frame arrived.
    private var liveRestarts = 0
    private var eventTask: Task<Void, Never>?
    /// UI value → Sony value, per property.
    private var valueMap: [String: [String: String]] = [:]

    init(camera: CameraModel) {
        self.camera = camera
        client = camera.makeHTTPClient(userAgent: "Shutterlink")
    }

    var liveViewFormat: LiveViewFormat { .pushed }

    var capabilities: CameraCapabilities {
        CameraCapabilities(tapToFocus: apis.contains("setTouchAFPosition") || apis.isEmpty,
                           movie: apis.contains("startMovieRec") || apis.contains("setShootMode"), videoSwitch: true,
                           lastShotReview: true, cardBrowser: apis.contains("setCameraFunction"))
    }

    // MARK: - JSON-RPC

    /// Calls `method` and returns its result array.
    @discardableResult
    func call(_ method: String, _ params: [Any] = [], service: String = "camera", version: String = "1.0",
              timeout: TimeInterval = 10, log: Bool = true) async throws -> [Any] {
        rpcID += 1
        let body: [String: Any] = ["method": method, "params": params, "id": rpcID, "version": version]
        let reply = try await client.requestJSON("POST", "/sony/\(service)", json: body, timeout: timeout, log: log)
        if let error = reply["error"] as? [Any] {
            throw SonyError(code: error.first as? Int ?? -1, message: error.dropFirst().first as? String ?? "", method: method)
        }
        return reply["result"] as? [Any] ?? reply["results"] as? [Any] ?? []
    }

    // MARK: - Connect

    /// Bodies from about 2020 on, which moved to Creators' App and may not offer the older remote API.
    static func isNewerBody(_ model: String) -> Bool {
        let m = model.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        return ["ILCE1", "ILCE9M3", "ILCE7M4", "ILCE7RM5", "ILCE7SM3", "ILCE7CM2", "ILCE7CR", "ILCE6700",
                "ZVE1", "ZVE10", "ZV1M2", "ILME"].contains { m.hasPrefix($0) }
    }

    func connect() async throws {
        try await camera.retryingConnect { try await call("getVersions", timeout: 5) }
        camera.status = "Reading camera info…"
        camera.cameraName = await deviceName() ?? "Sony"
        if Self.isNewerBody(camera.cameraName ?? "") {
            camera.cameraNote = "Shutterlink uses Sony's older remote control (Smart Remote / Ctrl w/ Smartphone). "
                + "Newer bodies like this one use Creators' App instead and may allow only some of it, or none. "
                + "Try it before buying Pro, and tell us what works."
        }
        if let info = try? await call("getApplicationInfo") {
            camera.rawCommandList = "Application: \(info.map { "\($0)" }.joined(separator: " "))\n"
        }
        try await refreshAPIs()
        // Bodies with a separate remote-shooting mode list startRecMode until it has run.
        if apis.contains("startRecMode") {
            camera.status = "Starting remote shooting…"
            _ = try? await call("startRecMode", timeout: 15)
            for _ in 0..<10 where !apis.contains("actTakePicture") {
                try? await Task.sleep(for: .milliseconds(500))
                try? await refreshAPIs()
            }
        }
        camera.rawCommandList += apis.sorted().joined(separator: "\n")
        startEvents()
    }

    private func refreshAPIs() async throws {
        if let list = try await call("getAvailableApiList").first as? [String] { apis = Set(list) }
    }

    /// The model name from the camera's UPnP description (e.g. "ILCE-6000"), if it serves one.
    private func deviceName() async -> String? {
        let ip = camera.connectionHost.split(separator: ":").first.map(String.init) ?? camera.connectionHost
        guard let data = try? await client.fetch(URL(string: "http://\(ip):64321/DmsRmtDesc.xml"), timeout: 3, log: false),
              let root = MiniXML.parse(data) else { return nil }
        return root.firstDescendant(named: ["modelName"])?.trimmedText
            ?? root.firstDescendant(named: ["friendlyName"])?.trimmedText
    }

    func disconnect() async {
        if apis.contains("stopRecMode") { _ = try? await call("stopRecMode", timeout: 3) }
    }

    func teardown() {
        stream?.stop()
        stream = nil
        eventTask?.cancel()
        eventTask = nil
    }

    /// Polls getEvent every 2 s for battery, card space and settings changed on the camera.
    private func startEvents() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, self.camera.phase == .connected else { continue }
                do {
                    let result = try await self.call("getEvent", [false], timeout: 5, log: false)
                    failures = 0
                    self.applyEvent(result)
                } catch {
                    failures += 1
                    if failures == 3 {
                        self.camera.lastError = "Lost contact with the camera. Check that this \(Platform.device) is still on the camera's Wi-Fi."
                    }
                }
            }
        }
    }

    /// getEvent's result is a fixed-position array of objects (or arrays of objects) with a "type".
    private func applyEvent(_ result: [Any]) {
        var objects: [[String: Any]] = []
        for item in result {
            if let object = item as? [String: Any] { objects.append(object) }
            if let array = item as? [[String: Any]] { objects += array }
        }
        var info = camera.liveInfo
        var settingsChanged = false
        for object in objects {
            switch object["type"] as? String {
            case "availableApiList":
                if let list = object["names"] as? [String] { apis = Set(list) }
            case "storageInformation":
                if let n = object["numberOfRecordableImages"] as? Int, n >= 0 { info.shotsRemaining = n }
            case "batteryInfo":
                if let battery = (object["batteryInfo"] as? [[String: Any]])?.first,
                   let numer = battery["levelNumer"] as? Int, let denom = battery["levelDenom"] as? Int, denom > 0 {
                    info.battery = numer * 100 / denom
                }
            case "fNumber", "shutterSpeed", "isoSpeedRate", "exposureCompensation", "whiteBalance", "exposureMode":
                settingsChanged = true
            default:
                break
            }
        }
        if info != camera.liveInfo { camera.liveInfo = info }
        if settingsChanged, !camera.isShooting { Task { await refreshProperties() } }
    }

    // MARK: - Live view

    func enterRecMode() async {
        camera.isSwitchingMode = true
        defer { camera.isSwitchingMode = false }
        if camera.mode == .play, apis.contains("setCameraFunction") {
            _ = try? await call("setCameraFunction", ["Remote Shooting"])
            try? await Task.sleep(for: .seconds(1))
            try? await refreshAPIs()
        }
        camera.mode = .rec
        await camera.refreshProperties()
        await camera.startLiveView()
    }

    func startLiveView() async {
        do {
            let result = try await call("startLiveview")
            guard let address = result.first as? String, let url = URL(string: address) else {
                throw CameraError("The camera gave no live-view address.")
            }
            let reader = HTTPStreamReader(url: url, parse: Self.parseLiveViewPackets)
            reader.onFrame = { [weak self] jpeg in
                Task { @MainActor in
                    self?.liveRestarts = 0
                    self?.camera.submitLiveViewJPEG(jpeg)
                }
            }
            reader.onEnd = { [weak self] error in
                Task { @MainActor in
                    guard let self, self.camera.liveViewRunning, self.stream === reader else { return }
                    debugLog("Sony live view ended: \(error?.localizedDescription ?? "closed")")
                    // A long exposure stalls the stream until the picture is done. Open it again once
                    // the camera is free, a few times at most before leaving it to Restart live view.
                    self.liveRestarts += 1
                    guard self.liveRestarts <= 3 else {
                        self.camera.liveViewRunning = false
                        return
                    }
                    let deadline = Date().addingTimeInterval(120)
                    while self.camera.isShooting, Date() < deadline { try? await Task.sleep(for: .milliseconds(500)) }
                    try? await Task.sleep(for: .seconds(1))
                    guard self.stream === reader, self.camera.phase == .connected, self.camera.mode == .rec else {
                        self.camera.liveViewRunning = false
                        return
                    }
                    await self.startLiveView()
                }
            }
            stream?.stop()
            stream = reader
            reader.start()
        } catch {
            camera.liveViewRunning = false
            camera.report(error)
        }
    }

    func stopLiveView() async {
        stream?.stop()
        stream = nil
        _ = try? await call("stopLiveview", timeout: 3)
    }

    /// Pulls complete JPEG packets off the front of the stream buffer.
    nonisolated static func parseLiveViewPackets(_ buffer: inout Data) -> [Data] {
        var frames: [Data] = []
        while buffer.count >= 136 {
            let b = buffer.startIndex
            // Resync on the common header's start byte and the payload header's start code.
            guard buffer[b] == 0xFF, buffer[b + 8] == 0x24, buffer[b + 9] == 0x35,
                  buffer[b + 10] == 0x68, buffer[b + 11] == 0x79 else {
                if let next = buffer[(b + 1)...].firstIndex(of: 0xFF) {
                    buffer.removeSubrange(b..<next)
                    continue
                }
                buffer.removeAll()
                break
            }
            let type = buffer[b + 1]
            let size = Int(buffer[b + 12]) << 16 | Int(buffer[b + 13]) << 8 | Int(buffer[b + 14])
            let padding = Int(buffer[b + 15])
            let total = 136 + size + padding
            guard buffer.count >= total else { break }
            if type == 0x01, size > 0 { frames.append(Data(buffer[(b + 136)..<(b + 136 + size)])) }
            buffer.removeSubrange(b..<(b + total))
        }
        return frames
    }

    // MARK: - Settings

    func refreshProperties() async {
        var result: [String: CameraProperty] = [:]
        valueMap = [:]

        // [current, [choices]] for the simple string settings.
        func available(_ method: String) async -> (String, [String])? {
            guard apis.isEmpty || apis.contains(method),
                  let reply = try? await call(method, log: false), let current = reply.first as? String else { return nil }
            return (current, reply.dropFirst().first as? [String] ?? [current])
        }
        func add(_ name: String, sony current: String, choices: [String], settable: Bool, ui: (String) -> String?) {
            var map: [String: String] = [:]
            var options: [String] = []
            for choice in choices {
                guard let label = ui(choice), map[label] == nil else { continue }
                map[label] = choice
                options.append(label)
            }
            valueMap[name] = map
            let value = ui(current) ?? current
            result[name] = CameraProperty(name: name, settable: settable && options.count > 1, value: value,
                                          options: options.contains(value) ? options : options + [value])
        }

        if let (current, choices) = await available("getAvailableExposureMode") {
            add("takemode", sony: current, choices: choices, settable: apis.contains("setExposureMode"), ui: Self.modeLabel)
        } else if let mode = try? await call("getExposureMode", log: false).first as? String {
            add("takemode", sony: mode, choices: [mode], settable: false, ui: Self.modeLabel)
        }
        if let (current, choices) = await available("getAvailableFNumber"), current != "--" {
            add("focalvalue", sony: current, choices: choices, settable: apis.contains("setFNumber")) { $0 == "--" ? nil : $0 }
        }
        if let (current, choices) = await available("getAvailableShutterSpeed"), current != "--" {
            add("shutspeedvalue", sony: current, choices: choices, settable: apis.contains("setShutterSpeed"),
                ui: Self.shutterLabel)
        }
        if let (current, choices) = await available("getAvailableIsoSpeedRate") {
            add("isospeedvalue", sony: current, choices: choices, settable: apis.contains("setIsoSpeedRate")) {
                $0.uppercased() == "AUTO" ? "auto" : (Int($0) != nil ? $0 : nil)
            }
        }
        if apis.isEmpty || apis.contains("getAvailableExposureCompensation"),
           let reply = try? await call("getAvailableExposureCompensation", log: false), reply.count >= 4,
           let current = reply[0] as? Int, let maxIndex = reply[1] as? Int, let minIndex = reply[2] as? Int,
           let step = reply[3] as? Int, maxIndex > minIndex {
            // Index step: 1 = ⅓ EV, 2 = ½ EV.
            let label = { (i: Int) in step == 2 ? (i == 0 ? "0.0" : String(format: "%+.1f", Double(i) / 2))
                                                : ExposureText.ev(thirds: i) }
            var map: [String: String] = [:]
            let options = (minIndex...maxIndex).map { i -> String in
                let text = label(i)
                map[text] = String(i)
                return text
            }
            valueMap["expcomp"] = map
            result["expcomp"] = CameraProperty(name: "expcomp", settable: apis.contains("setExposureCompensation"),
                                               value: label(current), options: options)
        }
        if apis.isEmpty || apis.contains("getAvailableWhiteBalance"),
           let reply = try? await call("getAvailableWhiteBalance", log: false),
           let current = (reply.first as? [String: Any])?["whiteBalanceMode"] as? String {
            let modes = (reply.dropFirst().first as? [[String: Any]] ?? []).compactMap { $0["whiteBalanceMode"] as? String }
            add("wbvalue", sony: current, choices: modes.isEmpty ? [current] : modes,
                settable: apis.contains("setWhiteBalance"), ui: Self.whiteBalanceCode)
        }
        camera.properties = result
    }

    func setProperty(_ name: String, to value: String, reportErrors: Bool) async -> Bool {
        let sony = valueMap[name]?[value] ?? value
        let request: (String, [Any])?
        switch name {
        case "takemode": request = ("setExposureMode", [sony])
        case "focalvalue": request = ("setFNumber", [sony])
        case "shutspeedvalue": request = ("setShutterSpeed", [sony])
        case "isospeedvalue": request = ("setIsoSpeedRate", [sony])
        case "expcomp": request = ("setExposureCompensation", [Int(sony) ?? 0])
        case "wbvalue": request = ("setWhiteBalance", [sony, false, -1])
        default: request = nil
        }
        guard let request else {
            if reportErrors { camera.lastError = "This setting can't be changed on a Sony camera from the app." }
            return false
        }
        let ok = await camera.optimisticallySet(name, to: value, reportErrors: reportErrors) {
            try await call(request.0, request.1)
        }
        await refreshProperties()
        return ok
    }

    static func modeLabel(_ sony: String) -> String? {
        switch sony {
        case "Program Auto": "P"
        case "Aperture": "A"
        case "Shutter": "S"
        case "Manual": "M"
        case "Intelligent Auto", "Superior Auto": "iAuto"
        default: sony
        }
    }

    /// "1/125" → "125", "2.5\"" → "2.5\"", "BULB" → "bulb".
    static func shutterLabel(_ sony: String) -> String? {
        if sony.uppercased() == "BULB" { return "bulb" }
        if sony.hasPrefix("1/") { return String(sony.dropFirst(2)) }
        if sony.hasSuffix("\"") { return sony }
        return nil
    }

    static func whiteBalanceCode(_ sony: String) -> String? {
        let lower = sony.lowercased()
        if lower.hasPrefix("auto") { return "0" }
        if lower.hasPrefix("fluorescent") { return lower.contains("warm") || lower.contains("(-1)") ? "35" : sony }
        if lower.hasPrefix("custom") { return lower.hasSuffix("1") || lower == "custom" ? "256" : sony }
        if lower.hasPrefix("color temperature") { return "512" }
        return ExposureText.whiteBalanceCodes[lower] ?? sony
    }

    // MARK: - Focus & shooting

    func focus(at normalized: CGPoint) async {
        guard apis.contains("setTouchAFPosition") else { return }
        do {
            let result = try await call("setTouchAFPosition", [Double(normalized.x * 100), Double(normalized.y * 100)])
            // [0, {"AFResult": true, "AFType": "Touch"}]
            let focused = result.compactMap { $0 as? [String: Any] }.first?["AFResult"] as? Bool ?? false
            camera.showAFResult(focused, at: normalized)
        } catch {
            camera.report(error)
        }
    }

    func releaseFocus() async {
        if apis.contains("cancelTouchAFPosition") { _ = try? await call("cancelTouchAFPosition", timeout: 3) }
    }

    func shutterPressed() async {
        let seconds = camera.beginShot()
        defer { camera.endShot() }
        do {
            var result: [Any]
            do {
                result = try await call("actTakePicture", timeout: max(30, seconds * 2 + 20))
            } catch let error as SonyError where error.code == 40403 {
                result = try await call("awaitTakePicture", timeout: max(30, seconds * 2 + 20))
            }
            camera.shotCounter += 1
            if let urls = result.first as? [String], let address = urls.first, let url = URL(string: address) {
                let client = client
                Task { [weak self] in
                    guard let data = try? await client.fetch(url, timeout: 10, log: false),
                          let image = UIImage(data: data) else { return }
                    self?.camera.lastShot = image.preparingForDisplay() ?? image
                }
                // Auto-save: the postview, which is the full JPEG when the camera's postview size is Original.
                camera.autoSave(name: url.lastPathComponent) {
                    try await client.fetch(url, timeout: 60, log: false)
                }
            }
        } catch {
            camera.report(error)
        }
    }

    func toggleOpenExposure() async {
        if camera.isShooting {
            _ = try? await call("stopBulbShooting")
            camera.isShooting = false
            camera.exposureStartedAt = nil
            camera.shotCounter += 1
            return
        }
        do {
            camera.isShooting = true
            camera.exposureStartedAt = Date()
            camera.exposureDuration = nil
            try await call("startBulbShooting")
        } catch {
            camera.isShooting = false
            camera.exposureStartedAt = nil
            camera.report(error)
        }
    }

    func toggleMovie() async {
        if camera.isRecordingMovie {
            _ = try? await call("stopMovieRec")
            camera.setRecordingMovie(false)
            if apis.contains("setShootMode") || apis.contains("getShootMode") {
                _ = try? await call("setShootMode", ["still"])
            }
            return
        }
        do {
            _ = try? await call("setShootMode", ["movie"])
            try await call("startMovieRec", timeout: 15)
            camera.setRecordingMovie(true)
        } catch {
            _ = try? await call("setShootMode", ["still"])
            camera.report(error)
        }
    }

    // MARK: - Card (avContent, in Contents Transfer mode)

    func openGallery() async {
        guard apis.contains("setCameraFunction") else {
            camera.galleryError = "This camera can't show its card over Wi-Fi in remote mode. Use Sony's own app, or the camera's Send to Smartphone."
            return
        }
        do {
            try await call("setCameraFunction", ["Contents Transfer"])
            camera.mode = .play
            // The switch takes a moment; avContent answers "not ready" until it's done.
            var sources: [Any] = []
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(700))
                if let reply = try? await call("getSourceList", [["scheme": "storage"]], service: "avContent") {
                    sources = reply
                    break
                }
            }
            let source = ((sources.first as? [[String: Any]])?.first?["source"] as? String) ?? "storage:memoryCard1"
            var found: [CameraImage] = []
            var start = 0
            while true {
                let page = try await call("getContentList", [["uri": source, "stIdx": start, "cnt": 100,
                                                               "view": "flat", "sort": "descending"]],
                                          service: "avContent", version: "1.3", timeout: 20)
                let items = page.first as? [[String: Any]] ?? []
                for item in items { found += Self.images(from: item) }
                start += items.count
                if items.count < 100 { break }
            }
            camera.images = found.sorted { ($0.date, $0.name) > ($1.date, $1.name) }
            camera.cardFolders = [CardFolder(path: "SONY", name: camera.cameraName ?? "Sony", count: camera.images.count,
                                             isForeign: false)]
        } catch {
            camera.galleryError = CameraModel.describe(error, host: camera.connectionHost)
        }
    }

    static func images(from item: [String: Any]) -> [CameraImage] {
        guard let content = item["content"] as? [String: Any] else { return [] }
        let originals = content["original"] as? [[String: Any]] ?? []
        let thumb = (content["thumbnailUrl"] as? String).flatMap(URL.init(string:))
        let large = ((content["largeUrl"] as? String) ?? (content["smallUrl"] as? String)).flatMap(URL.init(string:))
        let date = (item["createdTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? .distantPast
        return originals.compactMap { original in
            guard let name = original["fileName"] as? String,
                  let url = (original["url"] as? String).flatMap(URL.init(string:)) else { return nil }
            return CameraImage(directory: "SONY", name: name, size: 0, attributes: 0, date: date,
                               urls: MediaURLs(thumbnail: thumb, preview: large ?? thumb, original: url))
        }
    }

    func thumbnail(for image: CameraImage) async -> UIImage? { await client.thumbnail(for: image) }
    func preview(for image: CameraImage) async throws -> UIImage { try await client.preview(for: image) }
    func downloadOriginal(_ image: CameraImage) async throws -> Data { try await client.fetch(image.urls?.original, timeout: 300) }
}

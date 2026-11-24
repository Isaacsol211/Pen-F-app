import Foundation
import UIKit

// Canon Camera Control API (CCAPI): REST + JSON over HTTP on port 8080, built into recent EOS R,
// EOS M, DSLR and PowerShot bodies. Canon keeps it switched off until the camera has been
// activated once with Canon's CCAPI activation tool (free, needs a Canon developer account).
// After that the camera offers a CCAPI Wi-Fi connection the phone can join.
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
//   Card: GET …/contents → storages → folders → files (?kind=list&page=n), each file ?kind=
//         thumbnail | display | original.

@MainActor
final class CanonDriver: CameraDriver {
    unowned let camera: CameraModel
    let client: CameraHTTPClient
    /// Feature path ("shooting/settings/tv") → full path in the oldest version that has it (ver100
    /// payloads are the ones this driver speaks; ver110 changed some, e.g. recbutton).
    private var api: [String: String] = [:]
    private var methods: [String: Set<String>] = [:]
    private var liveTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    /// UI value → Canon value, per property.
    private var valueMap: [String: [String: String]] = [:]

    init(camera: CameraModel) {
        self.camera = camera
        client = camera.makeHTTPClient(userAgent: "Shutterlink", allowedStatus: 200...204)
    }

    var liveViewFormat: LiveViewFormat { .pushed }

    var capabilities: CameraCapabilities {
        CameraCapabilities(liveViewSizes: [], tapToFocus: has("shooting/liveview/afframeposition"),
                           openEndedExposure: has("shooting/control/shutterbutton/manual"),
                           movie: has("shooting/control/recbutton"), videoSwitch: true,
                           lastShotReview: has("event/polling"), clockSync: false, highResShot: false,
                           cardBrowser: has("contents"), powerOff: false,
                           focusDrive: has("shooting/control/drivefocus"))
    }

    /// `POST shooting/control/drivefocus {"value": "near1…3" | "far1…3"}`, in live view with the lens on AF.
    /// CCAPI doesn't say when the lens reaches infinity, so a stack runs to its frame count.
    func driveFocus(farther: Bool, step: FocusStepSize) async throws -> FocusDriveResult {
        let value = (farther ? "far" : "near") + "\(step.rawValue)"
        _ = try await client.request("POST", path("shooting/control/drivefocus"), json: ["value": value], timeout: 8)
        try? await Task.sleep(for: .milliseconds(200))
        return .moved
    }

    private func has(_ feature: String, _ method: String? = nil) -> Bool {
        guard api[feature] != nil else { return false }
        guard let method else { return true }
        return methods[feature]?.contains(method) ?? false
    }

    private func path(_ feature: String) -> String {
        api[feature] ?? "/ccapi/ver100/" + feature
    }

    // MARK: - Connect

    func connect() async throws {
        var root: [String: Any] = [:]
        var failure: Error?
        for attempt in 1...3 {
            do {
                root = try await client.requestJSON("GET", "/ccapi", timeout: 5)
                failure = nil
                break
            } catch {
                failure = error
                guard attempt < 3, error is URLError else { break }
                camera.status = "No answer yet, retrying (\(attempt + 1)/3)…"
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
        if let failure { throw failure }
        parseAPIList(root)
        guard !api.isEmpty else {
            throw CameraError("The camera answered but lists no CCAPI functions. Check that CCAPI is activated on it.")
        }
        camera.rawCommandList = api.keys.sorted().map { "\($0)  \(methods[$0]?.sorted().joined(separator: ",") ?? "")" }
            .joined(separator: "\n")

        camera.status = "Reading camera info…"
        if let info = try? await client.requestJSON("GET", path("deviceinformation")) {
            camera.cameraName = (info["productname"] as? String).map { $0.replacingOccurrences(of: "Canon ", with: "") }
            camera.rawDescList = "\(info)"
        }
        if camera.cameraName == nil { camera.cameraName = "Canon" }
        await readBattery()
        // Start from a clean slate so the first poll only reports what changes from now on.
        if has("event/polling") { _ = try? await client.request("GET", path("event/polling") + "?continue=off", log: false) }
        startEvents()
    }

    /// {"ver100": [{"path": "/ccapi/ver100/shooting/settings/tv", "get": true, "put": true, …}], "ver110": …}
    private func parseAPIList(_ root: [String: Any]) {
        api = [:]
        methods = [:]
        for version in root.keys.sorted() {   // ver100 < ver110 < ver120: the first one wins
            for entry in root[version] as? [[String: Any]] ?? [] {
                guard let full = entry["path"] as? String, let range = full.range(of: "/\(version)/") else { continue }
                let feature = String(full[range.upperBound...])
                guard api[feature] == nil else { continue }
                api[feature] = full
                methods[feature] = Set(["get", "put", "post", "delete"].filter { entry[$0] as? Bool == true })
            }
        }
    }

    private func readBattery() async {
        let reply: [String: Any]?
        if has("devicestatus/batterylist"), let list = try? await client.requestJSON("GET", path("devicestatus/batterylist"), log: false),
           let first = (list["batterylist"] as? [[String: Any]])?.first {
            reply = first
        } else {
            reply = try? await client.requestJSON("GET", path("devicestatus/battery"), log: false)
        }
        if let level = reply?["level"] as? String, let percent = Self.batteryPercent(level) {
            camera.liveInfo.battery = percent
        }
    }

    static func batteryPercent(_ level: String) -> Int? {
        if let n = Int(level) { return n }
        return ["full": 100, "high": 75, "half": 50, "quarter": 25, "low": 10, "empty": 0][level.lowercased()]
    }

    func teardown() {
        liveTask?.cancel()
        liveTask = nil
        eventTask?.cancel()
        eventTask = nil
    }

    /// Polls for changes every 2 s: settings turned on the camera, battery, new pictures.
    private func startEvents() {
        guard has("event/polling") else { return }
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, self.camera.phase == .connected, !self.camera.isShooting else { continue }
                do {
                    let changes = try await self.client.requestJSON("GET", self.path("event/polling") + "?continue=off",
                                                                     timeout: 5, log: false)
                    failures = 0
                    await self.apply(changes)
                } catch {
                    failures += 1
                    if failures == 3 {
                        self.camera.lastError = "Lost contact with the camera. Check that this \(Platform.device) is still on the camera's Wi-Fi."
                    }
                }
            }
        }
    }

    private func apply(_ changes: [String: Any]) async {
        if let battery = changes["battery"] as? [String: Any], let level = battery["level"] as? String,
           let percent = Self.batteryPercent(level) {
            camera.liveInfo.battery = percent
        }
        if let added = changes["addedcontents"] as? [String], let newest = added.last {
            await showLastShot(newest)
        }
        let settingKeys = ["tv", "av", "iso", "exposure", "wb", "shootingmode", "shootingmodedial"]
        if settingKeys.contains(where: { changes[$0] != nil }) { await refreshProperties() }
    }

    // MARK: - Live view

    func enterRecMode() async {
        camera.isSwitchingMode = true
        defer { camera.isSwitchingMode = false }
        camera.mode = .rec
        await camera.refreshProperties()
        await camera.startLiveView()
    }

    func startLiveView() async {
        do {
            _ = try await client.request("POST", path("shooting/liveview"),
                                         json: ["liveviewsize": "small", "cameradisplay": "on"])
        } catch {
            camera.liveViewRunning = false
            camera.report(error)
            return
        }
        let client = client
        let flip = path("shooting/liveview/flip")
        liveTask?.cancel()
        liveTask = camera.pullLiveView(every: .milliseconds(20)) {
            // 503 while the camera is busy (e.g. writing a shot): skip a frame.
            do {
                return try await client.request("GET", flip, timeout: 5, log: false)
            } catch let error as CameraHTTPError where error.status == 503 {
                try? await Task.sleep(for: .milliseconds(200))
                return nil
            }
        }
    }

    func stopLiveView() async {
        liveTask?.cancel()
        liveTask = nil
        _ = try? await client.request("POST", path("shooting/liveview"),
                                      json: ["liveviewsize": "off", "cameradisplay": "on"], timeout: 3)
    }

    // MARK: - Settings

    private static let settings: [(ui: String, canon: String)] = [
        ("takemode", "shootingmodedial"), ("takemode", "shootingmode"), ("focalvalue", "av"),
        ("shutspeedvalue", "tv"), ("isospeedvalue", "iso"), ("expcomp", "exposure"), ("wbvalue", "wb"),
    ]

    func refreshProperties() async {
        var all: [String: Any] = [:]
        if has("shooting/settings"), let reply = try? await client.requestJSON("GET", path("shooting/settings"), log: false) {
            all = reply
        }
        var result: [String: CameraProperty] = [:]
        valueMap = [:]
        for (ui, canon) in Self.settings where result[ui] == nil {
            var setting = all[canon] as? [String: Any]
            if setting == nil, all.isEmpty, has("shooting/settings/\(canon)") {
                setting = try? await client.requestJSON("GET", path("shooting/settings/\(canon)"), log: false)
            }
            guard let setting, let current = setting["value"] as? String, !current.isEmpty else { continue }
            let ability = setting["ability"] as? [String] ?? []
            let label = { (value: String) in Self.uiValue(ui, value) }
            var map: [String: String] = [:]
            var options: [String] = []
            for value in ability {
                let text = label(value)
                if map[text] == nil { map[text] = value; options.append(text) }
            }
            valueMap[ui] = map
            let value = label(current)
            if !options.contains(value) { options.append(value) }
            let settable = !ability.isEmpty && (methods["shooting/settings/\(canon)"]?.contains("put") ?? true)
                && canon != "shootingmodedial"
            result[ui] = CameraProperty(name: ui, settable: settable, value: value, options: options)
        }
        camera.properties = result
    }

    /// Canon spelling → the app's: "f5.6" → "5.6", "1/125" → "125", "0\"5" → "0.5\"", "+1_1/3" → "+1.3",
    /// "av" → "A", "daylight" → "18".
    static func uiValue(_ name: String, _ canon: String) -> String {
        switch name {
        case "focalvalue":
            return canon.hasPrefix("f") ? String(canon.dropFirst()) : canon
        case "shutspeedvalue":
            if canon.lowercased() == "bulb" { return "bulb" }
            if canon.hasPrefix("1/") { return String(canon.dropFirst(2)) }
            if canon.contains("\"") {
                let parts = canon.split(separator: "\"", omittingEmptySubsequences: false)
                let whole = parts.first.map(String.init) ?? "0"
                let fraction = parts.count > 1 ? String(parts[1]) : ""
                return (fraction.isEmpty ? whole : "\(whole).\(fraction)") + "\""
            }
            return canon
        case "isospeedvalue":
            return canon.lowercased() == "auto" ? "auto" : canon
        case "expcomp":
            return ExposureText.ev(evValue(canon))
        case "wbvalue":
            let codes = ["auto": "0", "daylight": "18", "shade": "16", "cloudy": "17", "tungsten": "20",
                         "whitefluorescent": "35", "flash": "23", "custom": "256", "colortemp": "512",
                         "awbwhite": "awb_white", "awbambience": "awb_ambience"]
            return codes[canon.lowercased()] ?? canon
        case "takemode":
            let modes = ["m": "M", "av": "A", "tv": "S", "p": "P", "a+": "iAuto", "auto": "iAuto", "fv": "Fv",
                         "bulb": "B", "movie": "movie"]
            return modes[canon.lowercased()] ?? canon.uppercased()
        default:
            return canon
        }
    }

    /// "+1_1/3" → 1.333, "-0_2/3" → -0.667, "+2" → 2, "0" → 0.
    static func evValue(_ canon: String) -> Double {
        var text = canon.trimmingCharacters(in: .whitespaces)
        var sign = 1.0
        if text.hasPrefix("-") { sign = -1; text.removeFirst() } else if text.hasPrefix("+") { text.removeFirst() }
        let parts = text.split(separator: "_")
        var value = Double(parts.first ?? "0") ?? 0
        if parts.count > 1 {
            let fraction = parts[1].split(separator: "/").compactMap { Double($0) }
            if fraction.count == 2, fraction[1] != 0 { value += fraction[0] / fraction[1] }
        }
        return sign * value
    }

    func setProperty(_ name: String, to value: String, reportErrors: Bool) async -> Bool {
        guard let canonName = Self.settings.first(where: { $0.ui == name && api["shooting/settings/\($0.canon)"] != nil
                                                            && $0.canon != "shootingmodedial" })?.canon,
              let canonValue = valueMap[name]?[value] else {
            if reportErrors { camera.lastError = "This setting can't be changed on this Canon from the app." }
            return false
        }
        let previous = camera.properties[name]?.value
        camera.properties[name]?.value = value
        do {
            _ = try await client.request("PUT", path("shooting/settings/\(canonName)"), json: ["value": canonValue])
        } catch {
            if let previous { camera.properties[name]?.value = previous }
            if reportErrors { camera.report(error) }
            await refreshProperties()
            return false
        }
        await refreshProperties()
        return true
    }

    // MARK: - Focus & shooting

    func focus(at normalized: CGPoint) async {
        // The AF frame position is in live-view pixels.
        let p = camera.pixelPoint(normalized)
        do {
            _ = try await client.request("PUT", path("shooting/liveview/afframeposition"),
                                         json: ["positionx": Int(p.x), "positiony": Int(p.y)])
            if has("shooting/control/shutterbutton/manual") {
                _ = try await client.request("POST", path("shooting/control/shutterbutton/manual"),
                                             json: ["action": "half_press", "af": true], timeout: 10)
                _ = try? await client.request("POST", path("shooting/control/shutterbutton/manual"),
                                              json: ["action": "release", "af": true], timeout: 5)
            }
        } catch {
            camera.report(error)
        }
    }

    func shutterPressed() async {
        camera.isShooting = true
        let seconds = PropertyFormat.seconds(fromShutter: camera.properties["shutspeedvalue"]?.value ?? "") ?? 0
        if seconds >= 1 {
            camera.exposureStartedAt = Date()
            camera.exposureDuration = seconds
        }
        defer {
            camera.isShooting = false
            camera.exposureStartedAt = nil
            camera.exposureDuration = nil
        }
        do {
            _ = try await client.request("POST", path("shooting/control/shutterbutton"), json: ["af": true],
                                         timeout: max(30, seconds * 2 + 20))
            camera.shotCounter += 1
            // The new file shows up in the next event poll; ask now so the thumbnail comes quickly.
            if seconds >= 1 { try? await Task.sleep(for: .seconds(seconds)) }
            try? await Task.sleep(for: .milliseconds(600))
            if let changes = try? await client.requestJSON("GET", path("event/polling") + "?continue=off", log: false) {
                await apply(changes)
            }
        } catch {
            camera.report(error)
        }
    }

    /// Bulb: hold the shutter fully pressed until the second tap.
    func toggleOpenExposure() async {
        let manual = path("shooting/control/shutterbutton/manual")
        if camera.isShooting {
            _ = try? await client.request("POST", manual, json: ["action": "release", "af": false], urgent: true)
            camera.isShooting = false
            camera.exposureStartedAt = nil
            camera.shotCounter += 1
            return
        }
        camera.isShooting = true
        camera.exposureStartedAt = Date()
        camera.exposureDuration = nil
        do {
            _ = try await client.request("POST", manual, json: ["action": "full_press", "af": false])
        } catch {
            camera.isShooting = false
            camera.exposureStartedAt = nil
            camera.report(error)
        }
    }

    func toggleMovie() async {
        if camera.isRecordingMovie {
            _ = try? await client.request("POST", path("shooting/control/recbutton"), json: ["action": "stop"])
            camera.isRecordingMovie = false
            camera.movieStartedAt = nil
            camera.shotCounter += 1
            if has("shooting/control/moviemode") {
                _ = try? await client.request("POST", path("shooting/control/moviemode"), json: ["action": "off"])
            }
            return
        }
        do {
            if has("shooting/control/moviemode") {
                _ = try await client.request("POST", path("shooting/control/moviemode"), json: ["action": "on"])
            }
            _ = try await client.request("POST", path("shooting/control/recbutton"), json: ["action": "start"])
            camera.isRecordingMovie = true
            camera.movieStartedAt = Date()
        } catch {
            camera.report(error)
        }
    }

    private func showLastShot(_ file: String) async {
        // kind=display is a screen-sized JPEG, also for RAW and HEIF files.
        guard let data = try? await client.request("GET", file + "?kind=display", timeout: 10, log: false),
              let image = UIImage(data: data) else { return }
        camera.lastShot = image.preparingForDisplay() ?? image
    }

    // MARK: - Card

    func openGallery() async {
        do {
            camera.mode = .play
            var found: [CameraImage] = []
            var folders: [CardFolder] = []
            let storages = try await client.requestJSON("GET", path("contents"))["path"] as? [String] ?? []
            for storage in storages {
                let dirs = try await client.requestJSON("GET", storage)["path"] as? [String] ?? []
                for dir in dirs {
                    let count = try await client.requestJSON("GET", dir + "?kind=number")
                    let pages = count["pagenumber"] as? Int ?? 1
                    var files: [CameraImage] = []
                    for page in 1...max(pages, 1) {
                        let list = try await client.requestJSON("GET", dir + "?page=\(page)")
                        for file in list["path"] as? [String] ?? [] {
                            files.append(CameraImage(directory: dir, name: (file as NSString).lastPathComponent,
                                                     size: 0, attributes: 0, date: .distantPast))
                        }
                    }
                    found += files
                    let name = (dir as NSString).lastPathComponent
                    folders.append(CardFolder(path: dir, name: name, count: files.count, isForeign: !name.uppercased().hasSuffix("CANON")))
                }
            }
            camera.cardFolders = folders.sorted { $0.name > $1.name }
            // No dates without asking for each file's info; newest folder and highest number first.
            camera.images = found.sorted { ($0.directory, $0.name) > ($1.directory, $1.name) }
        } catch {
            camera.galleryError = CameraModel.describe(error, host: camera.connectionHost)
        }
    }

    func thumbnail(for image: CameraImage) async -> UIImage? {
        guard let data = try? await client.request("GET", image.path + "?kind=thumbnail", log: false) else { return nil }
        return UIImage(data: data)
    }

    func preview(for image: CameraImage) async throws -> UIImage {
        let data = try await client.request("GET", image.path + "?kind=display", timeout: 30)
        guard let picture = UIImage(data: data) else { throw CameraError("Couldn't decode the preview.") }
        return picture
    }

    func downloadOriginal(_ image: CameraImage) async throws -> Data {
        try await client.request("GET", image.path, timeout: 300)
    }
}

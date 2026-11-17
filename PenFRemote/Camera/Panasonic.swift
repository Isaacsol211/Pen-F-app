import Foundation
import UIKit

// Panasonic LUMIX (GH5, G9, GH4, S-series…) over the camera's own Wi-Fi, as used by Image App /
// LUMIX Sync. Summary of the protocol (from open-source implementations; GH5 details are partly
// inferred from the GH5S and other bodies):
//
//   Camera at 192.168.54.1. Commands are GET /cam.cgi?mode=…; replies are XML
//   (<camrply><result>ok</result>…) or CSV ("ok,…"); errors start with "err_".
//   Pairing: mode=accctrl&type=req_acc&value=<uuid>&value2=<name>. While the camera asks the
//   user it answers "ok_under_research"; resend every second until it says ok.
//   Live view: mode=startstream&value=<udp port>; each datagram is one JPEG after a header.
//   The camera stops unless polled with mode=getstate (we poll every second).
//   Exposure values are APEX × 256 written "n/256": f-number = 2^(n/512), time = 2^(-n/256).
//   Photos: UPnP ContentDirectory on port 60606; files on port 50001 (DO/DL/DT prefixes).

struct PanasonicError: LocalizedError {
    let code: String
    let command: String

    var errorDescription: String? {
        switch code {
        case "err_user_refused":
            return "The camera said No to this iPhone. Start Remote Shooting & View on the camera again and choose Yes."
        case "err_others_requesting", "err_already_connected":
            return "Another phone or app is connected to the camera. Close Image App or LUMIX Sync on other devices, then try again."
        case "err_unsuitable_app":
            return "The camera won't accept this app in its current Wi-Fi mode. On the camera use New Connection ▸ Remote Shooting & View."
        case "err_busy":
            return "The camera is busy (probably still writing to the card). Try again in a moment."
        case "err_reject":
            return "The camera refused \(command) in its current mode. Check the mode dial."
        case "err_param", "err_non_support":
            return "This camera doesn't support \(command)."
        default:
            return "The camera answered \(code) to \(command)."
        }
    }
}

/// What the mounted lens and body allow, from mode=getinfo&type=lens.
struct LumixLens {
    /// Largest f-number (smallest aperture), e.g. 22.
    var maxFNumber: Double?
    /// Smallest f-number (widest aperture), e.g. 1.7, and its exact camera code.
    var minFNumber: Double?
    var minFNumberCode: Int?
    /// Shutter codes (APEX × 256): fastest (e.g. 3328 = 1/8000) and slowest (e.g. -1536 = 60 s).
    var fastestShutter: Int?
    var slowestShutter: Int?
    var focalMax: Int?
    var focalMin: Int?
}

/// Per-connection Panasonic state that doesn't belong in the shared model.
final class PanasonicSession {
    var lens = LumixLens()
    /// Allowed values per setting type, from getinfo&type=allmenu (e.g. "iso": ["auto", "200", …]).
    var menu: [String: [String]] = [:]
    /// UI value → camera code, built with each option list.
    var apertureCodes: [String: Int] = [:]
    var shutterCodes: [String: Int] = [:]
    var whiteBalanceCodes: [String: String] = [:]
    var contentDirectory: URL?
    var lastStreamKick = Date.distantPast

    /// Stable per-install id; the camera remembers approved phones by it.
    static var uuid: String {
        let key = "lumix.uuid"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let hex = (0..<12).map { _ in String(format: "%X", Int.random(in: 0..<16)) }.joined()
        let id = "4D454930-0100-1000-8001-" + hex
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    static let deviceName = "PENF-Remote"

    // Value tables shown in the UI (same spellings the Olympus side uses, so the rulers and
    // formatting work unchanged).
    static let fNumbers = ["1.0", "1.1", "1.2", "1.4", "1.6", "1.8", "2.0", "2.2", "2.5", "2.8", "3.2", "3.5",
                           "4.0", "4.5", "5.0", "5.6", "6.3", "7.1", "8.0", "9.0", "10", "11", "13", "14", "16",
                           "18", "20", "22"]
    static let shutterLabels = ["60\"", "50\"", "40\"", "30\"", "25\"", "20\"", "15\"", "13\"", "10\"", "8\"",
                                "6\"", "5\"", "4\"", "3.2\"", "2.5\"", "2\"", "1.6\"", "1.3\"", "1\"", "1.3",
                                "1.6", "2", "2.5", "3", "4", "5", "6", "8", "10", "13", "15", "20", "25", "30", "40",
                                "50", "60", "80", "100", "125", "160", "200", "250", "320", "400", "500", "640",
                                "800", "1000", "1250", "1600", "2000", "2500", "3200", "4000", "5000", "6400",
                                "8000"]
    static let isoFallback = ["auto", "i_iso", "100", "125", "160", "200", "250", "320", "400", "500", "640", "800",
                              "1000", "1250", "1600", "2000", "2500", "3200", "4000", "5000", "6400", "8000",
                              "10000", "12800", "16000", "20000", "25600"]
    static let whiteBalanceFallback = ["auto", "daylight", "cloudy", "shade", "halogen", "flash",
                                       "white_set1", "white_set2", "white_set3", "white_set4"]
    /// Panasonic white-balance names → the codes the UI already has names and icons for.
    static let whiteBalanceToUI = ["auto": "0", "daylight": "18", "shade": "16", "cloudy": "17", "halogen": "20",
                                   "incandescent": "20", "flash": "23", "white_set1": "256", "white_set2": "257",
                                   "white_set3": "258", "white_set4": "259", "color_temp": "512", "color_temp1": "512"]
    static let bulbCode = 16384
}

extension CameraModel {
    // MARK: - Commands

    /// Sends cam.cgi and returns the raw reply; throws PanasonicError for "err_…" answers.
    @discardableResult
    func lumixCommand(_ params: [(String, String)], timeout: TimeInterval = 8, log: Bool = true) async throws -> String {
        guard let client else { throw CameraError("Not connected.") }
        let data = try await client.get("cam", params, timeout: timeout, log: log)
        let text = String(decoding: data, as: UTF8.self)
        let result = Self.lumixResult(text)
        if result.hasPrefix("err") {
            let what = params.first { $0.0 == "value" || $0.0 == "type" }?.1 ?? params.first?.1 ?? "cam.cgi"
            throw PanasonicError(code: result, command: what)
        }
        return text
    }

    static func lumixResult(_ text: String) -> String {
        if let start = text.range(of: "<result>"),
           let end = text.range(of: "</result>", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.split(separator: ",", maxSplits: 1).first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }

    /// "1280/256" → 1280 (codes are APEX × 256).
    static func lumixCode(_ fraction: String) -> Int? {
        let parts = fraction.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, parts[1] != 0 { return Int((parts[0] * 256 / parts[1]).rounded()) }
        if parts.count == 1 { return Int(parts[0]) }
        return nil
    }

    // MARK: - Connect

    func panasonicHandshake() async throws {
        let uuid = PanasonicSession.uuid
        lumix = PanasonicSession()
        var attempt = 0
        let deadline = Date().addingTimeInterval(90)
        pairing: while true {
            attempt += 1
            do {
                let reply = try await lumixCommand([("mode", "accctrl"), ("type", "req_acc"), ("value", uuid),
                                                    ("value2", PanasonicSession.deviceName)], timeout: 5)
                let result = Self.lumixResult(reply)
                if result.hasPrefix("ok_under_research") {
                    status = "On the camera, choose Yes to allow this iPhone…"
                    guard Date() < deadline else {
                        throw CameraError("The camera is still waiting. Choose Yes on the camera's screen, then tap Connect again.")
                    }
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                let fields = reply.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if fields.count > 1, !fields[1].isEmpty { cameraName = fields[1] }
                break pairing
            } catch let error as PanasonicError where ["err_non_support", "err_param"].contains(error.code) {
                break pairing   // older bodies (GH4) don't pair; carry on
            } catch is URLError where attempt < 3 {
                // The first request can fail while iOS shows the Local Network prompt.
                status = "No answer yet, retrying (\(attempt + 1)/3)…"
                try await Task.sleep(for: .milliseconds(1500))
            }
        }

        status = "Reading camera info…"
        _ = try? await lumixCommand([("mode", "setsetting"), ("type", "device_name"), ("value", PanasonicSession.deviceName)])
        var info = ""
        if let capability = try? await lumixCommand([("mode", "getinfo"), ("type", "capability")]) {
            info += "CAPABILITY\n\(capability)\n\n"
        }
        if let lens = try? await lumixCommand([("mode", "getinfo"), ("type", "lens")]) {
            info += "LENS\n\(lens)\n\n"
            applyLumixLens(lens)
        }
        if let allmenu = try? await lumixCommand([("mode", "getinfo"), ("type", "allmenu")], timeout: 15) {
            rawCommandList = allmenu
            parseLumixMenu(allmenu)
        }
        if let state = try? await lumixCommand([("mode", "getstate")]) {
            info += "STATE\n\(state)\n"
            applyLumixState(state)
        }
        rawDescList = info
        debugLog("LUMIX connected: \(cameraName ?? "?")\n\(info)")
        if cameraName == nil { cameraName = "LUMIX" }
        startPanasonicKeepAlive()
    }

    private func applyLumixLens(_ reply: String) {
        // ok,<smallest aperture>,<widest aperture>,<fastest shutter>,<slowest shutter>,…,<focal max>,<focal min>
        let f = reply.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
        func code(_ i: Int) -> Int? { f.indices.contains(i) ? Self.lumixCode(f[i]) : nil }
        var lens = LumixLens()
        if let n = code(1) { lens.maxFNumber = pow(2, Double(n) / 512) }
        if let n = code(2) {
            lens.minFNumber = pow(2, Double(n) / 512)
            lens.minFNumberCode = n
        }
        lens.fastestShutter = code(3)
        lens.slowestShutter = code(4)
        lens.focalMax = f.indices.contains(7) ? Int(f[7]) : nil
        lens.focalMin = f.indices.contains(8) ? Int(f[8]) : nil
        lumix.lens = lens
        if let lo = lens.minFNumber, let hi = lens.maxFNumber, lo > 0, hi >= lo {
            liveInfo.apertureRange = lo...hi
        }
        // A prime lens reports one focal length: the Astro preset can use it.
        if let a = lens.focalMax, let b = lens.focalMin, a == b, a > 0 { liveInfo.focalLength = a }
    }

    private func parseLumixMenu(_ xml: String) {
        guard let root = MiniXML.parse(Data(xml.utf8)) else { return }
        var menu: [String: [String]] = [:]
        for item in root.descendants(named: "item") {
            guard let type = item.attributes["cmd_type"], let value = item.attributes["cmd_value"] else { continue }
            if !(menu[type]?.contains(value) ?? false) { menu[type, default: []].append(value) }
        }
        lumix.menu = menu
        debugLog("LUMIX menu types: \(menu.keys.sorted())")
    }

    func applyLumixState(_ reply: String) {
        guard let state = MiniXML.parse(Data(reply.utf8))?.firstDescendant(named: ["state"]) else { return }
        var info = liveInfo
        if let batt = state.value("batt") {
            let parts = batt.replacingOccurrences(of: "%", with: "").split(separator: "/").compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0 { info.battery = Int((parts[0] / parts[1] * 100).rounded()) }
            else if parts.count == 1 { info.battery = Int(parts[0]) }
        }
        if let remaining = state.value("remaincapacity").flatMap(Int.init) { info.shotsRemaining = remaining }
        if let temperature = state.value("temperature") {
            info.temperatureWarning = !["", "normal", "off"].contains(temperature.lowercased())
        }
        if info != liveInfo { liveInfo = info }
        if let cammode = state.value("cammode") {
            if cammode == "play", mode == .rec, !galleryLoading { debugLog("LUMIX reports play mode") }
        }
    }

    /// Polls getstate every second: keeps live view and the connection alive, refreshes battery.
    private func startPanasonicKeepAlive() {
        panasonicKeepAlive?.cancel()
        panasonicKeepAlive = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.phase == .disconnected { return }
                do {
                    let reply = try await self.lumixCommand([("mode", "getstate")], timeout: 3, log: false)
                    if failures >= 3 { self.lastError = nil }
                    failures = 0
                    self.applyLumixState(reply)
                    // If frames stop, ask again (the camera can drop the stream after a hiccup).
                    if self.liveViewRunning, self.mode == .rec, self.isLiveViewStalled(at: Date()),
                       Date().timeIntervalSince(self.lumix.lastStreamKick) > 3 {
                        self.lumix.lastStreamKick = Date()
                        _ = try? await self.lumixCommand([("mode", "startstream"), ("value", String(self.udpPort))])
                    }
                } catch {
                    failures += 1
                    if failures == 3 {
                        self.lastError = "Lost contact with the camera. Check that this iPhone is still on the camera's Wi-Fi."
                    }
                }
            }
        }
    }

    func panasonicPowerOff() async {
        _ = try? await lumixCommand([("mode", "camcmd"), ("value", "recmode")], timeout: 3)
        _ = try? await lumixCommand([("mode", "camcmd"), ("value", "poweroff")], timeout: 3)
    }

    // MARK: - Live view

    func panasonicEnterRecMode() async {
        isSwitchingMode = true
        defer { isSwitchingMode = false }
        do {
            _ = try? await lumixCommand([("mode", "stopstream")], timeout: 3)
            try await lumixCommand([("mode", "camcmd"), ("value", "recmode")], timeout: 5)
            mode = .rec
            // The new size only applies to the next startstream.
            let size = liveViewQuality == "0320x0240" ? "qvga" : "vga"
            _ = try? await lumixCommand([("mode", "setsetting"), ("type", "liveviewsize"), ("value", size)])
            try? await Task.sleep(for: .milliseconds(300))
            await refreshProperties()
            await startLiveView()
        } catch {
            lastError = Self.describe(error, host: host)
        }
    }

    func panasonicStartLiveView() async {
        do {
            lumix.lastStreamKick = Date()
            try await lumixCommand([("mode", "startstream"), ("value", String(udpPort))])
        } catch {
            liveViewRunning = false
            lastError = Self.describe(error, host: host)
        }
    }

    func panasonicStopLiveView() async {
        _ = try? await lumixCommand([("mode", "stopstream")], timeout: 3)
    }

    // MARK: - Settings

    func panasonicRefreshProperties() async {
        var result: [String: CameraProperty] = [:]
        func current(_ type: String) async -> String? {
            guard let reply = try? await lumixCommand([("mode", "getsetting"), ("type", type)], log: false),
                  let node = MiniXML.parse(Data(reply.utf8))?.firstDescendant(named: ["settingvalue"]) else { return nil }
            return node.attributes[type]
        }

        // Aperture: third stops within the lens's range, plus its exact widest value.
        let apertures = lumixApertureOptions()
        if let raw = await current("focal"), let code = Self.lumixCode(raw) {
            result["focalvalue"] = CameraProperty(name: "focalvalue", settable: true,
                                                  value: nearest(code, in: lumix.apertureCodes) ?? apertures.first ?? "",
                                                  options: apertures)
        }
        let shutters = lumixShutterOptions()
        if let raw = await current("shtrspeed"), let code = Self.lumixCode(raw) {
            let value = code == PanasonicSession.bulbCode ? "bulb" : (nearest(code, in: lumix.shutterCodes) ?? "")
            result["shutspeedvalue"] = CameraProperty(name: "shutspeedvalue", settable: true, value: value, options: shutters)
        }
        if let raw = await current("iso") {
            let options = lumix.menu["iso"] ?? PanasonicSession.isoFallback
            result["isospeedvalue"] = CameraProperty(name: "isospeedvalue", settable: true, value: raw,
                                                     options: options.contains(raw) ? options : options + [raw])
        }
        if let raw = await current("exposure") {
            let options = (-15...15).map(Self.evLabel)
            let value = Self.evLabel(Int((Self.lumixFraction(raw) * 3).rounded()))
            result["expcomp"] = CameraProperty(name: "expcomp", settable: true, value: value, options: options)
        }
        if let raw = await current("whitebalance") {
            let names = lumix.menu["whitebalance"] ?? PanasonicSession.whiteBalanceFallback
            var codes: [String: String] = [:]
            var options: [String] = []
            for name in names + [raw] {
                let ui = PanasonicSession.whiteBalanceToUI[name] ?? name
                if codes[ui] == nil { codes[ui] = name; options.append(ui) }
            }
            lumix.whiteBalanceCodes = codes
            result["wbvalue"] = CameraProperty(name: "wbvalue", settable: true,
                                               value: PanasonicSession.whiteBalanceToUI[raw] ?? raw, options: options)
        }
        properties = result
    }

    func panasonicSetProperty(_ name: String, to value: String, reportErrors: Bool) async -> Bool {
        let setting: (type: String, value: String)?
        switch name {
        case "focalvalue":
            setting = lumix.apertureCodes[value].map { ("focal", "\($0)/256") }
        case "shutspeedvalue":
            setting = value == "bulb" ? ("shtrspeed", "\(PanasonicSession.bulbCode)/256")
                : lumix.shutterCodes[value].map { ("shtrspeed", "\($0)/256") }
        case "isospeedvalue":
            setting = ("iso", value)
        case "expcomp":
            let thirds = Int(((Double(value) ?? 0) * 3).rounded())
            setting = ("exposure", thirds % 3 == 0 ? "\(thirds / 3)" : "\(thirds)/3")
        case "wbvalue":
            setting = ("whitebalance", lumix.whiteBalanceCodes[value] ?? value)
        default:
            setting = nil
        }
        guard let setting else {
            if reportErrors { lastError = "This setting can't be changed on a LUMIX camera from the app." }
            return false
        }
        let previous = properties[name]?.value
        properties[name]?.value = value
        do {
            try await lumixCommand([("mode", "setsetting"), ("type", setting.type), ("value", setting.value)])
        } catch {
            if let previous { properties[name]?.value = previous }
            if reportErrors { lastError = Self.describe(error, host: host) }
            await panasonicRefreshProperties()
            return false
        }
        await panasonicRefreshProperties()
        return true
    }

    private func lumixApertureOptions() -> [String] {
        var codes: [String: Int] = [:]
        var options: [String] = []
        let lens = lumix.lens
        if let widest = lens.minFNumber, let widestCode = lens.minFNumberCode {
            let label = Self.fLabel(widest)
            options.append(label)
            codes[label] = widestCode
        }
        for label in PanasonicSession.fNumbers {
            guard let f = Double(label), codes[label] == nil else { continue }
            if let lo = lens.minFNumber, f < lo + 0.05 { continue }
            if let hi = lens.maxFNumber, f > hi + 0.05 { continue }
            // Third-stop grid: Av = 2·log2(N) rounded to thirds, × 256.
            let thirds = (2 * log2(f) * 3).rounded()
            codes[label] = Int((256 * thirds / 3).rounded())
            options.append(label)
        }
        lumix.apertureCodes = codes
        return options
    }

    private func lumixShutterOptions() -> [String] {
        var codes: [String: Int] = [:]
        var options: [String] = []
        let fast = lumix.lens.fastestShutter ?? 3328     // 1/8000
        let slow = lumix.lens.slowestShutter ?? -1536    // 60 s
        for label in PanasonicSession.shutterLabels {
            guard let seconds = PropertyFormat.seconds(fromShutter: label) else { continue }
            let thirds = (-log2(seconds) * 3).rounded()
            let code = Int((256 * thirds / 3).rounded())
            guard code >= min(slow, fast), code <= max(slow, fast) else { continue }
            codes[label] = code
            options.append(label)
        }
        lumix.shutterCodes = codes
        return ["bulb"] + options
    }

    private func nearest(_ code: Int, in table: [String: Int]) -> String? {
        table.min { abs($0.value - code) < abs($1.value - code) }?.key
    }

    static func fLabel(_ f: Double) -> String {
        f >= 10 ? String(format: "%.0f", f) : String(format: "%.1f", f)
    }

    static func evLabel(_ thirds: Int) -> String {
        thirds == 0 ? "0.0" : String(format: "%+.1f", Double(thirds) / 3)
    }

    /// "-1/3" → -0.333, "2" → 2.
    static func lumixFraction(_ text: String) -> Double {
        let parts = text.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, parts[1] != 0 { return parts[0] / parts[1] }
        return parts.first ?? 0
    }

    // MARK: - Focus & shooting

    func panasonicFocus(at point: CGPoint) async {
        // Touch AF in a 0–1000 grid over the live-view frame.
        let x = Int((point.x * 1000).rounded()), y = Int((point.y * 1000).rounded())
        do {
            try await lumixCommand([("mode", "camctrl"), ("type", "touch"), ("value", "\(x)/\(y)"), ("value2", "on")])
        } catch let error as PanasonicError where error.code == "err_param" {
            // Older bodies use touchaf.
            _ = try? await lumixCommand([("mode", "camctrl"), ("type", "touchaf"), ("value", "\(x)/\(y)")])
        } catch {
            lastError = Self.describe(error, host: host)
        }
    }

    func panasonicReleaseFocus() async {
        _ = try? await lumixCommand([("mode", "camctrl"), ("type", "touch"), ("value", "0/0"), ("value2", "off")])
    }

    func panasonicShutterPressed() async {
        isShooting = true
        let seconds = PropertyFormat.seconds(fromShutter: properties["shutspeedvalue"]?.value ?? "") ?? 0
        if seconds >= 1 {
            exposureStartedAt = Date()
            exposureDuration = seconds
        }
        defer {
            exposureStartedAt = nil
            exposureDuration = nil
            isShooting = false
        }
        do {
            try await lumixCommand([("mode", "camcmd"), ("value", "capture")], timeout: 10)
            // capture returns straight away; keep the countdown honest for long exposures.
            if seconds >= 1 { try? await Task.sleep(for: .seconds(seconds + 0.5)) }
            shotCounter += 1
            _ = try? await lumixCommand([("mode", "camcmd"), ("value", "autoreviewunlock")], timeout: 3, log: false)
        } catch {
            lastError = Self.describe(error, host: host)
        }
    }

    func panasonicShutterReleased() async {}

    /// Bulb: first tap opens the shutter, second tap closes it.
    func panasonicToggleBulb() async {
        if isShooting {
            _ = try? await lumixCommand([("mode", "camcmd"), ("value", "capture_cancel")])
            isShooting = false
            exposureStartedAt = nil
            shotCounter += 1
            return
        }
        isShooting = true
        exposureStartedAt = Date()
        exposureDuration = nil
        do {
            try await lumixCommand([("mode", "camcmd"), ("value", "capture")], timeout: 10)
        } catch {
            isShooting = false
            exposureStartedAt = nil
            lastError = Self.describe(error, host: host)
        }
    }

    func panasonicToggleMovie() async {
        if isRecordingMovie {
            _ = try? await lumixCommand([("mode", "camcmd"), ("value", "video_recstop")])
            isRecordingMovie = false
            movieStartedAt = nil
            shotCounter += 1
        } else {
            do {
                try await lumixCommand([("mode", "camcmd"), ("value", "video_recstart")])
                isRecordingMovie = true
                movieStartedAt = Date()
            } catch {
                lastError = Self.describe(error, host: host)
            }
        }
    }

    /// LUMIX review images need playback mode, which would stop live view, so there's no quick review.
    func panasonicFetchLastShot() async {}

    func panasonicSyncClock() async -> Bool {
        lastError = "LUMIX cameras don't accept a clock setting over Wi-Fi. Set it on the camera."
        return false
    }

    // MARK: - Card (UPnP ContentDirectory)

    func panasonicOpenGallery() async {
        do {
            try await lumixCommand([("mode", "camcmd"), ("value", "playmode")], timeout: 5)
            mode = .play
            try? await Task.sleep(for: .seconds(1))
            let control = try await lumixContentDirectory()
            var found: [CameraImage] = []
            for entry in try await lumixBrowse(control, objectID: "0") {
                switch entry {
                case .item(let images): found += images
                case .container(let id):
                    for case .item(let images) in try await lumixBrowse(control, objectID: id) { found += images }
                }
            }
            images = found.sorted { ($0.date, $0.name) > ($1.date, $1.name) }
            cardFolders = [CardFolder(path: "LUMIX", name: cameraName ?? "LUMIX", count: images.count, isForeign: false)]
        } catch {
            galleryError = Self.describe(error, host: host)
        }
    }

    private var lumixHostIP: String { host.split(separator: ":").first.map(String.init) ?? host }

    /// Finds the ContentDirectory control URL from the camera's UPnP device description.
    private func lumixContentDirectory() async throws -> URL {
        if let known = lumix.contentDirectory { return known }
        guard let client else { throw CameraError("Not connected.") }
        let base = "http://\(lumixHostIP):60606"
        for path in ["/Server0/ddd", "/Lumix/Server0/ddd"] {
            guard let data = try? await client.fetch(URL(string: base + path), timeout: 5),
                  let root = MiniXML.parse(data) else { continue }
            for service in root.descendants(named: "service")
            where service.value("serviceType")?.contains("ContentDirectory") == true {
                guard let control = service.value("controlURL") else { continue }
                let url = control.hasPrefix("http") ? URL(string: control)
                    : URL(string: base + (control.hasPrefix("/") ? control : "/" + control))
                if let url {
                    lumix.contentDirectory = url
                    return url
                }
            }
        }
        // Fall back to the usual control path.
        let fallback = URL(string: base + "/Server0/CDS_control")!
        lumix.contentDirectory = fallback
        return fallback
    }

    enum LumixEntry {
        case item([CameraImage])
        case container(String)
    }

    private func lumixBrowse(_ control: URL, objectID: String) async throws -> [LumixEntry] {
        guard let client else { throw CameraError("Not connected.") }
        var entries: [LumixEntry] = []
        var start = 0
        while true {
            let body = """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1" xmlns:pana="urn:schemas-panasonic-com:pana">
            <ObjectID>\(objectID)</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter>
            <StartingIndex>\(start)</StartingIndex><RequestedCount>50</RequestedCount><SortCriteria></SortCriteria>
            <pana:X_FromCP>LumixLink2.0</pana:X_FromCP></u:Browse></s:Body></s:Envelope>
            """
            let data = try await client.soap(control, action: "urn:schemas-upnp-org:service:ContentDirectory:1#Browse", body: body)
            guard let response = MiniXML.parse(data),
                  let didl = response.firstDescendant(named: ["Result"])?.trimmedText,
                  let root = MiniXML.parse(Data(didl.utf8)) else { break }
            let returned = Int(response.firstDescendant(named: ["NumberReturned"])?.trimmedText ?? "") ?? 0
            let total = Int(response.firstDescendant(named: ["TotalMatches"])?.trimmedText ?? "") ?? 0
            for node in root.children {
                if node.name == "container", let id = node.attributes["id"] {
                    entries.append(.container(id))
                } else if node.name == "item" {
                    entries.append(.item(lumixImages(from: node)))
                }
            }
            start += returned
            if returned == 0 || start >= total { break }
        }
        return entries
    }

    /// One UPnP item → its JPEG/MP4 and (if present) its RAW file.
    private func lumixImages(from item: XMLNode) -> [CameraImage] {
        var original: URL?, raw: URL?, thumb: URL?, large: URL?
        var size = 0, rawSize = 0
        for res in item.children("res") {
            let kind = res.attributes["protocolInfo"] ?? ""
            let url = URL(string: res.trimmedText)
            let bytes = Int(res.attributes["size"] ?? "") ?? 0
            if kind.contains("CAM_RAW") { raw = url; rawSize = bytes }
            else if kind.contains("CAM_LRGTN") { large = url }
            else if kind.contains("CAM_TN") { thumb = url }
            else if kind.contains("CAM_ORG") { original = url; size = bytes }
        }
        let title = item.value("dc:title") ?? item.attributes["id"] ?? "photo"
        let date = item.value("dc:date").flatMap(Self.lumixDate) ?? .distantPast
        var result: [CameraImage] = []
        if let original {
            let ext = original.pathExtension.isEmpty ? "JPG" : original.pathExtension.uppercased()
            result.append(CameraImage(directory: "LUMIX", name: "\(title).\(ext)", size: size, attributes: 0, date: date,
                                      urls: MediaURLs(thumbnail: thumb, preview: large ?? thumb, original: original)))
        }
        if let raw {
            result.append(CameraImage(directory: "LUMIX", name: "\(title).RW2", size: rawSize, attributes: 0, date: date,
                                      urls: MediaURLs(thumbnail: thumb, preview: large ?? thumb, original: raw)))
        }
        return result
    }

    static func lumixDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

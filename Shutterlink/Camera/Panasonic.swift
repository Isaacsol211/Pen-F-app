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
            return "The camera said No to this \(Platform.device). Start Remote Shooting & View on the camera again and choose Yes."
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
    /// The extra settings the camera's menu offers (drive, Photo Style, AF mode…) and colour temperature.
    var settings: [LumixSetting] = []
    var kelvin: LumixKelvin?
    /// Their current values, merged into the properties on every refresh. Read again after one of
    /// them changes, or when the last reading is more than a few seconds old.
    var settingProperties: [String: CameraProperty] = [:]
    var settingsReadAt: Date?
    /// What the app last set, for settings the camera won't report back.
    var lastSet: [String: String] = [:]
    var loggedSettings = false
    /// Whether getsetting&type=recmode answers (asked once; bodies differ).
    var recmodeReadable = true
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

    static let deviceName = "Shutterlink"

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

@MainActor
final class PanasonicDriver: CameraDriver {
    unowned let camera: CameraModel
    let client: CameraHTTPClient
    /// Per-connection LUMIX state (lens limits, value tables, UPnP address).
    var lumix = PanasonicSession()
    /// The camera stops streaming unless it hears from the app regularly.
    private var keepAlive: Task<Void, Never>?

    init(camera: CameraModel) {
        self.camera = camera
        client = camera.makeHTTPClient(userAgent: "LUMIX Sync")
    }

    var liveViewFormat: LiveViewFormat { .jpegPerDatagram }

    var capabilities: CameraCapabilities {
        CameraCapabilities(liveViewSizes: CameraBrand.panasonic.defaultLiveViewSizes,
                           movie: !(camera.profile?.noVideo ?? false), videoSwitch: true, powerOff: true, focusDrive: true)
    }

    func teardown() {
        keepAlive?.cancel()
        keepAlive = nil
        PropertyFormat.setCameraText(CameraText())
    }

    // MARK: - Focus stacking

    /// `camctrl&type=focus`: "wide-…" steps nearer, "tele-…" farther, "-fast" in bigger steps. The camera
    /// has to be in MF (it answers err_reject otherwise) and replies "ok,<position>,<end>".
    func driveFocus(farther: Bool, step: FocusStepSize) async throws -> FocusDriveResult {
        let direction = farther ? "tele" : "wide"
        let (speed, repeats) = switch step {
        case .fine: ("normal", 1)
        case .medium: ("normal", 3)
        case .coarse: ("fast", 1)
        }
        var reply = ""
        for _ in 0..<repeats {
            do {
                reply = try await lumixCommand([("mode", "camctrl"), ("type", "focus"), ("value", "\(direction)-\(speed)")],
                                               timeout: 5)
            } catch let error as PanasonicError where error.code == "err_reject" {
                throw CameraError("The camera won't move focus: switch it to MF (manual focus) and try again.")
            }
        }
        // Community notes read the two numbers as position and end of travel; unconfirmed on a real body.
        let numbers = reply.split(separator: ",").dropFirst().compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if numbers.count >= 2, numbers[1] > 0, farther ? numbers[0] >= numbers[1] : numbers[0] <= 0 {
            return .endOfTravel
        }
        return .moved
    }

    // MARK: - Commands

    /// Sends cam.cgi and returns the raw reply; throws PanasonicError for "err_…" answers.
    @discardableResult
    func lumixCommand(_ params: [(String, String)], timeout: TimeInterval = 8, log: Bool = true) async throws -> String {
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

    func connect() async throws {
        let uuid = PanasonicSession.uuid
        lumix = PanasonicSession()
        PropertyFormat.setCameraText(CameraText())
        // Newer bodies (S5IIX, G9II…) say in their UPnP description that they want the newer pairing.
        let description = await readDeviceDescription()
        camera.profile = ModelProfiles.find(.panasonic, reported: description.model)
        if let reason = camera.profile?.unsupportedReason { throw CameraError(reason) }
        var pairingKind: LumixPairing = description.encrypted ? .newer : (camera.profile?.pairing ?? .standard)
        debugLog("LUMIX model \(description.model ?? "?") → \(camera.profile?.name ?? "not in the model table"), pairing \(pairingKind)")
        if pairingKind == .newer {
            // The newer pairing needs the UDN from the UPnP description; without it, try the usual one.
            if let udn = description.udn {
                do {
                    try await encryptedPairing(udn: udn)
                } catch let error as PanasonicError where ["err_param", "err_non_support"].contains(error.code) {
                    // e.g. the original S5 answers req_acc_g with err_param: it wants the usual pairing.
                    debugLog("LUMIX: newer pairing refused (\(error.code)); trying the usual one")
                    pairingKind = .standard
                }
            } else {
                pairingKind = .standard
            }
        }
        var attempt = 0
        let deadline = Date().addingTimeInterval(90)
        pairing: while pairingKind == .standard {
            attempt += 1
            do {
                let reply = try await lumixCommand([("mode", "accctrl"), ("type", "req_acc"), ("value", uuid),
                                                    ("value2", PanasonicSession.deviceName)], timeout: 5)
                let result = Self.lumixResult(reply)
                if result.hasPrefix("ok_under_research") {
                    camera.status = "On the camera, choose Yes to allow this \(Platform.device)…"
                    guard Date() < deadline else {
                        throw CameraError("The camera is still waiting. Choose Yes on the camera's screen, then \(Platform.tap) Connect again.")
                    }
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                let fields = reply.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if fields.count > 1, !fields[1].isEmpty { camera.cameraName = fields[1] }
                break pairing
            } catch let error as PanasonicError where ["err_non_support", "err_param"].contains(error.code) {
                break pairing   // older bodies (GH4) don't pair; carry on
            } catch is URLError where attempt < 3 {
                // The first request can fail while iOS shows the Local Network prompt.
                camera.status = "No answer yet, retrying (\(attempt + 1)/3)…"
                try await Task.sleep(for: .milliseconds(1500))
            }
        }

        camera.status = "Reading camera info…"
        _ = try? await lumixCommand([("mode", "setsetting"), ("type", "device_name"), ("value", PanasonicSession.deviceName)])
        var info = ""
        var model = description.model
        if let capability = try? await lumixCommand([("mode", "getinfo"), ("type", "capability")]) {
            info += "CAPABILITY\n\(capability)\n\n"
            // The G7 says <modelname>, newer bodies <model_name>.
            if let name = MiniXML.parse(Data(capability.utf8))?.firstDescendant(named: ["model_name", "modelname"])?.trimmedText {
                model = name
                if camera.profile == nil { camera.profile = ModelProfiles.find(.panasonic, reported: name) }
            }
        }
        if let lens = try? await lumixCommand([("mode", "getinfo"), ("type", "lens")]) {
            info += "LENS\n\(lens)\n\n"
            applyLumixLens(lens)
        }
        var version: String?
        if let state = try? await lumixCommand([("mode", "getstate")]) {
            info += "STATE\n\(state)\n"
            applyLumixState(state)
            version = MiniXML.parse(Data(state.utf8))?.firstDescendant(named: ["version"])?.trimmedText
        }
        if let allmenu = await lumixMenu(model: model, version: version) {
            camera.rawCommandList = allmenu
            parseLumixMenu(allmenu)
        }
        camera.rawDescList = info
        debugLog("LUMIX connected: \(camera.cameraName ?? "?")\n\(info)")
        camera.cameraName = camera.profile?.name ?? camera.cameraName ?? "LUMIX"
        startKeepAlive()
    }

    /// getinfo&type=allmenu: about 150 KB on a G7, which can take over 20 s on the camera's Wi-Fi. It
    /// only changes with firmware, so a copy is kept per model and version.
    private func lumixMenu(model: String?, version: String?) async -> String? {
        let key = [model, version].compactMap { $0 }.joined(separator: "-")
            .replacingOccurrences(of: "[^A-Za-z0-9.-]", with: "_", options: .regularExpression)
        let file = key.isEmpty ? nil : URL.cachesDirectory.appending(path: "lumix-allmenu-\(key).xml")
        if let file, let saved = try? String(contentsOf: file, encoding: .utf8) { return saved }
        camera.status = "Reading the camera's menus (first time only)…"
        guard let menu = try? await lumixCommand([("mode", "getinfo"), ("type", "allmenu")], timeout: 60) else { return nil }
        if let file, menu.contains("<menuset") { try? menu.write(to: file, atomically: true, encoding: .utf8) }
        return menu
    }

    /// Reads the camera's UPnP device description on port 60606: its UDN, whether it advertises the
    /// newer encrypted pairing (X_CamCapability ending in 1), and the card's ContentDirectory URL.
    private func readDeviceDescription() async -> (udn: String?, encrypted: Bool, model: String?) {
        let base = "http://\(lumixHostIP):60606"
        for path in ["/Server0/ddd", "/Lumix/Server0/ddd"] {
            guard let data = try? await client.fetch(URL(string: base + path), timeout: 3, log: false),
                  let root = MiniXML.parse(data) else { continue }
            rememberContentDirectory(root, base: base)
            let udn = root.firstDescendant(named: ["UDN"])?.trimmedText.replacingOccurrences(of: "uuid:", with: "")
            let capability = root.firstDescendant(named: ["pana:X_CamCapability", "X_CamCapability"])?.trimmedText ?? ""
            // modelName is always "LUMIX"; modelNumber is the body, e.g. "DC-GH5".
            let model = root.firstDescendant(named: ["modelNumber"])?.trimmedText
            debugLog("LUMIX ddd \(path): udn=\(udn ?? "?") model=\(model ?? "?") X_CamCapability=\(capability)")
            return (udn, capability.hasSuffix("1"), model)
        }
        return (nil, false, nil)
    }

    /// The newer LUMIX pairing (S5IIX, G9II…), as the open-source liblumix does it: req_acc_g, then
    /// req_acc_e with the camera's UDN and our name as lowercase hex until the camera says ok; the
    /// reply's last field is a session id that goes in an X-SESSION_ID header from then on.
    /// Unverified: Panasonic's own app is reported to XOR these fields with a nonce from req_acc_g.
    private func encryptedPairing(udn: String) async throws {
        camera.status = "Pairing with the camera…"
        _ = try await lumixCommand([("mode", "accctrl"), ("type", "req_acc_g")], timeout: 5)
        func hex(_ text: String) -> String { text.utf8.map { String(format: "%02x", $0) }.joined() }
        let deadline = Date().addingTimeInterval(90)
        while true {
            let reply = try await lumixCommand([("mode", "accctrl"), ("type", "req_acc_e"), ("value", hex(udn)),
                                                ("value2", hex(PanasonicSession.deviceName))], timeout: 5)
            let fields = reply.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if fields.first == "ok" {
                if fields.count > 1, !fields[1].isEmpty { camera.cameraName = fields[1] }
                if fields.count >= 5, let session = fields.last, !session.isEmpty {
                    client.extraHeaders["X-SESSION_ID"] = session
                }
                return
            }
            guard Date() < deadline else {
                throw CameraError("The camera didn't accept this \(Platform.device). Choose Yes on the camera's screen if it asks, then \(Platform.tap) Connect again. (Newer LUMIX pairing is new in Shutterlink; if it keeps failing, please tell us.)")
            }
            if fields.first?.hasPrefix("ok_under_research") == true {
                camera.status = "On the camera, choose Yes to allow this \(Platform.device)…"
            }
            try await Task.sleep(for: .seconds(1))
        }
    }

    private func rememberContentDirectory(_ root: XMLNode, base: String) {
        for service in root.descendants(named: "service")
        where service.value("serviceType")?.contains("ContentDirectory") == true {
            guard let control = service.value("controlURL") else { continue }
            let url = control.hasPrefix("http") ? URL(string: control)
                : URL(string: base + (control.hasPrefix("/") ? control : "/" + control))
            if let url { lumix.contentDirectory = url; return }
        }
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
            camera.liveInfo.apertureRange = lo...hi
        }
        // A prime lens reports one focal length: the Astro preset can use it.
        if let a = lens.focalMax, let b = lens.focalMin, a == b, a > 0 { camera.liveInfo.focalLength = a }
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

        // The extra settings, named the way the camera names them.
        let parsed = LumixMenu.parse(root)
        lumix.settings = parsed.settings
        lumix.kelvin = parsed.kelvin
        var text = CameraText()
        for setting in parsed.settings {
            text.titles[setting.name] = setting.title
            text.values[setting.name] = setting.labels.merging(["": "–"]) { own, _ in own }
        }
        if let kelvin = parsed.kelvin {
            text.titles[LumixMenu.kelvinName] = LumixMenu.kelvinTitle
            var labels = Dictionary(uniqueKeysWithValues: kelvin.options.map { ($0, "\($0) K") })
            labels[""] = "Off"
            text.values[LumixMenu.kelvinName] = labels
        }
        PropertyFormat.setCameraText(text)
        debugLog("LUMIX extra settings: \(parsed.settings.map { "\($0.type) (\($0.options.count))" }.joined(separator: ", "))"
                 + (parsed.kelvin.map { ", colour temperature \($0.min)–\($0.max) K" } ?? ""))
    }

    /// Reads the extra settings: their current values (getsetting) and what the camera allows right
    /// now (curmenu: options greyed out in this mode are left out, and a heading that is switched
    /// off locks its setting).
    private func readLumixSettings() async {
        lumix.settingsReadAt = Date()
        var dump = ""
        var menuState: [String: LumixMenuState] = [:]
        if let reply = try? await lumixCommand([("mode", "getinfo"), ("type", "curmenu")], log: false),
           let root = MiniXML.parse(Data(reply.utf8)) {
            menuState = LumixMenu.parseState(root)
            if !lumix.loggedSettings { dump += "CURMENU\n\(reply)\n\n" }
        }
        func enabled(_ ids: [String]) -> Bool { ids.allSatisfy { menuState[$0]?.enabled ?? true } }

        var properties: [String: CameraProperty] = [:]
        for setting in lumix.settings {
            let reading = await readLumixSetting(setting.type)
            if !lumix.loggedSettings { dump += "GETSETTING \(setting.type): \(reading.raw ?? "no answer")\n" }
            let value: String
            if let current = reading.value {
                value = Self.optionKey(current, reading.detail, in: setting.options)
            } else if let fromMenu = setting.headingItems.lazy.compactMap({ menuState[$0]?.value }).first {
                value = Self.optionKey(fromMenu, nil, in: setting.options)
            } else {
                value = lumix.lastSet[setting.name] ?? ""
            }
            var options = setting.options.filter { enabled(setting.optionItems[$0] ?? []) || $0 == value }
            if !value.isEmpty, !options.contains(value) { options.insert(value, at: 0) }
            let usable = enabled(setting.headingItems) && options.contains { $0 != value }
            if options.isEmpty { options = [value] }
            properties[setting.name] = CameraProperty(name: setting.name, settable: usable, value: value, options: options)
        }
        if let kelvin = lumix.kelvin {
            let reading = await readLumixSetting("whitebalance")
            let value = reading.value == "color_temp" ? (reading.detail ?? lumix.lastSet[LumixMenu.kelvinName] ?? "") : ""
            properties[LumixMenu.kelvinName] = CameraProperty(name: LumixMenu.kelvinName,
                                                              settable: enabled([kelvin.itemID].compactMap { $0 }),
                                                              value: value, options: kelvin.options)
        }
        // The mode dial can't be turned from an app, but showing it tells the user (and the presets)
        // which of aperture and shutter the camera is choosing. curmenu has it on some bodies,
        // getsetting&type=recmode on others.
        var dial = menuState["menu_item_id_recmode"]?.value
        if dial == nil, lumix.recmodeReadable {
            let reading = await readLumixSetting("recmode")
            if !lumix.loggedSettings { dump += "GETSETTING recmode: \(reading.raw ?? "no answer")\n" }
            dial = reading.value
            lumix.recmodeReadable = reading.raw != nil
        }
        if let mode = dial.flatMap(Self.lumixMode) {
            properties["takemode"] = CameraProperty(name: "takemode", settable: false, value: mode, options: [mode])
        }
        lumix.settingProperties = properties
        debugLog("LUMIX settings: " + properties.values.sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)\($0.settable ? "" : " (locked)")" }.joined(separator: " "))
        if !dump.isEmpty {
            // Kept with the connection info (Request log ▸ Settings) to check a new body against.
            camera.rawDescList += "\n" + dump
            lumix.loggedSettings = true
        }
    }

    /// LUMIX Rec Mode → the app's mode names; others (C1, Creative Control…) as the camera says them.
    static func lumixMode(_ value: String) -> String? {
        switch value {
        case "": nil
        case "program_ae": "P"
        case "aperture_ae": "A"
        case "shutter_ae": "S"
        case "manual_exposure": "M"
        case "intelligent_auto", "iauto": "iAuto"
        case "creative_movie": "movie"
        default: LumixMenu.words(value)
        }
    }

    /// getsetting: `<settingvalue drivemode="burst">h</settingvalue>`. The text, when there is one,
    /// is the second part of the value.
    private func readLumixSetting(_ type: String) async -> (value: String?, detail: String?, raw: String?) {
        guard let reply = try? await lumixCommand([("mode", "getsetting"), ("type", type)], log: false) else {
            return (nil, nil, nil)
        }
        let node = MiniXML.parse(Data(reply.utf8))?.firstDescendant(named: ["settingvalue"])
        let detail = node?.trimmedText ?? ""
        return (node?.attributes[type], detail.isEmpty ? nil : detail, reply)
    }

    /// The option a reading stands for: "burst" + "h" → "burst|h".
    static func optionKey(_ value: String, _ detail: String?, in options: [String]) -> String {
        if let detail, options.contains("\(value)|\(detail)") { return "\(value)|\(detail)" }
        if options.contains(value) { return value }
        return detail.map { "\(value)|\($0)" } ?? value
    }

    private func setLumixSetting(_ setting: LumixSetting, to key: String, reportErrors: Bool) async -> Bool {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard let base = parts.first else { return false }
        var params = [("mode", "setsetting"), ("type", setting.type), ("value", base)]
        if parts.count > 1 { params.append(("value2", parts[1])) }
        let previous = camera.properties[setting.name]?.value
        camera.properties[setting.name]?.value = key
        do {
            try await lumixCommand(params)
        } catch {
            if let previous { camera.properties[setting.name]?.value = previous }
            if reportErrors { camera.lastError = CameraModel.describe(error, host: camera.connectionHost) }
            lumix.settingsReadAt = nil
            await refreshProperties()
            return false
        }
        lumix.lastSet[setting.name] = key
        // Read it back: some bodies answer ok to a drive mode change and keep the old one.
        lumix.settingsReadAt = nil
        await refreshProperties()
        guard let now = camera.properties[setting.name]?.value, !now.isEmpty, now != key else { return true }
        let sameChoice = !now.contains("|") && now == base
        if sameChoice { return true }
        if reportErrors {
            camera.lastError = "The camera said OK but stayed on \(PropertyFormat.display(setting.name, now)). "
                + "Change \(setting.title.lowercased()) on the camera."
        }
        return false
    }

    private func setLumixKelvin(_ kelvin: String, reportErrors: Bool) async -> Bool {
        guard !kelvin.isEmpty else { return false }
        do {
            try await lumixCommand([("mode", "setsetting"), ("type", "whitebalance"), ("value", "color_temp"),
                                    ("value2", kelvin)])
        } catch {
            if reportErrors { camera.lastError = CameraModel.describe(error, host: camera.connectionHost) }
            return false
        }
        lumix.lastSet[LumixMenu.kelvinName] = kelvin
        lumix.settingsReadAt = nil
        await refreshProperties()
        return true
    }

    func applyLumixState(_ reply: String) {
        guard let state = MiniXML.parse(Data(reply.utf8))?.firstDescendant(named: ["state"]) else { return }
        var info = camera.liveInfo
        if let batt = state.value("batt") {
            let parts = batt.replacingOccurrences(of: "%", with: "").split(separator: "/").compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0 { info.battery = Int((parts[0] / parts[1] * 100).rounded()) }
            else if parts.count == 1 { info.battery = Int(parts[0]) }
        }
        if let remaining = state.value("remaincapacity").flatMap(Int.init) { info.shotsRemaining = remaining }
        if let temperature = state.value("temperature") {
            info.temperatureWarning = !["", "normal", "off"].contains(temperature.lowercased())
        }
        if info != camera.liveInfo { camera.liveInfo = info }
        if state.value("cammode") == "play", camera.mode == .rec, !camera.galleryLoading { debugLog("LUMIX reports play mode") }
    }

    /// Polls getstate every second: keeps live view and the connection alive, refreshes battery.
    private func startKeepAlive() {
        keepAlive?.cancel()
        keepAlive = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, self.camera.phase != .disconnected else { return }
                do {
                    let reply = try await self.lumixCommand([("mode", "getstate")], timeout: 3, log: false)
                    if failures >= 3 { self.camera.lastError = nil }
                    failures = 0
                    self.applyLumixState(reply)
                    // If frames stop, ask again (the camera can drop the stream after a hiccup).
                    if self.camera.liveViewRunning, self.camera.mode == .rec, self.camera.isLiveViewStalled(at: Date()),
                       Date().timeIntervalSince(self.lumix.lastStreamKick) > 3 {
                        self.lumix.lastStreamKick = Date()
                        _ = try? await self.lumixCommand([("mode", "startstream"), ("value", String(self.camera.udpPort))])
                    }
                } catch {
                    failures += 1
                    if failures == 3 {
                        self.camera.lastError = "Lost contact with the camera. Check that this \(Platform.device) is still on the camera's Wi-Fi."
                    }
                }
            }
        }
    }

    func powerOff() async {
        _ = try? await lumixCommand([("mode", "camcmd"), ("value", "recmode")], timeout: 3)
        _ = try? await lumixCommand([("mode", "camcmd"), ("value", "poweroff")], timeout: 3)
    }

    // MARK: - Live view

    func enterRecMode() async {
        camera.isSwitchingMode = true
        defer { camera.isSwitchingMode = false }
        do {
            _ = try? await lumixCommand([("mode", "stopstream")], timeout: 3)
            try await lumixCommand([("mode", "camcmd"), ("value", "recmode")], timeout: 5)
            camera.mode = .rec
            // The new size only applies to the next startstream.
            let size = camera.liveViewQuality == "0320x0240" ? "qvga" : "vga"
            _ = try? await lumixCommand([("mode", "setsetting"), ("type", "liveviewsize"), ("value", size)])
            try? await Task.sleep(for: .milliseconds(300))
            await camera.refreshProperties()
            await camera.startLiveView()
        } catch {
            camera.report(error)
        }
    }

    func startLiveView() async {
        do {
            lumix.lastStreamKick = Date()
            try await lumixCommand([("mode", "startstream"), ("value", String(camera.udpPort))])
        } catch {
            camera.liveViewRunning = false
            camera.report(error)
        }
    }

    func stopLiveView() async {
        _ = try? await lumixCommand([("mode", "stopstream")], timeout: 3)
    }

    // MARK: - Settings

    func refreshProperties() async {
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
            let options = (-15...15).map(ExposureText.ev(thirds:))
            let value = ExposureText.ev(Self.lumixFraction(raw))
            result["expcomp"] = CameraProperty(name: "expcomp", settable: true, value: value, options: options)
        }
        if let raw = await current("whitebalance") {
            // Colour temperature has its own setting (it needs a Kelvin value).
            let names = (lumix.menu["whitebalance"] ?? PanasonicSession.whiteBalanceFallback)
                .filter { lumix.kelvin == nil || $0 != "color_temp" }
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
        // Bodies whose controls are physical or fixed: show the values, don't offer to change them.
        if let profile = camera.profile {
            if profile.fixedExposure {
                result["focalvalue"]?.settable = false
                result["shutspeedvalue"]?.settable = false
            }
            if profile.noExposureComp { result["expcomp"]?.settable = false }
            if profile.noISO { result["isospeedvalue"]?.settable = false }
        }
        if lumix.settingsReadAt.map({ Date().timeIntervalSince($0) > 15 }) ?? true { await readLumixSettings() }
        for (name, property) in lumix.settingProperties where result[name] == nil { result[name] = property }
        // The dial decides which of these the camera sets itself.
        if let mode = result["takemode"]?.value {
            if ["P", "iAuto", "A"].contains(mode) { result["shutspeedvalue"]?.settable = false }
            if ["P", "iAuto", "S"].contains(mode) { result["focalvalue"]?.settable = false }
        }
        camera.properties = result
    }

    func setProperty(_ name: String, to value: String, reportErrors: Bool) async -> Bool {
        if let extra = lumix.settings.first(where: { $0.name == name }) {
            return await setLumixSetting(extra, to: value, reportErrors: reportErrors)
        }
        if name == LumixMenu.kelvinName, lumix.kelvin != nil {
            return await setLumixKelvin(value, reportErrors: reportErrors)
        }
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
            if reportErrors { camera.lastError = "This setting can't be changed on a LUMIX camera from the app." }
            return false
        }
        let ok = await camera.optimisticallySet(name, to: value, reportErrors: reportErrors) {
            try await lumixCommand([("mode", "setsetting"), ("type", setting.type), ("value", setting.value)])
        }
        await refreshProperties()
        return ok
    }

    private func lumixApertureOptions() -> [String] {
        var codes: [String: Int] = [:]
        var options: [String] = []
        let lens = lumix.lens
        if let widest = lens.minFNumber, let widestCode = lens.minFNumberCode {
            let label = ExposureText.aperture(widest)
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

    /// "-1/3" → -0.333, "2" → 2.
    static func lumixFraction(_ text: String) -> Double {
        let parts = text.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, parts[1] != 0 { return parts[0] / parts[1] }
        return parts.first ?? 0
    }

    // MARK: - Focus & shooting

    func focus(at point: CGPoint) async {
        // Touch AF in a 0–1000 grid over the live-view frame.
        let x = Int((point.x * 1000).rounded()), y = Int((point.y * 1000).rounded())
        do {
            try await lumixCommand([("mode", "camctrl"), ("type", "touch"), ("value", "\(x)/\(y)"), ("value2", "on")])
        } catch let error as PanasonicError where error.code == "err_param" {
            // Older bodies use touchaf.
            _ = try? await lumixCommand([("mode", "camctrl"), ("type", "touchaf"), ("value", "\(x)/\(y)")])
        } catch {
            camera.report(error)
        }
    }

    func releaseFocus() async {
        _ = try? await lumixCommand([("mode", "camctrl"), ("type", "touch"), ("value", "0/0"), ("value2", "off")])
    }

    func shutterPressed() async {
        let seconds = camera.beginShot()
        defer { camera.endShot() }
        do {
            try await lumixCommand([("mode", "camcmd"), ("value", "capture")], timeout: 10)
            // capture returns straight away; keep the countdown honest for long exposures.
            if seconds >= 1 { try? await Task.sleep(for: .seconds(seconds + 0.5)) }
            camera.shotCounter += 1
            // LUMIX can't send files during live view: auto-save takes it from the card later.
            camera.autoSaveLater()
            _ = try? await lumixCommand([("mode", "camcmd"), ("value", "autoreviewunlock")], timeout: 3, log: false)
        } catch {
            camera.report(error)
        }
    }

    /// Bulb: first tap opens the shutter, second tap closes it.
    func toggleOpenExposure() async {
        if camera.isShooting {
            _ = try? await lumixCommand([("mode", "camcmd"), ("value", "capture_cancel")])
            camera.isShooting = false
            camera.exposureStartedAt = nil
            camera.shotCounter += 1
            camera.autoSaveLater()
            return
        }
        camera.isShooting = true
        camera.exposureStartedAt = Date()
        camera.exposureDuration = nil
        do {
            try await lumixCommand([("mode", "camcmd"), ("value", "capture")], timeout: 10)
        } catch {
            camera.isShooting = false
            camera.exposureStartedAt = nil
            camera.report(error)
        }
    }

    func toggleMovie() async {
        if camera.isRecordingMovie {
            _ = try? await lumixCommand([("mode", "camcmd"), ("value", "video_recstop")])
            camera.setRecordingMovie(false)
        } else {
            do {
                try await lumixCommand([("mode", "camcmd"), ("value", "video_recstart")])
                camera.setRecordingMovie(true)
            } catch {
                camera.report(error)
            }
        }
    }

    // LUMIX review images need playback mode, which would stop live view, so there's no quick review,
    // and the clock can't be set over Wi-Fi: both are off in `capabilities`.

    // MARK: - Card (UPnP ContentDirectory)

    func openGallery() async {
        do {
            try await lumixCommand([("mode", "camcmd"), ("value", "playmode")], timeout: 5)
            camera.mode = .play
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
            camera.images = found.sorted { ($0.date, $0.name) > ($1.date, $1.name) }
            camera.cardFolders = [CardFolder(path: "LUMIX", name: camera.cameraName ?? "LUMIX", count: camera.images.count, isForeign: false)]
        } catch {
            camera.galleryError = CameraModel.describe(error, host: camera.connectionHost)
        }
    }

    func thumbnail(for image: CameraImage) async -> UIImage? { await client.thumbnail(for: image) }
    func preview(for image: CameraImage) async throws -> UIImage { try await client.preview(for: image) }
    func downloadOriginal(_ image: CameraImage) async throws -> Data { try await client.fetch(image.urls?.original, timeout: 300) }

    private var lumixHostIP: String { camera.connectionHost.split(separator: ":").first.map(String.init) ?? camera.connectionHost }

    /// Finds the ContentDirectory control URL from the camera's UPnP device description.
    private func lumixContentDirectory() async throws -> URL {
        if let known = lumix.contentDirectory { return known }
        let base = "http://\(lumixHostIP):60606"
        for path in ["/Server0/ddd", "/Lumix/Server0/ddd"] {
            guard let data = try? await client.fetch(URL(string: base + path), timeout: 5),
                  let root = MiniXML.parse(data) else { continue }
            rememberContentDirectory(root, base: base)
            if let url = lumix.contentDirectory { return url }
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

import Foundation
import Security
#if !targetEnvironment(macCatalyst)
import NetworkExtension
#endif

/// A camera's own Wi-Fi network: what the camera shows under its QR code.
struct CameraNetwork: Equatable, Sendable {
    var ssid: String
    var password: String
}

// MARK: - Joining (iPhone and iPad)

/// Joins the camera's network from inside the app (NEHotspotConfiguration, the Hotspot Configuration
/// capability). iOS asks once per network ("Shutterlink wants to join…"). On a Mac the user joins it in
/// System Settings, so this isn't offered there.
enum CameraWiFi {
    #if targetEnvironment(macCatalyst)
    static let canJoin = false
    #else
    static let canJoin = true
    #endif

    static func join(_ network: CameraNetwork) async throws {
        #if targetEnvironment(macCatalyst)
        throw CameraError("Join the camera's Wi-Fi in System Settings ▸ Wi-Fi.")
        #else
        let ssid = network.ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty else { throw CameraError("Type the camera's Wi-Fi name first.") }
        let configuration = network.password.isEmpty
            ? NEHotspotConfiguration(ssid: ssid)
            : NEHotspotConfiguration(ssid: ssid, passphrase: network.password, isWEP: false)
        // Kept (not join-once) so iOS treats it like a network joined in Settings: join-once networks
        // drop 15 s after the app leaves the screen, which would end a Watch-triggered shoot.
        configuration.joinOnce = false
        do {
            try await NEHotspotConfigurationManager.shared.apply(configuration)
            try await waitUntilOn(ssid)
        } catch let error as NSError where error.domain == NEHotspotConfigurationErrorDomain {
            switch NEHotspotConfigurationError(rawValue: error.code) {
            case .alreadyAssociated:
                return
            case .userDenied:
                throw CameraError("You chose not to join \(ssid). Tap the camera again and choose Join.")
            case .invalidWPAPassphrase:
                throw CameraError("That password isn't one Wi-Fi accepts (8–63 characters). Check it on the camera.")
            case .invalidSSID:
                throw CameraError("\"\(ssid)\" isn't a Wi-Fi name iOS accepts. Check it on the camera.")
            case .applicationIsNotInForeground:
                throw CameraError("Shutterlink can only join the camera's Wi-Fi while it's on screen.")
            default:
                let reason = error.localizedDescription.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                throw CameraError("iOS couldn't join \(ssid) (\(reason)). Join it in Settings ▸ Wi-Fi instead.")
            }
        }
        #endif
    }

    #if !targetEnvironment(macCatalyst)
    /// `apply` can report success while iOS stays on the network it was on (seen with a PEN-F, home
    /// Wi-Fi on the same 192.168.0.x range). Waits until iOS says it's on the camera's network and has
    /// an address there, so the first request doesn't go to the home network.
    private static func waitUntilOn(_ ssid: String) async throws {
        let deadline = Date().addingTimeInterval(20)
        var lastSeen: String?
        var everAnswered = false
        while Date() < deadline {
            let current = await NEHotspotNetwork.fetchCurrent()
            if let current { everAnswered = true; lastSeen = current.ssid }
            if current?.ssid == ssid, NetworkInfo.wifiAddress() != nil {
                debugLog("wifi: on \(ssid) at \(NetworkInfo.wifiAddress() ?? "?")")
                // A moment for the camera to see the new client before the first request.
                try? await Task.sleep(for: .seconds(1))
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        debugLog("wifi: still not on \(ssid) after 20 s (current: \(lastSeen ?? "unknown"))")
        guard everAnswered else { return }   // iOS wouldn't say which network it's on: try anyway.
        if let lastSeen {
            throw CameraError("iOS stayed on \(lastSeen) instead of joining \(ssid). Check the camera's Wi-Fi is still on, then try again, or join it in Settings ▸ Wi-Fi.")
        }
        throw CameraError("iOS didn't join \(ssid). Check the camera's Wi-Fi is still on, then try again, or join it in Settings ▸ Wi-Fi.")
    }
    #endif
}

// MARK: - The QR code on the camera's screen

/// Reads a camera's Wi-Fi QR code. Cameras show the network name and password both as text and as a
/// QR code, but most brands don't document the code's contents, so this reads the formats that are
/// known and otherwise leaves the user to type what the camera shows under the code.
enum WiFiQRCode {
    /// The brand a code's format gives away (Olympus' OIS codes, Sony's W01 codes).
    static func brand(for text: String) -> CameraBrand? {
        let upper = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper.hasPrefix("OIS") { return .olympus }
        if upper.hasPrefix("W01:") { return .sony }
        return nil
    }

    static func parse(_ text: String) -> CameraNetwork? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // The common Wi-Fi QR format: WIFI:S:<name>;T:WPA;P:<password>;;
        if trimmed.uppercased().hasPrefix("WIFI:") {
            let fields = fields(in: String(trimmed.dropFirst(5)))
            guard let ssid = fields["S"], !ssid.isEmpty else { return nil }
            return CameraNetwork(ssid: ssid, password: fields["P"] ?? "")
        }
        // Olympus / OM System: OIS1,<name>,<password>, each scrambled (see `olympusDecode`).
        if trimmed.uppercased().hasPrefix("OIS") {
            let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3 else { return nil }
            let ssid = olympusDecode(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let password = olympusDecode(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ssid.isEmpty else { return nil }
            return CameraNetwork(ssid: ssid, password: password)
        }
        // Sony bodies: W01:S:<name>;P:<password>;C:<model>;M:<MAC>; with the name given without its
        // DIRECT- prefix. Not yet checked on a real Sony camera; the fields stay editable.
        if trimmed.uppercased().hasPrefix("W01:") {
            let fields = fields(in: String(trimmed.dropFirst(4)))
            guard var ssid = fields["S"], !ssid.isEmpty, let password = fields["P"] else { return nil }
            if !ssid.uppercased().hasPrefix("DIRECT-") { ssid = "DIRECT-" + ssid }
            return CameraNetwork(ssid: ssid, password: password)
        }
        return nil
    }

    /// Olympus scrambles the name and password by mirroring each character in this alphabet (first ↔
    /// last, second ↔ second-to-last…). Worked out from a real PEN-F's code against the name and password
    /// it shows (PEN-F-P-BHNA17694 → GRI1Q1G1UOIV-YZW%, 50703650 → $/Y/*Z$/). Only the `+` (the slot
    /// paired with "2") hasn't been seen yet; characters outside the alphabet are kept as they are.
    private static let olympusAlphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ$%*+-/")

    static func olympusDecode(_ text: String) -> String {
        let last = olympusAlphabet.count - 1
        return String(text.map { character in
            guard let index = olympusAlphabet.firstIndex(of: character) else { return character }
            return olympusAlphabet[last - index]
        })
    }

    /// `K:value;K:value;` with `\` escaping `;`, `:`, `,`, `"` and `\`.
    private static func fields(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = "", value = "", readingKey = true, escaped = false
        func finish() {
            if !key.isEmpty, result[key] == nil { result[key] = value }
            key = ""; value = ""; readingKey = true
        }
        for character in text {
            if escaped {
                if readingKey { key.append(character) } else { value.append(character) }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == ";" {
                finish()
            } else if character == ":" && readingKey {
                readingKey = false
            } else if readingKey {
                key.append(character)
            } else {
                value.append(character)
            }
        }
        finish()
        return result
    }
}

// MARK: - Saved passwords

/// Camera Wi-Fi passwords, in the Keychain on this device, keyed by network name.
enum CameraWiFiPasswords {
    private static let service = "com.apexcommerce.shutterlink.camera-wifi"

    static func save(_ password: String, for ssid: String) {
        delete(for: ssid)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(password.utf8),
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { debugLog("keychain: couldn't save the password for \(ssid) (\(status))") }
    }

    static func password(for ssid: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(for ssid: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Joining, then connecting

extension CameraModel {
    /// Joins `network`, showing progress like a connection does. Returns false (with `lastError` set)
    /// when iOS couldn't join it.
    func join(_ network: CameraNetwork) async -> Bool {
        guard CameraWiFi.canJoin, phase == .disconnected else { return true }
        phase = .connecting
        lastError = nil
        status = "Joining \(network.ssid)…"
        debugLog("wifi: joining \(network.ssid)")
        defer {
            phase = .disconnected
            status = nil
        }
        do {
            try await CameraWiFi.join(network)
            joinedNetwork = network
            return true
        } catch {
            debugLog("wifi: \(error.localizedDescription)")
            lastError = error.localizedDescription
            return false
        }
    }

    /// The Add a camera sheet's Connect: joins the typed or scanned network first when there is one.
    func joinAndConnect() async {
        let network = CameraNetwork(ssid: wifiSSID.trimmingCharacters(in: .whitespacesAndNewlines),
                                    password: wifiPassword)
        guard CameraWiFi.canJoin, !network.ssid.isEmpty else {
            await connect()
            return
        }
        guard await join(network) else { return }
        await connect(waitingUntil: Date().addingTimeInterval(30))
    }

    /// The network saved with this camera, if Shutterlink joined it before.
    func savedNetwork(for saved: SavedCamera) -> CameraNetwork? {
        guard CameraWiFi.canJoin, let ssid = saved.ssid, !ssid.isEmpty else { return nil }
        return CameraNetwork(ssid: ssid, password: CameraWiFiPasswords.password(for: ssid) ?? "")
    }

    /// Fills Add a camera from a scanned QR code. Returns false when the code isn't one Shutterlink reads.
    func applyScannedCode(_ text: String) -> Bool {
        // The request log shows what the code said, so a brand's format can be added from a real camera.
        debugLog("wifi QR: \(text)")
        let network = WiFiQRCode.parse(text)
        appendLog(LogEntry(date: Date(), method: "QR", path: text.trimmingCharacters(in: .whitespacesAndNewlines),
                           status: network == nil ? nil : 200, millis: 0,
                           summary: network.map { "Wi-Fi \($0.ssid)" } ?? "not a code Shutterlink reads yet"))
        guard let network else { return false }
        wifiSSID = network.ssid
        wifiPassword = network.password
        if let brand = WiFiQRCode.brand(for: text) { setBrand(brand) }
        return true
    }

    /// Scan to connect: reads the code, joins the camera's Wi-Fi and connects, all in one go. Codes
    /// that don't say the brand use automatic detection. Returns false when the code isn't readable.
    func connectFromScannedCode(_ text: String) -> Bool {
        guard phase == .disconnected else { return false }
        if WiFiQRCode.brand(for: text) == nil { setBrand(nil) }
        guard applyScannedCode(text) else { return false }
        Task { await joinAndConnect() }
        return true
    }
}

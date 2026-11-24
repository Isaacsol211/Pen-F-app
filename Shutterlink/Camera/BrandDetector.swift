import Foundation
import Network

/// Works out which brand of camera is on the other end, so friends don't have to pick.
///
/// Each brand's camera access point uses its own subnet (Olympus 192.168.0.x, LUMIX 192.168.54.x,
/// Sony 192.168.122.x, Nikon and Canon 192.168.1.x), so the phone's own Wi-Fi address narrows it
/// down. Then the app asks each candidate a harmless read-only question in its own protocol
/// (camera info, state, API list); nothing here takes a picture or changes a setting.
enum BrandDetector {
    typealias Found = (brand: CameraBrand, host: String)

    /// The brands whose camera networks use this phone address's subnet, most likely first.
    static func candidates(forWiFi address: String?) -> [CameraBrand] {
        guard let address else { return CameraBrand.allCases }
        if address.hasPrefix("192.168.0.") { return [.olympus] }
        if address.hasPrefix("192.168.54.") { return [.panasonic] }
        if address.hasPrefix("192.168.122.") { return [.sony] }
        if address.hasPrefix("192.168.1.") { return [.nikon, .canon] }
        return CameraBrand.allCases
    }

    /// With `host` empty: probe each candidate brand at its usual address. With a host (a mock, or a
    /// camera on another network): ask that address in every protocol.
    static func detect(host: String) async -> Found? {
        if let found = await detectOnce(host: host) { return found }
        // The first try can fail while iOS shows the Local Network prompt.
        try? await Task.sleep(for: .milliseconds(1500))
        return await detectOnce(host: host)
    }

    private static func detectOnce(host: String) async -> Found? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        let targets: [Found] = trimmed.isEmpty
            ? candidates(forWiFi: NetworkInfo.wifiAddress()).flatMap { brand in brand.likelyHosts.map { (brand, $0) } }
            : CameraBrand.allCases.map { ($0, trimmed) }
        // Ask everyone at once; prefer the HTTP brands' answers, which are specific, over Nikon's
        // bare "something listens on the PTP/IP port".
        let results = await withTaskGroup(of: (Int, Found?).self) { group in
            for (index, target) in targets.enumerated() {
                group.addTask {
                    (await probe(target.brand, host: target.host)) ? (index, target) : (index, nil)
                }
            }
            var found: [(Int, Found)] = []
            for await (index, target) in group { if let target { found.append((index, target)) } }
            return found
        }
        let ranked = results.sorted { a, b in
            let aWeak = a.1.brand == .nikon, bWeak = b.1.brand == .nikon
            return aWeak != bWeak ? !aWeak : a.0 < b.0
        }
        return ranked.first?.1
    }

    static func notFoundMessage(wifi: String?) -> String {
        guard let wifi else {
            return "This \(Platform.device) isn't on Wi-Fi. Turn on the camera's smartphone Wi-Fi, join its network in \(Platform.settings) ▸ Wi-Fi, then \(Platform.tap) Connect."
        }
        return "No camera answered (this \(Platform.device) is at \(wifi)). Check that \(Platform.settings) ▸ Wi-Fi shows the camera's network and that Local Network is on for this app in \(Platform.settings) ▸ Privacy & Security, or pick your brand above."
    }

    // MARK: - Probes

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.allowsCellularAccess = false
        return URLSession(configuration: config)
    }()

    static func probe(_ brand: CameraBrand, host: String) async -> Bool {
        switch brand {
        case .olympus:
            let body = await get("http://\(host)/get_caminfo.cgi", userAgent: "OI.Share v2")
            return body?.contains("<model>") == true || body?.contains("<caminfo>") == true
        case .panasonic:
            let body = await get("http://\(host)/cam.cgi?mode=getinfo&type=capability", userAgent: "LUMIX Sync")
            return body.map { $0.contains("camrply") || $0.hasPrefix("ok,") || $0.hasPrefix("err_") } ?? false
        case .canon:
            let body = await get("http://\(host)/ccapi", userAgent: "Shutterlink")
            return body?.contains("\"ver100\"") == true
        case .sony:
            let body = await post("http://\(host)/sony/camera",
                                  json: ["method": "getVersions", "params": [], "id": 1, "version": "1.0"])
            return body?.contains("\"result\"") == true
        case .nikon:
            let (name, port) = PTPIPClient.split(host, defaultPort: 15740)
            return await tcpOpens(host: name, port: port)
        }
    }

    private static func get(_ address: String, userAgent: String) async -> String? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode ?? 0 < 500 else { return nil }
        return String(decoding: data.prefix(4000), as: UTF8.self)
    }

    private static func post(_ address: String, json: [String: Any]) async -> String? {
        guard let url = URL(string: address), let body = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return String(decoding: data.prefix(4000), as: UTF8.self)
    }

    /// Whether a TCP connection opens within 3 s (and then closes it again without sending anything).
    static func tcpOpens(host: String, port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let once = OnceFlag()
        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ ok: Bool) {
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: ok)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled, .waiting: finish(false)
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(false) }
        }
    }
}

/// Lets exactly one caller through (for continuations that several callbacks race to resume).
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}

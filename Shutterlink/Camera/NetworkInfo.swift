import Foundation
#if targetEnvironment(macCatalyst)
import Network
#endif

enum NetworkInfo {
    /// Whether `host` is on the local network: a private, link-local or loopback IP address, an
    /// unqualified name or a .local name. Cameras only speak plain HTTP (and PTP/IP) on their own Wi-Fi,
    /// so every connection is checked against this and nothing unencrypted ever goes to the internet,
    /// even if a typed address or a camera's reply points elsewhere.
    static func isLocal(_ host: String) -> Bool {
        let name = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if name == "localhost" || name.hasSuffix(".local") { return true }
        let octets = name.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        if octets.count == 4, octets.allSatisfy({ $0 != nil && (0...255).contains($0!) }) {
            let a = octets[0]!, b = octets[1]!
            return a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
                || (a == 169 && b == 254)
        }
        if name.contains(":") {   // IPv6: loopback, link-local (fe80::/10), unique local (fc00::/7)
            return name == "::1" || name.hasPrefix("fe8") || name.hasPrefix("fe9") || name.hasPrefix("fea")
                || name.hasPrefix("feb") || name.hasPrefix("fc") || name.hasPrefix("fd")
        }
        // An unqualified name (no dots) can only be resolved on the local network.
        return !name.isEmpty && !name.contains(".") && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// IPv4 address of this iPhone's Wi-Fi interface (en0), or nil when it isn't on Wi-Fi.
    /// The PEN-F hands out 192.168.0.x addresses when it is the access point.
    static func wifiAddress() -> String? {
        #if targetEnvironment(macCatalyst)
        let wifiName = WiFiInterface.shared.name ?? "en0"
        #else
        let wifiName = "en0"
        #endif
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.ifa_name) == wifiName else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            if result == 0 {
                return host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            }
        }
        return nil
    }
}

#if targetEnvironment(macCatalyst)
/// The Mac's Wi-Fi interface. On a laptop it's en0, but a desktop with Ethernet has Ethernet on
/// en0 and Wi-Fi on en1, so ask Network for the interface it calls Wi-Fi.
final class WiFiInterface: @unchecked Sendable {
    static let shared = WiFiInterface()

    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let lock = NSLock()
    private var current: String?

    /// nil until the first path update (a few milliseconds after launch) or while Wi-Fi is off.
    var name: String? { lock.withLock { current } }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let name = path.availableInterfaces.first { $0.type == .wifi }?.name
            guard let self else { return }
            self.lock.withLock { self.current = name }
        }
        monitor.start(queue: DispatchQueue(label: "shutterlink.wifi-interface"))
    }
}
#endif

/// Unbuffered debug output, visible with `xcrun devicectl device process launch --console`.
func debugLog(_ message: String) {
    FileHandle.standardError.write(Data("[Shutterlink] \(message)\n".utf8))
}

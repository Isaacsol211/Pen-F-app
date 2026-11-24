import Darwin
import Foundation
#if targetEnvironment(macCatalyst)
import Network
#endif

enum NetworkInfo {
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
    var name: String? {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let name = path.availableInterfaces.first { $0.type == .wifi }?.name
            guard let self else { return }
            self.lock.lock(); self.current = name; self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "shutterlink.wifi-interface"))
    }
}
#endif

/// Unbuffered debug output, visible with `xcrun devicectl device process launch --console`.
func debugLog(_ message: String) {
    FileHandle.standardError.write(Data("[Shutterlink] \(message)\n".utf8))
}

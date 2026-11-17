import Darwin
import Foundation

enum NetworkInfo {
    /// IPv4 address of this iPhone's Wi-Fi interface (en0), or nil when it isn't on Wi-Fi.
    /// The PEN-F hands out 192.168.0.x addresses when it is the access point.
    static func wifiAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.ifa_name) == "en0" else { continue }
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

/// Unbuffered debug output, visible with `xcrun devicectl device process launch --console`.
func debugLog(_ message: String) {
    FileHandle.standardError.write(Data("[PENF] \(message)\n".utf8))
}

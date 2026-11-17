import Foundation

/// Which camera family the app is talking to. Each speaks its own Wi-Fi protocol.
enum CameraBrand: String, CaseIterable, Identifiable {
    case olympus
    case panasonic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .olympus: "Olympus"
        case .panasonic: "Panasonic LUMIX"
        }
    }

    var shortTitle: String {
        switch self {
        case .olympus: "Olympus"
        case .panasonic: "LUMIX"
        }
    }

    /// The camera's own address on its Wi-Fi network.
    var defaultHost: String {
        switch self {
        case .olympus: "192.168.0.10"
        case .panasonic: "192.168.54.1"
        }
    }

    /// What the camera's Wi-Fi network is called, for instructions and errors.
    var ssidHint: String {
        switch self {
        case .olympus: "PEN-F-P-…"
        case .panasonic: "GH5-… (the camera's name)"
        }
    }

    var liveViewFormat: LiveViewFormat {
        switch self {
        case .olympus: .olympusRTP
        case .panasonic: .jpegPerDatagram
        }
    }
}

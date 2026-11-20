import Foundation

/// Which camera family the app is talking to. Each speaks its own Wi-Fi protocol; the driver for
/// each lives in its own file (OlympusDriver, Panasonic, Nikon, Canon, Sony).
enum CameraBrand: String, CaseIterable, Identifiable {
    case olympus
    case panasonic
    case nikon
    case canon
    case sony

    var id: String { rawValue }

    var title: String {
        switch self {
        case .olympus: "Olympus / OM"
        case .panasonic: "Panasonic LUMIX"
        case .nikon: "Nikon"
        case .canon: "Canon"
        case .sony: "Sony"
        }
    }

    var shortTitle: String {
        switch self {
        case .olympus: "Olympus"
        case .panasonic: "LUMIX"
        case .nikon: "Nikon"
        case .canon: "Canon"
        case .sony: "Sony"
        }
    }

    /// The camera's own address on its Wi-Fi network (with the port when it isn't 80).
    var defaultHost: String {
        switch self {
        case .olympus: "192.168.0.10"
        case .panasonic: "192.168.54.1"
        case .nikon: "192.168.1.1"
        case .canon: "192.168.1.2:8080"
        case .sony: "192.168.122.1:8080"
        }
    }

    /// Addresses to try when auto-detecting: the default, then others seen in the wild.
    var likelyHosts: [String] {
        switch self {
        case .canon: ["192.168.1.2:8080", "192.168.1.1:8080"]   // shown on the camera as the "CCAPI top URL"
        case .sony: ["192.168.122.1:8080", "192.168.122.1:10000"]
        default: [defaultHost]
        }
    }

    /// What the camera's Wi-Fi network is called, for instructions and errors.
    var ssidHint: String {
        switch self {
        case .olympus: "the camera's network (E-M10-P-…, PEN-F-P-…, OM-1-P-…)"
        case .panasonic: "the camera's network (GH5-…, G9-…, the camera's name)"
        case .nikon: "the camera's network (Nikon_WU2_…, Z_50_…, the camera's name)"
        case .canon: "the camera's network (EOSR6-…, the camera's name)"
        case .sony: "the camera's network (DIRECT-xxxx:ILCE-…)"
        }
    }

    /// Live-view sizes to offer before connecting (the camera's own list replaces these).
    var defaultLiveViewSizes: [String] {
        switch self {
        case .olympus: ["0320x0240", "0640x0480", "0800x0600", "1024x0768", "1280x0960"]
        case .panasonic: ["0320x0240", "0640x0480"]   // LUMIX: qvga or vga
        case .nikon, .canon, .sony: []                 // one size, chosen by the camera
        }
    }

    /// What to expect before connecting; the driver's own list replaces it once connected.
    var defaultCapabilities: CameraCapabilities {
        switch self {
        case .olympus:
            CameraCapabilities(liveViewSizes: defaultLiveViewSizes, openEndedExposure: true, movie: true,
                               lastShotReview: true, clockSync: true, highResShot: true, powerOff: true,
                               userAgentChoice: true)
        case .panasonic:
            CameraCapabilities(liveViewSizes: defaultLiveViewSizes, openEndedExposure: true, movie: true,
                               videoSwitch: true, powerOff: true)
        case .nikon:
            CameraCapabilities(tapToFocus: true)
        case .canon:
            CameraCapabilities(tapToFocus: true, movie: true, videoSwitch: true)
        case .sony:
            CameraCapabilities(tapToFocus: true, movie: true, videoSwitch: true)
        }
    }

    /// Drivers tried only against mock cameras so far.
    var isBeta: Bool { [.nikon, .canon, .sony].contains(self) }

    /// Which bodies this covers, under the brand's name when adding a camera.
    var coverage: String {
        switch self {
        case .olympus: "OM-D, PEN, Tough and OM System bodies with Wi-Fi"
        case .panasonic: "G, GH, GX, GF, S and compact bodies with Wi-Fi"
        case .nikon: "Z bodies and DSLRs with Wi-Fi"
        case .canon: "EOS bodies with Canon's CCAPI unlocked"
        case .sony: "Alpha and RX bodies with Smart Remote, up to about 2019"
        }
    }

    /// How far the app gets with this brand, shown on the Connect screen.
    var supportNote: String? {
        switch self {
        case .olympus: nil
        case .panasonic: "Tested against a mock GH5; not yet on a real LUMIX."
        case .nikon: "Experimental: tested against a mock camera only."
        case .canon: "Experimental: needs Canon's CCAPI unlocked on the camera first. Tested against a mock only."
        case .sony: "Experimental: older bodies with Smart Remote Control only. Tested against a mock only."
        }
    }
}

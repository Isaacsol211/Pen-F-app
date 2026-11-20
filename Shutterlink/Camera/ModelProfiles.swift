import Foundation

// What the app knows about each Wi-Fi Olympus / OM System and Panasonic LUMIX body, beyond what the
// camera reports about itself. Most differences come from the camera at connect time (Olympus lists
// its commands, live-view sizes and settable properties; LUMIX lists its menu values), so this
// table only holds what the camera doesn't say: which features exist, pairing quirks, and notes.
//
// Sources (see README "Supported cameras"): OPC protocol spec, olympus-wifi, omcap, OM System
// manuals, PhotoSync's camera lists; GMaster's camera profiles, libgphoto2's LUMIX driver,
// lumix-remote, liblumix, Panasonic's Image App / LUMIX Sync support pages.

enum SupportLevel: String {
    case hardware = "Tested on this camera"
    case mock = "Tested against a mock camera only"
    case researched = "Researched, not yet tried on this camera"
    case unsupported = "Not supported"
}

/// How a LUMIX body lets a phone in.
enum LumixPairing {
    /// No pairing request (GH3, GH4): just start sending commands.
    case none
    /// `accctrl req_acc`, with a Yes/No prompt on the camera the first time.
    case standard
    /// `req_acc_g` / `req_acc_e` and an `X-SESSION_ID` header (S5IIX, G9 II…). Unverified.
    case newer
}

struct ModelProfile {
    let brand: CameraBrand
    /// As people know it, e.g. "E-M10 Mark III", "LUMIX GX80 / GX85".
    let name: String
    /// What the camera may report (Olympus `get_caminfo` model, LUMIX UPnP modelNumber), any spelling.
    let aliases: [String]
    let year: Int
    var support: SupportLevel = .researched
    /// Shown once after connecting, and in the request log.
    var notes: [String] = []
    /// Remote shooting isn't possible; the reason, shown instead of connecting.
    var unsupportedReason: String?

    // Olympus
    var highResShot = false

    // LUMIX
    var pairing: LumixPairing = .standard
    /// Aperture and shutter can't be set over Wi-Fi (compacts with fixed controls).
    var fixedExposure = false
    var noExposureComp = false
    var noISO = false
    var noVideo = false

    /// "E-M10 Mark III", "E-M10MarkIII", "DC-GX80", "DMC-GX80 (mock)" → comparable keys.
    static func key(_ text: String) -> String {
        var s = text.uppercased()
        if let paren = s.firstIndex(of: "(") { s = String(s[..<paren]) }
        for prefix in ["OLYMPUS ", "OM SYSTEM ", "OMSYSTEM ", "PANASONIC ", "LUMIX ", "DMC-", "DC-"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        s = s.replacingOccurrences(of: "MARK", with: "")
        return s.filter { $0.isLetter || $0.isNumber }
    }
}

enum ModelProfiles {
    /// The profile for what the camera reported, if this body is in the table.
    static func find(_ brand: CameraBrand, reported: String?) -> ModelProfile? {
        guard let reported, !reported.isEmpty else { return nil }
        let key = ModelProfile.key(reported)
        return all.first { $0.brand == brand && $0.aliases.contains { ModelProfile.key($0) == key } }
    }

    static func profiles(for brand: CameraBrand) -> [ModelProfile] { all.filter { $0.brand == brand } }

    private static let om = "OM System bodies: start Device Connection on the camera (Bluetooth can stay off). OM System says remote shooting is partly limited, and its app may speak a newer protocol: this body hasn't been tried with Shutterlink yet."
    private static let proRemote = "Olympus may restrict remote shooting from other apps on this body (other apps only offer downloads). If controls are refused, use OI.Share."
    private static let newerPairing = "This body may use the newer LUMIX pairing, which is experimental in Shutterlink. Since the 2025 firmware the camera's Wi-Fi always has a password, shown on the camera."

    static let all: [ModelProfile] = olympus + panasonic

    static let olympus: [ModelProfile] = [
        ModelProfile(brand: .olympus, name: "PEN E-P5", aliases: ["E-P5"], year: 2013),
        ModelProfile(brand: .olympus, name: "OM-D E-M1", aliases: ["E-M1"], year: 2013,
                     notes: ["Remote control only works with the camera's Wi-Fi set to Private, not One-Time. Movie mode isn't available over Wi-Fi."]),
        ModelProfile(brand: .olympus, name: "Stylus 1 / 1s", aliases: ["STYLUS1", "STYLUS1S", "STYLUS1,1s"], year: 2013),
        ModelProfile(brand: .olympus, name: "OM-D E-M10", aliases: ["E-M10"], year: 2014),
        ModelProfile(brand: .olympus, name: "Stylus SH-1", aliases: ["SH-1"], year: 2014),
        ModelProfile(brand: .olympus, name: "Tough TG-3", aliases: ["TG-3"], year: 2014),
        ModelProfile(brand: .olympus, name: "PEN E-PL7", aliases: ["E-PL7"], year: 2014),
        ModelProfile(brand: .olympus, name: "OM-D E-M5 Mark II", aliases: ["E-M5MarkII", "E-M5 II"], year: 2015, highResShot: true),
        ModelProfile(brand: .olympus, name: "Stylus SH-2", aliases: ["SH-2"], year: 2015),
        ModelProfile(brand: .olympus, name: "Tough TG-4", aliases: ["TG-4"], year: 2015),
        ModelProfile(brand: .olympus, name: "Tough TG-860 / TG-870", aliases: ["TG-860", "TG-870"], year: 2015),
        ModelProfile(brand: .olympus, name: "OM-D E-M10 Mark II", aliases: ["E-M10MarkII", "E-M10 II"], year: 2015),
        ModelProfile(brand: .olympus, name: "AIR A01", aliases: ["AIR-A01", "A01", "AIR A01"], year: 2015,
                     support: .unsupported,
                     unsupportedReason: "The AIR A01 speaks Olympus's Open Platform API (switch_cameramode, newstarttake), which Shutterlink doesn't support yet."),
        ModelProfile(brand: .olympus, name: "PEN-F", aliases: ["PEN-F"], year: 2016, support: .hardware, highResShot: true),
        ModelProfile(brand: .olympus, name: "Stylus SH-3", aliases: ["SH-3"], year: 2016),
        ModelProfile(brand: .olympus, name: "PEN E-PL8", aliases: ["E-PL8"], year: 2016),
        ModelProfile(brand: .olympus, name: "OM-D E-M1 Mark II", aliases: ["E-M1MarkII", "E-M1 II"], year: 2016, highResShot: true),
        ModelProfile(brand: .olympus, name: "TG-Tracker", aliases: ["TG-Tracker"], year: 2016, support: .unsupported,
                     unsupportedReason: "The TG-Tracker works with OI.Track, not remote shooting."),
        ModelProfile(brand: .olympus, name: "Tough TG-5", aliases: ["TG-5"], year: 2017),
        ModelProfile(brand: .olympus, name: "OM-D E-M10 Mark III", aliases: ["E-M10MarkIII", "E-M10 III"], year: 2017),
        ModelProfile(brand: .olympus, name: "PEN E-PL9", aliases: ["E-PL9"], year: 2018),
        ModelProfile(brand: .olympus, name: "OM-D E-M1X", aliases: ["E-M1X"], year: 2019, notes: [proRemote], highResShot: true),
        ModelProfile(brand: .olympus, name: "Tough TG-6", aliases: ["TG-6"], year: 2019),
        ModelProfile(brand: .olympus, name: "OM-D E-M5 Mark III", aliases: ["E-M5MarkIII", "E-M5 III"], year: 2019, highResShot: true),
        ModelProfile(brand: .olympus, name: "PEN E-PL10", aliases: ["E-PL10"], year: 2019),
        ModelProfile(brand: .olympus, name: "OM-D E-M1 Mark III", aliases: ["E-M1MarkIII", "E-M1 III"], year: 2020, notes: [proRemote], highResShot: true),
        ModelProfile(brand: .olympus, name: "OM-D E-M10 Mark IV", aliases: ["E-M10MarkIV", "E-M10 IV"], year: 2020,
                     notes: ["Over Wi-Fi the E-M10 IV only changes mode, aperture, shutter, EV, ISO, white balance, drive, art filter and hue."]),
        ModelProfile(brand: .olympus, name: "PEN E-P7", aliases: ["E-P7"], year: 2021),
        ModelProfile(brand: .olympus, name: "OM System OM-1", aliases: ["OM-1"], year: 2022, notes: [om], highResShot: true),
        ModelProfile(brand: .olympus, name: "OM System OM-5", aliases: ["OM-5"], year: 2022, notes: [om], highResShot: true),
        ModelProfile(brand: .olympus, name: "OM System TG-7", aliases: ["TG-7"], year: 2023, notes: [om]),
        ModelProfile(brand: .olympus, name: "OM System OM-1 Mark II", aliases: ["OM-1MarkII", "OM-1 II"], year: 2024, notes: [om], highResShot: true),
        ModelProfile(brand: .olympus, name: "OM System OM-3", aliases: ["OM-3"], year: 2025, notes: [om], highResShot: true),
        ModelProfile(brand: .olympus, name: "OM System OM-5 Mark II", aliases: ["OM-5MarkII", "OM-5 II"], year: 2025, notes: [om], highResShot: true),
    ]

    static let panasonic: [ModelProfile] = [
        ModelProfile(brand: .panasonic, name: "LUMIX GH3", aliases: ["GH3"], year: 2012, pairing: .none),
        ModelProfile(brand: .panasonic, name: "LUMIX G6", aliases: ["G6"], year: 2013),
        ModelProfile(brand: .panasonic, name: "LUMIX GF6", aliases: ["GF6"], year: 2013, noISO: true),
        ModelProfile(brand: .panasonic, name: "LUMIX LF1", aliases: ["LF1"], year: 2013, noISO: true),
        ModelProfile(brand: .panasonic, name: "LUMIX GX7", aliases: ["GX7"], year: 2013),
        ModelProfile(brand: .panasonic, name: "LUMIX GM1 / GM1S", aliases: ["GM1", "GM1S"], year: 2013),
        ModelProfile(brand: .panasonic, name: "LUMIX TS5 / FT5", aliases: ["TS5", "FT5"], year: 2013),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ40 / ZS30", aliases: ["TZ40", "ZS30"], year: 2013),
        ModelProfile(brand: .panasonic, name: "LUMIX FZ70 / FZ72", aliases: ["FZ70", "FZ72"], year: 2013),
        ModelProfile(brand: .panasonic, name: "LUMIX GH4", aliases: ["GH4"], year: 2014, pairing: .none),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ60 / ZS40", aliases: ["TZ60", "ZS40", "TZ61"], year: 2014, fixedExposure: true),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ55 / ZS35", aliases: ["TZ55", "ZS35"], year: 2014, fixedExposure: true, noVideo: true),
        ModelProfile(brand: .panasonic, name: "LUMIX SZ8", aliases: ["SZ8"], year: 2014, fixedExposure: true, noVideo: true),
        ModelProfile(brand: .panasonic, name: "LUMIX LX100", aliases: ["LX100"], year: 2014,
                     notes: ["The LX100's aperture ring, shutter dial and EV dial are physical, so they can't be changed from the phone."],
                     fixedExposure: true, noExposureComp: true),
        ModelProfile(brand: .panasonic, name: "LUMIX FZ1000", aliases: ["FZ1000"], year: 2014),
        ModelProfile(brand: .panasonic, name: "LUMIX GM5", aliases: ["GM5"], year: 2014),
        ModelProfile(brand: .panasonic, name: "LUMIX G7 / G70", aliases: ["G7", "G70"], year: 2015),
        ModelProfile(brand: .panasonic, name: "LUMIX GF7", aliases: ["GF7"], year: 2015),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ70 / ZS50", aliases: ["TZ70", "ZS50", "TZ71"], year: 2015, noISO: true),
        ModelProfile(brand: .panasonic, name: "LUMIX FZ300 / FZ330", aliases: ["FZ300", "FZ330"], year: 2015),
        ModelProfile(brand: .panasonic, name: "LUMIX TS6 / FT6, TS30", aliases: ["TS6", "FT6", "TS30"], year: 2015),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ57 / ZS45", aliases: ["TZ57", "ZS45"], year: 2015, noVideo: true),
        ModelProfile(brand: .panasonic, name: "LUMIX SZ10", aliases: ["SZ10"], year: 2015, fixedExposure: true, noVideo: true),
        ModelProfile(brand: .panasonic, name: "LUMIX GX8", aliases: ["GX8"], year: 2015,
                     notes: ["The GX8's exposure compensation dial is physical, so EV can't be changed from the phone."],
                     noExposureComp: true),
        ModelProfile(brand: .panasonic, name: "LUMIX GX80 / GX85 / GX7 II", aliases: ["GX80", "GX85", "GX7MK2"], year: 2016),
        ModelProfile(brand: .panasonic, name: "LUMIX G80 / G85 / G81", aliases: ["G80", "G85", "G81"], year: 2016),
        ModelProfile(brand: .panasonic, name: "LUMIX GF8", aliases: ["GF8"], year: 2016),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ80 / ZS60", aliases: ["TZ80", "ZS60", "TZ81"], year: 2016),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ100 / ZS100", aliases: ["TZ100", "ZS100", "TZ101"], year: 2016),
        ModelProfile(brand: .panasonic, name: "LUMIX LX10 / LX15", aliases: ["LX10", "LX15"], year: 2016),
        ModelProfile(brand: .panasonic, name: "LUMIX FZ2000 / FZ2500", aliases: ["FZ2000", "FZ2500"], year: 2016),
        ModelProfile(brand: .panasonic, name: "LUMIX GH5", aliases: ["GH5"], year: 2017, support: .mock),
        ModelProfile(brand: .panasonic, name: "LUMIX GF9 / GX800 / GX850", aliases: ["GF9", "GX800", "GX850"], year: 2017),
        ModelProfile(brand: .panasonic, name: "LUMIX G9", aliases: ["G9"], year: 2017,
                     notes: ["High Resolution Mode can't be started from Shutterlink; set it on the camera."]),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ90 / ZS70", aliases: ["TZ90", "ZS70", "TZ91"], year: 2017),
        ModelProfile(brand: .panasonic, name: "LUMIX FZ80 / FZ82", aliases: ["FZ80", "FZ82"], year: 2017),
        ModelProfile(brand: .panasonic, name: "LUMIX GH5S", aliases: ["GH5S"], year: 2018),
        ModelProfile(brand: .panasonic, name: "LUMIX GX9 / GX7 III", aliases: ["GX9", "GX7MK3"], year: 2018),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ200 / ZS200", aliases: ["TZ200", "ZS200", "TZ202"], year: 2018),
        ModelProfile(brand: .panasonic, name: "LUMIX LX100 II", aliases: ["LX100M2", "LX100II"], year: 2018),
        ModelProfile(brand: .panasonic, name: "LUMIX GF10 / GF90", aliases: ["GF10", "GF90"], year: 2018),
        ModelProfile(brand: .panasonic, name: "LUMIX FT7 / TS7", aliases: ["FT7", "TS7"], year: 2018,
                     notes: ["4K recording is off while the camera's Wi-Fi is on."], fixedExposure: true),
        ModelProfile(brand: .panasonic, name: "LUMIX G90 / G95 / G91", aliases: ["G90", "G95", "G91"], year: 2019),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ95 / ZS80", aliases: ["TZ95", "ZS80", "TZ96"], year: 2019),
        ModelProfile(brand: .panasonic, name: "LUMIX FZ1000 II", aliases: ["FZ1000M2", "FZ1000II"], year: 2019),
        ModelProfile(brand: .panasonic, name: "LUMIX S1 / S1R / S1H", aliases: ["S1", "S1R", "S1H"], year: 2019),
        ModelProfile(brand: .panasonic, name: "LUMIX G100", aliases: ["G100", "G110"], year: 2020),
        ModelProfile(brand: .panasonic, name: "LUMIX S5", aliases: ["S5"], year: 2020,
                     notes: ["The S5 sends 16:9 live view (640×360)."]),
        ModelProfile(brand: .panasonic, name: "LUMIX BGH1", aliases: ["BGH1"], year: 2020),
        ModelProfile(brand: .panasonic, name: "LUMIX GH5 II", aliases: ["GH5M2", "GH5II"], year: 2021,
                     notes: ["Since firmware 1.4 the camera's Wi-Fi always has a password, shown on the camera."]),
        ModelProfile(brand: .panasonic, name: "LUMIX GH6", aliases: ["GH6"], year: 2022),
        ModelProfile(brand: .panasonic, name: "LUMIX BS1H", aliases: ["BS1H"], year: 2022),
        ModelProfile(brand: .panasonic, name: "LUMIX S5 II", aliases: ["S5M2", "S5II"], year: 2023, notes: [newerPairing]),
        ModelProfile(brand: .panasonic, name: "LUMIX S5 IIX", aliases: ["S5M2X", "S5IIX"], year: 2023, notes: [newerPairing], pairing: .newer),
        ModelProfile(brand: .panasonic, name: "LUMIX G9 II", aliases: ["G9M2", "G9II"], year: 2023, notes: [newerPairing], pairing: .newer),
        ModelProfile(brand: .panasonic, name: "LUMIX TZ99 / ZS99", aliases: ["TZ99", "ZS99"], year: 2023),
        ModelProfile(brand: .panasonic, name: "LUMIX G97", aliases: ["G97"], year: 2024),
        ModelProfile(brand: .panasonic, name: "LUMIX GH7", aliases: ["GH7"], year: 2024, notes: [newerPairing]),
        ModelProfile(brand: .panasonic, name: "LUMIX S9", aliases: ["S9"], year: 2024,
                     notes: ["Remote shooting needs S9 firmware 1.1 or later.", newerPairing]),
        ModelProfile(brand: .panasonic, name: "LUMIX G100D", aliases: ["G100D"], year: 2024),
        ModelProfile(brand: .panasonic, name: "LUMIX S1 II / S1R II / L10", aliases: ["S1M2", "S1RM2", "S1II", "S1RII", "L10"], year: 2025,
                     notes: ["These bodies pair with LUMIX Lab and LUMIX Flow; Panasonic's older Wi-Fi remote protocol may not be there at all."]),
    ]
}

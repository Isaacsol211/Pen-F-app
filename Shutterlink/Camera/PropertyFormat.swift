import Foundation
import Synchronization

/// Names the connected camera gives its own settings and values. LUMIX menus carry an English
/// name for every option; these are checked before the built-in tables.
struct CameraText: Sendable {
    var titles: [String: String] = [:]
    var values: [String: [String: String]] = [:]
}

/// Human-readable labels for the camera's raw property values.
enum PropertyFormat {
    private static let cameraText = Mutex(CameraText())

    /// Replaces the connected camera's own names (empty when it disconnects).
    static func setCameraText(_ text: CameraText) {
        cameraText.withLock { $0 = text }
    }

    static let featured: [(name: String, title: String)] = [
        ("takemode", "Mode"),
        ("focalvalue", "Aperture"),
        ("shutspeedvalue", "Shutter"),
        ("isospeedvalue", "ISO"),
        ("expcomp", "EV"),
        ("wbvalue", "WB"),
        ("drivemode", "Drive"),
        ("artfilter", "Art filter"),
        ("colortone", "Picture"),
        ("colorphase", "Hue (CRT)"),
    ]

    static func title(for name: String) -> String {
        if let title = cameraText.withLock({ $0.titles[name] }) { return title }
        return featured.first { $0.name == name }?.title ?? name
    }

    /// Exposure time in seconds for a shutter value: `60"` → 60, `250` → 1/250, `1.3` → 1/1.3.
    static func seconds(fromShutter value: String) -> Double? {
        if value.hasSuffix("\"") { return Double(value.dropLast()) }
        if let denominator = Double(value), denominator > 0 { return 1 / denominator }
        return nil
    }

    /// Live Composite, Live Time, Live Bulb and Bulb run until stopped.
    static func isOpenEnded(shutter value: String) -> Bool {
        let v = value.lowercased()
        return v.hasPrefix("live") || v == "bulb" || v == "time"
    }

    static func display(_ name: String, _ value: String) -> String {
        if let label = cameraText.withLock({ $0.values[name]?[value] }) { return label }
        switch name {
        case "takemode":
            switch value.lowercased() {
            case "iauto": return "iAUTO"
            case "movie": return "Movie"
            default: return value.uppercased()
            }
        case "focalvalue":
            return Double(value) != nil ? "F\(value)" : value
        case "shutspeedvalue":
            if value.hasSuffix("\"") { return value }           // 60" = 60 seconds
            if Double(value) != nil { return "1/\(value)" }      // 250 = 1/250
            switch value.lowercased() {
            case "livecomp": return "Live Comp"
            case "livetime": return "Live Time"
            case "livebulb": return "Live Bulb"
            case "bulb": return "Bulb"
            default: return words(value)
            }
        case "expcomp":
            return Double(value) == 0 ? "±0.0" : value
        case "isospeedvalue":
            switch value.lowercased() {
            case "auto": return "Auto"
            case "i_iso": return "iAuto"   // LUMIX intelligent ISO
            default: return value
            }
        case "wbvalue":
            if let name = whiteBalance[value] { return name }
            return Int(value) != nil ? "WB \(value)" : words(value)   // LUMIX names its other modes
        case "drivemode":
            return drive(value)
        case "artfilter", "colortone":
            return words(value)
        case "colorphase":
            return value.replacingOccurrences(of: "step", with: "Hue ")
        default:
            return value
        }
    }

    /// Best guess from the order the camera lists them (matches the WB menu order).
    /// The raw code is shown next to it in the picker so this can be checked.
    static let whiteBalance: [String: String] = [
        "0": "Auto", "18": "Sunny", "16": "Shade", "17": "Cloudy", "20": "Incandescent",
        "35": "Fluorescent", "64": "Underwater", "23": "Flash",
        "256": "One-touch 1", "257": "One-touch 2", "258": "One-touch 3", "259": "One-touch 4",
        "512": "Custom K",
    ]

    private static func drive(_ value: String) -> String {
        let names: [String: String] = [
            "normal": "Single", "lowvib": "Anti-shock", "silent": "Silent",
            "continuous": "Cont.", "selftimer": "Self-timer", "customselftimer": "Custom timer",
        ]
        return value.split(separator: "-").map { names[String($0)] ?? String($0) }.joined(separator: " ")
    }

    private static func words(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

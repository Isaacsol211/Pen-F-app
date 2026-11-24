import SwiftUI

extension CameraModel {
    /// Prefer the values the camera reports with each frame: they include what auto modes chose.
    func stripValue(_ name: String, _ property: CameraProperty?) -> String {
        let info = liveInfo
        switch name {
        case "focalvalue":
            if let live = info.aperture { return live }
        case "shutspeedvalue":
            if let p = property, PropertyFormat.isOpenEnded(shutter: p.value) {
                switch p.value.lowercased() {
                case "livecomp": return "LC"
                case "livetime": return "LT"
                case "livebulb": return "LB"
                default: return PropertyFormat.display(name, p.value)   // Bulb, Time
                }
            }
            if let live = info.shutter { return live }
        case "isospeedvalue":
            if let live = info.iso { return live.replacingOccurrences(of: "ISO ", with: "").replacingOccurrences(of: " A", with: "") }
        case "expcomp":
            if let live = info.expComp { return live }
        case "drivemode":
            return Self.driveShort(property?.value ?? "")
        case "wbvalue":
            guard let raw = property?.value else { return "–" }
            // Short enough for a strip cell, without cutting a word off mid-way ("Fluore").
            let short = ["0": "AWB", "20": "Incand.", "35": "Fluor.", "64": "Underw.", "256": "OT 1", "257": "OT 2",
                         "258": "OT 3", "259": "OT 4", "512": "Kelvin", "awb_white": "AWB W", "awb_ambience": "AWB A"]
            return short[raw] ?? PropertyFormat.whiteBalance[raw] ?? raw
        default:
            break
        }
        guard let property else { return "–" }
        return PropertyFormat.display(name, property.value)
    }

    /// The strip's value for a setting, using the lens-filtered options.
    func stripValue(_ name: String) -> String {
        stripValue(name, properties[name].map(dialOptions(for:)))
    }

    /// Drive in a strip cell: "Single", "Anti-shock", "Cont H", "Burst H", "Timer 2s"…
    static func driveShort(_ value: String) -> String {
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2 {   // LUMIX: "burst|h", "selftimer|2sec"…
            switch parts[0] {
            case "burst": return "Burst \(parts[1].uppercased())"
            case "selftimer": return "Timer " + parts[1].replacingOccurrences(of: "sec3shot", with: "s×3").replacingOccurrences(of: "sec", with: "s")
            case "4k_photo": return "4K"
            case "autobracket": return "Bracket"
            case "stopmotion_interval": return parts[1] == "interval" ? "Interval" : "Stop mo."
            default: return PropertyFormat.display("drivemode", value)
            }
        }
        // Olympus: "lowvib-normal", "silent-continuous-H", "customselftimer"…
        let words: [String: String] = ["normal": "Single", "lowvib": "Anti-shock", "silent": "Silent",
                                       "continuous": "Cont", "selftimer": "Timer", "customselftimer": "Timer C"]
        var tokens = value.split(separator: "-").map { words[String($0)] ?? String($0) }
        if tokens.count > 1, tokens.last == "Single" { tokens.removeLast() }   // "Anti-shock Single" → "Anti-shock"
        return tokens.isEmpty ? "–" : tokens.joined(separator: " ")
    }
}

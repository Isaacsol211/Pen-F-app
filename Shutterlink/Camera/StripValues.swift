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
        case "wbvalue":
            guard let raw = property?.value else { return "–" }
            // Short enough for a strip cell, without cutting a word off mid-way ("Fluore").
            let short = ["0": "AWB", "20": "Incand.", "35": "Fluor.", "64": "Underw.", "256": "OT 1", "257": "OT 2",
                         "258": "OT 3", "259": "OT 4", "512": "Kelvin"]
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
}

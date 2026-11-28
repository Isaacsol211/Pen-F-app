import Foundation

/// One of the extra LUMIX settings (drive mode, Photo Style, filters, AF mode…), read from the
/// camera's own menu (`getinfo&type=allmenu`). The menu lists every value with the exact
/// `setsetting` strings and an English name, so nothing here is hard-coded per model.
struct LumixSetting {
    /// Property name in the app. Drive mode uses the shared "drivemode" so it gets the Drive button.
    let name: String
    /// The `type` for getsetting/setsetting.
    let type: String
    let title: String
    /// "value", or "value|value2" when the camera wants a second part (burst speed, timer length…).
    var options: [String] = []
    var labels: [String: String] = [:]
    /// The menu items behind each option (its own and the choice it sits under, e.g. Burst), to look
    /// up in `curmenu` whether it's available right now.
    var optionItems: [String: [String]] = [:]
    /// The menu headings around the options (e.g. "Photo Style"), which `curmenu` can switch off.
    var headingItems: [String] = []
}

/// Colour-temperature white balance: `whitebalance=color_temp&value2=<kelvin>`.
struct LumixKelvin {
    let min: Int
    let max: Int
    let step: Int
    let itemID: String?

    var options: [String] { stride(from: min, through: max, by: Swift.max(step, 1)).map(String.init) }
}

/// What `getinfo&type=curmenu` says about a menu item.
struct LumixMenuState {
    var enabled: Bool
    var value: String?
}

enum LumixMenu {
    /// The settings offered, in display order: cmd_type → (property name, title).
    static let wanted: [(type: String, name: String, title: String)] = [
        ("drivemode", "drivemode", "Drive"),
        ("colormode", "colormode", "Photo Style"),
        ("filter_setting", "filter_setting", "Filter"),
        ("creativectrl", "creativectrl", "Creative Control"),
        ("afmode", "afmode", "AF mode"),
        ("lightmetering", "lightmetering", "Metering"),
        ("quality", "quality", "Picture quality"),
        ("aspectratio", "aspectratio", "Aspect ratio"),
        ("pictsize", "pictsize", "Picture size"),
        ("flash", "flash", "Flash"),
        ("peaking", "peaking", "Peaking on the camera"),
        ("videoformat", "videoformat", "Video format"),
        ("videoquality", "videoquality", "Video quality"),
    ]
    static let kelvinName = "colortemp"
    static let kelvinTitle = "Colour temperature"

    /// The camera puts this where a value is filled in at run time; it is never sent.
    private static let placeholder = "__value__"

    /// The settings the menu offers, and colour temperature if the white balance list has it.
    static func parse(_ root: XMLNode) -> (settings: [LumixSetting], kelvin: LumixKelvin?) {
        let titles = englishTitles(root)
        var found: [String: LumixSetting] = [:]
        var kelvin: LumixKelvin?
        let wantedTypes = Dictionary(uniqueKeysWithValues: wanted.map { ($0.type, $0) })

        func title(_ item: XMLNode) -> String? { item.attributes["title_id"].flatMap { titles[$0] } }
        func hasOptions(_ item: XMLNode) -> Bool {
            item.descendants(named: "item").contains { $0.attributes["cmd_type"] != nil }
        }

        func record(_ item: XMLNode, type: String, value: String, parent: XMLNode?, headings: [String]) {
            guard let spec = wantedTypes[type] else { return }
            let value2 = item.attributes["cmd_value2"].flatMap { $0.isEmpty || $0 == placeholder ? nil : $0 }
            let key = value2.map { "\(value)|\($0)" } ?? value
            var setting = found[type] ?? LumixSetting(name: spec.name, type: type, title: spec.title)
            guard !setting.options.contains(key) else { return }
            setting.options.append(key)
            let own = title(item) ?? words(value2 ?? value)
            let label = parent.flatMap(title).map { "\($0) · \(own)" } ?? own
            setting.labels[key] = type == "drivemode" ? (driveLabel(key) ?? label) : label
            setting.optionItems[key] = [item.attributes["id"], parent?.attributes["id"]].compactMap { $0 }
            for heading in headings where !setting.headingItems.contains(heading) { setting.headingItems.append(heading) }
            found[type] = setting
        }

        func visit(_ item: XMLNode, parent: XMLNode?, headings: [String]) {
            let type = item.attributes["cmd_type"]
            let value = item.attributes["cmd_value"]
            if type == "whitebalance", value == "color_temp",
               let lo = item.attributes["min_val"].flatMap(Int.init), let hi = item.attributes["max_val"].flatMap(Int.init), hi > lo {
                kelvin = LumixKelvin(min: lo, max: hi, step: item.attributes["step_val"].flatMap(Int.init) ?? 100,
                                     itemID: item.attributes["id"])
                return
            }
            if let type, let value, value != placeholder, !hasOptions(item) {
                record(item, type: type, value: value, parent: parent, headings: headings)
            } else if let type, hasOptions(item) {
                // A choice whose sub-items carry the second value: Burst → SH/H/M/L. Name the choice
                // itself too, in case the camera reports it without the second part.
                if let value, let spec = wantedTypes[type] {
                    var setting = found[type] ?? LumixSetting(name: spec.name, type: type, title: spec.title)
                    if setting.labels[value] == nil {
                        setting.labels[value] = (type == "drivemode" ? driveLabel(value) : nil) ?? title(item) ?? words(value)
                    }
                    found[type] = setting
                }
                walk(item, parent: item, headings: headings)
            } else {
                // A heading such as Photo Style or AF Mode.
                walk(item, parent: nil, headings: headings + [item.attributes["id"]].compactMap { $0 })
            }
        }

        func walk(_ node: XMLNode, parent: XMLNode?, headings: [String]) {
            for child in node.children where child.name != "titlelist" {
                if child.name == "item" {
                    visit(child, parent: parent, headings: headings)
                } else {
                    walk(child, parent: parent, headings: headings)
                }
            }
        }

        walk(root, parent: nil, headings: [])
        let settings = wanted.compactMap { found[$0.type] }.filter { !$0.options.isEmpty }
        return (settings, kelvin)
    }

    /// `curmenu`: which items are available right now, and the value some headings carry.
    static func parseState(_ root: XMLNode) -> [String: LumixMenuState] {
        var state: [String: LumixMenuState] = [:]
        for item in root.descendants(named: "item") {
            guard let id = item.attributes["id"] else { continue }
            state[id] = LumixMenuState(enabled: item.attributes["enable"]?.lowercased() != "no",
                                       value: item.attributes["value"])
        }
        return state
    }

    /// The menu's English names: title id → text.
    static func englishTitles(_ root: XMLNode) -> [String: String] {
        let languages = root.descendants(named: "language")
        guard let english = languages.first(where: { $0.attributes["code"] == "en" })
                ?? languages.first(where: { $0.attributes["default"] == "yes" }) else { return [:] }
        var titles: [String: String] = [:]
        for title in english.children("title") {
            guard let id = title.attributes["id"] else { continue }
            titles[id] = title.trimmedText.replacingOccurrences(of: "&apos;", with: "'")
        }
        return titles
    }

    /// Shorter names for drive modes than "Burst Shooting · H".
    static func driveLabel(_ key: String) -> String? {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        // An empty key from the camera ("" or "|") splits into nothing.
        guard let base = parts.first else { return nil }
        let detail = parts.count > 1 ? parts[1] : nil
        switch (base, detail) {
        case ("normal", nil): return "Single"
        case ("burst", nil): return "Burst"
        case ("burst", let speed?): return "Burst \(speed.uppercased())"
        case ("4k_photo", nil): return "4K Photo"
        case ("4k_photo", "burst"): return "4K Burst"
        case ("4k_photo", "start_stop"): return "4K Burst (S/S)"
        case ("4k_photo", "pre_burst"): return "4K Pre-Burst"
        case ("autobracket", let bracket?):
            // "3shot_1/3ev" → "Bracket 3 × 1/3 EV"
            let pieces = bracket.replacingOccurrences(of: "ev", with: "").split(separator: "_")
            guard pieces.count == 2, let shots = pieces[0].split(separator: "s").first else { return nil }
            return "Bracket \(shots) × \(pieces[1]) EV"
        case ("autobracket", nil): return "Bracket"
        case ("selftimer", nil): return "Self-timer"
        case ("selftimer", "10sec"): return "Self-timer 10 s"
        case ("selftimer", "10sec3shot"): return "Self-timer 10 s × 3"
        case ("selftimer", "2sec"): return "Self-timer 2 s"
        case ("stopmotion_interval", nil): return "Time lapse / Stop motion"
        case ("stopmotion_interval", "interval"): return "Time lapse"
        case ("stopmotion_interval", "stop_motion"): return "Stop motion"
        default: return nil
        }
    }

    static func words(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

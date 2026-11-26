import SwiftUI

/// How a setting is presented on the main screen.
struct SettingSpec {
    enum Style { case dial, grid }
    let name: String
    let title: String
    let icon: String
    let style: Style

    /// Everything the PEN-F lets an app change over Wi-Fi, in shooting order.
    static let all: [SettingSpec] = [
        SettingSpec(name: "takemode", title: "Mode", icon: "camera", style: .dial),
        SettingSpec(name: "focalvalue", title: "Aperture", icon: "camera.aperture", style: .dial),
        SettingSpec(name: "shutspeedvalue", title: "Shutter", icon: "camera.shutter.button", style: .dial),
        SettingSpec(name: "isospeedvalue", title: "ISO", icon: "sun.max", style: .dial),
        SettingSpec(name: "expcomp", title: "EV", icon: "plusminus.circle", style: .dial),
        SettingSpec(name: "wbvalue", title: "White balance", icon: "thermometer.sun", style: .dial),
        SettingSpec(name: "drivemode", title: "Drive", icon: "square.stack.3d.up", style: .grid),
        SettingSpec(name: "quality", title: "Quality", icon: "photo", style: .grid),
        SettingSpec(name: "colorphase", title: "Hue", icon: "swatchpalette", style: .dial),
        SettingSpec(name: "exposemovie", title: "Movie", icon: "video", style: .dial),
    ]

    static func spec(for name: String) -> SettingSpec? { all.first { $0.name == name } }

    /// Icon for an individual option in a grid.
    static func optionIcon(_ name: String, _ value: String) -> String? {
        switch name {
        case "takemode":
            return ["iauto": "wand.and.stars", "p": "p.circle", "a": "a.circle", "s": "s.circle",
                    "m": "m.circle", "movie": "video", "art": "paintbrush"][value.lowercased()]
        case "wbvalue":
            return ["0": "a.circle", "18": "sun.max", "16": "sun.haze", "17": "cloud", "20": "lightbulb",
                    "35": "light.max", "64": "drop", "23": "bolt", "256": "hand.point.up.left",
                    "257": "hand.point.up.left", "258": "hand.point.up.left", "259": "hand.point.up.left",
                    "512": "slider.horizontal.3"][value]
        case "drivemode":
            if value.contains("customselftimer") { return "timer.circle" }
            if value.contains("selftimer") { return "timer" }
            if value.contains("continuous-H") { return "square.stack.3d.up.fill" }
            if value.contains("continuous") { return "square.stack.3d.up" }
            // LUMIX
            if value.hasPrefix("burst") { return value.hasSuffix("|sh") || value.hasSuffix("|h") ? "square.stack.3d.up.fill" : "square.stack.3d.up" }
            if value.hasPrefix("4k_photo") { return "4k.tv" }
            if value.hasPrefix("autobracket") { return "plusminus.circle" }
            if value.hasPrefix("stopmotion_interval") { return "clock.arrow.2.circlepath" }
            return value.hasPrefix("silent") ? "speaker.slash" : "square"
        case "exposemovie":
            return ["p": "p.circle", "a": "a.circle", "s": "s.circle", "m": "m.circle"][value.lowercased()]
        default:
            return nil
        }
    }
}

/// The options for one setting: a swipe dial or a grid of buttons. Locked settings explain why.
struct OptionPanel: View {
    @Environment(CameraModel.self) private var camera
    let spec: SettingSpec
    let onClose: () -> Void

    var body: some View {
        if let raw = camera.properties[spec.name] {
            let property = camera.dialOptions(for: raw)
            let isDial = spec.style == .dial
            let auto = ExposureGrid.isAuto(spec.name, locked: !property.settable, mode: camera.properties["takemode"]?.value)
            // The readout says what the setting is called (201–207: Shutter, Aperture, ISO, White balance, Mode).
            let label = spec.name == "expcomp" ? "EV" : spec.title
            VStack(alignment: .center, spacing: 10) {
                if !isDial {
                    HStack(spacing: 8) {
                        Text(spec.title).font(.num(26))
                        Spacer()
                        Text(PropertyFormat.display(spec.name, property.value))
                            .font(.num(22, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.footnote.weight(.bold))
                        }
                        .buttonStyle(.surfaceCircle)
                        .accessibilityLabel("Close \(spec.title)")
                    }
                }
                if !property.settable {
                    let mode = camera.properties["takemode"]?.value.uppercased() ?? ""
                    if spec.name == "expcomp" && mode == "M" {
                        // 205: EV means nothing in M, so no readout: a lock, why, and the way out.
                        Image(systemName: "lock")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.tertiary)
                            .padding(.top, 20)
                    } else {
                        DialReadout(label: label + (auto ? " · Auto" : ""),
                                    value: ExposureStrip.text(spec.name, camera: camera)
                                        .replacingOccurrences(of: "ISO ", with: ""), locked: true)
                            .padding(.top, 10)
                    }
                    lockedExplanation
                        .padding(.horizontal, 24)
                    Spacer(minLength: 0)
                } else if spec.name == "shutspeedvalue" {
                    ShutterOptions(property: property)
                } else if isDial {
                    ValueDial(property: property, readoutLabel: label) { value in
                        Task { await camera.setProperty(spec.name, to: value) }
                    }
                    .id(spec.name)
                    .overlay(alignment: .top) {
                        // A camera that lets EV be set in M (LUMIX) only uses it with ISO on Auto.
                        if spec.name == "expcomp", camera.properties["takemode"]?.value.uppercased() == "M",
                           let iso = camera.properties["isospeedvalue"]?.value, !iso.lowercased().contains("auto") {
                            Text("In M the camera applies EV only with ISO on Auto.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondary)
                                .offset(y: 104)
                        }
                    }
                } else {
                    OptionGrid(property: property) { value in
                        Task { await camera.setProperty(spec.name, to: value) }
                    }
                }
            }
            .padding(.horizontal, isDial ? 0 : 14)
            .padding(.vertical, isDial ? 0 : 14)
            .animation(.snappy, value: property.value)
        }
    }

    @ViewBuilder private var lockedExplanation: some View {
        let mode = camera.properties["takemode"]?.value ?? ""
        let unlock: (label: String, mode: String)? = switch spec.name {
        case "focalvalue": ("Switch to A (aperture priority)", "A")
        case "shutspeedvalue": ("Switch to S (shutter priority)", "S")
        case "expcomp": ("Switch to A", "A")
        default: nil
        }
        let exposure = ["focalvalue", "shutspeedvalue", "isospeedvalue", "wbvalue"].contains(spec.name)
        let modeSettable = camera.properties["takemode"]?.settable == true
        let why = if spec.name == "takemode" {
            ExposureStrip.modeDialHint
        } else if spec.name == "expcomp", mode.uppercased() == "M" {
            "Exposure compensation has no effect in M, where you set the exposure yourself. It works in P, A and S."
        } else if mode.isEmpty || !(exposure || spec.name == "expcomp") {
            // No mode to blame (the body doesn't report it), or not an exposure setting (a drive dial).
            "Set this on the camera: this body doesn't let the phone change it right now."
        } else {
            "The camera sets this itself in \(PropertyFormat.display("takemode", mode)) mode."
        }
        VStack(alignment: .center, spacing: 12) {
            Text(why)
                .font(.system(size: 15))
                .lineSpacing(2)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if spec.name == "expcomp", mode.uppercased() == "M",
               let modes = camera.properties["takemode"]?.options, modes.contains("A") || modes.contains("S") {
                // 205: both ways out of M, as outline buttons.
                ForEach([("Switch to A (aperture priority)", "A"), ("Switch to S (shutter priority)", "S")]
                    .filter { modes.contains($0.1) }, id: \.1) { item in
                    Button(item.0) { Task { await camera.setProperty("takemode", to: item.1) } }
                        .buttonStyle(UnlockButtonStyle())
                }
            } else if let unlock, camera.properties["takemode"]?.options.contains(unlock.mode) == true {
                Button(unlock.label) {
                    Task { await camera.setProperty("takemode", to: unlock.mode) }
                }
                .buttonStyle(UnlockButtonStyle())
            } else if let unlock, !modeSettable, !mode.isEmpty, mode.uppercased() != unlock.mode {
                // The mode is on a physical dial (LUMIX): say which way to turn it.
                Text("Turn the camera's mode dial to \(unlock.mode) to set this from the phone.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The way out of a locked value (205): a white-outlined capsule, 44 pt.
struct UnlockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 20)
            .frame(minHeight: Theme.target)
            .overlay(Capsule().stroke(Theme.text, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.capsule)
    }
}

/// Tappable grid for settings with a handful of named values (mode, WB, drive…).
struct OptionGrid: View {
    let property: CameraProperty
    let onSelect: (String) -> Void

    // Three across, text only, 62 pt tiles: the chosen one filled with the accent (208, 209). The
    // bottom panel scrolls when a camera has many (LUMIX lists a dozen drive modes).
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(property.options.enumerated()), id: \.offset) { _, option in
                let selected = option == property.value
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                Button {
                    onSelect(option)
                } label: {
                    Text(PropertyFormat.display(property.name, option))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                        .background(shape.fill(selected ? Theme.accent : Color.clear))
                        .overlay(shape.stroke(selected ? Color.clear : Theme.outline, lineWidth: 1))
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(1)
        .feedback(.select, trigger: property.value)
    }
}

/// Shutter: Live Composite / Live Time / Live Bulb as a segmented choice, timed speeds on the dial.
struct ShutterOptions: View {
    @Environment(CameraModel.self) private var camera
    let property: CameraProperty
    @AppStorage("lastTimedShutter") private var lastTimed = "250"

    private var liveModes: [String] { property.options.filter { PropertyFormat.isOpenEnded(shutter: $0) } }
    private var timed: CameraProperty {
        var p = property
        p.options = property.options.filter { !PropertyFormat.isOpenEnded(shutter: $0) }
        if !p.options.contains(p.value) { p.value = p.options.contains(lastTimed) ? lastTimed : (p.options.first ?? p.value) }
        return p
    }

    var body: some View {
        let current = PropertyFormat.isOpenEnded(shutter: property.value) ? property.value : "timed"
        // The dial runs on past its slowest speed into the camera's own Live Comp / Live Time / Bulb; once
        // one is chosen the kinds show as chips, with Stop after (210). Not over timed speeds (201, 214).
        VStack(spacing: 8) {
            if !liveModes.isEmpty && current != "timed" {
                // Compact chips, like the Camera app's small mode toggles.
                HStack(spacing: 6) {
                    ForEach(["timed"] + liveModes, id: \.self) { choice in
                        let on = choice == current
                        Button {
                            let value = choice == "timed" ? timed.value : choice
                            Task { await camera.setProperty("shutspeedvalue", to: value) }
                        } label: {
                            Text(choice == "timed" ? "Timed" : PropertyFormat.display("shutspeedvalue", choice))
                                .font(.system(size: 13, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Theme.background : Theme.text)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(on ? AnyShapeStyle(Theme.text) : AnyShapeStyle(Color.black.opacity(0.25)), in: .capsule)
                                .overlay(Capsule().stroke(on ? Color.clear : Theme.text.opacity(0.35), lineWidth: 1))
                                .contentShape(.capsule.inset(by: -5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .feedback(.select, trigger: current)
            }
            if current == "timed" {
                ValueDial(property: property, readoutLabel: "Shutter") { value in
                    if !PropertyFormat.isOpenEnded(shutter: value) { lastTimed = value }
                    Task { await camera.setProperty("shutspeedvalue", to: value) }
                }
                .id("shutter-dial")
                .transition(.blurReplace)
            } else {
                VStack(alignment: .center, spacing: 12) {
                    BulbTimerControl()
                        .padding(.top, 22)
                    Text(current == "livecomp"
                         ? "Live Composite stacks only new light: star trails without over-exposing the sky. "
                            + (camera.bulbTimer > 0 ? "It stops by itself after \(CameraModel.durationLabel(camera.bulbTimer))." : "Tap the shutter to start, again to stop.")
                         : (camera.bulbTimer > 0
                            ? "The exposure stops by itself after \(CameraModel.durationLabel(camera.bulbTimer)), or when you tap the shutter."
                            : "The exposure runs until you tap the shutter again."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .transition(.blurReplace)
            }
        }
        .animation(.smooth, value: current)
    }
}

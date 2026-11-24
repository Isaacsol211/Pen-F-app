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
        SettingSpec(name: "takemode", title: "Mode", icon: "camera", style: .grid),
        SettingSpec(name: "focalvalue", title: "Aperture", icon: "camera.aperture", style: .dial),
        SettingSpec(name: "shutspeedvalue", title: "Shutter", icon: "camera.shutter.button", style: .dial),
        SettingSpec(name: "isospeedvalue", title: "ISO", icon: "sun.max", style: .dial),
        SettingSpec(name: "expcomp", title: "EV", icon: "plusminus.circle", style: .dial),
        SettingSpec(name: "wbvalue", title: "White balance", icon: "thermometer.sun", style: .dial),
        SettingSpec(name: "drivemode", title: "Drive", icon: "square.stack.3d.up", style: .grid),
        SettingSpec(name: "colorphase", title: "Hue", icon: "swatchpalette", style: .dial),
        SettingSpec(name: "exposemovie", title: "Movie", icon: "video", style: .grid),
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
            // Rulers carry their own title and live value; other styles get a header.
            let ruler = property.settable && spec.style == .dial
            VStack(alignment: .leading, spacing: 10) {
                if !ruler {
                HStack(spacing: 8) {
                    Image(systemName: spec.icon).foregroundStyle(Theme.accent)
                    CapsLabel(spec.title, color: Theme.accent)
                    Spacer()
                    Text(PropertyFormat.display(spec.name, property.value))
                        .font(.subheadline.monospaced().weight(.semibold))
                        .contentTransition(.numericText())
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.footnote.weight(.bold))
                    }
                    .buttonStyle(.surfaceCircle)
                    .accessibilityLabel("Close \(spec.title)")
                }
                }
                if !property.settable {
                    lockedExplanation
                } else if spec.name == "shutspeedvalue" {
                    ShutterOptions(property: property)
                } else if spec.style == .dial {
                    ValueDial(property: property) { value in
                        Task { await camera.setProperty(spec.name, to: value) }
                    }
                    .id(spec.name)
                } else {
                    OptionGrid(property: property) { value in
                        Task { await camera.setProperty(spec.name, to: value) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, ruler ? 8 : 14)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("The camera sets this itself in \(PropertyFormat.display("takemode", mode)) mode.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let unlock, camera.properties["takemode"]?.options.contains(unlock.mode) == true {
                Button(unlock.label, systemImage: "lock.open") {
                    Task { await camera.setProperty("takemode", to: unlock.mode) }
                }
                .buttonStyle(.surface)
            }
        }
    }
}

/// Tappable grid for settings with a handful of named values (mode, WB, drive…).
struct OptionGrid: View {
    let property: CameraProperty
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(Array(property.options.enumerated()), id: \.offset) { _, option in
                    let selected = option == property.value
                    Button {
                        onSelect(option)
                    } label: {
                        VStack(spacing: 4) {
                            if let icon = SettingSpec.optionIcon(property.name, option) {
                                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                            }
                            Text(PropertyFormat.display(property.name, option))
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(selected ? Color.black : Color.white)
                    }
                    .buttonStyle(.plain)
                    .surface(selected ? .regular.tint(Theme.accent) : .regular,
                                 in: .rect(cornerRadius: 14, style: .continuous))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(2)
        }
        .frame(maxHeight: 190)
        .sensoryFeedback(.selection, trigger: property.value)
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
        VStack(spacing: 8) {
            if !liveModes.isEmpty {
                // Compact chips, like the Camera app's small mode toggles.
                HStack(spacing: 6) {
                    ForEach(["timed"] + liveModes, id: \.self) { choice in
                        let on = choice == current
                        Button {
                            let value = choice == "timed" ? timed.value : choice
                            Task { await camera.setProperty("shutspeedvalue", to: value) }
                        } label: {
                            Text(choice == "timed" ? "Timed" : PropertyFormat.display("shutspeedvalue", choice))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(on ? Color.black : Color.white.opacity(0.8))
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.1)),
                                            in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: current)
            }
            if current == "timed" {
                ValueDial(property: timed) { value in
                    lastTimed = value
                    Task { await camera.setProperty("shutspeedvalue", to: value) }
                }
                .id("shutter-dial")
                .transition(.blurReplace)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    BulbTimerControl()
                    Text(current == "livecomp"
                         ? "Live Composite stacks only new light: star trails without over-exposing the sky. "
                            + (camera.bulbTimer > 0 ? "It stops by itself after \(CameraModel.durationLabel(camera.bulbTimer))." : "Tap the shutter to start, again to stop.")
                         : (camera.bulbTimer > 0
                            ? "The exposure stops by itself after \(CameraModel.durationLabel(camera.bulbTimer)), or when you tap the shutter."
                            : "The exposure runs until you tap the shutter again."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.blurReplace)
            }
        }
        .animation(.smooth, value: current)
    }
}

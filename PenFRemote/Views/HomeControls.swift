import SwiftUI

// Camera-app style controls: a Final Cut Camera–like strip of live exposure values,
// an iPhone-style mode carousel, and a tools tray that stays out of the way until needed.

// MARK: - Status

/// Live dot, battery and shots left: the only always-on status.
struct StatusPill: View {
    @Environment(CameraModel.self) private var camera

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(camera.liveViewRunning ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .shadow(color: camera.liveViewRunning ? .green : .orange, radius: 4)
            CameraStatusRow()
        }
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Exposure strip

/// One tappable row of the values that matter, showing what the camera is actually using
/// (so in P you still see the shutter and aperture it picked, marked "A").
struct ExposureStrip: View {
    @Environment(CameraModel.self) private var camera
    @Binding var active: String?
    var compact = false
    @Namespace private var selection

    private var items: [String] {
        var names = ["focalvalue", "shutspeedvalue", "isospeedvalue", "expcomp", "wbvalue", "drivemode"]
        if camera.isMovieMode { names.append("exposemovie") }
        return names.filter { camera.properties[$0] != nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { name in
                item(name)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .glassEffect(.regular, in: .capsule)
        .animation(.bouncy(duration: 0.35), value: active)
        .animation(.smooth, value: items)
        .disabled(camera.isBusyExposing)
        .sensoryFeedback(.selection, trigger: active)
    }

    /// One compact value, like the Camera app's top bar: no labels, the value says what it is.
    private func item(_ name: String) -> some View {
        let property = camera.properties[name].map(camera.dialOptions(for:))
        let locked = !(property?.settable ?? false)
        let selected = active == name
        let size: CGFloat = compact ? 12 : 13
        return Button {
            active = selected ? nil : name
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                switch name {
                case "drivemode":
                    Image(systemName: SettingSpec.optionIcon(name, property?.value ?? "") ?? "square")
                        .font(.system(size: size, weight: .semibold))
                case "isospeedvalue":
                    Text("ISO").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    Text(value(name, property))
                        .font(.system(size: size, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                default:
                    Text(value(name, property))
                        .font(.system(size: size, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                }
                if locked && name != "drivemode" {
                    // The camera is choosing this value itself (e.g. shutter in P).
                    Text("A").font(.system(size: 7, weight: .heavy)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(selected ? Theme.accent : (locked ? Color.white.opacity(0.7) : .white))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: compact ? 28 : 30)
            .background {
                if selected {
                    Capsule()
                        .fill(Theme.accent.opacity(0.18))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(SettingSpec.spec(for: name)?.title ?? name): \(value(name, property))\(locked ? ", automatic" : "")")
        .accessibilityHint("Shows the options")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func label(_ name: String) -> String {
        switch name {
        case "focalvalue": "APERTURE"
        case "shutspeedvalue": "SHUTTER"
        case "isospeedvalue": "ISO"
        case "expcomp": "EV"
        case "wbvalue": "WB"
        case "drivemode": "DRIVE"
        case "exposemovie": "VIDEO"
        default: name.uppercased()
        }
    }

    /// Prefer the values the camera reports with each frame: they include what auto modes chose.
    private func value(_ name: String, _ property: CameraProperty?) -> String {
        let info = camera.liveInfo
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
            return raw == "0" ? "AWB" : (PropertyFormat.whiteBalance[raw].map { String($0.prefix(6)) } ?? raw)
        default:
            break
        }
        guard let property else { return "–" }
        return PropertyFormat.display(name, property.value)
    }
}

// MARK: - Mode carousel

/// iPhone-style mode picker: swipe or tap AUTO · P · A · S · M · VIDEO.
struct ModeCarousel: View {
    @Environment(CameraModel.self) private var camera
    var axis: Axis = .horizontal
    @State private var centered: String?
    @State private var committed: String?

    private var options: [String] { camera.properties["takemode"]?.options ?? [] }
    private var current: String { camera.properties["takemode"]?.value ?? "" }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                    let layout = axis == .horizontal
                        ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                    layout {
                        ForEach(options, id: \.self) { mode in
                            let isCurrent = mode == (centered ?? current)
                            Text(title(mode))
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(isCurrent ? Theme.accent : Color.white.opacity(0.6))
                                .scaleEffect(isCurrent ? 1.08 : 1)
                                .frame(width: axis == .horizontal ? 64 : 76, height: axis == .horizontal ? 30 : 34)
                                .contentShape(.rect)
                                .id(mode)
                                .onTapGesture {
                                    withAnimation(.snappy) { proxy.scrollTo(mode, anchor: .center) }
                                    centered = mode
                                    commit(mode)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(axis == .horizontal ? .horizontal : .vertical,
                                max(0, ((axis == .horizontal ? geo.size.width : geo.size.height)
                                        - (axis == .horizontal ? 64 : 34)) / 2),
                                for: .scrollContent)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
                .scrollPosition(id: $centered, anchor: .center)
                .onScrollPhaseChange { _, phase in
                    if phase == .idle, let centered { commit(centered) }
                }
                .task(id: options) {
                    try? await Task.sleep(for: .milliseconds(30))
                    committed = current
                    proxy.scrollTo(current, anchor: .center)
                }
                .onChange(of: current) { _, mode in
                    committed = mode
                    if centered != mode {
                        withAnimation(.snappy) { proxy.scrollTo(mode, anchor: .center) }
                        centered = mode
                    }
                }
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                           .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                   startPoint: axis == .horizontal ? .leading : .top,
                                   endPoint: axis == .horizontal ? .trailing : .bottom)
                }
            }
        }
        .frame(width: axis == .horizontal ? nil : 80, height: axis == .horizontal ? 30 : nil)
        .disabled(camera.isBusyExposing || camera.properties["takemode"]?.settable != true)
        // Every mode is a hard detent, like the mode dial on the camera.
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: centered)
        .accessibilityElement()
        .accessibilityLabel("Mode")
        .accessibilityValue(title(current))
        .accessibilityAdjustableAction { direction in
            guard let i = options.firstIndex(of: current) else { return }
            let next = direction == .increment ? i + 1 : i - 1
            if options.indices.contains(next) { commit(options[next]) }
        }
    }

    private func title(_ mode: String) -> String {
        switch mode.lowercased() {
        case "iauto": "AUTO"
        case "movie": "VIDEO"
        default: mode.uppercased()
        }
    }

    private func commit(_ mode: String) {
        guard mode != committed, mode != current else { return }
        committed = mode
        Task { await camera.setProperty("takemode", to: mode) }
    }
}

// MARK: - Tools

/// Round button next to the shutter that opens the tools tray (and shows interval progress).
struct ToolsButton: View {
    @Environment(CameraModel.self) private var camera
    @Binding var open: Bool

    var body: some View {
        Button {
            withAnimation(.bouncy(duration: 0.4)) { open.toggle() }
        } label: {
            ZStack {
                if camera.interval.running {
                    Text(camera.interval.total == 0 ? "\(camera.interval.done)" : "\(camera.interval.done)/\(camera.interval.total)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText(value: Double(camera.interval.done)))
                } else {
                    Image(systemName: open ? "xmark" : "slider.horizontal.3")
                        .font(.system(size: 19, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 58, height: 58)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(open ? .regular.tint(Theme.accent.opacity(0.3)).interactive() : .regular.interactive(), in: .circle)
        .accessibilityLabel(open ? "Close tools" : "Tools")
    }
}

/// The tools that used to crowd the screen, one tap away.
struct ToolsTray: View {
    let tools: [ToolItem]
    var columns = 4

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(tools) { ToolButton(item: $0) }
            }
            .padding(12)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
    }
}

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
                .frame(width: 8, height: 8)
            CameraStatusRow()
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
        }
        .fixedSize()
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .surface(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// The top of the live screen: what's connected and how it's doing, like the info line on a
/// camera's rear screen. Battery and card stay readable at a glance; the menu sits at the end.
struct InfoBar<Trailing: View>: View {
    @Environment(CameraModel.self) private var camera
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(camera.liveViewRunning ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text((camera.cameraName ?? camera.brand.shortTitle).uppercased())
                    .font(.system(.subheadline, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(camera.cameraName ?? "Camera"), \(camera.liveViewRunning ? "live" : "live view off")")
            Spacer(minLength: 8)
            CameraStatusRow()
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(Theme.secondary)
                .fixedSize()
            trailing
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(minHeight: 52)
    }
}

/// The shooting aids you toggle most (grid, histogram, peaking, loupe, night), one tap away under the
/// readouts and drawn the same way: a small-caps label under each icon, amber when on.
struct QuickAidStrip: View {
    let tools: [ToolItem]
    /// Labels that fit a fifth of a phone's width.
    static let shortTitles = ["histogram": "Histo"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: 22)
                }
                Button(action: item.action) {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(height: 20)
                            .symbolEffect(.bounce, value: item.on)
                        CapsLabel(Self.shortTitles[item.id] ?? item.title, color: item.on ? Theme.accent : Theme.tertiary)
                    }
                    .foregroundStyle(item.on ? Theme.accent : .white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(alignment: .bottom) {
                        if item.on {
                            Capsule().fill(Theme.accent).frame(width: 18, height: 3).offset(y: -2)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: item.on)
                .accessibilityLabel(item.title)
                .accessibilityValue(item.on ? "On" : "Off")
            }
        }
        .padding(.horizontal, 4)
        .surface(.regular, in: .rect(cornerRadius: 18, style: .continuous))
        .animation(.snappy, value: tools.map(\.on))
    }
}

// MARK: - Exposure strip

/// The readouts: one cell per value that matters, a small-caps label over a big monospaced value,
/// showing what the camera is actually using (in P the shutter and aperture it picked, labelled AUTO).
/// Tap a cell for its dial.
struct ExposureStrip: View {
    @Environment(CameraModel.self) private var camera
    @Binding var active: String?
    /// Over the live image (landscape): a little shorter and see-through.
    var compact = false
    @Namespace private var selection
    @ScaledMetric(relativeTo: .title3) private var valueSize: CGFloat = 18

    private var items: [String] { Self.items(camera) }

    /// The values that get a cell, here and in the workspace's `ExposureGrid`.
    static func items(_ camera: CameraModel) -> [String] {
        var names = ["focalvalue", "shutspeedvalue", "isospeedvalue", "expcomp", "wbvalue", "drivemode", "quality"]
        if camera.isMovieMode { names.append("exposemovie") }
        return names.filter { camera.properties[$0] != nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, name in
                if index > 0 {
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: 26)
                }
                item(name)
            }
        }
        .padding(4)
        .surface(compact ? .clear : .regular, in: .rect(cornerRadius: 18, style: .continuous))
        .animation(.bouncy(duration: 0.35), value: active)
        .animation(.smooth, value: items)
        .disabled(camera.isBusyExposing)
        .sensoryFeedback(.selection, trigger: active)
    }

    private func item(_ name: String) -> some View {
        let property = camera.properties[name].map(camera.dialOptions(for:))
        let locked = !(property?.settable ?? false)
        let selected = active == name
        let auto = ExposureGrid.isAuto(name, locked: locked, mode: camera.properties["takemode"]?.value)
        return Button {
            active = selected ? nil : name
        } label: {
            VStack(spacing: 3) {
                // AUTO replaces the label when the camera is choosing this value itself (e.g. shutter in P).
                CapsLabel(auto ? "Auto" : ExposureGrid.label(name),
                          color: selected ? Theme.accent : (auto ? Theme.accent.opacity(0.85) : Theme.tertiary))
                Group {
                    if name == "drivemode" || name == "quality" {
                        // Words, not an icon: Single and Anti-shock look the same as symbols.
                        Text(camera.stripValue(name, property))
                            .font(.system(size: valueSize * 0.72, weight: .semibold))
                    } else {
                        Text(camera.stripValue(name, property))
                            .font(.system(size: valueSize, weight: .semibold, design: .monospaced))
                            .contentTransition(.numericText())
                    }
                }
                .foregroundStyle(selected ? Theme.accent : (locked ? Theme.secondary : .white))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            // Room either side so a long value (1/4000) shrinks instead of touching the dividers.
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: compact ? 50 : 58)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.accent.opacity(0.16))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(SettingSpec.spec(for: name)?.title ?? name): \(camera.stripValue(name, property))\(auto ? ", automatic" : "")")
        .accessibilityHint("Shows the options")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                                .font(.system(size: 15, weight: .heavy))
                                .tracking(1.6)
                                .foregroundStyle(isCurrent ? Theme.accent : Theme.tertiary)
                                .scaleEffect(isCurrent ? 1.1 : 1)
                                .frame(width: axis == .horizontal ? 70 : 80, height: Theme.target)
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
                                        - (axis == .horizontal ? 70 : Theme.target)) / 2),
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
                // The dial's index mark: the mode under it is the one set.
                .overlay(alignment: axis == .horizontal ? .bottom : .leading) {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 7, weight: .bold))
                        .rotationEffect(.degrees(axis == .horizontal ? 0 : 90))
                        .foregroundStyle(Theme.accent)
                        .offset(x: axis == .horizontal ? 0 : -2, y: axis == .horizontal ? 4 : 0)
                }
                .accessibilityHidden(true)
            }
        }
        .frame(width: axis == .horizontal ? nil : 84, height: axis == .horizontal ? Theme.target : nil)
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
                    Image(systemName: open ? "xmark" : "square.grid.2x2")
                        .font(.system(size: 20, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 58, height: 58)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .surface(open ? .regular.tint(Theme.accent.opacity(0.22)) : .regular, in: .circle)
        .accessibilityLabel(open ? "Close tools" : "Tools")
    }
}

/// Every tool, in two groups: shooting tools that open their own screen, and switches.
struct ToolsTray: View {
    let tools: [ToolItem]
    var columns = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("Shooting", tools.filter(\.opens))
            section("Switches", tools.filter { !$0.opens })
        }
        .padding(14)
        .surface(.regular, in: .rect(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private func section(_ title: String, _ items: [ToolItem]) -> some View {
        if !items.isEmpty {
            CapsLabel(title, color: Theme.tertiary)
                .padding(.leading, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(items) { ToolButton(item: $0) }
            }
        }
    }
}

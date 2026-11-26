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
                .fill(camera.liveViewRunning ? Theme.green : Theme.accent)
                .frame(width: 8, height: 8)
            CameraStatusRow()
                .font(.system(size: 13, weight: .medium))
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
                    .fill(camera.liveViewRunning ? Theme.green : Theme.accent)
                    .frame(width: 7, height: 7)
                Text(camera.cameraName ?? camera.brand.shortTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(camera.cameraName ?? "Camera"), \(camera.liveViewRunning ? "live" : "live view off")")
            Spacer(minLength: 8)
            CameraStatusRow()
                .font(.system(size: 13))
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
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
        .animation(.snappy, value: tools.map(\.on))
    }
}

// MARK: - Exposure strip

/// The row of values under the picture (mode, aperture, shutter, ISO, EV): what the camera is actually
/// using, in Barlow, the selected one in the accent. Tap one and the dial below becomes its dial.
struct ExposureStrip: View {
    @Environment(CameraModel.self) private var camera
    @Binding var active: String?
    /// Over the live image (landscape): a little shorter and see-through.
    var compact = false
    /// The selected value; one is always selected in the portrait remote.
    var selected: String?
    @ScaledMetric(relativeTo: .title3) private var valueSize: CGFloat = 20

    /// The values that get a cell here; white balance, drive and quality are the small line (`SettingLine`).
    static func items(_ camera: CameraModel) -> [String] {
        var names = ["takemode", "focalvalue", "shutspeedvalue", "isospeedvalue", "expcomp"]
        if camera.isMovieMode { names.append("exposemovie") }
        return names.filter { camera.properties[$0] != nil }
    }

    /// What to show as the value of a cell.
    static func text(_ name: String, camera: CameraModel) -> String {
        let property = camera.properties[name].map(camera.dialOptions(for:))
        let raw = camera.stripValue(name, property)
        switch name {
        case "focalvalue": return raw.first?.isNumber == true ? "f/" + raw : raw
        case "isospeedvalue": return raw.first?.isNumber == true ? "ISO " + raw : raw
        case "takemode": return ModeCarousel.title(property?.value ?? raw)
        default: return raw
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ExposureStrip.items(camera), id: \.self) { name in
                item(name)
            }
        }
        .padding(.horizontal, 8)
        .background {
            if compact { Capsule().fill(Color.black.opacity(0.55)) }
        }
        .animation(.snappy, value: selected)
        .disabled(camera.isBusyExposing)
        .sensoryFeedback(.selection, trigger: active)
    }

    private func item(_ name: String) -> some View {
        let property = camera.properties[name].map(camera.dialOptions(for:))
        let locked = !(property?.settable ?? false)
        let isSelected = (selected ?? active) == name
        let text = Self.text(name, camera: camera)
        if name == "takemode", locked {
            // A body with a physical mode dial the phone can't turn (LUMIX): the mode is a plain label,
            // not a value with a dial. Tapping it says where to change it.
            return AnyView(
                Text(text)
                    .font(.num(valueSize, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: Theme.target)
                    .contentShape(.rect)
                    .onTapGesture { camera.showToast(Self.modeDialHint) }
                    .accessibilityElement()
                    .accessibilityLabel("Mode: \(text)")
                    .accessibilityHint(Self.modeDialHint)
            )
        }
        return AnyView(Button {
            active = name
        } label: {
            Text(text)
                .font(.num(valueSize, weight: isSelected ? .semibold : .medium))
                .tracking(0.6)
                .foregroundStyle(isSelected ? Theme.accent : (locked ? Theme.tertiary : Color(hex: 0xC9C5BA)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: Theme.target)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(SettingSpec.spec(for: name)?.title ?? name): \(text)")
        .accessibilityHint("Shows the dial")
        .accessibilityAddTraits(isSelected ? .isSelected : []))
    }

    /// Where to change the mode on a body whose mode dial the phone can't turn.
    static let modeDialHint = "Turn the mode dial on the camera to change the mode."
}

/// The small line under the picture: white balance, drive and quality. White balance picks its dial;
/// drive and quality open a sheet of options.
struct SettingLine: View {
    @Environment(CameraModel.self) private var camera
    @Binding var active: String?
    let openSheet: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(["wbvalue", "drivemode", "quality"].filter { camera.properties[$0] != nil }, id: \.self) { name in
                let property = camera.properties[name].map(camera.dialOptions(for:))
                let on = active == name
                Button {
                    if name == "wbvalue" { active = name } else { openSheet(name) }
                } label: {
                    Text((name == "wbvalue" ? "WB " : "") + camera.stripValue(name, property))
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.accent : Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .frame(minHeight: Theme.target)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(SettingSpec.spec(for: name)?.title ?? name): \(camera.stripValue(name, property))")
            }
        }
        .disabled(camera.isBusyExposing)
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
                            Text(Self.title(mode))
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
        .accessibilityValue(Self.title(current))
        .accessibilityAdjustableAction { direction in
            guard let i = options.firstIndex(of: current) else { return }
            let next = direction == .increment ? i + 1 : i - 1
            if options.indices.contains(next) { commit(options[next]) }
        }
    }

    static func title(_ mode: String) -> String {
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

/// Round button next to the shutter that opens the tools (and shows interval progress).
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
                        .font(.num(16))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText(value: Double(camera.interval.done)))
                } else {
                    Image(systemName: open ? "xmark" : "slider.horizontal.3")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 48, height: 48)
            .overlay(Circle().stroke(camera.interval.running ? Theme.accent : Theme.text.opacity(0.4), lineWidth: 1))
            .frame(width: 58, height: 58)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
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

/// The Tools sheet: the live view stays visible above it.
struct ToolsSheet: View {
    @Environment(CameraModel.self) private var camera
    let tools: [ToolItem]
    @Binding var isOpen: Bool
    @Binding var height: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Tools").font(.num(26))
                    Spacer()
                    Button { isOpen = false } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.text)
                            .frame(width: Theme.target, height: Theme.target)
                    }
                    .accessibilityLabel("Close tools")
                }
                ToolsTray(tools: tools)
                if camera.interval.running {
                    Text("The interval timer is running: the Tools button shows \(camera.interval.done)\(camera.interval.total > 0 ? "/\(camera.interval.total)" : "").")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 + 16 }
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
    }
}

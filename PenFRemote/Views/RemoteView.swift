import SwiftUI

struct RemoteView: View {
    @Environment(CameraModel.self) private var camera
    @State private var showGallery = false
    @State private var showLog = false
    @State private var showAllSettings = false
    @State private var showAstro = false
    @State private var showInterval = false
    @State private var showHighRes = false
    @State private var confirmPowerOff = false
    @State private var confirmDisconnect = false
    @State private var toolsOpen = false
    /// Exposure value whose dial is open (nil = closed, keeps the screen clean).
    @State private var activeSetting: String?
    @State private var isLandscape = false
    @AppStorage("ui.histogram") private var showHistogram = false
    @AppStorage("ui.grid") private var showGrid = false
    @AppStorage("ui.nightMode") private var nightMode = false
    @State private var showLoupe = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                AmbientBackground().opacity(0.6)
                if landscape {
                    // Keep the shutter rail on the side away from the Dynamic Island.
                    landscapeLayout(railOnLeading: !Self.islandOnLeading(size: geo.size))
                        .transition(.opacity)
                } else {
                    portraitLayout
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.35), value: landscape)
            .onAppear { isLandscape = landscape }
            .onChange(of: landscape) { _, value in isLandscape = value }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        // Red night-vision mode keeps your eyes dark-adapted under the stars. Applied only when on:
        // a colour filter over the whole screen forces it to re-render offscreen on every frame.
        .modifier(NightVision(enabled: nightMode))
        .overlay(alignment: .top) { ToastView() }
        .sheet(isPresented: $showAllSettings) { AllSettingsView() }
        .sheet(isPresented: $showLog) { LogView() }
        .sheet(isPresented: $showAstro) { AstroView() }
        .sheet(isPresented: $showHighRes) { HighResView().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showInterval) {
            IntervalView().presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showGallery) { GalleryView() }
        .confirmationDialog("Turn the camera off?", isPresented: $confirmPowerOff, titleVisibility: .visible) {
            Button("Turn off", role: .destructive) { Task { await camera.powerOff() } }
        } message: {
            Text("You'll need to switch it on and start Wi-Fi on the camera again to reconnect.")
        }
        .confirmationDialog("Disconnect from the camera?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await camera.disconnect() } }
        }
        .onChange(of: showLoupe) { _, on in Task { await camera.setLoupe(on) } }
        .onChange(of: camera.isMovieMode) {
            if activeSetting == "exposemovie", !camera.isMovieMode {
                withAnimation(.snappy) { activeSetting = nil }
            }
        }
        .onChange(of: activeSetting) { _, value in
            if value != nil { withAnimation(.snappy) { toolsOpen = false } }
        }
        .onChange(of: toolsOpen) { _, open in
            if open { withAnimation(.snappy) { activeSetting = nil } }
        }
        .sensoryFeedback(.success, trigger: camera.liveInfo.afState == 1)
        .sensoryFeedback(.error, trigger: camera.lastError)
    }

    // MARK: - Layouts

    /// Landscape safe-area insets are symmetric, so ask the scene which way round the phone is.
    /// `.landscapeRight` means the top of the phone (and the island) is on the left.
    static func islandOnLeading(size: CGSize) -> Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.effectiveGeometry.interfaceOrientation == .landscapeRight
    }

    /// Portrait, like the iPhone Camera app: status on top, a clean viewfinder, and everything you
    /// touch in one band at the bottom (values → modes → shutter).
    private var portraitLayout: some View {
        VStack(spacing: 10) {
            HStack {
                StatusPill()
                Spacer(minLength: 0)
                menuButton
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
            liveView
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .top) { ErrorBanner().padding(.top, 8) }
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                VStack(spacing: 12) {
                    optionPanel
                    ExposureStrip(active: $activeSetting)
                }
                if toolsOpen {
                    ToolsTray(tools: tools)
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.horizontal, 12)
            ModeCarousel()
                .padding(.vertical, 2)
            shutterRow
                .padding(.bottom, 4)
        }
    }

    /// Landscape, like Final Cut Camera: a big viewfinder with values along its bottom edge and a
    /// rail of mode carousel and shutter under the thumb.
    private func landscapeLayout(railOnLeading: Bool) -> some View {
        HStack(spacing: 10) {
            if railOnLeading { landscapeRail }
            liveView
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        HStack {
                            StatusPill()
                            Spacer(minLength: 0)
                        }
                        ErrorBanner()
                    }
                    .padding(10)
                }
                .overlay(alignment: .bottom) {
                    ZStack(alignment: .bottom) {
                        // The loupe has its own controls at the bottom of the viewfinder.
                        if !showLoupe {
                            VStack(spacing: 8) {
                                optionPanel.frame(maxWidth: 440)
                                ExposureStrip(active: $activeSetting, compact: true)
                                    .frame(maxWidth: 520)
                            }
                            .transition(.opacity)
                        }
                        if toolsOpen {
                            ToolsTray(tools: tools).frame(maxWidth: 440)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity)
            if !railOnLeading { landscapeRail }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var landscapeRail: some View {
        VStack(spacing: 10) {
            menuButton
            ModeCarousel(axis: .vertical)
                .frame(maxHeight: 130)
            Spacer(minLength: 0)
            ShutterButton()
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                LastShotButton { showGallery = true }
                    .disabled(camera.isBusyExposing || camera.interval.running)
                ToolsButton(open: $toolsOpen)
                    .scaleEffect(0.85)
            }
        }
        .frame(width: 128)
        .padding(.vertical, 6)
    }

    // MARK: - Pieces

    private var liveView: some View {
        LiveViewPane(showGrid: showGrid, showHistogram: showHistogram, showLoupe: $showLoupe,
                     hudTopInset: isLandscape ? 46 : 0)
            .clipShape(.rect(cornerRadius: isLandscape ? 18 : 0, style: .continuous))
    }

    @ViewBuilder private var optionPanel: some View {
        if let name = activeSetting, let spec = SettingSpec.spec(for: name), camera.properties[name] != nil {
            OptionPanel(spec: spec) {
                withAnimation(.bouncy(duration: 0.35)) { activeSetting = nil }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))))
            .id(name)
        }
    }

    private var menuButton: some View {
        Menu {
            Section(camera.cameraName ?? "Camera") {
                Picker(selection: Binding(get: { camera.liveViewQuality },
                                          set: { q in Task { await camera.changeLiveViewQuality(q) } })) {
                    ForEach(camera.availableLiveViewSizes, id: \.self) { Text(CameraModel.liveViewLabel($0)).tag($0) }
                } label: {
                    Label("Live view size", systemImage: "rectangle.dashed")
                }
                .pickerStyle(.menu)
                Button { Task { await camera.restartLiveView() } } label: {
                    Label("Restart live view", systemImage: "arrow.clockwise")
                }
            }
            Section {
                Button { showHighRes = true } label: {
                    Label("High Res Shot helper", systemImage: "square.grid.3x3.square")
                }
                Button {
                    Task { if await camera.syncClock() { camera.showToast("Camera clock set to this iPhone") } }
                } label: {
                    Label("Sync camera clock", systemImage: "clock.arrow.2.circlepath")
                }
                Button { showAllSettings = true } label: {
                    Label("All camera settings", systemImage: "list.bullet")
                }
                Button { showLog = true } label: {
                    Label("Request log", systemImage: "list.bullet.rectangle")
                }
            }
            Section {
                Button { confirmDisconnect = true } label: {
                    Label("Disconnect", systemImage: "wifi.slash")
                }
                Button(role: .destructive) { confirmPowerOff = true } label: {
                    Label("Turn camera off", systemImage: "power")
                }
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(camera.isBusyExposing)
        .accessibilityLabel("More")
    }

    private var tools: [ToolItem] {
        [
            ToolItem(id: "astro", icon: "moon.stars.fill", title: "Astro", on: false) {
                toolsOpen = false; showAstro = true
            },
            ToolItem(id: "interval", icon: "timer", title: "Interval", on: camera.interval.running) {
                toolsOpen = false; showInterval = true
            },
            ToolItem(id: "loupe", icon: "plus.magnifyingglass", title: "Loupe", on: showLoupe) {
                showLoupe.toggle(); withAnimation(.snappy) { toolsOpen = false }
            },
            ToolItem(id: "night", icon: "eye", title: "Night", on: nightMode) { nightMode.toggle() },
            ToolItem(id: "histogram", icon: "chart.bar.xaxis", title: "Histogram", on: showHistogram) { showHistogram.toggle() },
            ToolItem(id: "grid", icon: "grid", title: "Grid", on: showGrid) { showGrid.toggle() },
            ToolItem(id: "tap", icon: camera.touchShutter ? "hand.tap.fill" : "hand.tap",
                     title: camera.touchShutter ? "Tap shoots" : "Tap AF", on: camera.touchShutter) {
                camera.touchShutter.toggle()
            },
            ToolItem(id: "highres", icon: "square.grid.3x3.square", title: "High Res", on: false) {
                toolsOpen = false; showHighRes = true
            },
        ]
    }

    private var shutterRow: some View {
        HStack {
            LastShotButton { showGallery = true }
                .disabled(camera.isBusyExposing || camera.interval.running)
                .frame(width: 84)
            Spacer()
            ShutterButton()
            Spacer()
            ToolsButton(open: $toolsOpen)
                .frame(width: 84)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Tools

struct ToolItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let on: Bool
    let action: () -> Void
}

struct ToolButton: View {
    let item: ToolItem
    var compact = false

    var body: some View {
        Button(action: item.action) {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.bounce, value: item.on)
                if !compact {
                    Text(item.title).font(.system(size: 9, weight: .medium)).lineLimit(1)
                }
            }
            .foregroundStyle(item.on ? Theme.accent : Color.white)
            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(item.on ? .regular.tint(Theme.accent.opacity(0.25)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 14, style: .continuous))
        .sensoryFeedback(.selection, trigger: item.on)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item.on ? .isSelected : [])
    }
}

/// The latest capture as a thumbnail (opens the card browser); a card icon before the first shot.
struct LastShotButton: View {
    @Environment(CameraModel.self) private var camera
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let shot = camera.lastShot {
                    Image(uiImage: shot)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        .id(camera.shotCounter)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                }
            }
            .padding(3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 17, style: .continuous))
        .animation(.bouncy(duration: 0.45), value: camera.shotCounter)
        .accessibilityLabel(camera.lastShot == nil ? "Card" : "Last photo. Opens the card.")
    }
}

/// Shows interval progress next to the shutter while a sequence runs.
struct IntervalBadge: View {
    @Environment(CameraModel.self) private var camera
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if camera.interval.running {
                    Text(camera.interval.total == 0 ? "\(camera.interval.done)" : "\(camera.interval.done)/\(camera.interval.total)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .contentTransition(.numericText(value: Double(camera.interval.done)))
                    Text("interval").font(.system(size: 9))
                } else {
                    Image(systemName: "timer").font(.title3)
                }
            }
            .foregroundStyle(camera.interval.running ? Theme.accent : Color.white)
            .frame(width: 58, height: 58)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(camera.interval.running ? "Interval running, \(camera.interval.done) shots" : "Interval timer")
    }
}

/// Floating confirmation capsule.
struct ToastView: View {
    @Environment(CameraModel.self) private var camera

    var body: some View {
        if let toast = camera.toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// A blurred, oversized copy of the live view behind everything, so the glass picks up its colours.
struct AmbientBackground: View {
    @Environment(CameraModel.self) private var camera

    var body: some View {
        // Not animated: a cross-fading full-screen blur costs more than the live view itself.
        Color.black
            .overlay {
                if let frame = camera.ambientFrame {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 60)
                        .saturation(1.4)
                        .opacity(0.55)
                }
            }
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct NightVision: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.colorMultiply(Color(red: 1, green: 0.22, blue: 0.18))
        } else {
            content
        }
    }
}

struct ErrorBanner: View {
    @Environment(CameraModel.self) private var camera

    var body: some View {
        if let error = camera.lastError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(error).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                Button { withAnimation { camera.lastError = nil } } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .glassEffect(.regular.tint(.red.opacity(0.35)), in: .rect(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 12)
            .transition(.blurReplace)
        }
    }
}

struct ReadoutBar: View {
    @Environment(CameraModel.self) private var camera
    var compact = false
    /// Drawn on top of the live image (no outer padding, clear glass).
    var overlay = false

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            Text(camera.liveInfo.shutter ?? formatted("shutspeedvalue"))
            Text(camera.liveInfo.aperture ?? formatted("focalvalue"))
            Text(camera.liveInfo.expComp ?? formatted("expcomp"))
            Text(camera.liveInfo.iso ?? "ISO " + formatted("isospeedvalue"))
            Spacer(minLength: 0)
            Text("\(camera.fps) fps")
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(camera.fps)))
        }
        .contentTransition(.numericText())
        .animation(.snappy, value: camera.liveInfo)
        .font(.system(compact ? .footnote : .subheadline, design: .monospaced).weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, compact ? 7 : 10)
        .glassEffect(overlay ? .clear : .regular, in: .capsule)
        .padding(.horizontal, overlay ? 0 : 12)
    }

    private func formatted(_ name: String) -> String {
        guard let p = camera.properties[name] else { return "–" }
        return PropertyFormat.display(name, camera.dialOptions(for: p).value)
    }
}

struct ShutterButton: View {
    @Environment(CameraModel.self) private var camera
    @State private var pressed = false

    var body: some View {
        let enabled = camera.mode == .rec && !camera.isSwitchingMode
        let movie = camera.isMovieMode
        ZStack {
            // Interval progress wraps the shutter.
            if camera.interval.running, camera.interval.total > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(camera.interval.done) / CGFloat(camera.interval.total))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 102, height: 102)
                    .animation(.smooth, value: camera.interval.done)
            }
            if let started = camera.exposureStartedAt {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let elapsed = context.date.timeIntervalSince(started)
                    if let duration = camera.exposureDuration {
                        Circle()
                            .trim(from: 0, to: min(1, elapsed / duration))
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    } else {
                        Circle()
                            .trim(from: 0, to: 0.22)
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(elapsed * 140))
                    }
                }
                .frame(width: 102, height: 102)
                .transition(.opacity)
            }
            Group {
                if let started = camera.exposureStartedAt, let duration = camera.exposureDuration {
                    // Timed long exposure: big countdown in the shutter.
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let left = max(0, Int((duration - context.date.timeIntervalSince(started)).rounded(.up)))
                        Text(left > 0 ? "\(left)" : "NR")
                            .font(.system(size: left > 99 ? 22 : 28, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: left)
                    }
                    .frame(width: 68, height: 68)
                    .accessibilityLabel("Exposing")
                } else if (camera.isShooting && camera.isOpenEndedShutter) || camera.isRecordingMovie {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red)
                        .frame(width: pressed ? 26 : 30, height: pressed ? 26 : 30)
                } else {
                    Circle()
                        .fill(movie ? Color.red : (camera.isShooting ? Theme.accent : Color.white))
                        .frame(width: pressed ? 58 : 68, height: pressed ? 58 : 68)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
            }
            .frame(width: 90, height: 90)
            .glassEffect(.regular.interactive(), in: .circle)
            if let started = camera.isRecordingMovie ? camera.movieStartedAt
                : (camera.isOpenEndedShutter && camera.isShooting ? camera.exposureStartedAt : nil) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(context.date.timeIntervalSince(started)).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(.regular, in: .capsule)
                }
                .offset(y: -62)
            }
        }
        .frame(width: 104, height: 104)
        .animation(.spring(duration: 0.18), value: pressed)
        .animation(.snappy, value: camera.isShooting)
        .animation(.snappy, value: camera.isRecordingMovie)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !pressed else { return }
                    pressed = true
                    if !camera.isOpenEndedShutter && !camera.isMovieMode {
                        Task { await camera.shutterPressed() }
                    }
                }
                .onEnded { _ in
                    guard pressed else { return }
                    pressed = false
                    if camera.isMovieMode {
                        Task { await camera.toggleMovie() }
                    } else if camera.isOpenEndedShutter {
                        Task { await camera.toggleOpenExposure() }
                    } else {
                        Task { await camera.shutterReleased() }
                    }
                }
        )
        .opacity(enabled ? 1 : 0.4)
        .animation(.smooth, value: camera.exposureStartedAt)
        .sensoryFeedback(.impact(weight: .medium), trigger: camera.shotCounter)
        .sensoryFeedback(.start, trigger: camera.isRecordingMovie)
        .accessibilityElement()
        .accessibilityLabel(movie ? (camera.isRecordingMovie ? "Stop recording" : "Record movie") : "Shutter")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            Task {
                if camera.isMovieMode {
                    await camera.toggleMovie()
                } else if camera.isOpenEndedShutter {
                    await camera.toggleOpenExposure()
                } else {
                    await camera.shutterPressed()
                    await camera.shutterReleased()
                }
            }
        }
    }
}

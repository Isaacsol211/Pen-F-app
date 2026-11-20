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
    @State private var showBracket = false
    @State private var pocketMode = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Theme.background.ignoresSafeArea()
                if landscape {
                    // Keep the shutter rail on the side away from the Dynamic Island.
                    landscapeLayout(railOnLeading: !Self.islandOnLeading(size: geo.size), size: geo.size)
                        .transition(.opacity)
                } else {
                    portraitLayout(height: geo.size.height)
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
        .sheet(isPresented: $showBracket) {
            BracketView().presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $pocketMode) { PocketModeView() }
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
        // TODO: Modernization - Window bounds can't replace this check: it tells landscape-left from
        // landscape-right to keep the rail away from the Dynamic Island, and bounds don't say which way
        // round the phone is. But orientation doesn't say where the island is in a resized scene either
        // (iPhone Duo's inner screen, or a scene with a vertical bar on one edge), and
        // connectedScenes.first may not be the scene showing this view. Decide whether to keep this
        // heuristic, place the rail from @Environment(\.toolbarVerticalEdge) (iOS 27.1) where the
        // system puts a vertical bar, or fix the rail to one side when the island isn't beside it.
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.effectiveGeometry.interfaceOrientation == .landscapeRight
    }

    /// Portrait, like the iPhone Camera app: status on top, a clean viewfinder, and everything you
    /// touch in one band at the bottom (values → modes → shutter).
    private func portraitLayout(height: CGFloat) -> some View {
        // The quick-aid strip needs a tall screen; the Duo's outer screen keeps the aids in the tray.
        let showAids = height >= 740
        return VStack(spacing: 10) {
            InfoBar { menuButton }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
            // Viewfinder and readouts are one block, centred in the spare height like a camera's
            // rear screen (on short screens such as the Duo's outer one the spacers collapse).
            Spacer(minLength: 0)
            liveView
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .top) { ErrorBanner().padding(.top, 8) }
            VStack(spacing: 10) {
                optionPanel
                ExposureStrip(active: $activeSetting)
                if showAids {
                    QuickAidStrip(tools: quickAids)
                }
            }
            // The tools float over the picture rather than squeezing it.
            .overlay(alignment: .bottom) {
                if toolsOpen {
                    ToolsTray(tools: tools)
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.horizontal, 12)
            .zIndex(1)
            Spacer(minLength: 0)
            // LUMIX bodies have a physical mode dial the app can't read or turn.
            if camera.properties["takemode"] != nil {
                ModeCarousel()
                    .padding(.vertical, 2)
            }
            shutterRow
                .padding(.bottom, 4)
        }
    }

    /// Landscape, like Final Cut Camera: a big viewfinder and a rail with the mode dial and shutter
    /// under the thumb. The readouts go under the picture when there's room for them (the Duo's
    /// inner screen), and float over its bottom edge when there isn't (a phone on its side).
    private func landscapeLayout(railOnLeading: Bool, size: CGSize) -> some View {
        let imageWidth = max(0, size.width - 128 - 10 - 12)
        let imageHeight = min(size.height - 8, imageWidth * 3 / 4)
        let readoutsBelow = size.height - 8 - imageHeight >= 74
        return HStack(spacing: 10) {
            if railOnLeading { landscapeRail }
            VStack(spacing: 8) {
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
                        if !readoutsBelow { landscapeControls(overImage: true).padding(10) }
                    }
                if readoutsBelow {
                    landscapeControls(overImage: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: readoutsBelow ? .top : .center)
            if !railOnLeading { landscapeRail }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func landscapeControls(overImage: Bool) -> some View {
        VStack(spacing: 8) {
            // The loupe has its own controls at the bottom of the viewfinder.
            if !showLoupe || !overImage {
                optionPanel.frame(maxWidth: 480)
                ExposureStrip(active: $activeSetting, compact: overImage)
                    .frame(maxWidth: 620)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        // The tools float over the picture rather than squeezing it.
        .overlay(alignment: .bottom) {
            if toolsOpen {
                ToolsTray(tools: tools, columns: 6).frame(maxWidth: 620)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var landscapeRail: some View {
        VStack(spacing: 12) {
            menuButton
            Spacer(minLength: 0)
            // The mode dial sits right above the shutter, both under the thumb.
            if camera.properties["takemode"] != nil {
                ModeCarousel(axis: .vertical)
                    .frame(maxHeight: 140)
            }
            ShutterButton()
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                LastShotButton { showGallery = true }
                    .disabled(camera.isBusyExposing || camera.interval.running || !camera.capabilities.cardBrowser)
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
            .surface(.regular, in: .rect(cornerRadius: 26, style: .continuous))
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))))
            .id(name)
        }
    }

    private var menuButton: some View {
        Menu {
            Section(camera.cameraName ?? "Camera") {
                if !camera.availableLiveViewSizes.isEmpty {
                    Picker(selection: Binding(get: { camera.liveViewQuality },
                                              set: { q in Task { await camera.changeLiveViewQuality(q) } })) {
                        ForEach(camera.availableLiveViewSizes, id: \.self) { Text(CameraModel.liveViewLabel($0)).tag($0) }
                    } label: {
                        Label("Live view size", systemImage: "rectangle.dashed")
                    }
                    .pickerStyle(.menu)
                }
                Button { Task { await camera.restartLiveView() } } label: {
                    Label("Restart live view", systemImage: "arrow.clockwise")
                }
            }
            Section {
                if camera.capabilities.highResShot {
                    Button { showHighRes = true } label: {
                        Label("High Res Shot helper", systemImage: "square.grid.3x3.square")
                    }
                }
                if camera.capabilities.clockSync {
                    Button {
                        Task { if await camera.syncClock() { camera.showToast("Camera clock set to this iPhone") } }
                    } label: {
                        Label("Sync camera clock", systemImage: "clock.arrow.2.circlepath")
                    }
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
                if camera.capabilities.powerOff {
                    Button(role: .destructive) { confirmPowerOff = true } label: {
                        Label("Turn camera off", systemImage: "power")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: Theme.target, height: Theme.target)
        }
        .buttonStyle(.surfaceCircle)
        .tint(.white)
        .disabled(camera.isBusyExposing)
        .accessibilityLabel("More")
    }

    private var tools: [ToolItem] {
        let all = [
            ToolItem(id: "astro", icon: "moon.stars.fill", title: "Astro", on: false, opens: true) {
                toolsOpen = false; showAstro = true
            },
            ToolItem(id: "interval", icon: "timer", title: "Interval", on: camera.interval.running, opens: true) {
                toolsOpen = false; showInterval = true
            },
            ToolItem(id: "loupe", icon: "plus.magnifyingglass", title: "Loupe", on: showLoupe) {
                showLoupe.toggle(); withAnimation(.snappy) { toolsOpen = false }
            },
            ToolItem(id: "night", icon: "eye.fill", title: "Night", on: nightMode) { nightMode.toggle() },
            ToolItem(id: "histogram", icon: "chart.bar.xaxis", title: "Histogram", on: showHistogram) { showHistogram.toggle() },
            ToolItem(id: "grid", icon: "squareshape.split.3x3", title: "Grid", on: showGrid) { showGrid.toggle() },
            ToolItem(id: "peaking", icon: "scope", title: "Peaking", on: camera.focusPeaking) {
                camera.focusPeaking.toggle()
            },
            ToolItem(id: "bracket", icon: "square.stack.3d.down.right", title: "Bracket", on: camera.bracket.running,
                     opens: true) {
                toolsOpen = false; showBracket = true
            },
            ToolItem(id: "pocket", icon: "moon.zzz", title: "Pocket", on: false, opens: true) {
                toolsOpen = false; pocketMode = true
            },
            ToolItem(id: "geotag", icon: camera.geotagging ? "location.fill" : "location", title: "Geotag",
                     on: camera.geotagging) {
                camera.geotagging.toggle()
                camera.showToast(camera.geotagging ? "Geotagging on: saved photos get your location"
                                                   : "Geotagging off")
            },
            ToolItem(id: "tap", icon: camera.touchShutter ? "hand.tap.fill" : "hand.tap",
                     title: camera.touchShutter ? "Tap shoots" : "Tap AF", on: camera.touchShutter) {
                camera.touchShutter.toggle()
            },
            ToolItem(id: "highres", icon: "square.grid.3x3.square", title: "High Res", on: false, opens: true) {
                toolsOpen = false; showHighRes = true
            },
        ]
        let caps = camera.capabilities
        var shown = all.filter { item in
            switch item.id {
            case "highres": caps.highResShot
            case "tap": caps.tapToFocus
            default: true
            }
        }
        if caps.videoSwitch && caps.movie {
            // Video is a switch here when the camera's photo/video mode can't be read.
            let video = ToolItem(id: "video", icon: camera.videoMode ? "video.fill" : "video", title: "Video",
                                 on: camera.videoMode) {
                guard !camera.isRecordingMovie else { return }
                camera.videoMode.toggle()
                withAnimation(.snappy) { toolsOpen = false }
            }
            shown.insert(video, at: 0)
        }
        return shown
    }

    /// The aids worth one tap from the live screen, in the order a photographer reaches for them.
    private var quickAids: [ToolItem] {
        let order = ["grid", "histogram", "peaking", "loupe", "night"]
        let all = tools
        return order.compactMap { id in all.first { $0.id == id } }
    }

    private var shutterRow: some View {
        HStack {
            LastShotButton { showGallery = true }
                .disabled(camera.isBusyExposing || camera.interval.running || !camera.capabilities.cardBrowser)
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
    /// Opens its own screen (Astro, Interval…) rather than switching something on and off.
    var opens = false
    let action: () -> Void
}

struct ToolButton: View {
    let item: ToolItem
    var compact = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: item.action) {
            VStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 21, weight: .semibold))
                    .frame(height: 24)
                    .symbolEffect(.bounce, value: item.on)
                if !compact {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(item.on ? Theme.accent : Color.white)
            .frame(maxWidth: .infinity, minHeight: compact ? Theme.target : 66)
            .background(shape.fill(item.on ? Theme.accent.opacity(0.14) : Theme.surfaceRaised))
            .overlay(shape.stroke(item.on ? Theme.accent.opacity(0.85) : Theme.stroke, lineWidth: item.on ? 1.5 : 1))
            // Tools that open their own screen say so; the rest are switches.
            .overlay(alignment: .topTrailing) {
                if item.opens {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(item.on ? Theme.accent : Theme.tertiary)
                        .padding(7)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: item.on)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.opens ? "" : (item.on ? "On" : "Off"))
        .accessibilityHint(item.opens ? "Opens \(item.title)" : "")
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
        .surface(.regular.interactive(), in: .rect(cornerRadius: 17, style: .continuous))
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
        .surface(.regular.interactive(), in: .circle)
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
                .surface(.regular, in: .capsule)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
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
            .surface(.regular.tint(.red.opacity(0.35)), in: .rect(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 12)
            .transition(.blurReplace)
        } else if let note = camera.cameraNote {
            // Model-specific advice from the model table, until dismissed once for this model.
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent)
                Text(note).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                Button { withAnimation { camera.dismissCameraNote() } } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .surface(.regular.tint(Theme.accent.opacity(0.18)), in: .rect(cornerRadius: 18, style: .continuous))
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
        .surface(overlay ? .clear : .regular, in: .capsule)
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

    /// Interval or bracket progress, drawn as a ring around the shutter.
    private var sequenceProgress: CGFloat? {
        if camera.interval.running, camera.interval.total > 0 {
            return CGFloat(camera.interval.done) / CGFloat(camera.interval.total)
        }
        if camera.bracket.running, camera.bracket.total > 0 {
            return CGFloat(camera.bracket.done) / CGFloat(camera.bracket.total)
        }
        return nil
    }

    var body: some View {
        let enabled = camera.mode == .rec && !camera.isSwitchingMode && !camera.bracket.running
        let movie = camera.isMovieMode
        ZStack {
            // Interval progress wraps the shutter.
            if let progress = sequenceProgress {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 102, height: 102)
                    .animation(.smooth, value: progress)
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
                        Text(left >= 60 ? String(format: "%d:%02d", left / 60, left % 60) : (left > 0 ? "\(left)" : "NR"))
                            .font(.system(size: left >= 600 ? 18 : (left >= 60 ? 22 : 28), weight: .semibold, design: .rounded).monospacedDigit())
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
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 4))
            if let started = camera.isRecordingMovie ? camera.movieStartedAt
                : (camera.isOpenEndedShutter && camera.isShooting ? camera.exposureStartedAt : nil) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(context.date.timeIntervalSince(started)).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .surface(.regular, in: .capsule)
                }
                .offset(y: -62)
            } else if camera.bracket.running {
                Button { camera.cancelBracket() } label: {
                    HStack(spacing: 4) {
                        Text("\(camera.bracket.done + 1)/\(camera.bracket.total)\(camera.bracket.label.map { " · \($0)" } ?? "")")
                        Image(systemName: "xmark").font(.system(size: 8, weight: .heavy))
                    }
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .surface(.regular, in: .capsule)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .offset(y: -62)
                .accessibilityLabel("Cancel bracketing")
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

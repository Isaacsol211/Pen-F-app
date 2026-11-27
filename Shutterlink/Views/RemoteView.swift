import SwiftUI

struct RemoteView: View {
    @Environment(CameraModel.self) private var camera
    @State private var showGallery = false
    @State private var showLog = false
    @State private var showReport = false
    @State private var showAllSettings = false
    @State private var showAstro = false
    /// The Pro screen, with the locked tool that opened it.
    @State private var proPrompt: ProPrompt?
    /// The tool panel that is open: a sheet on a phone, a panel in the workspace inspector.
    @State private var openPanel: SidePanel?
    @State private var confirmPowerOff = false
    @State private var confirmDisconnect = false
    @State private var toolsOpen = false
    /// Exposure value whose dial is open (nil = closed, keeps the screen clean).
    @State private var activeSetting: String?
    /// The canvas is big enough for the workspace layouts (see `Workspace`): tools that are sheets on a
    /// phone open as panels in the inspector instead.
    @State private var isWorkspace = false
    #if !targetEnvironment(macCatalyst)
    /// The scene showing this screen (not just the first connected one).
    @State private var windowScene: UIWindowScene?
    #endif
    @AppStorage("ui.histogram") private var showHistogram = false
    @AppStorage("ui.grid") private var showGrid = false
    @AppStorage("ui.nightMode") private var nightMode = false
    @State private var showLoupe = false
    @State private var pocketMode = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let workspace = Workspace.isWorkspace(geo)
            ZStack {
                Theme.background.ignoresSafeArea()
                if workspace {
                    // The inspector (and with it the shutter) keeps to the side away from the
                    // system's vertical bar; with no bar it sits on the trailing side.
                    VerticalBarEdgeReader { barEdge in
                        if landscape {
                            workspaceLandscape(inspectorOnLeading: barEdge == .trailing, size: geo.size)
                        } else {
                            workspacePortrait(shutterOnLeading: barEdge == .trailing, size: geo.size)
                        }
                    }
                    .transition(.opacity)
                } else if landscape {
                    // Keep the shutter rail on the side away from the system's vertical bar, or,
                    // where there's no such bar, away from the Dynamic Island.
                    VerticalBarEdgeReader { barEdge in
                        landscapeLayout(railOnLeading: barEdge.map { $0 == .trailing } ?? !islandOnLeading,
                                        size: geo.size)
                    }
                    .transition(.opacity)
                } else {
                    portraitLayout(height: geo.size.height)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.35), value: landscape)
            .animation(.smooth(duration: 0.35), value: workspace)
            .onAppear { isWorkspace = workspace }
            .onChange(of: workspace) { _, value in isWorkspace = value }
        }
        #if !targetEnvironment(macCatalyst)
        .background(WindowSceneReader { windowScene = $0 })
        #endif
        .task { await camera.runSceneAssistant() }
        // The Mac menu bar and iPad keyboard shortcuts (see KeyCommands.swift).
        .focusedSceneValue(\.remoteActions, remoteActions)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        // Red night-vision mode keeps your eyes dark-adapted under the stars. Applied only when on:
        // a colour filter over the whole screen forces it to re-render offscreen on every frame.
        .modifier(NightVision(enabled: nightMode))
        .overlay(alignment: .top) { ToastView() }
        .sheet(isPresented: $showAllSettings) { AllSettingsView() }
        .sheet(isPresented: $showLog) { LogView() }
        .sheet(isPresented: $showReport) { ReportProblemView() }
        .sheet(isPresented: $showAstro) { AstroView() }
        .sheet(item: $proPrompt) { ProView(feature: $0.feature) }
        // A tool's sheet is only for the phone layouts; in the workspace the same state opens its panel.
        .sheet(item: Binding(get: { isWorkspace ? nil : openPanel }, set: { openPanel = $0 })) { panel in
            SidePanelView(panel: panel, openAstro: openAstroFromPresets, openFocusStack: openFocusStackFromPresets)
                .presentationDetents([.medium, .large])
                // Live view stays usable above the motion trigger, so the box can be dragged into place.
                .presentationBackgroundInteraction(panel == .motion ? .enabled(upThrough: .medium) : .automatic)
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

    /// Widest the portrait controls get, so they stay within reach on an iPad.
    static let controlsMaxWidth: CGFloat = 640

    /// Whether the Dynamic Island is on the leading side (phone layouts in landscape): the fallback
    /// for scenes with no vertical bar (iPhones without one, iOS before 27.1). Landscape safe-area
    /// insets are symmetric there, so ask this view's scene which way round the phone is.
    /// `.landscapeRight` means the top of the phone (and the island) is on the left.
    private var islandOnLeading: Bool {
        #if targetEnvironment(macCatalyst)
        false   // A Mac window has no island, and it always gets the workspace layouts anyway.
        #else
        // TODO: Modernization - Window bounds can't replace this check: it tells landscape-left from
        // landscape-right to keep the rail away from the Dynamic Island, and bounds don't say which way
        // round the phone is. Where the system has a vertical bar the rail already follows
        // @Environment(\.toolbarVerticalEdge); this orientation heuristic only runs where that is nil.
        // Decide whether to keep it there or fix the rail to one side when the island isn't beside it.
        windowScene?.effectiveGeometry.interfaceOrientation == .landscapeRight
        #endif
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
            liveView(cornerRadius: 0)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .top) { ErrorBanner().padding(.top, 8) }
            VStack(spacing: 10) {
                optionPanel
                ExposureStrip(active: $activeSetting)
                // While a setting's panel is open (Drive, ISO…) it gets the aids' room; they come back
                // when it closes.
                if showAids && activeSetting == nil {
                    QuickAidStrip(tools: quickAids)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: activeSetting == nil)
            // The tools float over the picture rather than squeezing it.
            .overlay(alignment: .bottom) {
                if toolsOpen {
                    ToolsTray(tools: tools)
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.horizontal, 12)
            // On an iPad the picture can use the full width; the controls stay a hand's width.
            .frame(maxWidth: Self.controlsMaxWidth)
            .zIndex(1)
            Spacer(minLength: 0)
            // LUMIX bodies have a physical mode dial the app can't read or turn.
            if camera.properties["takemode"] != nil {
                ModeCarousel()
                    .padding(.vertical, 2)
                    .frame(maxWidth: Self.controlsMaxWidth)
            }
            shutterRow
                .frame(maxWidth: Self.controlsMaxWidth)
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
                liveView(cornerRadius: 18, hudTopInset: 46)
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
                ToolsButton(open: $toolsOpen)
                    .scaleEffect(0.85)
            }
        }
        .frame(width: 128)
        .padding(.vertical, 6)
    }

    // MARK: - Workspace layouts (large canvases)

    /// A wide canvas: the picture as large as it goes, the status line above it, the aids under it,
    /// and an inspector column that keeps every exposure value, the histogram, the tools, the mode
    /// dial and the shutter in view. Nothing is hidden behind a tray.
    private func workspaceLandscape(inspectorOnLeading: Bool, size: CGSize) -> some View {
        let inspectorWidth = min(420, max(320, (size.width * 0.29).rounded()))
        // Five tiles in a row once they're wide enough for their labels; a tall inspector has height
        // to spare, so give it to the histogram.
        let side = inspector(tileColumns: inspectorWidth >= 390 ? 5 : 4, histogramHeight: size.height >= 900 ? 132 : 76)
            .frame(width: inspectorWidth)
        return HStack(spacing: 0) {
            if inspectorOnLeading {
                side
                Hairline(axis: .vertical).ignoresSafeArea(edges: .vertical)
            }
            VStack(spacing: 10) {
                InfoBar { menuButton }
                Spacer(minLength: 0)
                liveView(cornerRadius: 18, histogramOverImage: false)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay(alignment: .top) { ErrorBanner().padding(.top, 10) }
                Spacer(minLength: 0)
                QuickAidStrip(tools: workspaceAids)
                    .frame(maxWidth: 520)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !inspectorOnLeading {
                Hairline(axis: .vertical).ignoresSafeArea(edges: .vertical)
                side
            }
        }
    }

    /// A tall canvas: the picture across the full width, and under it a two-column deck: values
    /// and tools on one side, the histogram, aids, mode dial and shutter on the other.
    private func workspacePortrait(shutterOnLeading: Bool, size: CGSize) -> some View {
        // The deck keeps a usable height; in a nearly square window the picture gives way.
        let imageHeight = max(200, min(size.width * 3 / 4, size.height - 53 - 400))
        let shootWidth = min(360, max(300, (size.width * 0.38).rounded()))
        return VStack(spacing: 0) {
            InfoBar { menuButton }
            Hairline()
            liveView(cornerRadius: 0, histogramOverImage: false)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: imageHeight)
                .overlay(alignment: .top) { ErrorBanner().padding(.top, 8) }
            Hairline()
            HStack(spacing: 0) {
                if shutterOnLeading {
                    shootColumn.frame(width: shootWidth)
                    Hairline(axis: .vertical)
                }
                ScrollView {
                    controlSections(histogramHeight: nil, tileColumns: nil)
                        .padding(14)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity)
                if !shutterOnLeading {
                    Hairline(axis: .vertical)
                    shootColumn.frame(width: shootWidth)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// The inspector of the wide layout: everything you set, scrolling if it has to, over the
    /// shutter, which never scrolls away.
    private func inspector(tileColumns: Int, histogramHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                controlSections(histogramHeight: histogramHeight, tileColumns: tileColumns)
                    .padding(14)
            }
            .scrollIndicators(.hidden)
            Hairline()
            shutterCluster
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
    }

    /// The shooting column of the tall layout: histogram and aids over the mode dial and shutter.
    private var shootColumn: some View {
        VStack(spacing: 12) {
            HistogramCard(height: 72)
            QuickAidStrip(tools: workspaceAids)
            Spacer(minLength: 0)
            shutterCluster
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    /// Values, the open dial and the tools; or, while a tool's panel is open, that panel.
    /// `histogramHeight`: nil where the histogram is shown elsewhere (the tall layout's shooting column).
    @ViewBuilder private func controlSections(histogramHeight: CGFloat?, tileColumns: Int?) -> some View {
        if let panel = sidePanel {
            SidePanelView(panel: panel, onClose: { withAnimation(.snappy) { close(panel) } },
                          openAstro: openAstroFromPresets, openFocusStack: openFocusStackFromPresets)
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let histogramHeight {
                    HistogramCard(height: histogramHeight)
                }
                if camera.properties.isEmpty {
                    Text("Reading camera settings…")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 68)
                } else {
                    ExposureGrid(active: $activeSetting)
                }
                optionPanel
                ToolTiles(tools: tools.filter { item in !quickAids.contains { $0.id == item.id } }, columns: tileColumns)
            }
            .transition(.opacity)
        }
    }

    /// Mode dial over the shutter, with the last shot and the interval timer either side.
    private var shutterCluster: some View {
        VStack(spacing: 6) {
            // LUMIX bodies have a physical mode dial the app can't read or turn.
            if camera.properties["takemode"] != nil {
                ModeCarousel()
            }
            HStack {
                LastShotButton { showGallery = true }
                    .frame(width: 72)
                Spacer(minLength: 0)
                ShutterButton()
                Spacer(minLength: 0)
                IntervalBadge { withAnimation(.snappy) { toggle(.interval) } }
                    .frame(width: 72)
            }
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Menus and keyboard

    /// What the menu bar (Mac) and keyboard shortcuts (iPad) can do here: the same as the buttons.
    private var remoteActions: RemoteActions {
        RemoteActions(
            openCard: { showGallery = true },
            cardAvailable: !camera.isBusyExposing && !camera.interval.running && camera.capabilities.cardBrowser,
            allSettings: { showAllSettings = true },
            log: { showLog = true },
            disconnect: { confirmDisconnect = true },
            activeSetting: activeSetting,
            toggleDial: { name in
                // A dial lives where the tool panels do, so close any panel first.
                openPanel = nil
                withAnimation(.snappy) { activeSetting = activeSetting == name ? nil : name }
            },
            tools: tools)
    }

    // MARK: - Panels (sheets on a phone)

    /// The tool panel open in the inspector. One at a time: in the workspace they share it.
    private var sidePanel: SidePanel? { isWorkspace ? openPanel : nil }

    private func open(_ panel: SidePanel) {
        openPanel = panel
        if isWorkspace { activeSetting = nil }
    }

    private func close(_ panel: SidePanel) {
        if openPanel == panel { openPanel = nil }
    }

    private func toggle(_ panel: SidePanel) {
        if sidePanel == panel { close(panel) } else { open(panel) }
    }

    /// Presets → Astro: Astro is a sheet everywhere, so close the presets first.
    private func openAstroFromPresets() {
        leavePresets { showAstro = true }
    }

    /// Presets → Macro → Focus stack: the Bracket tool on its Focus tab.
    private func openFocusStackFromPresets() {
        UserDefaults.standard.set(true, forKey: "bracket.focus")
        leavePresets { withAnimation(.snappy) { open(.bracket) } }
    }

    /// Closes the presets, then runs `next`: on a phone the presets sheet has to go before another
    /// sheet can come up.
    private func leavePresets(then next: @escaping () -> Void) {
        let wasSheet = !isWorkspace
        close(.presets)
        if wasSheet {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: next)
        } else {
            next()
        }
    }

    // MARK: - Pieces

    /// `histogramOverImage` is off in the workspace layouts, which always show a big histogram in
    /// the inspector instead.
    private func liveView(cornerRadius: CGFloat, hudTopInset: CGFloat = 0, histogramOverImage: Bool = true) -> some View {
        LiveViewPane(showGrid: showGrid, showHistogram: showHistogram && histogramOverImage, showLoupe: $showLoupe,
                     hudTopInset: hudTopInset)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .bottom) {
                if let suggestion = camera.sceneSuggestion, !showLoupe {
                    SceneSuggestionPill(suggestion: suggestion) { applySuggestion(suggestion) }
                        .padding(10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: camera.sceneSuggestion?.id)
    }

    /// Recipes and settings run straight away; ND and Motion open their panel, ready to go.
    private func applySuggestion(_ suggestion: SceneSuggestion) {
        // Suggestions that change one setting (exposure, ISO, white balance) are free; the ones that
        // run a setup or open a Pro tool need Pro.
        let needsPro: Bool = switch suggestion.action {
        case .setting, .showGrid: false
        case .recipe, .freezeMotion, .exposeToTheRight, .openND: true
        }
        if needsPro, !ShutterlinkPro.shared.isUnlocked {
            proPrompt = ProPrompt(feature: suggestion.actionTitle)
            return
        }
        Task { await camera.applySceneSuggestion(suggestion) }
        if case .openND = suggestion.action { open(.nd) }
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
                if !camera.capabilities.liveViewSizes.isEmpty {
                    Picker(selection: Binding(get: { camera.liveViewQuality },
                                              set: { q in Task { await camera.changeLiveViewQuality(q) } })) {
                        ForEach(camera.capabilities.liveViewSizes, id: \.self) { Text(CameraModel.liveViewLabel($0)).tag($0) }
                    } label: {
                        Label("Live view size", systemImage: "rectangle.dashed")
                    }
                    .pickerStyle(.menu)
                }
                Button { Task { await camera.restartLiveView() } } label: {
                    Label("Restart live view", systemImage: "arrow.clockwise")
                }
                Toggle(isOn: Binding(get: { camera.sceneAssistantOn }, set: { camera.sceneAssistantOn = $0 })) {
                    Label("Scene suggestions", systemImage: "sparkle.magnifyingglass")
                }
                Toggle(isOn: Binding(get: { camera.autoSaveNewPhotos }, set: { camera.autoSaveNewPhotos = $0 })) {
                    Label("Save new photos to Photos", systemImage: "square.and.arrow.down.on.square")
                }
                Button {
                    proPrompt = ProPrompt(feature: nil)
                } label: {
                    Label {
                        Text("Shutterlink Pro")
                        Text(ShutterlinkPro.shared.statusText)
                    } icon: {
                        Image(systemName: "star.circle")
                    }
                }
            }
            Section {
                if camera.capabilities.highResShot {
                    Button { open(.highRes) } label: {
                        Label("High Res Shot helper", systemImage: "square.grid.3x3.square")
                    }
                }
                if camera.capabilities.clockSync {
                    Button {
                        Task { if await camera.syncClock() { camera.showToast("Camera clock set to this \(Platform.device)") } }
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
                Button { showReport = true } label: {
                    Label("Report a problem", systemImage: "exclamationmark.bubble")
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

    /// Runs a Pro tool's action when Pro is unlocked; otherwise opens the Pro screen for it.
    private func pro(_ feature: String, _ action: @escaping () -> Void) -> () -> Void {
        {
            if ShutterlinkPro.shared.isUnlocked {
                action()
            } else {
                withAnimation(.snappy) { toolsOpen = false }
                proPrompt = ProPrompt(feature: feature)
            }
        }
    }

    /// A Pro tool that opens its panel; `running` keeps it lit while it works with the panel closed.
    private func panelTool(_ panel: SidePanel, id: String, title: String, feature: String,
                           running: Bool = false) -> ToolItem {
        ToolItem(id: id, icon: panel.icon, title: title, on: running || sidePanel == panel, opens: true,
                 locked: !ShutterlinkPro.shared.isUnlocked, action: pro(feature) { toolsOpen = false; toggle(panel) })
    }

    private var tools: [ToolItem] {
        let all = [
            panelTool(.presets, id: "presets", title: "Presets", feature: "Presets"),
            // Stays on once applied; tapping it then turns it off and puts the old settings back.
            ToolItem(id: "astro", icon: "moon.stars.fill", title: "Astro", on: camera.isPresetOn(PresetRecipe.astro.id),
                     opens: !camera.isPresetOn(PresetRecipe.astro.id),
                     locked: !ShutterlinkPro.shared.isUnlocked, action: pro("Astro") {
                toolsOpen = false
                if camera.isPresetOn(PresetRecipe.astro.id) {
                    Task { await camera.undoPreset() }
                } else {
                    showAstro = true
                }
            }),
            panelTool(.interval, id: "interval", title: "Interval", feature: "The interval timer",
                      running: camera.interval.running),
            ToolItem(id: "loupe", icon: "plus.magnifyingglass", title: "Loupe", on: showLoupe) {
                showLoupe.toggle(); withAnimation(.snappy) { toolsOpen = false }
            },
            ToolItem(id: "night", icon: "eye.fill", title: "Night", on: nightMode) { nightMode.toggle() },
            ToolItem(id: "histogram", icon: "chart.bar.xaxis", title: "Histogram", on: showHistogram) { showHistogram.toggle() },
            ToolItem(id: "grid", icon: "squareshape.split.3x3", title: "Grid", on: showGrid) { showGrid.toggle() },
            ToolItem(id: "peaking", icon: "scope", title: "Peaking", on: camera.focusPeaking) {
                camera.focusPeaking.toggle()
            },
            panelTool(.bracket, id: "bracket", title: "Bracket", feature: "Bracketing and focus stacking",
                      running: camera.bracket.running),
            panelTool(.nd, id: "nd", title: "ND filter", feature: "The ND filter calculator"),
            panelTool(.motion, id: "motion", title: "Motion", feature: "The motion trigger", running: camera.motion.armed),
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
            panelTool(.highRes, id: "highres", title: "High Res", feature: "The High Res Shot helper"),
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

    /// The workspace layouts keep the histogram in view in the inspector, so it isn't a switch there.
    private var workspaceAids: [ToolItem] {
        quickAids.filter { $0.id != "histogram" }
    }

    private var shutterRow: some View {
        HStack {
            LastShotButton { showGallery = true }
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
    /// A Pro tool while Pro is locked: shows a lock, and tapping it opens the Pro screen.
    var locked = false
    let action: () -> Void
}

struct ToolButton: View {
    let item: ToolItem

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: item.action) {
            VStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 21, weight: .semibold))
                    .frame(height: 24)
                    .symbolEffect(.bounce, value: item.on)
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(item.on ? Theme.accent : Color.white)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(shape.fill(item.on ? Theme.accent.opacity(0.14) : Theme.surfaceRaised))
            .overlay(shape.stroke(item.on ? Theme.accent.opacity(0.85) : Theme.stroke, lineWidth: item.on ? 1.5 : 1))
            // Tools that open their own screen say so; the rest are switches.
            .overlay(alignment: .topTrailing) {
                if item.locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(7)
                } else if item.opens {
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
        .accessibilityHint(item.locked ? "Part of Shutterlink Pro" : (item.opens ? "Opens \(item.title)" : ""))
    }
}

/// The latest capture as a thumbnail (opens the card browser); a card icon before the first shot.
/// Greyed out while the card can't be browsed.
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
        .surface(.regular, in: .rect(cornerRadius: 17, style: .continuous))
        .animation(.bouncy(duration: 0.45), value: camera.shotCounter)
        .disabled(camera.isBusyExposing || camera.interval.running || !camera.capabilities.cardBrowser)
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
        .surface(.regular, in: .circle)
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
    /// Long messages show three lines until tapped, so the banner doesn't bury the live view.
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 6) {
            if let error = camera.lastError {
                banner(error, icon: "exclamationmark.triangle.fill", color: .yellow, tint: .red.opacity(0.35)) {
                    camera.lastError = nil
                }
            } else if let note = camera.cameraNote {
                // Model-specific advice from the model table, until dismissed once for this model.
                banner(note, icon: "info.circle.fill", color: Theme.accent, tint: Theme.accent.opacity(0.18)) {
                    camera.dismissCameraNote()
                }
            }
            // A one-tap setup that's on stays in view, with its way back.
            if let on = camera.presetUndo, !camera.presetRunning {
                Button {
                    Task { await camera.undoPreset() }
                } label: {
                    Label("\(on.title) on · Turn off", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .surface(.regular.tint(.green.opacity(0.35)), in: .capsule)
                .accessibilityHint("Puts back the settings from before \(on.title)")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: camera.presetUndo)
    }

    private func banner(_ text: String, icon: String, color: Color, tint: Color,
                        dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.footnote).lineLimit(expanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
            Button { withAnimation { dismiss() } } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .surface(.regular.tint(tint), in: .rect(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .transition(.blurReplace)
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
            Task { await camera.pressShutterOnce() }
        }
    }
}

/// Hands its content the edge where the system places its vertical bar (iOS 27.1), or nil where
/// the system never places one (iPhones without one, earlier iOS).
private struct VerticalBarEdgeReader<Content: View>: View {
    @ViewBuilder var content: (HorizontalEdge?) -> Content

    var body: some View {
        if #available(iOS 27.1, *) {
            Reader(content: content)
        } else {
            content(nil)
        }
    }

    @available(iOS 27.1, *)
    private struct Reader: View {
        @Environment(\.toolbarVerticalEdge) private var edge
        var content: (HorizontalEdge?) -> Content

        var body: some View { content(edge) }
    }
}

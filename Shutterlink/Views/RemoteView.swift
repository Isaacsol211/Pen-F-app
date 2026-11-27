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
    /// Drive or Quality, whose options open in a sheet from the small line under the picture.
    @State private var settingSheet: String?
    @State private var showMore = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let workspace = Workspace.isWorkspace(geo)
            ZStack {
                Theme.background.ignoresSafeArea()
                if workspace || landscape { LiveBackdrop() }
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
        // The design's bottom panels (208, 209, 219–221), drawn by the app, edge to edge.
        .dPanel(isPresented: $toolsOpen, title: "Tools") {
            ToolsSheet(tools: tools, isOpen: $toolsOpen)
        }
        .dPanel(isPresented: Binding(get: { settingSheet != nil }, set: { if !$0 { settingSheet = nil } }),
                title: settingSheet.flatMap { SettingSpec.spec(for: $0)?.title }) {
            if let name = settingSheet, let spec = SettingSpec.spec(for: name) { SettingSheet(spec: spec) }
        }
        .dPanel(isPresented: $showMore, title: camera.cameraName ?? "Camera") {
            moreSheet
        }
        .modifier(NightVision(enabled: nightMode))
        .overlay {
            ZStack {
                if confirmDisconnect {
                    DialogCard(title: "Disconnect from the camera?", action: "Disconnect", compact: true,
                               onAction: { confirmDisconnect = false; Task { await camera.disconnect() } },
                               onCancel: { confirmDisconnect = false })
                }
                if confirmPowerOff {
                    DialogCard(title: "Turn the camera off?",
                               message: "You'll need to switch it on and start Wi-Fi on the camera again to reconnect.",
                               action: "Turn off",
                               onAction: { confirmPowerOff = false; Task { await camera.powerOff() } },
                               onCancel: { confirmPowerOff = false })
                }
            }
            .animation(Motion.shutter, value: confirmDisconnect || confirmPowerOff)
        }
        .overlay(alignment: .top) { ToastView() }
        // Design screens: full screen on a phone.
        .dScreen(isPresented: $showAllSettings) { AllSettingsView() }
        .dScreen(isPresented: $showLog) { LogView() }
        .dScreen(isPresented: $showReport) { ReportProblemView() }
        .dScreen(isPresented: $showAstro) { AstroView() }
        .dScreen(item: $proPrompt) { ProView(feature: $0.feature) }
        // A tool's screen is only for the phone layouts; in the workspace the same state opens its panel.
        .dScreen(item: Binding(get: { isWorkspace || openPanel == .motion ? nil : openPanel }, set: { openPanel = $0 })) { panel in
            SidePanelView(panel: panel, openAstro: openAstroFromPresets, openFocusStack: openFocusStackFromPresets)
        }
        .fullScreenCover(isPresented: $pocketMode) { PocketModeView() }
        .fullScreenCover(isPresented: $showGallery) { GalleryView() }
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

    /// Portrait: the whole live view near the top over a blurred copy of itself, a small line (white
    /// balance, drive, quality), the row of values, one big readout with a curved dial, then the shutter row.
    private func portraitLayout(height: CGFloat) -> some View {
        let names = ExposureStrip.items(camera)
        let selected = names.contains(activeSetting ?? "") || ["wbvalue"].contains(activeSetting ?? "")
            ? activeSetting!
            // Video mode opens on its exposure dial (215); otherwise the shutter (201).
            : (camera.isMovieMode && names.contains("exposemovie") ? "exposemovie"
               : names.contains("shutspeedvalue") ? "shutspeedvalue" : names.first { $0 != "takemode" } ?? names.first ?? "")
        let dialBinding = Binding<String?>(get: { selected }, set: { activeSetting = $0 })
        return ZStack {
            LiveBackdrop()
            VStack(spacing: 0) {
                InfoBar { menuButton }
                liveView(cornerRadius: 0, loupeControlsBelow: true)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay(alignment: .top) { ErrorBanner().padding(.top, 8) }
                if camera.properties.isEmpty {
                    Text("Reading camera settings…")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 0) {
                        if !showLoupe && openPanel != .motion {
                            SettingLine(active: dialBinding,
                                        aids: tools.filter { ["grid", "histogram", "peaking", "tap"].contains($0.id) }) { settingSheet = $0 }
                            ExposureStrip(active: dialBinding, selected: selected)
                                .padding(.horizontal, 12)
                        }
                        if openPanel == .motion {
                            // 311: the trigger's controls take the place of the remote's, under the picture
                            // with its box.
                            MotionPanel(close: { withAnimation(.snappy) { openPanel = nil } })
                                .padding(.horizontal, 20)
                                .padding(.top, 10)
                                .padding(.bottom, 8)
                                .transition(.opacity)
                        } else if showLoupe {
                            // 213: the loupe's zoom and focus reading take the dial's place.
                            LoupeReadout()
                                .padding(.top, 18)
                                .transition(.opacity)
                            Spacer(minLength: 0)
                        } else if camera.bracket.running {
                            // 218: the sequence's progress in place of the dial.
                            BigNumber(label: camera.bracket.isFocusStack ? "Focus stack" : "Bracketing",
                                      value: "\(camera.bracket.done + 1) of \(camera.bracket.total)",
                                      caption: camera.bracket.label, size: 68)
                                .padding(.top, 16)
                                .transition(.blurReplace)
                            Spacer(minLength: 0)
                        } else if camera.isBusyExposing && !camera.isRecordingMovie {
                            // A long or open exposure: one big running time in place of the dial.
                            ExposingReadout()
                                .padding(.top, 16)
                                .transition(.blurReplace)
                            Spacer(minLength: 0)
                        } else if let spec = SettingSpec.spec(for: selected), camera.properties[selected] != nil {
                            OptionPanel(spec: spec) { activeSetting = nil }
                                .id(selected)
                                .frame(maxHeight: .infinity, alignment: .top)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: Self.controlsMaxWidth)
                }
                if openPanel != .motion {
                    shutterRow
                        .frame(maxWidth: Self.controlsMaxWidth)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    /// Landscape, like Final Cut Camera: a big viewfinder and a rail with the mode dial and shutter
    /// under the thumb. The readouts go under the picture when there's room for them (the Duo's
    /// inner screen), and float over its bottom edge when there isn't (a phone on its side).
    private func landscapeLayout(railOnLeading: Bool, size: CGSize) -> some View {
        // 227: the picture fills everything beside a black rail; the status sits on it top left, the
        // values along a dark band at its bottom.
        HStack(spacing: 0) {
            if railOnLeading { landscapeRail }
            ZStack {
                // In an overlay so the filled picture can't make the screen's layout bigger.
                Color.clear
                    .overlay { liveView(cornerRadius: 0, hudTopInset: 50).aspectRatio(4.0 / 3.0, contentMode: .fill) }
                    .clipped()
                    .ignoresSafeArea()
                VStack(spacing: 8) {
                    HStack {
                        StatusPill(showsName: true)
                        Spacer(minLength: 0)
                    }
                    ErrorBanner()
                    Spacer(minLength: 0)
                    if !showLoupe { landscapeControls(overImage: true) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !railOnLeading { landscapeRail }
        }
    }

    private func landscapeControls(overImage: Bool) -> some View {
        VStack(spacing: 4) {
            optionPanel.frame(maxWidth: 480)
                .padding(.vertical, 6)
                .background {
                    if activeSetting != nil {
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LiveBackdrop.wash.opacity(0.8))
                    }
                }
            LandscapeValues(active: $activeSetting)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(colors: [LiveBackdrop.wash.opacity(0), LiveBackdrop.wash.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .padding(.horizontal, -16)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var landscapeRail: some View {
        // 227: a black rail: ⋯ at the top, the mode dial over the shutter, last shot and Tools below.
        VStack(spacing: 10) {
            menuButton
            Spacer(minLength: 0)
            if camera.properties["takemode"] != nil {
                ModeCarousel(axis: .vertical)
                    .frame(maxHeight: 110)
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
        .background(Theme.background.ignoresSafeArea())
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
            // A solid column beside the picture (design 502); the colour wash stays with the picture.
            .background(Theme.background.ignoresSafeArea())
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
                AidChips(tools: workspaceAids)
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
            // The deck is a solid surface, like the inspector in 502.
            .background(Theme.background.ignoresSafeArea(edges: .bottom))
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
            AidChips(tools: workspaceAids)
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
                    ExposureGrid(active: Binding(get: { workspaceSetting }, set: { activeSetting = $0 }))
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
    private func liveView(cornerRadius: CGFloat, hudTopInset: CGFloat = 0, histogramOverImage: Bool = true,
                          loupeControlsBelow: Bool = false) -> some View {
        LiveViewPane(showGrid: showGrid, showHistogram: showHistogram && histogramOverImage, showLoupe: $showLoupe,
                     hudTopInset: hudTopInset, loupeControlsBelow: loupeControlsBelow)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .bottom) {
                if let suggestion = camera.sceneSuggestion, !showLoupe, !Self.evHasNoEffect(suggestion, camera) {
                    SceneSuggestionPill(suggestion: suggestion) { applySuggestion(suggestion) }
                        .padding(10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: camera.sceneSuggestion?.id)
    }

    /// An EV suggestion in M with a fixed ISO: the camera takes the value but the picture doesn't change
    /// (in M, EV only steers Auto ISO), so it isn't offered, the same as the EV dial explains (205).
    static func evHasNoEffect(_ suggestion: SceneSuggestion, _ camera: CameraModel) -> Bool {
        guard case .setting(let property, _) = suggestion.action, property == "expcomp",
              camera.properties["takemode"]?.value.uppercased() == "M" else { return false }
        let iso = camera.properties["isospeedvalue"]?.value.lowercased() ?? ""
        return !iso.contains("auto")
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

    /// In the workspace one value is always selected, shutter first, like the phone remote.
    private var workspaceSetting: String? {
        if let activeSetting { return activeSetting }
        let names = ["shutspeedvalue", "focalvalue", "isospeedvalue"]
        return names.first { camera.properties[$0] != nil }
    }

    @ViewBuilder private var optionPanel: some View {
        if let name = (isWorkspace ? workspaceSetting : activeSetting), let spec = SettingSpec.spec(for: name), camera.properties[name] != nil {
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
        Button { showMore = true } label: {
            // "···" after the status, as on the iPad design (502); the phone design leaves it out, but
            // the menu needs a way in.
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: Theme.target, height: Theme.target)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(camera.isBusyExposing)
        .accessibilityLabel("More")
    }

    /// The ⋯ menu's rows (221), in the bottom panel.
    private var moreSheet: some View {
        MoreSheet(
            openPro: { showMore = false; proPrompt = ProPrompt(feature: nil) },
            openHighRes: { showMore = false; open(.highRes) },
            allSettings: { showMore = false; showAllSettings = true },
            log: { showMore = false; showLog = true },
            report: { showMore = false; showReport = true },
            disconnect: { withAnimation(.snappy) { showMore = false; confirmDisconnect = true } },
            powerOff: { withAnimation(.snappy) { showMore = false; confirmPowerOff = true } })
    }

    /// Runs `next` as the Tools panel closes. The panel is drawn by the app (not a sheet), so the
    /// screen it opens can come up straight away.
    private func afterSheet(_ next: @escaping () -> Void) {
        next()
    }

    /// Runs a Pro tool's action when Pro is unlocked; otherwise opens the Pro screen for it.
    private func pro(_ feature: String, _ action: @escaping () -> Void) -> () -> Void {
        {
            if ShutterlinkPro.shared.isUnlocked {
                action()
            } else {
                withAnimation(.snappy) { toolsOpen = false }
                afterSheet { proPrompt = ProPrompt(feature: feature) }
            }
        }
    }

    /// A Pro tool that opens its panel; `running` keeps it lit while it works with the panel closed.
    private func panelTool(_ panel: SidePanel, id: String, title: String, feature: String,
                           running: Bool = false) -> ToolItem {
        ToolItem(id: id, icon: panel.icon, title: title, on: running || sidePanel == panel, opens: true,
                 locked: !ShutterlinkPro.shared.isUnlocked, action: pro(feature) {
            // Bracket opens on Exposure; Focus stack has its own tile.
            if panel == .bracket { UserDefaults.standard.set(false, forKey: "bracket.focus") }
            toolsOpen = false; afterSheet { toggle(panel) }
        })
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
                    afterSheet { showAstro = true }
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
                      running: camera.bracket.running && !camera.bracket.isFocusStack),
            // Its own tile so it's easy to find; the same screen as Bracket, on its Focus tab (305–307).
            ToolItem(id: "focusstack", icon: "square.stack.3d.forward.dottedline", title: "Focus stack",
                     on: camera.bracket.running && camera.bracket.isFocusStack, opens: true,
                     locked: !ShutterlinkPro.shared.isUnlocked, action: pro("Bracketing and focus stacking") {
                UserDefaults.standard.set(true, forKey: "bracket.focus")
                toolsOpen = false
                afterSheet { toggle(.bracket) }
            }),
            panelTool(.nd, id: "nd", title: "ND filter", feature: "The ND filter calculator"),
            panelTool(.motion, id: "motion", title: "Motion", feature: "The motion trigger", running: camera.motion.armed),
            ToolItem(id: "pocket", icon: "moon.zzz", title: "Pocket", on: false, opens: true) {
                toolsOpen = false; afterSheet { pocketMode = true }
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
            ShutterButton(elapsedBadge: false)
            Spacer()
            ToolsButton(open: $toolsOpen)
                .frame(width: 84)
        }
        .padding(.horizontal, 24)
    }
}

/// The values along the bottom of the landscape picture (227): the selected one larger with its
/// label over it, the others in Barlow, white balance and drive at the end. Tap one for its dial.
struct LandscapeValues: View {
    @Environment(CameraModel.self) private var camera
    @Binding var active: String?

    var body: some View {
        let names = ExposureStrip.items(camera).filter { $0 != "takemode" }
        let selected = active ?? (names.contains("shutspeedvalue") ? "shutspeedvalue" : names.first)
        HStack(alignment: .lastTextBaseline, spacing: 26) {
            ForEach(names, id: \.self) { name in
                let on = name == selected
                Button {
                    withAnimation(.snappy) { active = active == name ? nil : name }
                } label: {
                    VStack(spacing: 2) {
                        if on {
                            Text((SettingSpec.spec(for: name)?.title ?? name).uppercased())
                                .font(.system(size: 11, weight: .medium)).tracking(1.5)
                                .foregroundStyle(Theme.accent)
                        }
                        Text(ExposureStrip.text(name, camera: camera))
                            .font(.num(on ? 40 : 22, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? Theme.text : Color(hex: 0xC9C5BA))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(minHeight: Theme.target, alignment: .bottom)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(SettingSpec.spec(for: name)?.title ?? name): \(ExposureStrip.text(name, camera: camera))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            let extras = ["wbvalue", "drivemode"].compactMap { name in
                camera.properties[name].map { camera.stripValue(name, camera.dialOptions(for: $0)) }
            }
            if !extras.isEmpty {
                Text(extras.joined(separator: " · "))
                    .font(.num(18, weight: .medium))
                    .foregroundStyle(Color(hex: 0xC9C5BA))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.bottom, 6)
        .padding(.leading, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: selected)
        .disabled(camera.isBusyExposing)
        .feedback(.select, trigger: active)
    }
}

/// While a long (timed) or open-ended exposure runs: what is happening, in the accent (red for an
/// open-ended one), over the running time at 100 pt (designs 216, 217).
struct ExposingReadout: View {
    @Environment(CameraModel.self) private var camera

    var body: some View {
        let open = camera.isOpenEndedShutter
        let started = camera.exposureStartedAt ?? camera.movieStartedAt
        let shutter = camera.properties["shutspeedvalue"]?.value ?? ""
        VStack(spacing: 4) {
            CapsLabel(open ? PropertyFormat.display("shutspeedvalue", shutter) : "Exposing",
                      color: open ? Theme.red : Theme.accent)
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let elapsed = started.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
                let shown = camera.exposureDuration.map { max(0, $0 - elapsed) } ?? elapsed
                Text(Duration.seconds(shown.rounded(.down))
                    .formatted(.time(pattern: .minuteSecond(padMinuteToLength: open ? 2 : 1))))
                    .font(.num(100))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(countsDown: camera.exposureDuration != nil))
                    .animation(.snappy, value: Int(shown))
                    .fixedSize()
                    .frame(height: 100)
            }
            Group {
                if let duration = camera.exposureDuration {
                    Text("of \(CameraModel.durationLabel(duration))")
                } else if camera.bulbTimer > 0 {
                    Text("The exposure stops by itself after \(CameraModel.durationLabel(camera.bulbTimer)), or when you tap the shutter.")
                } else {
                    Text("The exposure runs until you tap the shutter again.")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}


/// The live frame, blurred and dimmed to fill the screen behind the remote. Refreshed a couple of
/// times a second: it is only a colour wash, so it needn't follow every frame.
struct LiveBackdrop: View {
    enum Style {
        /// Behind the remote: the colour strongest around the values, dark under the dial and shutter.
        case remote
        /// Behind a sheet or a full-screen page (tools, presets, settings): dimmer, so rows stay readable.
        case page
    }
    @Environment(CameraModel.self) private var camera
    var style: Style = .remote
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.background
            if let image {
                // The overlay keeps the filled image from widening the screen's layout.
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            // A touch more colour than the frame: the wash should glow, not look muddy.
                            .saturation(1.35)
                            .brightness(0.04)
                            .scaleEffect(1.2)
                            .blur(radius: 36, opaque: true)
                            // Toned down like the design's dusk: real scenes are much brighter.
                            .brightness(-0.12)
                            .opacity(style == .remote ? 0.85 : 0.7)
                    }
                    .clipped()
            }
            // As in the design (D-SPEC, remote): clear down to just under the picture, near-black from
            // the dial down.
            switch style {
            case .remote:
                // Dark under the status line, a glow beside the picture, then near-black from just under
                // the picture so the small line, values and dial read crisply over any scene.
                LinearGradient(stops: [.init(color: Self.wash.opacity(0.72), location: 0),
                                       .init(color: Self.wash.opacity(0.35), location: 0.1),
                                       .init(color: Self.wash.opacity(0.3), location: 0.4),
                                       .init(color: Self.wash.opacity(0.82), location: 0.5),
                                       .init(color: Self.wash.opacity(0.96), location: 0.66)],
                               startPoint: .top, endPoint: .bottom)
            case .page:
                LinearGradient(stops: [.init(color: Self.wash.opacity(0.25), location: 0),
                                       .init(color: Self.wash.opacity(0.55), location: 0.45),
                                       .init(color: Self.wash.opacity(0.94), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            while !Task.isCancelled {
                if let frame = camera.liveFrame {
                    if image == nil { image = frame } else { withAnimation(.linear(duration: 0.5)) { image = frame } }
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    /// The design's dark wash, a hair warmer than the background.
    static let wash = Color(red: 6 / 255, green: 6 / 255, blue: 8 / 255)
}

/// Drive or Quality: the options in a sheet, the live view still above it.
struct SettingSheet: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    let spec: SettingSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let raw = camera.properties[spec.name] {
                let property = camera.dialOptions(for: raw)
                if property.settable {
                    OptionGrid(property: property) { value in
                        Task { await camera.setProperty(spec.name, to: value) }
                    }
                } else {
                    Text("Set this on the camera: this body doesn't let the phone change it right now.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
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
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: item.action) {
            VStack(spacing: 6) {
                glyph
                    .frame(width: 26, height: 26)
                    .scaleEffect(item.on ? 1.08 : 1)
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(item.on ? Theme.onAccent : Theme.text)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(shape.fill(item.on ? Theme.accent : Theme.surface.opacity(0.9)))
            .overlay(shape.stroke(item.on ? Color.clear : Theme.outline, lineWidth: 1))
            // Tools that open their own screen say so; the rest are switches.
            .overlay(alignment: .topTrailing) {
                if item.locked {
                    Image(systemName: "lock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(7)
                } else if item.opens {
                    Text("↗")
                        .font(.system(size: 12))
                        .foregroundStyle(item.on ? Theme.onAccent : Theme.secondary)
                        .padding(.trailing, 8)
                        .padding(.top, 4)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.25), value: item.on)
        .feedback(.select, trigger: item.on)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.opens ? "" : (item.on ? "On" : "Off"))
        .accessibilityHint(item.locked ? "Part of Shutterlink Pro" : (item.opens ? "Opens \(item.title)" : ""))
    }

    /// The design's drawn line icon for the tool (Assets ▸ Tools), or its SF Symbol where there's none.
    @ViewBuilder private var glyph: some View {
        if Self.drawn.contains(item.id) {
            Image("Tools/\(item.id)").resizable().scaledToFit()
        } else {
            Image(systemName: item.icon).font(.system(size: 21, weight: .regular))
        }
    }

    private static let drawn: Set<String> = ["presets", "astro", "interval", "bracket", "focusstack", "nd", "motion", "highres", "pocket",
                                             "video", "loupe", "night", "histogram", "grid", "peaking", "geotag", "tap"]
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
                        .frame(width: 48, height: 48)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        .id(camera.shotCounter)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(Theme.text)
                        .frame(width: 48, height: 48)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.text.opacity(0.4), lineWidth: 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(Theme.text)
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
            content.colorMultiply(Theme.red)
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
                banner(error, icon: "exclamationmark.triangle.fill", color: Theme.accent, tint: Theme.red.opacity(0.3)) {
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
                .surface(.regular.tint(Theme.green.opacity(0.25)), in: .capsule)
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
    /// The small running-time badge over the button; off in portrait, where the big readout shows it.
    var elapsedBadge = true
    @Environment(CameraModel.self) private var camera
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    /// Between letting go and the camera confirming the shot (the Wi-Fi round trip): the blades show it.
    @State private var awaiting = false

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
                    .frame(width: 90, height: 90)
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
                            .stroke(Theme.red, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(elapsed * 140))
                    }
                }
                .frame(width: 90, height: 90)
                .transition(.opacity)
            }
            Group {
                if let started = camera.exposureStartedAt, let duration = camera.exposureDuration {
                    // Timed long exposure: big countdown in the shutter.
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let left = max(0, Int((duration - context.date.timeIntervalSince(started)).rounded(.up)))
                        // m:ss as in 216 ("0:18"); NR while the camera reduces noise.
                        Text(left > 0 ? String(format: "%d:%02d", left / 60, left % 60) : "NR")
                                    .font(.num(left >= 600 ? 20 : 24))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: left)
                    }
                    .frame(width: 64, height: 64)
                    .accessibilityLabel("Exposing")
                } else if (camera.isShooting && camera.isOpenEndedShutter) || camera.isRecordingMovie {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.red)
                        .frame(width: pressed ? 26 : 30, height: pressed ? 26 : 30)
                } else {
                    Circle()
                        .fill(movie ? Theme.red : (camera.isShooting ? Theme.accent : Theme.text))
                        .frame(width: pressed ? 50 : 58, height: pressed ? 50 : 58)
                }
            }
            .frame(width: 74, height: 74)
            // The blades close over the button while the camera is asked, and open when it answers.
            .overlay {
                ShutterBlades(closing: awaiting, spinning: awaiting && !reduceMotion)
                    .frame(width: 58, height: 58)
                    .allowsHitTesting(false)
            }
            // The ring tightens under the finger.
            .overlay(Circle().stroke(Theme.text, lineWidth: pressed ? 4.5 : 3).scaleEffect(pressed ? 0.93 : 1))
            if let started = camera.isRecordingMovie ? camera.movieStartedAt
                : (elapsedBadge && camera.isOpenEndedShutter && camera.isShooting ? camera.exposureStartedAt : nil) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(context.date.timeIntervalSince(started)).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .surface(.regular, in: .capsule)
                }
                .offset(y: -58)
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
                .offset(y: -58)
                .accessibilityLabel("Cancel bracketing")
            }
        }
        .frame(width: 104, height: 104)
        .animation(Motion.track, value: pressed)
        .animation(.snappy, value: camera.isShooting)
        .animation(.snappy, value: camera.isRecordingMovie)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !pressed else { return }
                    pressed = true
                    Feedback.prepare()
                    if !camera.isOpenEndedShutter && !camera.isMovieMode {
                        // Half press: focus. The hand gets its answer now, not when the camera replies.
                        Feedback.play(.press)
                        Task { await camera.shutterPressed() }
                    }
                }
                .onEnded { _ in
                    guard pressed else { return }
                    pressed = false
                    Feedback.play(.shutter)
                    if camera.isMovieMode {
                        Task { await camera.toggleMovie() }
                    } else if camera.isOpenEndedShutter {
                        Task { await camera.toggleOpenExposure() }
                    } else {
                        waitForCamera(since: camera.shotCounter)
                        Task { await camera.shutterReleased() }
                    }
                }
        )
        // The camera's answer: the shot arrived, the exposure started or ended, or it refused.
        .onChange(of: camera.shotCounter) { awaiting = false }
        .onChange(of: camera.exposureStartedAt) { awaiting = false }
        .onChange(of: camera.lastError) { _, error in
            // The error pattern itself comes from FeedbackObserver (it covers every refusal, not only the shutter).
            if error != nil { awaiting = false }
        }
        .opacity(enabled ? 1 : 0.4)
        .animation(.smooth, value: camera.exposureStartedAt)
        .animation(Motion.shutter, value: awaiting)
        .accessibilityElement()
        .accessibilityLabel(movie ? (camera.isRecordingMovie ? "Stop recording" : "Record movie") : "Shutter")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            Task { await camera.pressShutterOnce() }
        }
    }
}

extension ShutterButton {
    /// Shows the blades until the camera confirms, or for at most 5 s (a camera that never says).
    fileprivate func waitForCamera(since counter: Int) {
        awaiting = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if camera.shotCounter == counter { awaiting = false }
        }
    }
}

/// Six blades of an iris over the shutter: open (invisible) at rest, closing to a small hexagon while
/// the camera is asked, turning slowly; they open again when it answers. With Reduce Motion they only
/// fade.
struct ShutterBlades: View {
    let closing: Bool
    let spinning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !spinning)) { context in
            let turn = spinning ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) * 60 : 0
            Canvas { ctx, size in
                let r = min(size.width, size.height) / 2
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let aperture = r * 0.42
                for i in 0..<6 {
                    let a = (Double(i) * 60 + turn) * .pi / 180
                    var blade = Path()
                    // Each blade: from the rim to a point on the small opening, swept by 60°.
                    blade.move(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
                    blade.addLine(to: CGPoint(x: c.x + r * cos(a + .pi / 3), y: c.y + r * sin(a + .pi / 3)))
                    blade.addLine(to: CGPoint(x: c.x + aperture * cos(a + .pi / 2.2), y: c.y + aperture * sin(a + .pi / 2.2)))
                    blade.addLine(to: CGPoint(x: c.x + aperture * cos(a + .pi / 6), y: c.y + aperture * sin(a + .pi / 6)))
                    blade.closeSubpath()
                    ctx.fill(blade, with: .color(Theme.onAccent.opacity(0.85)))
                    ctx.stroke(blade, with: .color(Theme.text.opacity(0.35)), lineWidth: 0.8)
                }
            }
            .clipShape(Circle())
        }
        .scaleEffect(closing ? 1 : 1.35)
        .opacity(closing ? 1 : 0)
        .accessibilityHidden(true)
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

/// The ⋯ menu as a sheet: the camera's name, then rows.
private struct MoreSheet: View {
    @Environment(CameraModel.self) private var camera
    let openPro: () -> Void
    let openHighRes: () -> Void
    let allSettings: () -> Void
    let log: () -> Void
    let report: () -> Void
    let disconnect: () -> Void
    let powerOff: () -> Void
    @AppStorage(Feedback.Key.haptics) private var haptics = true
    @AppStorage(Feedback.Key.sounds) private var sounds = false
    @AppStorage(Feedback.Key.quietOnTripod) private var quietOnTripod = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !camera.capabilities.liveViewSizes.isEmpty {
                    Menu {
                        Picker("Live view size", selection: Binding(get: { camera.liveViewQuality },
                                                                    set: { q in Task { await camera.changeLiveViewQuality(q) } })) {
                            ForEach(camera.capabilities.liveViewSizes, id: \.self) { Text(CameraModel.liveViewLabel($0)).tag($0) }
                        }
                    } label: {
                        row("Live view size", value: CameraModel.liveViewLabel(camera.liveViewQuality), chevron: true)
                    }
                }
                Button { Task { await camera.restartLiveView() } } label: { row("Restart live view") }
                toggle("Scene suggestions", isOn: Binding(get: { camera.sceneAssistantOn }, set: { camera.sceneAssistantOn = $0 }))
                toggle("Save new photos to Photos", isOn: Binding(get: { camera.autoSaveNewPhotos }, set: { camera.autoSaveNewPhotos = $0 }))
                Spacer().frame(height: 14)
                toggle("Haptics", isOn: $haptics)
                toggle("Sounds", isOn: $sounds)
                toggle("Quiet on tripod", isOn: $quietOnTripod)
                Text("No vibration or sound from this \(Platform.device) while the shutter is open: Bulb, long exposures and each frame of a series. Sounds follow the Ring/Silent switch.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                Button(action: openPro) {
                    row("Shutterlink Pro", value: ShutterlinkPro.shared.statusText, valueColor: Theme.accent, chevron: true)
                }
                Spacer().frame(height: 14)
                if camera.capabilities.highResShot {
                    Button(action: openHighRes) { row("High Res Shot helper", chevron: true) }
                }
                if camera.capabilities.clockSync {
                    Button {
                        Task { if await camera.syncClock() { camera.showToast("Camera clock set to this \(Platform.device)") } }
                    } label: { row("Sync camera clock") }
                }
                Button(action: allSettings) { row("All camera settings", chevron: true) }
                Button(action: log) { row("Request log", chevron: true) }
                Button(action: report) { row("Report a problem", chevron: true) }
                Spacer().frame(height: 14)
                Button(action: disconnect) { row("Disconnect") }
                if camera.capabilities.powerOff {
                    Button(action: powerOff) { row("Turn camera off", color: Theme.red) }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
    }

    private func row(_ title: String, value: String? = nil, valueColor: Color = Theme.secondary,
                     color: Color = Theme.text, chevron: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(color)
            Spacer(minLength: 8)
            if let value { Text(value).font(.system(size: 15)).foregroundStyle(valueColor).lineLimit(1) }
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary) }
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
        .hairRow()
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).font(.system(size: 16, weight: .medium)) }
            .tint(Theme.accent)
            .frame(minHeight: 52)
            .hairRow()
    }
}

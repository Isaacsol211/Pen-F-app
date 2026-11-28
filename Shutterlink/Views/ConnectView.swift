import SwiftUI

/// The home screen while not connected: the cameras this iPhone knows as cards (one tap to
/// reconnect), and "Add a camera" for a new one. First run shows an empty state instead.
struct ConnectView: View {
    @Environment(CameraModel.self) private var camera
    @State private var showAdd = false
    @State private var connectingID: String?
    /// Edit on "Your cameras": each card shows a button to forget it.
    @State private var editingCameras = false
    @State private var forgetting: SavedCamera?
    /// The canvas is big enough for the two-pane home (see `Workspace`).
    @State private var isWorkspace = false
    /// Brand whose steps the connection guide shows; until one is picked, the last camera's.
    @State private var guideBrand: CameraBrand?
    @State private var guidePicked = false
    @State private var showScanner = false
    @State private var scanNote: String?
    @State private var showReport = false

    var body: some View {
        GeometryReader { geo in
            let workspace = Workspace.isWorkspace(geo)
            ScrollView {
                if camera.phase == .connecting && !showAdd {
                    // 104: the whole screen says what's happening while it connects.
                    // The camera being connected: the card tapped, else the last one of this brand, else the
                    // network being joined, else the brand.
                    let saved = camera.savedCameras.first { $0.id == connectingID }
                        ?? (camera.autoDetectBrand ? nil : camera.savedCameras.filter { $0.brand == camera.brand }
                            .max { $0.lastUsed < $1.lastUsed })
                    ConnectingView(name: saved?.name ?? (camera.wifiSSID.isEmpty
                                                         ? (camera.autoDetectBrand ? "Camera" : camera.brand.shortTitle) : camera.wifiSSID),
                                   ssid: saved?.ssid ?? (camera.wifiSSID.isEmpty ? nil : camera.wifiSSID))
                        .frame(maxWidth: 560, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                } else if workspace {
                    workspaceContent(width: geo.size.width)
                } else {
                    cameras(grid: false, compactCover: geo.size.height < 600)
                        .frame(maxWidth: 560, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 56)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            // While connecting (104) the screen is only the connecting view; no footer.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !(camera.phase == .connecting && !showAdd) { footer(workspace: workspace) }
            }
            .onAppear { isWorkspace = workspace }
            .onChange(of: workspace) { _, value in isWorkspace = value }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        // 107: forgetting a camera asks in the design's dialog card.
        .overlay {
            ZStack {
                if let saved = forgetting {
                    DialogCard(title: "Forget \(saved.name)?",
                               message: "It comes off this list, with the Wi-Fi password Shutterlink saved for it. Connect again to add it back.",
                               action: "Forget this camera",
                               onAction: {
                                   withAnimation(.snappy) {
                                       camera.forget(saved)
                                       if camera.savedCameras.isEmpty { editingCameras = false }
                                   }
                                   forgetting = nil
                               },
                               onCancel: { forgetting = nil })
                }
            }
            .animation(.spring(duration: 0.28, bounce: 0), value: forgetting)
        }
        .background { ConnectBackground(firstRun: camera.savedCameras.isEmpty && camera.phase != .connecting) }
        .dScreen(isPresented: $showAdd) {
            AddCameraSheet(twoColumns: isWorkspace)
                .environment(camera)
        }
        .dScreen(isPresented: $showReport) {
            ReportProblemView()
                .environment(camera)
        }
        #if !targetEnvironment(macCatalyst)
        .dScreen(isPresented: $showScanner) {
            QRScannerSheet { camera.connectFromScannedCode($0) }
        }
        #endif
        .onChange(of: camera.phase) { _, phase in
            if phase != .connecting { connectingID = nil }
        }
        #if DEBUG
        // Design checks in the Simulator (no camera there): -designScreen 106 opens the scanner.
        .onAppear {
            if let i = CommandLine.arguments.firstIndex(of: "-designScreen"), CommandLine.arguments.count > i + 1,
               CommandLine.arguments[i + 1] == "106" { showScanner = true }
        }
        #endif
    }

    // MARK: - Workspace (large canvases)

    /// Widest the two-pane home gets, so lines stay readable on a 13-inch screen.
    static let workspaceMaxWidth: CGFloat = 1180

    /// Your cameras with Scan to connect, or on first run the cover. `grid`: the workspace home, where
    /// the cards go side by side and the tip sits under the guide instead.
    private func cameras(grid: Bool, compactCover: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if camera.savedCameras.isEmpty {
                cover(compact: compactCover)
                scanToConnect
                emptyState
            } else if grid {
                // 504: the lockup, the headline, then the cameras as cards side by side.
                BrandLockup(markSize: 44)
                    .padding(.top, 28)
                SolidHeadline("Shoot from\nyour \(Platform.isMac ? "Mac" : (UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "phone")).", size: 76)
                    .padding(.top, 16)
                scanToConnect
                cameraList(grid: true)
            } else {
                BrandLockup(markSize: 40)
                    .padding(.top, 20)
                scanToConnect
                cameraList(grid: false)
                tip
            }
        }
    }

    /// Two panes: your cameras as a grid of cards, and beside them the connection guide that is
    /// otherwise a sheet away.
    private func workspaceContent(width: CGFloat) -> some View {
        let guideWidth = min(440, max(330, (width * 0.36).rounded()))
        return HStack(alignment: .top, spacing: 32) {
            cameras(grid: true, compactCover: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 20) {
                guide
                if !camera.savedCameras.isEmpty { tip.padding(.horizontal, 4) }
            }
            .frame(width: guideWidth)
            .padding(.top, 28)
        }
        .frame(maxWidth: Self.workspaceMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    private var shownGuideBrand: CameraBrand? {
        guidePicked ? guideBrand : camera.savedCameras.max { $0.lastUsed < $1.lastUsed }?.brand
    }

    /// The connection steps for one brand, with the brands to switch between.
    private var guide: some View {
        let brand = shownGuideBrand
        return VStack(alignment: .leading, spacing: 16) {
            CapsLabel("How to connect", color: Theme.accent)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    guideChip(nil, selected: brand == nil)
                    ForEach(CameraBrand.allCases) { guideChip($0, selected: brand == $0) }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            Self.stepRows(for: brand)
            Spacer(minLength: 0)
        }
        .padding(20)
        // 504: the panel runs the height of the screen beside the cameras.
        .frame(maxWidth: .infinity, minHeight: 600, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .animation(.smooth, value: brand)
        .feedback(.select, trigger: brand)
    }

    private func guideChip(_ brand: CameraBrand?, selected: Bool) -> some View {
        Button {
            guideBrand = brand
            guidePicked = true
        } label: {
            Text(brand?.shortTitle ?? "Any")
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.background : Theme.secondary)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(selected ? Theme.text : Color.clear, in: .capsule)
                .overlay(Capsule().stroke(selected ? Color.clear : Theme.outline, lineWidth: 1))
                // 44 pt to tap, 36 pt to look at.
                .frame(minHeight: Theme.target)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(brand?.title ?? "Any camera")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Scan to connect

    /// iPhone and iPad: scan the QR code on the camera's screen and Shutterlink joins its Wi-Fi,
    /// connects and saves the camera with its network, so its card connects in one tap from then on.
    @ViewBuilder private var scanToConnect: some View {
        if CameraWiFi.canJoin && CameraCodeScanner.isSupported {
            let busy = camera.phase == .connecting && connectingID == nil && !showAdd
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task {
                        if await CameraCodeScanner.requestAccess() {
                            scanNote = nil
                            showScanner = true
                        } else {
                            scanNote = "Camera access is off. Turn it on in Settings ▸ Shutterlink ▸ Camera."
                        }
                    }
                } label: {
                    HStack(spacing: 14) {
                        Group {
                            if busy {
                                ProgressView().tint(Theme.onAccent)
                            } else {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 22, weight: .semibold))
                            }
                        }
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 40, height: 50)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(busy ? (camera.status ?? "Connecting…") : "Scan the camera's QR code")
                                .font(.headline)
                                .foregroundStyle(Theme.onAccent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text("Joins its Wi-Fi and connects. No trip to Settings.")
                                .font(.footnote)
                                .foregroundStyle(Theme.onAccent.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.accent))
                    .contentShape(.rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .disabled(camera.phase != .disconnected)
                .accessibilityHint("Scans the code on the camera's screen, joins its Wi-Fi and connects")
                if let scanNote {
                    Text(scanNote)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    // MARK: - First run

    private func cover(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            BrandLockup(markSize: compact ? 38 : 48)
            SolidHeadline("Shoot from\nyour phone.", size: compact ? 56 : 76)
                .padding(.top, compact ? 0 : 24)
            Text("Remote control for Olympus, OM System, Panasonic LUMIX, Nikon, Canon and Sony cameras over their own Wi-Fi.")
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Color(hex: 0xD8D4C9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, compact ? 16 : 32)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel("Your cameras")
            Text("No cameras yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Add your camera once. After that it waits here: turn on its Wi-Fi and tap it.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Saved cameras

    /// `grid`: cards side by side where the column is wide enough (the workspace home).
    private func cameraList(grid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CapsLabel("Your cameras")
                Spacer()
                Button(editingCameras ? "Done" : "Edit") {
                    withAnimation(.snappy) { editingCameras.toggle() }
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .frame(minHeight: Theme.target)
                .disabled(camera.phase != .disconnected)
            }
            .padding(.bottom, -10)
            // Under the heading, as designed (103).
            Text(CameraWiFi.canJoin
                 ? "Turn on the camera's Wi-Fi and tap it. A camera added by scanning joins its Wi-Fi by itself; for others, join it in Settings ▸ Wi-Fi first, or scan its code once."
                 : "Turn on the camera's Wi-Fi and join it in \(Platform.settings) ▸ Wi-Fi, then \(Platform.tap) it.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)
            if grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 12)], spacing: 12) {
                    ForEach(camera.savedCameras) { tile($0) }
                    addTile
                }

            } else {
                ForEach(Array(camera.savedCameras.enumerated()), id: \.element.id) { card($1, hero: $0 == 0) }
                addButton(minHeight: 60)
            }

        }
    }

    /// A camera as a card in the workspace home (504): name in Barlow, brand and when under it, a chevron.
    private func tile(_ saved: SavedCamera) -> some View {
        let connecting = camera.phase == .connecting && connectingID == saved.id
        let lastUsed = saved.lastUsed.formatted(.relative(presentation: .named))
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            connectingID = saved.id
            Task { await camera.connect(to: saved) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(saved.name).font(.num(28)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
                    CapsLabel(connecting ? (camera.status ?? "Connecting…") : "\(saved.brand.shortTitle) · \(lastUsed)",
                              color: connecting ? Theme.accent : Theme.secondary)
                }
                Spacer(minLength: 6)
                if connecting { ProgressView().tint(Theme.accent) } else if !editingCameras {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 72)
            .background(shape.fill(Theme.surface.opacity(0.85)))
            .overlay(shape.stroke(Theme.outline, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(camera.phase != .disconnected || editingCameras)
        .overlay(alignment: .trailing) {
            if editingCameras {
                Button { forgetting = saved } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 24))
                        .symbolRenderingMode(.palette).foregroundStyle(Theme.background, Theme.red)
                        .frame(width: Theme.target, height: Theme.target)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .accessibilityLabel("Forget \(saved.name)")
            }
        }
        .contextMenu {
            Button("Forget this camera", systemImage: "trash", role: .destructive) {
                withAnimation(.snappy) { camera.forget(saved) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(saved.name), \(saved.brand.title), last used \(lastUsed)")
        .accessibilityHint("Connects to this camera")
        .accessibilityAddTraits(.isButton)
    }

    /// "+ Add a camera" as a dashed card (504).
    private var addTile: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button { showAdd = true } label: {
            Text("+ Add a camera")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: 72)
                .overlay(shape.strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(camera.phase != .disconnected)
    }

    private func addButton(minHeight: CGFloat) -> some View {
        Button {
            showAdd = true
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 26, height: 26)
                    .overlay(Text("+").font(.system(size: 16)).foregroundStyle(Theme.secondary))
                Text("Add a camera")
            }
            .font(.system(size: 16))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(camera.phase != .disconnected)
    }

    private func card(_ saved: SavedCamera, hero: Bool = false) -> some View {
        let connecting = camera.phase == .connecting && connectingID == saved.id
        let lastUsed = saved.lastUsed.formatted(.relative(presentation: .named))
        return Button {
            connectingID = saved.id
            Task { await camera.connect(to: saved) }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: hero ? 8 : 3) {
                    if hero {
                        CapsLabel("\(saved.brand.shortTitle) · \(lastUsed)")
                    }
                    Text(saved.name)
                        .font(.num(hero ? 60 : 28, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if connecting {
                        Text(camera.status ?? "Connecting…")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                    } else if hero {
                        Text("Tap to connect")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    } else {
                        CapsLabel("\(saved.brand.shortTitle) · \(lastUsed)", color: Theme.tertiary)
                    }
                }
                Spacer(minLength: 8)
                if hero && !connecting { CameraLineArt().frame(width: 118, height: 84) }
                if connecting {
                    ProgressView().tint(Theme.accent)
                } else if !editingCameras && !hero {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .padding(hero ? 20 : 0)
            .padding(.vertical, hero ? 0 : 10)
            .frame(minHeight: hero ? 120 : 64)
            .background {
                if hero {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(connecting ? Theme.surfaceRaised : Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(connecting ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
                }
            }
            .overlay(alignment: .bottom) { if !hero { Hairline() } }
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(camera.phase != .disconnected || editingCameras)
        .overlay(alignment: .trailing) {
            if editingCameras {
                Button {
                    forgetting = saved
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.background, Theme.red)
                        .frame(width: Theme.target, height: Theme.target)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .accessibilityLabel("Forget \(saved.name)")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contextMenu {
            Button("Forget this camera", systemImage: "trash", role: .destructive) {
                withAnimation(.snappy) { camera.forget(saved) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(saved.name), \(saved.brand.title), last used \(lastUsed)")
        .accessibilityHint("Connects to this camera")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Forget this camera") { camera.forget(saved) }
    }

    private var tip: some View {
        Label {
            #if targetEnvironment(macCatalyst)
            // No Action button on a Mac; the same shortcut is in Shortcuts and Spotlight.
            Text("**One step next time:** run the \"Connect to Camera\" shortcut from Spotlight or the Shortcuts app, or give it a keyboard shortcut there. It reconnects to the camera you used last.")
            #else
            Text("**One tap next time:** put the \"Connect to Camera\" shortcut on the Action button (Settings ▸ Action Button ▸ Shortcut ▸ Shutterlink). It reconnects to the camera you used last.")
            #endif
        } icon: {
            Image(systemName: "bolt.circle").foregroundStyle(Theme.accent)
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondary)
    }

    // MARK: - Footer

    /// Problems and the Wi-Fi state stay in view; first run gets the Add button here too.
    private func footer(workspace: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = camera.lastError, !showAdd {
                ConnectErrorBanner(text: error, report: { showReport = true }) { camera.lastError = nil }
            }
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                WifiStatusRow(address: NetworkInfo.wifiAddress(), host: camera.host)
            }
            if camera.savedCameras.isEmpty && camera.phase != .connecting {
                Button {
                    showAdd = true
                } label: {
                    Text("Add your camera").frame(maxWidth: .infinity)
                }
                .buttonStyle(.outline)
                // In the workspace the button stays a button, not a bar across a 13-inch screen.
                .frame(maxWidth: workspace ? 360 : .infinity)
            }
        }
        .padding(.horizontal, workspace ? 32 : 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: workspace ? Self.workspaceMaxWidth + 64 : 600, alignment: workspace ? .leading : .center)
        .frame(maxWidth: .infinity)
        // A short fade, then solid: the list scrolls clear under it.
        .background(LinearGradient(stops: [.init(color: Theme.background.opacity(0), location: 0),
                                           .init(color: Theme.background, location: 0.14)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    /// A brand's setup steps, numbered, then its support note.
    @ViewBuilder static func stepRows(for brand: CameraBrand?) -> some View {
        ForEach(Array(steps(for: brand).enumerated()), id: \.offset) { index, step in
            StepRow(number: index + 1, title: step.title, detail: step.detail)
        }
        if let note = brand?.supportNote {
            Label(note, systemImage: "flask")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
    }

    /// Setup steps for a brand; nil = auto-detect.
    static func steps(for brand: CameraBrand?) -> [(title: String, detail: String)] {
        switch brand {
        case nil:
            return [
                ("Start the camera's Wi-Fi",
                 "Open its smartphone or Wi-Fi connection menu. Pick your brand above for the exact steps."),
                ("Join that network",
                 "\(Platform.settings) ▸ Wi-Fi ▸ the camera's network, with the password the camera shows. \"No Internet Connection\" is expected."),
                ("Connect",
                 "Allow Local Network access when \(Platform.os) asks. The app works out which camera it is from the network and by asking it."),
            ]
        case .olympus:
            return [
                ("Start Wi-Fi on the camera",
                 "Open Connection to Smartphone (OM System: Wi-Fi/Bluetooth ▸ Connection to Smartphone) and wait for the screen with the SSID, password and QR code."),
                ("Join that network",
                 "\(Platform.settings) ▸ Wi-Fi ▸ the camera's network (E-M10-P-…, PEN-F-P-…, OM-1-P-…) with the password from the camera. \"No Internet Connection\" is expected. If \(Platform.os) hops back to your home Wi-Fi, turn off Auto-Join for it."),
                ("Connect", "Allow Local Network access when \(Platform.os) asks. Live view needs it."),
            ]
        case .panasonic:
            return [
                ("Start Wi-Fi on the camera",
                 "MENU ▸ Setup ▸ Wi-Fi ▸ Wi-Fi Function ▸ New Connection ▸ Remote Shooting & View. The camera shows its network name."),
                ("Join that network",
                 "\(Platform.settings) ▸ Wi-Fi ▸ the camera's network (e.g. GH5-…). Enter the password if the camera shows one. \"No Internet Connection\" is expected."),
                ("Connect, then approve on the camera",
                 "Allow Local Network access when \(Platform.os) asks. The first time, the camera asks whether to connect to this \(Platform.device): choose Yes."),
            ]
        case .nikon:
            return [
                ("Start Wi-Fi on the camera",
                 "Z bodies: MENU ▸ Network ▸ Connect to smart device ▸ Wi-Fi connection ▸ Establish Wi-Fi connection. Older DSLRs with built-in Wi-Fi: turn Wi-Fi on in the Setup menu."),
                ("Join that network",
                 "\(Platform.settings) ▸ Wi-Fi ▸ the camera's network, with the password the camera shows. \"No Internet Connection\" is expected."),
                ("Connect", "Allow Local Network access when \(Platform.os) asks. If the camera asks to allow the connection, choose OK."),
            ]
        case .canon:
            return [
                ("Unlock CCAPI once",
                 "Canon locks third-party control until the camera is activated with Canon's free CCAPI tool (developer account, one time per camera). Without it the app can't connect."),
                ("Start Wi-Fi on the camera",
                 "MENU ▸ Wireless ▸ Wi-Fi ▸ the CCAPI connection, as camera access point, with HTTPS and user authentication turned off. Join the camera's network in \(Platform.settings) ▸ Wi-Fi."),
                ("Connect", "Allow Local Network access when \(Platform.os) asks."),
            ]
        case .sony:
            return [
                ("Start Smart Remote on the camera",
                 "Older Alpha / RX bodies: MENU ▸ Application ▸ Smart Remote Control (or Ctrl w/ Smartphone). Bodies from 2020 on (a7 IV, ZV-E10…) don't offer this to other apps."),
                ("Join that network",
                 "\(Platform.settings) ▸ Wi-Fi ▸ DIRECT-xxxx:ILCE-…, with the password the camera shows."),
                ("Connect", "Allow Local Network access when \(Platform.os) asks."),
            ]
        }
    }
}

/// New camera: pick the brand (or Automatic), follow its steps, connect. The camera is saved the
/// first time it connects.
struct AddCameraSheet: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    /// Opened from the workspace home: brands and steps go side by side when the sheet is wide enough.
    var twoColumns = false
    @State private var showAdvanced = false
    @State private var sheetWidth: CGFloat = 0
    @State private var showScanner = false
    @State private var scanNote: String?
    @State private var showReport = false

    private var selection: CameraBrand? { camera.autoDetectBrand ? nil : camera.brand }
    private var sideBySide: Bool { twoColumns && sheetWidth >= 660 }

    var body: some View {
        VStack(spacing: 0) {
            // A design screen (105): Cancel on the left, the title centred.
            ScreenHeader("Add a camera", centred: true, titleSize: 18) {
                HeaderButton("Cancel") {
                    camera.lastError = nil   // a failed try here shouldn't follow the user home
                    dismiss()
                }
                .disabled(camera.phase == .connecting)
                .padding(.leading, -8)
            } trailing: { EmptyView() }
            .padding(.top, 4)
            ScrollView {
                Group {
                    if sideBySide {
                        VStack(alignment: .leading, spacing: 20) {
                            scanButton
                            HStack(alignment: .top, spacing: 20) {
                                brandList
                                    .frame(maxWidth: .infinity)
                                VStack(alignment: .leading, spacing: 24) {
                                    stepsCard
                                    wifiCard
                                    advanced
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: 960)
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            scanButton
                            brandList
                            stepsCard
                            wifiCard
                            advanced
                        }
                        .frame(maxWidth: 560, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sheetWidth = $0 }
            .safeAreaInset(edge: .bottom, spacing: 0) { connectBar }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background.ignoresSafeArea())
        .dScreen(isPresented: $showReport) {
            ReportProblemView()
                .environment(camera)
        }
        #if !targetEnvironment(macCatalyst)
        .dScreen(isPresented: $showScanner) {
            QRScannerSheet { text in
                guard camera.applyScannedCode(text) else { return false }
                scanNote = nil
                Task { await camera.joinAndConnect() }
                return true
            }
        }
        #endif
        .presentationBackground(Theme.background)
        .presentationCornerRadius(28)
        .presentationSizing(WorkspaceSheetSizing(page: twoColumns))
        .tint(Theme.accent)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .interactiveDismissDisabled(camera.phase == .connecting)
    }

    private var brandList: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel("Camera")
            VStack(spacing: 0) {
                row(nil)
                ForEach(CameraBrand.allCases) { brand in
                    Hairline()
                    row(brand)
                }
            }
            .overlay(alignment: .top) { Hairline() }
            .disabled(camera.phase != .disconnected)
        }
    }

    private func row(_ brand: CameraBrand?) -> some View {
        let on = selection == brand
        return Button {
            withAnimation(.snappy) { camera.setBrand(brand) }
        } label: {
            // A radio row (105): the ring on the left, an outlined badge after the name.
            HStack(spacing: 14) {
                Circle()
                    .strokeBorder(on ? Theme.accent : Theme.tertiary, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay { if on { Circle().fill(Theme.accent).frame(width: 10, height: 10) } }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(brand?.title ?? "Automatic")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.text)
                        if brand == nil {
                            badge("Recommended", Theme.green)
                        } else if brand?.isBeta == true {
                            badge("Beta", Theme.accent)
                        }
                    }
                    Text(brand?.coverage ?? "Works out which camera it is from its Wi-Fi")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .feedback(.select, trigger: on)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CapsLabel("How to connect").padding(.bottom, 8)
            ConnectView.stepRows(for: selection)
        }
        .padding(.vertical, 8)
        .animation(.smooth, value: selection)
    }

    private var connectBar: some View {
        let connecting = camera.phase == .connecting
        return VStack(alignment: .leading, spacing: 10) {
            if let error = camera.lastError {
                ConnectErrorBanner(text: error, report: { showReport = true }) { camera.lastError = nil }
            }
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                WifiStatusRow(address: NetworkInfo.wifiAddress(), host: camera.host)
            }
            Button {
                Task { await camera.joinAndConnect() }
            } label: {
                HStack(spacing: 10) {
                    if connecting { ProgressView().tint(Theme.onAccent) }
                    Text(connecting ? (camera.status ?? "Connecting…") : (joinsWiFi ? "Join Wi-Fi and Connect" : "Connect"))
                        .contentTransition(.interpolate)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.accent)
            .disabled(connecting)
            .animation(.smooth, value: connecting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    /// Scans the camera's QR code, then joins its Wi-Fi and connects straight away.
    @ViewBuilder private var scanButton: some View {
        if CameraWiFi.canJoin && CameraCodeScanner.isSupported {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task {
                        if await CameraCodeScanner.requestAccess() {
                            scanNote = nil
                            showScanner = true
                        } else {
                            scanNote = "Camera access is off. Turn it on in Settings ▸ Shutterlink ▸ Camera, or type the name and password below."
                        }
                    }
                } label: {
                    // The accent card (105): the QR icon, the action, what it does.
                    HStack(spacing: 14) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 24, weight: .medium))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan the camera's QR code").font(.system(size: 17, weight: .semibold))
                            Text("Start the camera's smartphone connection so it shows a QR code. Shutterlink joins its Wi-Fi and connects.")
                                .font(.system(size: 13))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.accent))
                    .contentShape(.rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .disabled(camera.phase != .disconnected)
                if let scanNote {
                    Text(scanNote)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Connect joins the typed or scanned network first.
    private var joinsWiFi: Bool {
        CameraWiFi.canJoin && !camera.wifiSSID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// iPhone and iPad: Shutterlink joins the camera's network itself, from its QR code or its name and
    /// password, and remembers it so the camera's card does everything next time.
    @ViewBuilder private var wifiCard: some View {
        if CameraWiFi.canJoin {
            @Bindable var camera = camera
            VStack(alignment: .leading, spacing: 14) {
                CapsLabel("Or type the camera's Wi-Fi", color: Theme.accent)
                Text("The network name and password shown on the camera. Shutterlink joins it for you, and next time tapping the camera joins and connects in one go.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    wifiField("Network name", $camera.wifiSSID, label: "Camera network name")
                    Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 14)
                    wifiField("Password", $camera.wifiPassword, label: "Camera network password")
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceRaised))
                .disabled(camera.phase != .disconnected)
            }
            .padding(18)
            .surface(.regular, in: .rect(cornerRadius: 20, style: .continuous))
        }
    }

    private func wifiField(_ title: String, _ text: Binding<String>, label: String) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.target)
            .accessibilityLabel(label)
    }

    @ViewBuilder private var advanced: some View {
        @Bindable var camera = camera
        Button {
            withAnimation(.snappy) { showAdvanced.toggle() }
        } label: {
            HStack {
                CapsLabel("Advanced")
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.secondary)
                    .rotationEffect(.degrees(showAdvanced ? 0 : -90))
            }
            .frame(minHeight: Theme.target)
            .padding(.horizontal, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Advanced")
        .accessibilityValue(showAdvanced ? "Expanded" : "Collapsed")

        if showAdvanced {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Camera address") {
                    TextField(camera.autoDetectBrand ? "Automatic" : camera.brand.defaultHost, text: $camera.host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospaced())
                }
                if camera.brand == .olympus && !camera.autoDetectBrand {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("User-Agent").font(.subheadline).foregroundStyle(Theme.secondary)
                        Picker("User-Agent", selection: $camera.userAgent) {
                            ForEach(CameraModel.userAgents, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if !camera.autoDetectBrand, !camera.brand.defaultLiveViewSizes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live view size").font(.subheadline).foregroundStyle(Theme.secondary)
                        Picker("Live view size", selection: $camera.liveViewQuality) {
                            ForEach(camera.brand.defaultLiveViewSizes, id: \.self) {
                                Text(CameraModel.liveViewLabel($0)).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
                Text(camera.autoDetectBrand
                     ? "Leave the address empty and the app looks for the camera at each brand's usual address." + simulatorMockHint
                     : "The \(camera.brand.shortTitle) camera is normally at \(camera.brand.defaultHost)." + simulatorMockHint)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                #if targetEnvironment(macCatalyst)
                // The Mac joins the camera's network itself: open System Settings ▸ Wi-Fi.
                Button("Open Wi-Fi Settings", systemImage: "wifi") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.surface)
                #else
                Button("Open iPhone Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.surface)
                #endif
            }
            .padding(20)
            .surface(.regular, in: .rect(cornerRadius: 24, style: .continuous))
            .transition(.blurReplace)
        }
    }
}

private struct ConnectErrorBanner: View {
    let text: String
    var report: () -> Void
    var dismiss: () -> Void
    @State private var expanded = false

    var body: some View {
        // Long explanations open on request, so the banner doesn't cover the form.
        let long = text.count > 140
        // 107: a red outline on near-black, the message, "More" on the right; tap × to clear.
        HStack(alignment: .top, spacing: 10) {
            Text(text)
                .lineLimit(expanded || !long ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if long {
                Button(expanded ? "Less" : "More") { withAnimation(.snappy) { expanded.toggle() } }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .buttonStyle(.plain)
            }
            Button("Report", action: report)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            Button { withAnimation { dismiss() } } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .font(.system(size: 13))
        .lineSpacing(2)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.background.opacity(0.86)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.red, lineWidth: 1))
        .transition(.blurReplace)
    }
}

/// Pure black with a large, faint amber aperture breaking out of the top-right corner: the cover.
private struct ConnectBackground: View {
    /// First run: the picture itself across the top, fading to black (102). Otherwise blurred (103).
    var firstRun = false

    var body: some View {
        if firstRun {
            ZStack(alignment: .top) {
                Theme.background
                DuskScene().frame(height: 560).frame(maxWidth: .infinity).clipped()
                LinearGradient(stops: [.init(color: LiveBackdrop.wash.opacity(0.3), location: 0),
                                       .init(color: LiveBackdrop.wash.opacity(0.35), location: 0.3),
                                       .init(color: Theme.background, location: 0.62)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        } else {
            DuskBackdrop()
        }
    }
}

/// Shows this iPhone's Wi-Fi address. It can't prove the phone is on the camera's network:
/// many home routers also use 192.168.0.x, so only the network name in Settings tells for sure.
private struct WifiStatusRow: View {
    let address: String?
    let host: String

    var body: some View {
        let (icon, color, text): (String, Color, String) = {
            guard let address else { return ("wifi.slash", .orange, "This \(Platform.device) isn't on Wi-Fi") }
            // The phone should be on the camera's subnet (192.168.0.x for Olympus, 192.168.54.x for LUMIX).
            let octets = host.split(separator: ":").first.map { $0.split(separator: ".") } ?? []
            if octets.count == 4, octets[0] != "127", !address.hasPrefix(octets.prefix(3).joined(separator: ".") + ".") {
                return ("exclamationmark.triangle.fill", .orange,
                        "On another Wi-Fi network (\(address)). Join the camera's network first.")
            }
            return ("wifi", Theme.secondary,
                    "Wi-Fi \(address). Check \(Platform.settings) ▸ Wi-Fi shows the camera's network.")
        }()
        Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(color)
            .lineLimit(2)
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        // A numbered step (105): the first in an accent disc, the rest in an outlined ring.
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.num(18))
                .foregroundStyle(number == 1 ? Theme.onAccent : Theme.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(number == 1 ? Theme.accent : Color.clear))
                .overlay(Circle().strokeBorder(number == 1 ? Color.clear : Theme.tertiary, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Hairline() }
        // One VoiceOver stop per step; "▸" reads as "then".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number): \(title). \(detail.replacingOccurrences(of: " ▸ ", with: ", then "))")
    }
}

/// Where the mock cameras listen, shown under the address field in the Simulator only.
#if targetEnvironment(simulator) || (DEBUG && targetEnvironment(macCatalyst))
private let simulatorMockHint = " For the mock cameras, use 127.0.0.1 with the mock's port: 8080 Olympus, 8082 LUMIX, 15740 Nikon, 8084 Canon, 8086 Sony."
#else
private let simulatorMockHint = ""
#endif

/// A line drawing of a camera (body, hump, lens, viewfinder) for the saved-camera hero card.
private struct CameraLineArt: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let line = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            let body = Path(roundedRect: CGRect(x: 2, y: h * 0.28, width: w - 4, height: h * 0.68), cornerRadius: 12)
            ctx.stroke(body, with: .color(Theme.text.opacity(0.9)), style: line)
            var hump = Path()
            hump.move(to: CGPoint(x: w * 0.12, y: h * 0.28)); hump.addLine(to: CGPoint(x: w * 0.12, y: h * 0.14))
            hump.addLine(to: CGPoint(x: w * 0.34, y: h * 0.14)); hump.addLine(to: CGPoint(x: w * 0.34, y: h * 0.28))
            ctx.stroke(hump, with: .color(Theme.text.opacity(0.9)), style: line)
            let c = CGPoint(x: w * 0.56, y: h * 0.62)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52)), with: .color(Theme.text.opacity(0.9)), style: line)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)), with: .color(Theme.accent))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.82, y: h * 0.4, width: 7, height: 7)), with: .color(Theme.text.opacity(0.6)))
        }
        .accessibilityHidden(true)
    }
}

/// While connecting (104): the camera drawn in line with signal arcs, its name large, the current
/// status in the accent, and three steps (Wi-Fi, finding it, reading it) that tick off as the app's
/// own status lines move on.
struct ConnectingView: View {
    @Environment(CameraModel.self) private var camera
    let name: String
    var ssid: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which of the three steps the status is on.
    private var stage: Int {
        let s = camera.status ?? ""
        if s.hasPrefix("Waiting for the camera's Wi-Fi") { return 0 }
        if s.hasPrefix("Joining") || s.hasPrefix("Looking") || s.hasPrefix("Finding") || s.contains("retrying")
            || s.hasPrefix("Connecting") { return 1 }
        return 2
    }

    var body: some View {
        let status = camera.status ?? "Looking for the camera…"
        VStack(alignment: .leading, spacing: 0) {
            BrandLockup(markSize: 40).padding(.top, 20)
            ConnectingArt(animating: !reduceMotion)
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            Text(name)
                .font(.num(44))
                .foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(status)
                .font(.system(size: 17))
                .foregroundStyle(Theme.accent)
                .contentTransition(.interpolate)
                .padding(.top, 6)
            VStack(spacing: 0) {
                step(1, "Waiting for the camera's Wi-Fi…")
                step(2, stage == 1 ? status : (ssid.map { "Joining \($0)…" } ?? "Looking for the camera…"))
                step(3, stage == 2 ? status : "Reading camera info…")
            }
            .overlay(alignment: .top) { Hairline() }
            .padding(.top, 18)
        }
        .animation(.smooth, value: camera.status)
        .accessibilityElement(children: .contain)
    }

    private func step(_ n: Int, _ title: String) -> some View {
        let state = n - 1 < stage ? 0 : (n - 1 == stage ? 1 : 2)   // done, now, to do
        return HStack(spacing: 14) {
            ZStack {
                switch state {
                case 0:
                    Circle().fill(Theme.green)
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.background)
                case 1:
                    Circle().fill(Theme.accent)
                    Text("\(n)").font(.num(18)).foregroundStyle(Theme.background)
                default:
                    Circle().strokeBorder(Theme.tertiary, lineWidth: 1.5)
                    Text("\(n)").font(.num(18)).foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 30, height: 30)
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == 0 ? "Done" : (state == 1 ? "In progress" : "Not yet"))
    }
}

/// The camera in line (104), with two arcs under it that pulse outward while connecting.
private struct ConnectingArt: View {
    let animating: Bool

    var body: some View {
        TimelineView(.animation(paused: !animating)) { context in
            let t = animating ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 : 0.5
            Canvas { ctx, size in
                // The design's 390 × 300 drawing, centred.
                let k = min(size.width / 390, size.height / 300)
                ctx.translateBy(x: (size.width - 390 * k) / 2, y: (size.height - 300 * k) / 2)
                ctx.scaleBy(x: k, y: k)
                let line = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                let ink = GraphicsContext.Shading.color(Theme.text)
                ctx.stroke(Path(roundedRect: CGRect(x: 95, y: 50, width: 200, height: 120), cornerRadius: 16), with: ink, style: line)
                var hump = Path()
                hump.move(to: CGPoint(x: 165, y: 50)); hump.addLine(to: CGPoint(x: 177, y: 28))
                hump.addLine(to: CGPoint(x: 213, y: 28)); hump.addLine(to: CGPoint(x: 225, y: 50))
                ctx.stroke(hump, with: ink, style: line)
                ctx.stroke(Path(roundedRect: CGRect(x: 113, y: 38, width: 28, height: 12), cornerRadius: 3), with: ink, style: line)
                ctx.stroke(Path(roundedRect: CGRect(x: 250, y: 36, width: 26, height: 14), cornerRadius: 3), with: ink, style: line)
                ctx.stroke(Path(ellipseIn: CGRect(x: 149, y: 66, width: 92, height: 92)), with: ink, style: line)
                ctx.stroke(Path(ellipseIn: CGRect(x: 164, y: 81, width: 62, height: 62)), with: ink, style: line)
                ctx.fill(Path(ellipseIn: CGRect(x: 182, y: 99, width: 26, height: 26)), with: .color(Theme.accent))
                // Two arcs: the near one, then the far one, brightening in turn.
                for (i, r) in [(0, 50.0), (1, 90.0)] {
                    var arc = Path()
                    let cy = i == 0 ? 233.0 : 268.0
                    arc.addArc(center: CGPoint(x: 195, y: cy - r), radius: r, startAngle: .degrees(150), endAngle: .degrees(30), clockwise: true)
                    let phase = (t + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    let base = i == 0 ? 0.4 : 0.7
                    let alpha = animating ? 0.25 + 0.75 * (0.5 + 0.5 * sin(phase * 2 * .pi)) * base / 0.7 : base
                    ctx.stroke(arc, with: .color(Theme.accent.opacity(alpha)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

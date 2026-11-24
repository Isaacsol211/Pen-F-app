import SwiftUI

/// The home screen while not connected: the cameras this iPhone knows as cards (one tap to
/// reconnect), and "Add a camera" for a new one. First run shows an empty state instead.
struct ConnectView: View {
    @Environment(CameraModel.self) private var camera
    @State private var showAdd = false
    @State private var connectingID: String?
    /// The canvas is big enough for the two-pane home (see `Workspace`).
    @State private var isWorkspace = false
    /// Brand whose steps the connection guide shows; until one is picked, the last camera's.
    @State private var guideBrand: CameraBrand?
    @State private var guidePicked = false
    @State private var showScanner = false
    @State private var scanNote: String?

    var body: some View {
        GeometryReader { geo in
            let workspace = Workspace.isWorkspace(geo)
            ScrollView {
                if workspace {
                    workspaceContent(width: geo.size.width)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        if camera.savedCameras.isEmpty {
                            cover(compact: geo.size.height < 600)
                            scanToConnect
                            emptyState
                        } else {
                            BrandLockup(markSize: 40)
                                .padding(.top, 20)
                            scanToConnect
                            cameraList(grid: false)
                            tip
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer(workspace: workspace) }
            .onAppear { isWorkspace = workspace }
            .onChange(of: workspace) { _, value in isWorkspace = value }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .background { ConnectBackground() }
        .sheet(isPresented: $showAdd) {
            AddCameraSheet(twoColumns: isWorkspace)
                .environment(camera)
        }
        #if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { camera.connectFromScannedCode($0) }
        }
        #endif
        .onChange(of: camera.phase) { _, phase in
            if phase != .connecting { connectingID = nil }
        }
    }

    // MARK: - Workspace (large canvases)

    /// Widest the two-pane home gets, so lines stay readable on a 13-inch screen.
    static let workspaceMaxWidth: CGFloat = 1180

    /// Two panes: your cameras as a grid of cards, and beside them the connection guide that is
    /// otherwise a sheet away.
    private func workspaceContent(width: CGFloat) -> some View {
        let guideWidth = min(440, max(330, (width * 0.36).rounded()))
        return HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 24) {
                if camera.savedCameras.isEmpty {
                    cover(compact: false)
                    scanToConnect
                    emptyState
                } else {
                    BrandLockup(markSize: 44)
                        .padding(.top, 28)
                    scanToConnect
                    cameraList(grid: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 20) {
                guide
                if !camera.savedCameras.isEmpty { tip }
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
            ForEach(Array(Self.steps(for: brand).enumerated()), id: \.offset) { index, step in
                StepRow(number: index + 1, title: step.title, detail: step.detail)
            }
            if let note = brand?.supportNote {
                Label(note, systemImage: "flask")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .animation(.smooth, value: brand)
        .sensoryFeedback(.selection, trigger: brand)
    }

    private func guideChip(_ brand: CameraBrand?, selected: Bool) -> some View {
        Button {
            guideBrand = brand
            guidePicked = true
        } label: {
            Text(brand?.shortTitle ?? "Any")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Theme.onAccent : .white)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(selected ? Theme.accent : Theme.surfaceRaised, in: .capsule)
                .overlay(Capsule().stroke(selected ? Color.clear : Theme.stroke, lineWidth: 1))
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
                        .frame(width: 50, height: 50)
                        .background(Theme.accent, in: .rect(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(busy ? (camera.status ?? "Connecting…") : "Scan the camera's QR code")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text("Joins its Wi-Fi and connects. No trip to Settings.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.accent.opacity(0.6), lineWidth: 1))
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
            Text("Shoot from\nyour phone.")
                .font(.system(size: compact ? 30 : 38, weight: .heavy))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Remote control for Olympus, OM System, Panasonic LUMIX, Nikon, Canon and Sony cameras over their own Wi-Fi.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, compact ? 16 : 32)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            CapsLabel("Your cameras")
            VStack(spacing: 14) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("No cameras yet")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Add your camera once. After that it waits here: turn on its Wi-Fi and tap it.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
    }

    // MARK: - Saved cameras

    /// `grid`: cards side by side where the column is wide enough (the workspace home).
    private func cameraList(grid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel("Your cameras")
            Text(CameraWiFi.canJoin
                 ? "Turn on the camera's Wi-Fi and tap it. A camera added by scanning joins its Wi-Fi by itself; for others, join it in Settings ▸ Wi-Fi first, or scan its code once."
                 : "Turn on the camera's Wi-Fi and join it in \(Platform.settings) ▸ Wi-Fi, then \(Platform.tap) it.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            if grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12)], spacing: 12) {
                    ForEach(camera.savedCameras) { saved in
                        card(saved)
                    }
                    addButton(minHeight: 84)
                }
            } else {
                ForEach(camera.savedCameras) { saved in
                    card(saved)
                }
                addButton(minHeight: 60)
            }
        }
    }

    private func addButton(minHeight: CGFloat) -> some View {
        Button {
            showAdd = true
        } label: {
            Label("Add a camera", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(camera.phase != .disconnected)
    }

    private func card(_ saved: SavedCamera) -> some View {
        let connecting = camera.phase == .connecting && connectingID == saved.id
        let lastUsed = saved.lastUsed.formatted(.relative(presentation: .named))
        return Button {
            connectingID = saved.id
            Task { await camera.connect(to: saved) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 50, height: 50)
                    .background(Theme.accent, in: .rect(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(saved.name)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if connecting {
                        Text(camera.status ?? "Connecting…")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                    } else {
                        HStack(spacing: 6) {
                            CapsLabel(saved.brand.shortTitle)
                            Text("· \(lastUsed)")
                                .font(.footnote)
                                .foregroundStyle(Theme.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                if connecting {
                    ProgressView().tint(Theme.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .padding(16)
            .frame(minHeight: 84)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(connecting ? Theme.surfaceRaised : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(connecting ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(camera.phase != .disconnected)
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
                ConnectErrorBanner(text: error)
            }
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                WifiStatusRow(address: NetworkInfo.wifiAddress(), host: camera.host)
            }
            if camera.savedCameras.isEmpty {
                Button {
                    showAdd = true
                } label: {
                    Label("Add your camera", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.accent)
                // In the workspace the button stays a button, not a bar across a 13-inch screen.
                .frame(maxWidth: workspace ? 360 : .infinity)
            }
        }
        .padding(.horizontal, workspace ? 32 : 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: workspace ? Self.workspaceMaxWidth + 64 : 600, alignment: workspace ? .leading : .center)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
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
                 "MENU ▸ Wireless ▸ Wi-Fi ▸ the CCAPI connection, as camera access point. Join the camera's network in \(Platform.settings) ▸ Wi-Fi."),
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

    private var selection: CameraBrand? { camera.autoDetectBrand ? nil : camera.brand }
    private var sideBySide: Bool { twoColumns && sheetWidth >= 660 }

    var body: some View {
        NavigationStack {
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
            .background(Theme.background)
            .navigationTitle("Add a camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(camera.phase == .connecting)
                }
            }
        }
        #if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { text in
                guard camera.applyScannedCode(text) else { return false }
                scanNote = nil
                Task { await camera.joinAndConnect() }
                return true
            }
        }
        #endif
        .presentationBackground(Theme.background)
        .presentationSizing(WorkspaceSheetSizing(page: twoColumns))
        .tint(Theme.accent)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .interactiveDismissDisabled(camera.phase == .connecting)
    }

    private var brandList: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel("Camera")
            VStack(spacing: 0) {
                row(nil)
                ForEach(CameraBrand.allCases) { brand in
                    Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 16)
                    row(brand)
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            .disabled(camera.phase != .disconnected)
        }
    }

    private func row(_ brand: CameraBrand?) -> some View {
        let on = selection == brand
        return Button {
            withAnimation(.snappy) { camera.setBrand(brand) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(brand?.title ?? "Automatic")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                        if brand == nil {
                            Text("Recommended").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                        }
                    }
                    Text(brand?.coverage ?? "Works out which camera it is from its Wi-Fi")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Theme.accent : Theme.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: on)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            CapsLabel("How to connect", color: Theme.accent)
            ForEach(Array(ConnectView.steps(for: selection).enumerated()), id: \.offset) { index, step in
                StepRow(number: index + 1, title: step.title, detail: step.detail)
            }
            if let note = selection?.supportNote {
                Label(note, systemImage: "flask")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .animation(.smooth, value: selection)
    }

    private var connectBar: some View {
        let connecting = camera.phase == .connecting
        return VStack(alignment: .leading, spacing: 10) {
            if let error = camera.lastError {
                ConnectErrorBanner(text: error)
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
                    Label("Scan the camera's QR code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.accent)
                .disabled(camera.phase != .disconnected)
                Text("Start the camera's smartphone connection so it shows a QR code. Shutterlink joins its Wi-Fi and connects.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    TextField("Network name", text: $camera.wifiSSID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .padding(.horizontal, 14)
                        .frame(minHeight: Theme.target)
                        .accessibilityLabel("Camera network name")
                    Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 14)
                    TextField("Password", text: $camera.wifiPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .padding(.horizontal, 14)
                        .frame(minHeight: Theme.target)
                        .accessibilityLabel("Camera network password")
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceRaised))
                .disabled(camera.phase != .disconnected)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        }
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
                        Text("User-Agent").font(.subheadline).foregroundStyle(.secondary)
                        Picker("User-Agent", selection: $camera.userAgent) {
                            ForEach(CameraModel.userAgents, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if !camera.autoDetectBrand, !camera.brand.defaultLiveViewSizes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live view size").font(.subheadline).foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.red)
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.red.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.red.opacity(0.5), lineWidth: 1))
        .transition(.blurReplace)
    }
}

/// Pure black with a large, faint amber aperture breaking out of the top-right corner: the cover.
private struct ConnectBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            GeometryReader { geo in
                let side = max(geo.size.width, geo.size.height) * 0.8
                ApertureMark(showsLink: false, monochrome: Theme.accent.opacity(0.16))
                    .frame(width: side, height: side)
                    .position(x: geo.size.width - side * 0.08, y: side * 0.18)
            }
        }
        .ignoresSafeArea()
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
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: .rect(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(detail).font(.subheadline).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

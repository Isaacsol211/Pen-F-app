import SwiftUI

/// The home screen while not connected: the cameras this iPhone knows as cards (one tap to
/// reconnect), and "Add a camera" for a new one. First run shows an empty state instead.
struct ConnectView: View {
    @Environment(CameraModel.self) private var camera
    @State private var showAdd = false
    @State private var connectingID: String?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if camera.savedCameras.isEmpty {
                        cover(compact: geo.size.height < 600)
                        emptyState
                    } else {
                        BrandLockup(markSize: 40)
                            .padding(.top, 20)
                        cameraList
                        tip
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .background { ConnectBackground() }
        .sheet(isPresented: $showAdd) {
            AddCameraSheet()
                .environment(camera)
        }
        .onChange(of: camera.phase) { _, phase in
            if phase != .connecting { connectingID = nil }
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
            Text("Remote control for Olympus, OM System and Panasonic LUMIX cameras over their own Wi-Fi, with Nikon, Canon and Sony in beta.")
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

    private var cameraList: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel("Your cameras")
            Text("Turn on the camera's Wi-Fi and join it in Settings ▸ Wi-Fi, then tap it.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            ForEach(camera.savedCameras) { saved in
                card(saved)
            }
            Button {
                showAdd = true
            } label: {
                Label("Add a camera", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    .contentShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .disabled(camera.phase != .disconnected)
        }
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
                            if saved.brand.isBeta { BetaBadge() }
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
            Text("**One tap next time:** put the \"Connect to Camera\" shortcut on the Action button (Settings ▸ Action Button ▸ Shortcut ▸ Shutterlink). It reconnects to the camera you used last.")
        } icon: {
            Image(systemName: "bolt.circle").foregroundStyle(Theme.accent)
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondary)
    }

    // MARK: - Footer

    /// Problems and the Wi-Fi state stay in view; first run gets the Add button here too.
    private var footer: some View {
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
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 600)
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
                 "Settings ▸ Wi-Fi ▸ the camera's network, with the password the camera shows. \"No Internet Connection\" is expected."),
                ("Connect",
                 "Allow Local Network access when iOS asks. The app works out which camera it is from the network and by asking it."),
            ]
        case .olympus:
            return [
                ("Start Wi-Fi on the camera",
                 "Open Connection to Smartphone (OM System: Wi-Fi/Bluetooth ▸ Connection to Smartphone) and wait for the screen with the SSID, password and QR code."),
                ("Join that network",
                 "Settings ▸ Wi-Fi ▸ the camera's network (E-M10-P-…, PEN-F-P-…, OM-1-P-…) with the password from the camera. \"No Internet Connection\" is expected. If iOS hops back to your home Wi-Fi, turn off Auto-Join for it."),
                ("Connect", "Allow Local Network access when iOS asks. Live view needs it."),
            ]
        case .panasonic:
            return [
                ("Start Wi-Fi on the camera",
                 "MENU ▸ Setup ▸ Wi-Fi ▸ Wi-Fi Function ▸ New Connection ▸ Remote Shooting & View. The camera shows its network name."),
                ("Join that network",
                 "Settings ▸ Wi-Fi ▸ the camera's network (e.g. GH5-…). Enter the password if the camera shows one. \"No Internet Connection\" is expected."),
                ("Connect, then approve on the camera",
                 "Allow Local Network access when iOS asks. The first time, the camera asks whether to connect to this iPhone: choose Yes."),
            ]
        case .nikon:
            return [
                ("Start Wi-Fi on the camera",
                 "Z bodies: MENU ▸ Network ▸ Connect to smart device ▸ Wi-Fi connection ▸ Establish Wi-Fi connection. Older DSLRs with built-in Wi-Fi: turn Wi-Fi on in the Setup menu."),
                ("Join that network",
                 "Settings ▸ Wi-Fi ▸ the camera's network, with the password the camera shows. \"No Internet Connection\" is expected."),
                ("Connect", "Allow Local Network access when iOS asks. If the camera asks to allow the connection, choose OK."),
            ]
        case .canon:
            return [
                ("Unlock CCAPI once",
                 "Canon locks third-party control until the camera is activated with Canon's free CCAPI tool (developer account, one time per camera). Without it the app can't connect."),
                ("Start Wi-Fi on the camera",
                 "MENU ▸ Wireless ▸ Wi-Fi ▸ the CCAPI connection, as camera access point. Join the camera's network in Settings ▸ Wi-Fi."),
                ("Connect", "Allow Local Network access when iOS asks."),
            ]
        case .sony:
            return [
                ("Start Smart Remote on the camera",
                 "Older Alpha / RX bodies: MENU ▸ Application ▸ Smart Remote Control (or Ctrl w/ Smartphone). Bodies from 2020 on (a7 IV, ZV-E10…) don't offer this to other apps."),
                ("Join that network",
                 "Settings ▸ Wi-Fi ▸ DIRECT-xxxx:ILCE-…, with the password the camera shows."),
                ("Connect", "Allow Local Network access when iOS asks."),
            ]
        }
    }

}

/// New camera: pick the brand (or Automatic), follow its steps, connect. The camera is saved the
/// first time it connects.
struct AddCameraSheet: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @State private var showAdvanced = false

    private var selection: CameraBrand? { camera.autoDetectBrand ? nil : camera.brand }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    brandList
                    stepsCard
                    advanced
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
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
        .presentationBackground(Theme.background)
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
                        if brand?.isBeta == true { BetaBadge() }
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
                Task { await camera.connect() }
            } label: {
                HStack(spacing: 10) {
                    if connecting { ProgressView().tint(Theme.onAccent) }
                    Text(connecting ? (camera.status ?? "Connecting…") : "Connect")
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
                     ? "Leave the address empty and the app looks for the camera at each brand's usual address. For the mock cameras in the Simulator, enter 127.0.0.1 with the mock's port: 8080 Olympus, 8082 LUMIX, 15740 Nikon, 8084 Canon, 8086 Sony."
                     : "The \(camera.brand.shortTitle) camera is normally at \(camera.brand.defaultHost). For the mock cameras in the Simulator, use 127.0.0.1 with the mock's port: 8080 Olympus, 8082 LUMIX, 15740 Nikon, 8084 Canon, 8086 Sony.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open iPhone Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.surface)
            }
            .padding(20)
            .surface(.regular, in: .rect(cornerRadius: 24, style: .continuous))
            .transition(.blurReplace)
        }
    }
}

/// "Beta" next to brands whose drivers have only been tried against mock cameras.
struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(Theme.accent.opacity(0.7), lineWidth: 1))
            .accessibilityLabel("Beta")
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
            guard let address else { return ("wifi.slash", .orange, "This iPhone isn't on Wi-Fi") }
            // The phone should be on the camera's subnet (192.168.0.x for Olympus, 192.168.54.x for LUMIX).
            let octets = host.split(separator: ":").first.map { $0.split(separator: ".") } ?? []
            if octets.count == 4, octets[0] != "127", !address.hasPrefix(octets.prefix(3).joined(separator: ".") + ".") {
                return ("exclamationmark.triangle.fill", .orange,
                        "On another Wi-Fi network (\(address)). Join the camera's network first.")
            }
            return ("wifi", Theme.secondary,
                    "Wi-Fi \(address). Check Settings ▸ Wi-Fi shows the camera's network.")
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

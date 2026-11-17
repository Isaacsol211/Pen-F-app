import SwiftUI

struct ConnectView: View {
    @Environment(CameraModel.self) private var camera
    @State private var showAdvanced = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                if geo.size.width > geo.size.height {
                    // Landscape: steps on the left, Connect always visible on the right.
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            steps
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            connectSection
                            advanced
                        }
                        .frame(width: min(360, geo.size.width * 0.42))
                        .padding(.top, 28)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        steps
                        connectSection
                        advanced
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .background { ConnectBackground() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PEN-F REMOTE")
                .font(.system(size: 13, weight: .semibold))
                .tracking(3)
                .foregroundStyle(Theme.accent)
            Text("Shoot from\nyour phone")
                .font(.system(size: 38, weight: .bold))
        }
        .padding(.top, 28)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepRow(number: 1,
                    title: "Start Wi-Fi on the camera",
                    detail: "Open Connection to Smartphone on the PEN-F and wait for the screen with the SSID, password and QR code.")
            StepRow(number: 2,
                    title: "Join that network",
                    detail: "Settings ▸ Wi-Fi ▸ PEN-F-P-… with the 8-digit password from the camera. \"No Internet Connection\" is expected. If iOS hops back to your home Wi-Fi, turn off Auto-Join for it.")
            StepRow(number: 3,
                    title: "Connect",
                    detail: "Allow Local Network access when iOS asks. Live view needs it.")
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder private var connectSection: some View {
        let connecting = camera.phase == .connecting
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            WifiStatusRow(address: NetworkInfo.wifiAddress(), host: camera.host)
        }
        .padding(.horizontal, 4)

        Button {
            Task { await camera.connect() }
        } label: {
            HStack(spacing: 10) {
                if connecting { ProgressView() }
                Text(connecting ? (camera.status ?? "Connecting…") : "Connect to camera")
                    .contentTransition(.interpolate)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .disabled(connecting)
        .animation(.smooth, value: connecting)

        if let error = camera.lastError {
            Label {
                Text(error)
            } icon: {
                Image(systemName: "wifi.exclamationmark")
            }
            .font(.callout)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.red.opacity(0.35)), in: .rect(cornerRadius: 20, style: .continuous))
            .transition(.blurReplace)
        }
    }

    @ViewBuilder private var advanced: some View {
        @Bindable var camera = camera
        Button {
            withAnimation(.snappy) { showAdvanced.toggle() }
        } label: {
            HStack {
                Text("Advanced")
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(showAdvanced ? 90 : 0))
            }
            .padding(.horizontal, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)

        if showAdvanced {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Camera address") {
                    TextField("192.168.0.10", text: $camera.host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospaced())
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("User-Agent").font(.subheadline).foregroundStyle(.secondary)
                    Picker("User-Agent", selection: $camera.userAgent) {
                        ForEach(CameraModel.userAgents, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Live view size").font(.subheadline).foregroundStyle(.secondary)
                    Picker("Live view size", selection: $camera.liveViewQuality) {
                        ForEach(CameraModel.defaultLiveViewSizes, id: \.self) { Text(CameraModel.liveViewLabel($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Text("The camera is always 192.168.0.10. For the mock camera in the Simulator, use 127.0.0.1:8080.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open iPhone Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.glass)
            }
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
            .transition(.blurReplace)
        }
    }
}

/// Warm glow behind the connect screen so the glass has something to refract.
private struct ConnectBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Theme.accent.opacity(0.55), .clear], center: .topTrailing,
                           startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Color(red: 0.25, green: 0.35, blue: 0.75).opacity(0.5), .clear],
                           center: .bottomLeading, startRadius: 10, endRadius: 560)
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
            if host.hasPrefix("192.168.0."), !address.hasPrefix("192.168.0.") {
                return ("exclamationmark.triangle.fill", .orange,
                        "On another Wi-Fi network (\(address)). Join PEN-F-P-… first.")
            }
            return ("wifi", .secondary,
                    "Wi-Fi address \(address). Check that Settings ▸ Wi-Fi shows PEN-F-P-…")
        }()
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(color)
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

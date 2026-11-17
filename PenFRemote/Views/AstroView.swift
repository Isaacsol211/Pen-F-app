import SwiftUI

/// One-tap night-sky setup.
struct AstroView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @AppStorage("astro.focalLength") private var focalLength = 17.0
    @AppStorage("astro.strict") private var strict = true
    @AppStorage("astro.iso") private var iso = 1600
    @State private var trails = false
    @State private var applied = false

    private var plan: AstroPlan {
        AstroPlan(focalLength: focalLength, strict: strict, iso: iso, trails: trails)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Style", selection: $trails) {
                        Label("Stars", systemImage: "sparkles").tag(false)
                        Label("Star trails", systemImage: "circle.dotted.circle").tag(true)
                    }
                    .pickerStyle(.segmented)

                    card {
                        HStack {
                            Text("Lens focal length")
                            Spacer()
                            Text("\(Int(focalLength)) mm")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .contentTransition(.numericText(value: focalLength))
                        }
                        if let lens = camera.liveInfo.focalLength {
                            Label(Int(focalLength) == lens ? "From your lens (\(lens) mm)" : "Your lens reports \(lens) mm",
                                  systemImage: Int(focalLength) == lens ? "checkmark.circle.fill" : "camera.aperture")
                                .font(.footnote)
                                .foregroundStyle(Int(focalLength) == lens ? Color.green : .secondary)
                                .onTapGesture { withAnimation(.snappy) { focalLength = Double(lens) } }
                        }
                        Slider(value: $focalLength, in: 7...45, step: 1)
                        HStack(spacing: 8) {
                            ForEach([8, 12, 17, 25], id: \.self) { mm in
                                Button("\(mm) mm") { focalLength = Double(mm) }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                            }
                        }
                        if !trails {
                            Toggle("Pin-sharp stars", isOn: $strict)
                            Text(strict
                                 ? "300 rule: stars stay round even at 100%."
                                 : "500 rule: longer exposures, slight streaks when zoomed in.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    card {
                        Text("ISO")
                        Picker("ISO", selection: $iso) {
                            ForEach([800, 1600, 3200, 6400], id: \.self) { Text(verbatim: "\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    card {
                        Text("Will set").font(.headline)
                        ForEach(camera.presetRunning || !camera.presetSteps.isEmpty
                                ? camera.presetSteps : camera.astroSteps(for: plan)) { step in
                            StepResultRow(step: step)
                        }
                    }

                    card {
                        Label("Before you shoot", systemImage: "lightbulb").font(.headline)
                        tip("Put the camera on a tripod and turn image stabilisation off on the camera.")
                        tip("Focus manually on a bright star: switch the lens to MF and use the camera's magnify view.")
                        tip("Shoot from the phone so nothing touches the camera.")
                        if trails {
                            tip("Set the base exposure for Live Composite on the camera (Shooting menu ▸ Composite Settings). Tap the shutter to start and again to stop.")
                        }
                    }
                }
                .padding(16)
            }
            // Apply stays reachable without scrolling.
            .safeAreaBar(edge: .bottom) {
                Button {
                    Task {
                        await camera.applyAstro(plan)
                        let allGood = camera.presetSteps.allSatisfy {
                            if case .failed = $0.state { return false }
                            return true
                        }
                        if allGood {
                            withAnimation(.bouncy) { applied = true }
                            camera.showToast("Astro settings applied")
                            try? await Task.sleep(for: .seconds(1.1))
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if camera.presetRunning { ProgressView() }
                        if applied {
                            Image(systemName: "checkmark.circle.fill").symbolEffect(.bounce, value: applied)
                        }
                        Text(applied ? "Applied" : camera.presetRunning ? "Applying…" : "Apply astro settings")
                            .contentTransition(.interpolate)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(applied ? Color.green : Theme.accent)
                .disabled(camera.presetRunning || camera.mode != .rec)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .sensoryFeedback(.success, trigger: applied)
            }
            .navigationTitle("Astro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .onChange(of: trails) { camera.presetSteps = [] }
            .onChange(of: focalLength) { camera.presetSteps = [] }
            .onChange(of: strict) { camera.presetSteps = [] }
            .onChange(of: iso) { camera.presetSteps = [] }
            .onAppear {
                camera.presetSteps = []
                // Start from the mounted lens when it reports its focal length.
                if let lens = camera.liveInfo.focalLength { focalLength = Double(lens) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

private struct StepResultRow: View {
    let step: PresetStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(step.title)
                    Spacer()
                    Text(step.value.map { PropertyFormat.display(step.property, $0) } ?? "–")
                        .font(.body.monospaced().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch step.state {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.orange)
        }
    }

    private var caption: String {
        switch step.state {
        case .failed(let why), .skipped(let why): why
        default: step.detail
        }
    }
}

/// Countdown shown over live view while a long exposure runs.
struct ExposureOverlay: View {
    @Environment(CameraModel.self) private var camera

    var body: some View {
        if let started = camera.exposureStartedAt {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let elapsed = context.date.timeIntervalSince(started)
                let text: String = if let duration = camera.exposureDuration {
                    elapsed < duration
                        ? "Exposing · \(Int((duration - elapsed).rounded(.up))) s left"
                        : "Processing (noise reduction)…"
                } else {
                    "Open exposure · \(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond))) · tap shutter to stop"
                }
                Label(text, systemImage: "timer")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
            }
            .transition(.blurReplace)
        }
    }
}

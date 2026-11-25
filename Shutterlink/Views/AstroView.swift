import SwiftUI

/// One-tap night-sky setup.
struct AstroView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @AppStorage("astro.focalLength") private var focalLength = 17.0
    @AppStorage("astro.strict") private var strict = true
    @AppStorage("astro.iso") private var iso = 1600
    @State private var trails = false

    private var plan: AstroPlan {
        AstroPlan(focalLength: focalLength, strict: strict, iso: iso, trails: trails, cropFactor: camera.cropFactor)
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BigNumber(value: trails ? (camera.hasLiveComposite ? "Live Composite" : "30 s series")
                                             : "\(Int(plan.maxSeconds.rounded())) s",
                              caption: trails ? "Star trails" : "The longest exposure that keeps stars round",
                              size: trails ? 60 : 132, color: Theme.astroText, accent: Theme.astroAccent)
                    Picker("Style", selection: $trails) {
                        Label("Stars", systemImage: "sparkles").tag(false)
                        Label("Star trails", systemImage: "circle.dotted.circle").tag(true)
                    }
                    .pickerStyle(.segmented)

                    card(spacing: 10) {
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
                                .foregroundStyle(Int(focalLength) == lens ? Theme.green : Theme.secondary)
                                .onTapGesture { withAnimation(.snappy) { focalLength = Double(lens) } }
                        }
                        Slider(value: $focalLength, in: 7...45, step: 1)
                        HStack(spacing: 8) {
                            ForEach([8, 12, 17, 25], id: \.self) { mm in
                                Button("\(mm) mm") { focalLength = Double(mm) }
                                    .buttonStyle(.surface)
                                    .controlSize(.small)
                            }
                        }
                        if !trails {
                            Toggle("Pin-sharp stars", isOn: $strict)
                            Text(strict
                                 ? "300 rule: stars stay round even at 100%."
                                 : "500 rule: longer exposures, slight streaks when zoomed in.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondary)
                        }
                    }

                    card(spacing: 10) {
                        Text("ISO")
                        Picker("ISO", selection: $iso) {
                            ForEach([800, 1600, 3200, 6400], id: \.self) { Text(verbatim: "\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    card(spacing: 10) {
                        Text("Will set").font(.headline)
                        ForEach(camera.presetRunning || !camera.presetSteps.isEmpty
                                ? camera.presetSteps : camera.astroSteps(for: plan)) { step in
                            StepResultRow(step: step)
                        }
                    }

                    card(spacing: 10) {
                        Label("Before you shoot", systemImage: "lightbulb").font(.headline)
                        tip("Put the camera on a tripod and turn image stabilisation off on the camera.")
                        tip("Focus manually on a bright star: switch the lens to MF and use the camera's magnify view.")
                        tip("Shoot from the phone so nothing touches the camera.")
                        if trails && camera.hasLiveComposite {
                            tip("Set the base exposure for Live Composite on the camera (Shooting menu ▸ Composite Settings). Tap the shutter to start and again to stop.")
                        } else if trails {
                            tip("This camera has no Live Composite, so the app shoots a series of 30 s frames with the interval timer. Stack them afterwards (StarStaX, Sequator or Photoshop) for the trails.")
                        }
                    }
                }
                .padding(16)
            }
            // Apply stays reachable without scrolling.
            .safeAreaBar(edge: .bottom) {
                // Stays on after it's applied; tapping again turns it off and puts the old settings back.
                let astroOn = camera.isPresetOn(PresetRecipe.astro.id)
                VStack(spacing: 8) {
                    if astroOn, let series = camera.trailsSeries(for: plan), !camera.interval.running {
                        Button {
                            camera.startTrailsSeries(series)
                            dismiss()
                        } label: {
                            Label("Start the series: \(series.count) frames, about \(Int((Double(series.count) * series.seconds / 60).rounded())) min",
                                  systemImage: "timer")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.accent)
                        .disabled(camera.presetRunning || camera.mode != .rec)
                        .padding(.horizontal, 16)
                    }
                    Button {
                        Task {
                            if astroOn {
                                await camera.undoPreset()
                                return
                            }
                            await camera.applyAstro(plan)
                            let allGood = camera.presetSteps.allSatisfy {
                                if case .failed = $0.state { return false }
                                return true
                            }
                            // Trails without Live Composite stay open for Start the series.
                            if allGood, camera.trailsSeries(for: plan) == nil {
                                camera.showToast("Astro is on")
                                try? await Task.sleep(for: .seconds(1.1))
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if camera.presetRunning { ProgressView() }
                            if astroOn {
                                Image(systemName: "checkmark.circle.fill").symbolEffect(.bounce, value: astroOn)
                            }
                            Text(camera.presetRunning ? "Applying…" : astroOn ? "Astro is on · Tap to turn off" : "Apply astro settings")
                                .contentTransition(.interpolate)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.accent)
                    .tint(astroOn ? Theme.green : Theme.astroAccent)
                    .disabled(camera.presetRunning || camera.mode != .rec)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .sensoryFeedback(.success, trigger: astroOn)
                }
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
        .presentationBackground(Theme.astroBackground)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .tint(Theme.astroAccent)
        .environment(\.astroPalette, true)
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(Theme.secondary)
    }
}

struct StepResultRow: View {
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
                Text(caption).font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch step.state {
        case .pending: Image(systemName: "circle").foregroundStyle(Theme.secondary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.red)
        // Not an error: the caption says what to do on the camera instead.
        case .skipped: Image(systemName: "info.circle").foregroundStyle(Theme.secondary)
        }
    }

    private var caption: String {
        switch step.state {
        case .failed(let why), .skipped(let why): why
        default: step.detail
        }
    }
}

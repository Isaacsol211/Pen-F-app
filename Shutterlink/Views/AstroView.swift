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
        // 308/309: a night screen of its own: stars and the moon behind, the night palette throughout.
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Astro").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.astroText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                HStack(spacing: 0) {
                    pill("Stars", on: !trails) { trails = false }
                    pill("Star trails", on: trails) { trails = true }
                }
                .overlay(Capsule().stroke(Theme.astroText.opacity(0.3), lineWidth: 1))
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.astroText)
                        .frame(width: Theme.target, height: Theme.target)
                }
                .accessibilityLabel("Done")
            }
            .padding(.leading, 20).padding(.trailing, 6)
            .padding(.top, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    bigNumber
                        .padding(.top, 8)
                        .padding(.bottom, 18)
                    focalRuler
                    if !trails { HStack(spacing: 8) {
                        ForEach([8, 12, 17, 25], id: \.self) { mm in
                            Button("\(mm) mm") { withAnimation(.snappy) { focalLength = Double(mm) } }
                                .buttonStyle(AstroChipStyle(selected: Int(focalLength) == mm))
                        }
                    }
                    .padding(.vertical, 12) }
                    if !trails {
                        Toggle(isOn: $strict) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pin-sharp stars").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.astroText)
                                Text(strict ? "300 rule: stars stay round even at 100%."
                                            : "500 rule: longer exposures, slight streaks when zoomed in.")
                                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            }
                        }
                        .tint(Theme.astroAccent)
                        .hairRow(minHeight: 62)
                        .overlay(alignment: .top) { Hairline() }
                    }
                    SegRow(label: "ISO", options: [800, 1600, 3200, 6400], selection: $iso, accent: Theme.astroAccent) { "\($0)" }
                    SectionLabel("Will set")
                    ForEach(camera.presetRunning || !camera.presetSteps.isEmpty
                            ? camera.presetSteps : camera.astroSteps(for: plan)) { step in
                        StepResultRow(step: step)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Hairline() }
                    }
                    SectionLabel("Before you shoot")
                    tip("Put the camera on a tripod and turn image stabilisation off on the camera.")
                    tip("Focus manually on a bright star: switch the lens to MF and use the camera's magnify view.")
                    tip("Shoot from the phone so nothing touches the camera.")
                    if trails && camera.hasLiveComposite {
                        tip("Set the base exposure for Live Composite on the camera (Shooting menu ▸ Composite Settings). Tap the shutter to start and again to stop.")
                    } else if trails {
                        tip("This camera has no Live Composite, so the app shoots a series of 30 s frames with the interval timer. Stack them afterwards (StarStaX, Sequator or Photoshop) for the trails.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            // Apply stays at the bottom without scrolling.
            .safeAreaInset(edge: .bottom, spacing: 0) { applyBar }
        }
        .background { AstroSky().ignoresSafeArea() }
        .onChange(of: trails) { camera.presetSteps = [] }
        .onChange(of: focalLength) { camera.presetSteps = [] }
        .onChange(of: strict) { camera.presetSteps = [] }
        .onChange(of: iso) { camera.presetSteps = [] }
        .onAppear {
            camera.presetSteps = []
            // Start from the mounted lens when it reports its focal length.
            if let lens = camera.liveInfo.focalLength { focalLength = Double(lens) }
        }
        .tint(Theme.astroAccent)
        .environment(\.astroPalette, true)
        .sensoryFeedback(.selection, trigger: trails)
    }

    private func pill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Text(title)
                .font(.system(size: 14, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.astroBackground : Theme.astroText)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(on ? Theme.astroText : Color.clear))
                .frame(minHeight: Theme.target)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 308: the longest exposure; 309: the series (frames × seconds) or Live Composite.
    @ViewBuilder private var bigNumber: some View {
        if trails {
            if let series = camera.trailsSeries(for: plan) {
                BigNumber(value: "\(series.count) × \(Int(series.seconds)) s",
                          caption: "A series for star trails, about \(Int((Double(series.count) * series.seconds / 60).rounded())) min",
                          size: 64, color: Theme.astroText, accent: Theme.astroAccent)
            } else {
                BigNumber(value: camera.hasLiveComposite ? "Live Composite" : "30 s series", caption: "Star trails",
                          size: 64, color: Theme.astroText, accent: Theme.astroAccent)
                    .padding(.horizontal, 24)
            }
        } else {
            BigNumber(value: "\(Int(plan.maxSeconds.rounded())) s", caption: "The longest exposure that keeps stars round",
                      size: 132, color: Theme.astroText, accent: Theme.astroAccent)
        }
    }

    /// 308: a ruler from 7 to 45 mm with a marker at the lens; drag or tap along it.
    private var focalRuler: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Lens focal length").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Spacer()
                if let lens = camera.liveInfo.focalLength {
                    Text(Int(focalLength) == lens ? "From your lens (\(lens) mm)" : "Your lens reports \(lens) mm")
                        .font(.system(size: 12))
                        .foregroundStyle(Int(focalLength) == lens ? Theme.green : Theme.secondary)
                        .onTapGesture { withAnimation(.snappy) { focalLength = Double(lens) } }
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                let x = { (mm: Double) in CGFloat((mm - 7) / 38) * w }
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        for mm in 7...45 {
                            let major = [7, 17, 25, 35, 45].contains(mm)
                            var p = Path()
                            p.move(to: CGPoint(x: x(Double(mm)), y: major ? 0 : 6))
                            p.addLine(to: CGPoint(x: x(Double(mm)), y: 16))
                            ctx.stroke(p, with: .color(Theme.astroText.opacity(major ? 0.7 : 0.35)), lineWidth: 1)
                        }
                        var marker = Path()
                        marker.move(to: CGPoint(x: x(focalLength), y: -4)); marker.addLine(to: CGPoint(x: x(focalLength), y: 22))
                        ctx.stroke(marker, with: .color(Theme.astroAccent), lineWidth: 2.5)
                    }
                    .frame(height: 22)
                    ForEach([7, 17, 25, 35, 45], id: \.self) { mm in
                        let on = Int(focalLength) == mm
                        Text(mm == 17 || on ? "\(mm) mm" : "\(mm)")
                            .font(.num(on ? 18 : 16, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? Theme.astroText : Theme.secondary)
                            .fixedSize()
                            .position(x: min(max(x(Double(mm)), 12), w - 12), y: 40)
                    }
                }
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let mm = (7 + Double(value.location.x / max(1, w)) * 38).rounded()
                    focalLength = min(45, max(7, mm))
                })
            }
            .frame(height: 52)
            .sensoryFeedback(.selection, trigger: focalLength)
            .accessibilityElement()
            .accessibilityLabel("Lens focal length")
            .accessibilityValue("\(Int(focalLength)) millimetres")
            .accessibilityAdjustableAction { direction in
                focalLength = min(45, max(7, focalLength + (direction == .increment ? 1 : -1)))
            }
        }
    }

    private var applyBar: some View {
        // Stays on after it's applied; tapping again turns it off and puts the old settings back.
        let astroOn = camera.isPresetOn(PresetRecipe.astro.id)
        return VStack(spacing: 8) {
            if astroOn, let series = camera.trailsSeries(for: plan), !camera.interval.running {
                Button("Start the series: \(series.count) frames, about \(Int((Double(series.count) * series.seconds / 60).rounded())) min") {
                    camera.startTrailsSeries(series)
                    dismiss()
                }
                .buttonStyle(AstroButtonStyle(fill: Theme.astroAccent))
                .disabled(camera.presetRunning || camera.mode != .rec)
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
                    if camera.presetRunning { ProgressView().tint(Theme.astroBackground) }
                    Text(camera.presetRunning ? "Applying…" : astroOn ? "Astro is on · Tap to turn off" : "Apply astro settings")
                        .contentTransition(.interpolate)
                }
            }
            .buttonStyle(AstroButtonStyle(fill: astroOn ? Theme.green : Theme.astroText))
            .disabled(camera.presetRunning || camera.mode != .rec)
            .sensoryFeedback(.success, trigger: astroOn)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [Theme.astroBackground.opacity(0), Theme.astroBackground],
                                   startPoint: .top, endPoint: .init(x: 0.5, y: 0.3)).ignoresSafeArea())
    }

    private func tip(_ text: String) -> some View {
        NoteRow(text, color: Theme.astroText.opacity(0.85))
    }
}

/// The night sky behind Astro (308): near-black blue, scattered stars, a crescent moon top right.
struct AstroSky: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.astroBackground))
            var rng = SeededRandom(seed: 7)
            // Stars only in the sky band at the top, behind the header and the big number, never under rows.
            for _ in 0..<38 {
                let x = rng.next() * size.width, y = 40 + rng.next() * size.height * 0.2
                let r = 0.5 + rng.next() * 1.1
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.35 + rng.next() * 0.5)))
            }
            let moon = CGRect(x: size.width - 58, y: 112, width: 24, height: 24)
            ctx.fill(Path(ellipseIn: moon), with: .color(Color(hex: 0xEEF1F7)))
            ctx.fill(Path(ellipseIn: moon.offsetBy(dx: -7, dy: -4)), with: .color(Theme.astroBackground))
        }
        .accessibilityHidden(true)
    }
}

/// A fixed sequence of pseudo-random numbers in 0..<1, so the stars stay put between frames.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// Astro's lens chips: light when chosen.
struct AstroChipStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.astroBackground : Theme.astroText.opacity(0.8))
            .padding(.horizontal, 16)
            .frame(minHeight: Theme.target)
            .background(Capsule().fill(selected ? Theme.astroText : Color.clear))
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.astroText.opacity(0.3), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.capsule)
    }
}

/// Astro's main button: a 54 pt capsule in the night palette.
struct AstroButtonStyle: ButtonStyle {
    var fill: Color
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.astroBackground)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Capsule().fill(fill.opacity(isEnabled ? 1 : 0.4)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.capsule)
    }
}

struct StepResultRow: View {
    let step: PresetStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(step.title).font(.system(size: 16, weight: .medium))
                    Spacer()
                    Text(step.value.map { PropertyFormat.display(step.property, $0) } ?? "–")
                        .font(.num(18, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(caption).font(.system(size: 13)).foregroundStyle(Theme.secondary)
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

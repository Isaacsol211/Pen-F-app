import SwiftUI

/// "1/250", "4 s", "2 min 8 s".
func shutterLabel(seconds: Double) -> String {
    if seconds < 0.75 { return "1/\(Int((1 / seconds).rounded()))" }
    if seconds < 10 { return String(format: seconds == seconds.rounded() ? "%.0f s" : "%.1f s", seconds) }
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total) s" }
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    if h > 0 { return "\(h) h \(m) min" }
    return s == 0 ? "\(m) min" : "\(m) min \(s) s"
}

// MARK: - Presets

/// One-tap recipes, Undo, the user's own presets, and expose-to-the-right.
struct PresetsPanel: View {
    @Environment(CameraModel.self) private var camera
    var openAstro: () -> Void
    var openFocusStack: () -> Void
    @State private var expanded: String?
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("One tap.\nCamera set.")
                .font(.num(50, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
            if let undo = camera.presetUndo {
                undoCard(undo)
            }
            card {
                CapsLabel("One tap")
                ForEach(PresetRecipe.allCases) { recipe in
                    recipeRow(recipe)
                }
            }
            card {
                HStack {
                    CapsLabel("My presets")
                    Spacer()
                    Button("Save current", systemImage: "plus") {
                        newName = ""
                        naming = true
                    }
                    .buttonStyle(.surface)
                    .controlSize(.small)
                    .disabled(camera.properties.isEmpty)
                }
                let saved = camera.savedPresetsForCamera
                if saved.isEmpty {
                    Text("Set the camera the way you like it, then Save current. Presets are kept for each camera brand.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                ForEach(saved) { savedRow($0) }
            }
            card {
                CapsLabel("Exposure")
                Text("Expose to the right raises the exposure until the brightest parts are about to clip, then stops a step short: the cleanest RAW files.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                Button {
                    Task { await camera.exposeToTheRight() }
                } label: {
                    HStack {
                        if camera.ettrRunning { ProgressView().controlSize(.small) }
                        Label(camera.ettrRunning ? "Measuring…" : "Expose to the right", systemImage: "sun.max")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.surface)
                .disabled(camera.ettrRunning || camera.mode != .rec || camera.isShooting)
            }
        }
        .animation(.smooth, value: expanded)
        .animation(.smooth, value: camera.presetUndo)
        .alert("Save current settings", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") { camera.saveCurrentSettings(as: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mode, aperture, shutter, ISO, exposure, white balance and drive: whatever the camera lets the app set.")
        }
    }

    private func undoCard(_ undo: SettingsSnapshot) -> some View {
        card {
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Undo \(undo.title)").font(.headline)
                    Text("Puts back the settings from before it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                Button("Undo") { Task { await camera.undoPreset() } }
                    .buttonStyle(.surface)
                    .disabled(camera.presetRunning)
            }
        }
    }

    private func header(icon: String, title: String, subtitle: String, open: Bool, chevron: String,
                        on: Bool = false, recipe: PresetRecipe? = nil) -> some View {
        HStack(spacing: 14) {
            Group {
                if let recipe {
                    RecipeArt(recipe: recipe)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 68, height: 68)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.outline, lineWidth: 1))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.green, lineWidth: 2.5).padding(-4).opacity(on ? 1 : 0))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.num(28)).foregroundStyle(Theme.text)
                Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if on {
                Label("On", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.green)
            }
            Image(systemName: chevron)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.tertiary)
                .rotationEffect(.degrees(open ? 90 : 0))
        }
        .frame(minHeight: Theme.target)
        .contentShape(.rect)
    }

    @ViewBuilder private func recipeRow(_ recipe: PresetRecipe) -> some View {
        let open = expanded == recipe.id
        Button {
            if recipe == .astro { openAstro() } else { expanded = open ? nil : recipe.id }
        } label: {
            header(icon: recipe.icon, title: recipe.title, subtitle: recipe.summary, open: open,
                   chevron: recipe == .astro ? "arrow.up.right" : "chevron.right", on: camera.isPresetOn(recipe.id),
                   recipe: recipe)
        }
        .buttonStyle(.plain)
        if open {
            let steps = camera.presetResultsFor == recipe.id && !camera.presetSteps.isEmpty
                ? camera.presetSteps : camera.steps(for: recipe)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { StepResultRow(step: $0) }
                if !recipe.tip.isEmpty {
                    Label(recipe.tip, systemImage: "lightbulb")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                applyButton("Apply \(recipe.title)", id: recipe.id) { _ = await camera.apply(recipe) }
                if recipe == .macro, camera.capabilities.focusDrive {
                    Button("Focus stack next", systemImage: "square.stack.3d.forward.dottedline") { openFocusStack() }
                        .buttonStyle(.surface)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, 6)
            .transition(.opacity)
        }
    }

    @ViewBuilder private func savedRow(_ saved: SavedPreset) -> some View {
        let open = expanded == saved.id.uuidString
        Button {
            expanded = open ? nil : saved.id.uuidString
        } label: {
            header(icon: "bookmark.fill", title: saved.name, subtitle: summary(saved), open: open, chevron: "chevron.right",
                   on: camera.isPresetOn(saved.id.uuidString))
        }
        .buttonStyle(.plain)
        if open {
            let steps = camera.presetResultsFor == saved.id.uuidString && !camera.presetSteps.isEmpty
                ? camera.presetSteps : camera.steps(for: saved)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { StepResultRow(step: $0) }
                applyButton("Apply \(saved.name)", id: saved.id.uuidString) { await camera.apply(saved) }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    expanded = nil
                    camera.deleteSavedPreset(saved)
                }
                .buttonStyle(.surface)
                .frame(maxWidth: .infinity)
            }
            .padding(.leading, 6)
            .transition(.opacity)
        }
    }

    private func summary(_ saved: SavedPreset) -> String {
        CameraModel.presetOrder.compactMap { name in
            saved.values[name].map { value in
                name == "isospeedvalue" ? "ISO \(PropertyFormat.display(name, value))" : PropertyFormat.display(name, value)
            }
        }
        .joined(separator: " · ")
    }

    /// Applies the setup; once it's on, turns it off again (the settings from before come back).
    private func applyButton(_ title: String, id: String, action: @escaping () async -> Void) -> some View {
        let on = camera.isPresetOn(id)
        return Button {
            Task { if on { await camera.undoPreset() } else { await action() } }
        } label: {
            HStack {
                if camera.presetRunning { ProgressView() }
                Text(camera.presetRunning ? "Applying…" : on ? "Turn off · put back the settings from before" : title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.accent)
        .tint(on ? Color.green : Theme.accent)
        .disabled(camera.presetRunning || camera.mode != .rec)
    }
}

// MARK: - ND filter calculator

/// Meter without the filter, pick its strength, and the app sets M, works out the exposure and times
/// Bulb when it's longer than the camera's own speeds.
struct NDPanel: View {
    @Environment(CameraModel.self) private var camera
    @AppStorage("nd.stops") private var stops = 10
    @State private var meter: NDMeter?

    private var seconds: Double? { meter.map { CameraModel.ndSeconds(metered: $0.seconds, stops: stops) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let seconds, let meter {
                BigNumber(label: "With the filter on, expose for", value: shutterLabel(seconds: seconds),
                          caption: "\(shutterLabel(seconds: meter.seconds)) → \(shutterLabel(seconds: seconds))", size: 96, color: Theme.accent)
            } else {
                BigNumber(label: "ND filter", value: "\(stops) stops", caption: "Meter without the filter first", size: 88)
            }
            card {
                Text("1. Meter without the filter").font(.headline)
                if let live = camera.meteredExposure {
                    Text(describe(live))
                        .font(.num(26, weight: .medium))
                } else {
                    Text("Waiting for the camera's exposure…").foregroundStyle(Theme.secondary)
                }
                Button(meter == nil ? "Use this exposure" : "Meter again", systemImage: "camera.metering.center.weighted") {
                    meter = camera.meteredExposure
                }
                .buttonStyle(.surface)
                .disabled(camera.meteredExposure == nil)
                Text("Let the camera meter in A or P (or set the exposure yourself in M), with a fixed ISO.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            card {
                Text("2. The filter").font(.headline)
                HStack(spacing: 6) {
                    ForEach([(3, "ND8"), (6, "ND64"), (10, "ND1000"), (15, "ND32k")], id: \.0) { value, name in
                        Button {
                            stops = value
                        } label: {
                            VStack(spacing: 1) {
                                Text("\(value) stops").font(.caption.weight(.semibold))
                                Text(name).font(.caption2).foregroundStyle(stops == value ? Theme.onAccent : Theme.secondary)
                            }
                            .foregroundStyle(stops == value ? Theme.onAccent : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(stops == value ? Theme.accent : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(stops == value ? Color.clear : Theme.outline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Stepper(value: $stops, in: 1...20) {
                    LabeledContent("Strength", value: "\(stops) stops")
                }
                if let meter, let seconds {
                    HStack(alignment: .firstTextBaseline) {
                        Text(shutterLabel(seconds: meter.seconds)).foregroundStyle(Theme.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(Theme.tertiary)
                        Text(shutterLabel(seconds: seconds))
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    if camera.ndShutter(seconds: seconds).timedByApp {
                        Text("Longer than the camera's own speeds: the app runs Bulb and stops it. Keep Shutterlink open.")
                            .font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
            }
            if let meter {
                Button {
                    Task { await camera.runPreset(id: "nd", title: "ND filter") { camera.ndSteps(meter: meter, stops: stops) } }
                } label: {
                    HStack {
                        if camera.presetRunning { ProgressView() }
                        Text("Set up the camera")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.accent)
                .disabled(camera.presetRunning || camera.mode != .rec)
                if camera.presetResultsFor == "nd", !camera.presetSteps.isEmpty {
                    card {
                        ForEach(camera.presetSteps) { StepResultRow(step: $0) }
                    }
                }
                if let seconds {
                    card {
                        Text("3. Fit the filter and shoot").font(.headline)
                        Text("Focus first: with a dark filter on, autofocus may not find anything. Then switch the lens to MF.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                        Button {
                            Task { await camera.shootND(seconds: seconds) }
                        } label: {
                            Label("Shoot \(shutterLabel(seconds: seconds))", systemImage: "camera.aperture")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.surface)
                        .disabled(camera.isShooting || camera.mode != .rec || camera.presetRunning)
                    }
                }
            }
        }
        .animation(.smooth, value: meter)
    }

    private func describe(_ meter: NDMeter) -> String {
        var parts = [shutterLabel(seconds: meter.seconds)]
        if let aperture = meter.aperture { parts.append(PropertyFormat.display("focalvalue", aperture)) }
        parts.append(meter.iso.map { "ISO \($0)" } ?? "ISO Auto")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Motion trigger

/// Shoots when something moves in a box on live view: bird feeders, wildlife, a door opening.
struct MotionPanel: View {
    @Environment(CameraModel.self) private var camera

    private static let sizes: [(String, Double)] = [("Small", 0.25), ("Medium", 0.4), ("Large", 0.6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                Text("Shoots when something moves inside the box on live view. Drag the box to move it.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                Text("Box").font(.headline)
                Picker("Box", selection: Binding(
                    get: { Self.sizes.min { abs($0.1 - camera.motion.region.width) < abs($1.1 - camera.motion.region.width) }?.1 ?? 0.4 },
                    set: { camera.motion.resize(to: $0) })) {
                    ForEach(Self.sizes, id: \.1) { Text($0.0).tag($0.1) }
                }
                .pickerStyle(.segmented)
                Text("Sensitivity").font(.headline)
                Slider(value: Binding(get: { camera.motion.sensitivity }, set: { camera.motion.sensitivity = $0 }), in: 0...1)
                meter
                Stepper(value: Binding(get: { camera.motion.cooldown }, set: { camera.motion.cooldown = $0 }), in: 1...60) {
                    LabeledContent("Wait between shots", value: "\(Int(camera.motion.cooldown)) s")
                }
            }
            Button {
                camera.armMotion(!camera.motion.armed)
            } label: {
                Label(camera.motion.armed ? "Disarm" : "Arm", systemImage: camera.motion.armed ? "stop.fill" : "figure.walk.motion")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.accent)
            .disabled(camera.mode != .rec || !camera.liveViewRunning || (camera.isOpenEndedShutter && !camera.motion.armed))
            if camera.isOpenEndedShutter && !camera.motion.armed {
                Text("The motion trigger needs a timed shutter speed, not Bulb or a Live mode.")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            }
            if camera.motion.armed || camera.motion.shots > 0 {
                Text(camera.motion.armed ? "Armed · \(camera.motion.shots) shots so far" : "\(camera.motion.shots) shots")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(camera.motion.armed ? Theme.accent : Theme.secondary)
            }
            Text("Live view over Wi-Fi lags a little, so this suits birds at a feeder and slow subjects, not lightning. Keep Shutterlink open and the \(Platform.device) awake.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
        .onAppear { camera.motion.editing = true }
        .onDisappear { camera.motion.editing = false }
    }

    /// How much the box is changing, against the level that fires.
    private var meter: some View {
        GeometryReader { geo in
            let scale = 0.3
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceRaised)
                Capsule().fill(camera.motionLevel > camera.motion.threshold ? Theme.accent : .white.opacity(0.6))
                    .frame(width: geo.size.width * min(camera.motionLevel / scale, 1))
                Rectangle().fill(Theme.accent)
                    .frame(width: 2)
                    .offset(x: geo.size.width * min(camera.motion.threshold / scale, 1))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Movement level")
    }
}


/// The 68 pt illustrated tile for a one-tap recipe, drawn on a 64-unit grid.
struct RecipeArt: View {
    let recipe: PresetRecipe

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 64
            ctx.scaleBy(x: k, y: k)
            func rect(_ r: CGRect, _ c: Color) { ctx.fill(Path(r), with: .color(c)) }
            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: Color) {
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(c))
            }
            func poly(_ pts: [(CGFloat, CGFloat)], _ c: Color) {
                var p = Path(); p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
                for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
                p.closeSubpath(); ctx.fill(p, with: .color(c))
            }
            func line(_ pts: [(CGFloat, CGFloat)], _ c: Color, _ w: CGFloat) {
                var p = Path(); p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
                for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
                ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
            let cream = Color(hex: 0xF4F1EA)
            switch recipe {
            case .astro:
                rect(CGRect(x: 0, y: 0, width: 64, height: 64), Color(hex: 0x070A18))
                for s in [(12, 14, 1.2), (30, 8, 1.0), (50, 18, 1.4), (22, 30, 1.0), (44, 36, 1.1), (56, 8, 0.9)] as [(CGFloat, CGFloat, CGFloat)] {
                    dot(s.0, s.1, s.2, Color(hex: 0xEEF1F7))
                }
                var arc = Path(); arc.move(to: CGPoint(x: 6, y: 44))
                arc.addQuadCurve(to: CGPoint(x: 58, y: 18), control: CGPoint(x: 14, y: 12))
                ctx.stroke(arc, with: .color(Theme.astroAccent), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [14, 60]))
                poly([(0, 52), (14, 44), (26, 50), (42, 40), (64, 52), (64, 64), (0, 64)], Color(hex: 0x141A36))
            case .moon:
                rect(CGRect(x: 0, y: 0, width: 64, height: 64), Color(hex: 0x070A18))
                dot(32, 30, 17, Color(hex: 0xE8E4D8)); dot(26, 25, 4, Color(hex: 0xC9C5BA))
                dot(38, 36, 3, Color(hex: 0xC9C5BA)); dot(37, 23, 2, Color(hex: 0xC9C5BA))
            case .fireworks:
                rect(CGRect(x: 0, y: 0, width: 64, height: 64), Color(hex: 0x0A0A0A))
                for end in [(32, 10), (45, 16), (49, 30), (43, 41), (21, 41), (15, 30), (19, 16)] as [(CGFloat, CGFloat)] {
                    line([(32, 28), end], Theme.accent, 2)
                }
                for end in [(46, 39), (51, 42), (51, 49), (41, 49), (41, 42)] as [(CGFloat, CGFloat)] {
                    line([(46, 46), end], Color(hex: 0xFF6A45), 2)
                }
                dot(32, 28, 2.4, Color(hex: 0xFFE2A6))
            case .landscape:
                rect(CGRect(x: 0, y: 0, width: 64, height: 64), Color(hex: 0x4B4470))
                rect(CGRect(x: 0, y: 34, width: 64, height: 30), Color(hex: 0xC77F6E))
                dot(44, 38, 7, Color(hex: 0xFFE2A6))
                poly([(0, 46), (14, 32), (24, 40), (38, 24), (64, 48), (64, 64), (0, 64)], Color(hex: 0x1B1C33))
            case .action:
                rect(CGRect(x: 0, y: 0, width: 64, height: 64), Color(hex: 0x16233A))
                line([(6, 22), (28, 22)], Color(hex: 0x8FB8FF), 2.4); line([(4, 32), (22, 32)], Color(hex: 0x8FB8FF), 2.4)
                line([(10, 42), (24, 42)], Color(hex: 0x8FB8FF), 2.4)
                dot(42, 32, 12, cream); line([(34, 32), (50, 32)], Color(hex: 0x16233A), 2)
            case .macro:
                rect(CGRect(x: 0, y: 0, width: 64, height: 64), Color(hex: 0x16281F))
                for c in [(32, 18), (45, 28), (40, 43), (24, 43), (19, 28)] as [(CGFloat, CGFloat)] { dot(c.0, c.1, 8, Color(hex: 0xF3B36F)) }
                dot(32, 32, 7, Color(hex: 0xFFE2A6))
            case .trails:
                rect(CGRect(x: 0, y: 0, width: 64, height: 64), Color(hex: 0x0E1430))
                var a = Path(); a.move(to: CGPoint(x: -2, y: 56)); a.addCurve(to: CGPoint(x: 66, y: 24), control1: CGPoint(x: 20, y: 44), control2: CGPoint(x: 30, y: 30))
                ctx.stroke(a, with: .color(Theme.red), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                var b = Path(); b.move(to: CGPoint(x: -2, y: 62)); b.addCurve(to: CGPoint(x: 66, y: 34), control1: CGPoint(x: 24, y: 50), control2: CGPoint(x: 36, y: 38))
                ctx.stroke(b, with: .color(Theme.red.opacity(0.6)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                var c = Path(); c.move(to: CGPoint(x: -2, y: 46)); c.addCurve(to: CGPoint(x: 66, y: 14), control1: CGPoint(x: 16, y: 38), control2: CGPoint(x: 26, y: 22))
                ctx.stroke(c, with: .color(Color(hex: 0xFFE2A6)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        }
        .frame(width: 68, height: 68)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

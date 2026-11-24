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
                        on: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if on {
                Label("On", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
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
                   chevron: recipe == .astro ? "arrow.up.right" : "chevron.right", on: camera.isPresetOn(recipe.id))
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
            card {
                Text("1. Meter without the filter").font(.headline)
                if let live = camera.meteredExposure {
                    Text(describe(live))
                        .font(.body.monospaced().weight(.semibold))
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
                            .foregroundStyle(stops == value ? Theme.onAccent : .white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(stops == value ? Theme.accent : Theme.surfaceRaised))
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
                    .foregroundStyle(.orange)
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

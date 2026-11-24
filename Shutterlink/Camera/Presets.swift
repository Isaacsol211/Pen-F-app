import Foundation

// MARK: - Recipes

/// One-tap recipes. Each sets only what the camera lets the app change over Wi-Fi, and says why for
/// anything it can't.
enum PresetRecipe: String, CaseIterable, Identifiable {
    case astro, moon, fireworks, landscape, action, macro, trails

    var id: String { rawValue }

    var title: String { self == .trails ? "Light trails & silky water" : rawValue.capitalized }

    var icon: String {
        switch self {
        case .astro: "moon.stars.fill"
        case .moon: "moon.fill"
        case .fireworks: "sparkles"
        case .landscape: "mountain.2.fill"
        case .action: "figure.run"
        case .macro: "camera.macro"
        case .trails: "water.waves"
        }
    }

    var summary: String {
        switch self {
        case .astro: "Stars or star trails, from your lens and sensor"
        case .moon: "A sharp, properly exposed moon: M, f/8, 1/250 s"
        case .fireworks: "Whole bursts on a dark sky"
        case .landscape: "f/8, lowest ISO, nothing shaking the camera"
        case .action: "1/1000 s to freeze movement, fast bursts"
        case .macro: "f/8 and steady, ready for a focus stack"
        case .trails: "Long exposures: car lights, waterfalls, the sea"
        }
    }

    var tip: String {
        switch self {
        case .astro: ""
        case .moon: "Use your longest lens and focus manually on the moon's edge. If the moon still looks too bright, try 1/500 s."
        case .fireworks: "Put the camera on a tripod and focus manually where the bursts are. Start the exposure just before a burst."
        case .landscape: "Shoot from the phone so nothing touches the camera. Focus about a third of the way into the scene."
        case .action: "Hold the shutter for a burst. Use the camera's continuous AF (C-AF) for moving subjects: the app can't switch the AF mode."
        case .macro: "Use a tripod. For more depth than f/8 gives, shoot a focus stack next."
        case .trails: "In daylight this needs an ND filter: use the ND calculator to work out the exposure."
        }
    }
}

/// The settings before a preset changed them, so Undo can put them back.
struct SettingsSnapshot: Equatable, Codable {
    /// The setup that's on (a recipe's id, or a saved preset's).
    let id: String
    let title: String
    let values: [String: String]
}

/// Settings the user saved under a name, for the camera brand they were saved on.
struct SavedPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var brand: String
    var values: [String: String]
    var created = Date()

    private static let key = "presets.saved"

    static func load() -> [SavedPreset] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedPreset].self, from: data)) ?? []
    }

    static func store(_ presets: [SavedPreset]) {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Engine

extension CameraModel {
    /// Properties a preset may change, in the order they're applied: the mode first, because it decides
    /// which of the others the camera lets the app set.
    static let presetOrder = ["takemode", "focalvalue", "shutspeedvalue", "isospeedvalue", "expcomp", "wbvalue", "drivemode"]

    /// A property the app can change right now.
    func settableProperty(_ name: String) -> CameraProperty? {
        properties[name].flatMap { $0.settable ? $0 : nil }
    }

    /// Which exposure settings a mode lets you set.
    static func mode(_ mode: String, allows name: String) -> Bool {
        switch name {
        case "focalvalue": ["A", "M"].contains(mode)
        case "shutspeedvalue": ["S", "M"].contains(mode)
        case "expcomp": ["P", "A", "S"].contains(mode)
        default: true
        }
    }

    /// The mode step, and whether the camera will be in that mode once it has run.
    func modeStep(_ target: String, why: String) -> (step: PresetStep, inMode: Bool) {
        let option = settableProperty("takemode")?.options.first { $0.uppercased() == target }
        let current = properties["takemode"]?.value
        let already = current?.uppercased() == target
        let names = ["M": "Manual", "A": "Aperture priority", "S": "Shutter priority", "P": "Program"]
        let step = PresetStep(title: "\(names[target] ?? target) mode", detail: why, property: "takemode",
                              value: option ?? (already ? current : nil),
                              unavailable: "Turn the camera's mode dial to \(target): the app can't change the mode on this camera")
        return (step, option != nil || already)
    }

    /// A step for one setting, with nothing to set when the camera doesn't offer it (now, or once in `mode`).
    func presetStep(_ title: String, _ detail: String, _ name: String, _ value: String?,
                    mode: String? = nil, inMode: Bool = false,
                    unavailable: String = "Not offered by the camera over Wi-Fi") -> PresetStep {
        let available = settableProperty(name) != nil
            || (inMode && properties[name] != nil && mode.map { Self.mode($0, allows: name) } == true)
        var step = PresetStep(title: title, detail: detail, property: name, value: available ? value : nil,
                              unavailable: unavailable)
        if let mode, !inMode, ["focalvalue", "shutspeedvalue", "expcomp"].contains(name) {
            step.onCamera = "Turn the camera's mode dial to \(mode), then apply again."
        } else if name == "drivemode" {
            // Several bodies have a drive dial the phone can't turn (or say OK and ignore the change).
            step.onCamera = unavailable
        }
        return step
    }

    // MARK: Values

    func aperture(near f: Double) -> String? {
        guard let property = properties["focalvalue"] else { return nil }
        return dialOptions(for: property).options
            .compactMap { option in Double(option).map { (option, $0) } }
            .min { abs(Foundation.log($0.1 / f)) < abs(Foundation.log($1.1 / f)) }?.0
    }

    /// The timed shutter speed closest to `seconds` (Bulb and Live modes excluded).
    func shutter(near seconds: Double) -> String? {
        timedShutters.min { abs(Foundation.log($0.1 / seconds)) < abs(Foundation.log($1.1 / seconds)) }?.0
    }

    /// The camera's timed shutter speeds with their length in seconds.
    var timedShutters: [(String, Double)] {
        (properties["shutspeedvalue"]?.options ?? [])
            .compactMap { option in PropertyFormat.seconds(fromShutter: option).map { (option, $0) } }
    }

    var lowestISO: String? {
        properties["isospeedvalue"]?.options
            .compactMap { option in Int(option).map { (option, $0) } }
            .min { $0.1 < $1.1 }?.0
    }

    var autoISO: String? {
        properties["isospeedvalue"]?.options.first { $0.lowercased() == "auto" }
    }

    var zeroEV: String? {
        properties["expcomp"]?.options.first { Double($0) == 0 }
    }

    /// The first of `preferred` the camera offers for `name`.
    func option(_ name: String, in preferred: [String]) -> String? {
        let options = properties[name]?.options ?? []
        return preferred.first { options.contains($0) }
    }

    /// Keeps a tripod shot steady: anti-shock drive where the camera has it, else a 2 s self-timer,
    /// else what to set on the camera, so the step never just says "not offered".
    func antiShockStep(_ detail: String = "Avoids shutter-shock blur on a tripod") -> PresetStep {
        let onCamera = brand == .panasonic
            ? "Set it on the camera: turn the drive dial to the self-timer and choose 2 s in MENU ▸ Rec ▸ Self Timer, "
                + "or choose ESHTR (electronic shutter) in MENU ▸ Rec ▸ Shutter Type."
            : "Set it on the camera: a 2 s self-timer, or the electronic (silent) shutter."
        var step = if let timer = option("drivemode", in: ["selftimer|2sec"]), option("drivemode", in: ["lowvib-normal"]) == nil {
            presetStep("2 s self-timer", "\(detail): the camera waits 2 s after the press", "drivemode", timer)
        } else {
            presetStep("Anti-shock drive", detail, "drivemode", option("drivemode", in: ["lowvib-normal"]), unavailable: onCamera)
        }
        step.onCamera = onCamera
        return step
    }

    /// Runs steps in order and records what the camera accepted. They're worked out again before each
    /// one, because changing the mode changes what the camera offers. What they change is remembered
    /// so Undo can put it back. Returns false if the camera refused any of them.
    @discardableResult
    func runPreset(id: String, title: String, steps make: () -> [PresetStep]) async -> Bool {
        guard !presetRunning else { return false }
        presetRunning = true
        defer { presetRunning = false }
        presetResultsFor = id
        let before = Dictionary(uniqueKeysWithValues: Self.presetOrder.compactMap { name in
            properties[name].map { (name, $0.value) }
        })
        presetSteps = make()
        var changed = false
        for index in presetSteps.indices {
            let fresh = make()
            guard index < fresh.count else { break }
            presetSteps[index].value = fresh[index].value
            presetSteps[index].unavailable = fresh[index].unavailable
            presetSteps[index].onCamera = fresh[index].onCamera
            let step = presetSteps[index]
            guard let value = step.value, let property = properties[step.property] else {
                presetSteps[index].state = .skipped(step.unavailable)
                continue
            }
            if property.value == value {
                presetSteps[index].state = .done
                continue
            }
            presetSteps[index].state = .running
            let ok = await setProperty(step.property, to: value, reportErrors: false)
            if ok {
                changed = true
                presetSteps[index].state = .done
            } else if let onCamera = step.onCamera {
                // A dial or mode the phone can't turn: say what to do, not "refused".
                presetSteps[index].state = .skipped("Couldn't set \(PropertyFormat.display(step.property, value)) from the phone. \(onCamera)")
            } else {
                presetSteps[index].state = .failed("The camera refused \(PropertyFormat.display(step.property, value))")
            }
        }
        let failed = presetSteps.contains { if case .failed = $0.state { true } else { false } }
        // The setup stays on (even when the camera was already set that way) until it's turned off,
        // which puts back the settings from just before it.
        if changed || !failed {
            presetUndo = SettingsSnapshot(id: id, title: title, values: before)
            savePresetUndo()
        }
        return !failed
    }

    /// Puts back the settings from before the last preset: the mode first, then whatever it lets the
    /// app set (in A, for example, the camera picks the shutter itself again).
    /// The setup (recipe or saved preset) is on: applied, and not yet turned off.
    func isPresetOn(_ id: String) -> Bool { presetUndo?.id == id }

    /// A setup that's on is kept per camera, so after a restart it still shows and can be turned off.
    private var presetUndoKey: String? { savedCameras.first.map { "presetOn.\($0.id)" } }

    func savePresetUndo() {
        guard let key = presetUndoKey else { return }
        if let presetUndo, let data = try? JSONEncoder().encode(presetUndo) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func restorePresetUndo() {
        guard let key = presetUndoKey, let data = UserDefaults.standard.data(forKey: key) else { return }
        presetUndo = try? JSONDecoder().decode(SettingsSnapshot.self, from: data)
    }

    /// Turns the setup off: puts back the settings from before it.
    func undoPreset() async {
        guard let snapshot = presetUndo, !presetRunning else { return }
        presetRunning = true
        defer { presetRunning = false }
        var missed: [String] = []
        for name in Self.presetOrder {
            guard let value = snapshot.values[name], let property = properties[name], property.value != value,
                  property.settable else { continue }
            if !(await setProperty(name, to: value, reportErrors: false)) {
                missed.append(PropertyFormat.title(for: name))
            }
        }
        presetUndo = nil
        savePresetUndo()
        presetSteps = []
        presetResultsFor = nil
        if missed.isEmpty {
            showToast("Settings from before \(snapshot.title) are back")
        } else {
            lastError = "Couldn't put back: \(missed.joined(separator: ", "))."
        }
    }

    // MARK: Recipes

    func steps(for recipe: PresetRecipe) -> [PresetStep] {
        switch recipe {
        case .astro:
            return astroSteps(for: AstroPlan(cropFactor: cropFactor))
        case .moon:
            let (mode, inM) = modeStep("M", why: "The moon is as bright as daylight: auto exposure burns it out")
            return [
                mode,
                presetStep("Aperture f/8", "Sharpest on most lenses", "focalvalue", aperture(near: 8), mode: "M", inMode: inM),
                presetStep("Shutter 1/250 s", "Freezes the moon's movement", "shutspeedvalue", shutter(near: 1.0 / 250),
                           mode: "M", inMode: inM),
                presetStep("ISO 200", "Low noise: the moon is bright", "isospeedvalue", nearestISO(to: 200)),
                presetStep("Daylight white balance", "The moon is lit by the sun", "wbvalue", option("wbvalue", in: ["18"])),
                antiShockStep(),
            ]
        case .fireworks:
            let (mode, inM) = modeStep("M", why: "Auto exposure is fooled by a dark sky")
            let liveComposite = option("shutspeedvalue", in: ["livecomp"])
            let shutterStep = liveComposite != nil
                ? presetStep("Live Composite", "Each burst adds up without washing out the sky", "shutspeedvalue",
                             liveComposite, mode: "M", inMode: inM)
                : presetStep("Shutter 4 s", "Long enough for a whole burst", "shutspeedvalue", shutter(near: 4),
                             mode: "M", inMode: inM)
            return [
                mode,
                presetStep("Aperture f/8", "Crisp, colourful trails", "focalvalue", aperture(near: 8), mode: "M", inMode: inM),
                shutterStep,
                presetStep("Lowest ISO", "Fireworks are bright; keep the sky black", "isospeedvalue", lowestISO),
                presetStep("Daylight white balance", "True firework colours", "wbvalue", option("wbvalue", in: ["18"])),
                antiShockStep(),
            ]
        case .landscape, .macro:
            let (mode, inA) = modeStep("A", why: "You pick the depth of field, the camera the shutter")
            let macro = recipe == .macro
            return [
                mode,
                presetStep("Aperture f/8", macro ? "More depth without softening from diffraction" : "Front-to-back sharpness on most lenses",
                           "focalvalue", aperture(near: 8), mode: "A", inMode: inA),
                presetStep("Lowest ISO", "The cleanest files", "isospeedvalue", lowestISO),
                presetStep("Exposure ±0", "Start from the camera's metering", "expcomp", zeroEV, mode: "A", inMode: inA),
                macro ? antiShockStep("Close up, the smallest shake shows") : antiShockStep(),
            ]
        case .action:
            let (mode, inS) = modeStep("S", why: "You pick the shutter, the camera the aperture")
            return [
                mode,
                presetStep("Shutter 1/1000 s", "Freezes running, sport and birds", "shutspeedvalue", shutter(near: 1.0 / 1000),
                           mode: "S", inMode: inS),
                presetStep("Auto ISO", "Keeps the fast shutter as the light changes", "isospeedvalue", autoISO,
                           unavailable: "Set Auto ISO on the camera"),
                presetStep("Exposure ±0", "Start from the camera's metering", "expcomp", zeroEV, mode: "S", inMode: inS),
                presetStep("Fast continuous drive", "Hold the shutter for a burst", "drivemode",
                           option("drivemode", in: ["continuous-H", "silent-continuous-H"]),
                           unavailable: "Set continuous shooting on the camera"),
            ]
        case .trails:
            let (mode, inM) = modeStep("M", why: "The exposure stays fixed while the lights move")
            return [
                mode,
                presetStep("Aperture f/11", "Lets the shutter stay open longer", "focalvalue", aperture(near: 11),
                           mode: "M", inMode: inM),
                presetStep("Shutter 15 s", "Long enough to draw trails and smooth water", "shutspeedvalue",
                           shutter(near: 15), mode: "M", inMode: inM),
                presetStep("Lowest ISO", "The cleanest files, and the longest exposure", "isospeedvalue", lowestISO),
                antiShockStep(),
            ]
        }
    }

    func apply(_ recipe: PresetRecipe) async -> Bool {
        let ok = await runPreset(id: recipe.id, title: recipe.title) { steps(for: recipe) }
        if ok, recipe != .astro { showToast("\(recipe.title) settings applied") }
        return ok
    }

    // MARK: Saved presets

    /// Saves what the app can set right now under `name`, for this camera brand.
    func saveCurrentSettings(as name: String) {
        let values = Dictionary(uniqueKeysWithValues: Self.presetOrder.compactMap { key in
            settableProperty(key).map { (key, $0.value) }
        })
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        savedPresets.insert(SavedPreset(name: trimmed.isEmpty ? "My preset" : trimmed, brand: brand.rawValue,
                                        values: values), at: 0)
        showToast("Saved \"\(savedPresets[0].name)\"")
    }

    var savedPresetsForCamera: [SavedPreset] {
        savedPresets.filter { $0.brand == brand.rawValue }
    }

    func steps(for saved: SavedPreset) -> [PresetStep] {
        var steps: [PresetStep] = []
        var target: String?
        var inMode = false
        if let mode = saved.values["takemode"] {
            let option = settableProperty("takemode")?.options.first { $0 == mode }
            let already = properties["takemode"]?.value == mode
            target = mode.uppercased()
            inMode = option != nil || already
            steps.append(PresetStep(title: "Mode", detail: "As saved", property: "takemode",
                                    value: option ?? (already ? mode : nil),
                                    unavailable: "Turn the camera's mode dial to \(PropertyFormat.display("takemode", mode))"))
        }
        for name in Self.presetOrder.dropFirst() {
            guard let value = saved.values[name] else { continue }
            let offered = properties[name]?.options.contains(value) ?? false
            steps.append(presetStep(PropertyFormat.title(for: name), "As saved", name, offered ? value : nil,
                                    mode: target, inMode: inMode,
                                    unavailable: offered ? "Not settable in this mode" : "Not offered by the camera now"))
        }
        return steps
    }

    func apply(_ saved: SavedPreset) async {
        if await runPreset(id: saved.id.uuidString, title: saved.name, steps: { steps(for: saved) }) {
            showToast("\(saved.name) applied")
        }
    }

    func deleteSavedPreset(_ saved: SavedPreset) {
        savedPresets.removeAll { $0.id == saved.id }
    }
}

import Foundation

/// One setting a preset tries to apply, with what happened.
struct PresetStep: Identifiable, Equatable {
    enum State: Equatable {
        case pending, running, done
        case failed(String)
        case skipped(String)
    }

    let id = UUID()
    let title: String
    let detail: String
    let property: String
    var value: String?
    /// Why the step can't run on this camera, shown when `value` is nil.
    var unavailable = "Not offered by the camera over Wi-Fi"
    var state: State = .pending
}

/// Night-sky settings for a camera on a tripod.
struct AstroPlan {
    var focalLength: Double = 17
    /// 300 rule (pin-sharp on a 20 MP sensor) instead of the classic 500 rule.
    var strict = true
    var iso = 1600
    /// Star trails with Live Composite instead of single exposures.
    var trails = false
    /// The sensor's crop factor: 2 for Micro Four Thirds, about 1.5 for APS-C, 1 for full frame.
    var cropFactor: Double = 2

    /// Longest exposure before stars visibly streak: rule ÷ (focal length × crop factor).
    var maxSeconds: Double { (strict ? 300 : 500) / (focalLength * cropFactor) }
}

extension CameraModel {
    /// Slowest available shutter that still keeps stars round (or Live Composite for trails).
    func astroShutter(for plan: AstroPlan) -> String? {
        guard let options = properties["shutspeedvalue"]?.options else { return nil }
        if plan.trails { return options.first { $0.lowercased() == "livecomp" } }
        return options
            .compactMap { option in PropertyFormat.seconds(fromShutter: option).map { (option, $0) } }
            .filter { $0.1 <= plan.maxSeconds }
            .max { $0.1 < $1.1 }?.0
    }

    var widestAperture: String? {
        guard let property = properties["focalvalue"] else { return nil }
        return dialOptions(for: property).options
            .compactMap { option in Double(option).map { (option, $0) } }
            .min { $0.1 < $1.1 }?.0
    }

    func nearestISO(to target: Int) -> String? {
        properties["isospeedvalue"]?.options
            .compactMap { option in Int(option).map { (option, $0) } }
            .min { abs($0.1 - target) < abs($1.1 - target) }?.0
    }

    /// The sensor's crop factor, from the brand and model, for the 300/500 rules.
    var cropFactor: Double { Self.cropFactor(brand: brand, model: cameraName ?? "") }

    static func cropFactor(brand: CameraBrand, model: String) -> Double {
        let m = model.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        func starts(_ prefixes: [String]) -> Bool { prefixes.contains { m.hasPrefix($0) } }
        switch brand {
        case .olympus:
            return 2
        case .panasonic:
            // LUMIX S bodies (DC-S1, S1R, S1H, S5, S5 II, S9) are full frame; G, GH, GX, GF are Four Thirds.
            return starts(["DCS", "S1", "S5", "S9"]) ? 1 : 2
        case .nikon:
            // Full frame: Z5, Z6 (II, III), Z7, Z8, Z9, Zf and the FX DSLRs. Z50, Z30, Zfc and D3xxx–D7xxx are DX.
            let name = m.replacingOccurrences(of: "NIKON", with: "")
            let fullFrame = ["Z5", "Z6", "Z7", "Z8", "Z9", "ZF", "D3", "D4", "D5", "D6", "D600", "D610", "D700",
                             "D750", "D780", "D800", "D810", "D850", "DF"]
            let isFullFrame = fullFrame.contains { body in
                ["", "_", "II", "S", "X", "E", "H"].contains { suffix in
                    name == body + suffix || (!suffix.isEmpty && name.hasPrefix(body + suffix) && suffix != "S")
                }
            }
            return isFullFrame ? 1 : 1.5
        case .canon:
            let name = m.replacingOccurrences(of: "CANON", with: "").replacingOccurrences(of: "EOS", with: "")
            if ["R", "RP", "R1", "R3", "R5", "R5II", "R5MARKII", "R6", "R6II", "R6MARKII", "R8"].contains(name)
                || name.hasPrefix("5D") || name.hasPrefix("6D") || name.hasPrefix("1D") { return 1 }
            if name.hasPrefix("POWERSHOT") || name.hasPrefix("G") || name.hasPrefix("SX") { return 2.7 }
            return 1.6
        case .sony:
            // a7 / a9 / a1 (ILCE-7…, -9, -1) and RX1 are full frame; RX100 and RX10 have 1-inch sensors.
            let name = m.replacingOccurrences(of: "SONY", with: "")
            if ["ILCE7", "ILCE9", "ILCE1", "A7", "A9", "A1", "DSCRX1", "RX1"].contains(where: { name.hasPrefix($0) })
                && !["DSCRX10", "RX10"].contains(where: { name.hasPrefix($0) }) { return 1 }
            if ["DSCRX10", "RX10"].contains(where: { name.hasPrefix($0) }) { return 2.7 }
            return 1.5
        }
    }

    func astroSteps(for plan: AstroPlan) -> [PresetStep] {
        /// Only properties the app can change take part; the others get a reason instead of a value.
        func settable(_ name: String) -> CameraProperty? { properties[name].flatMap { $0.settable ? $0 : nil } }

        let mode = settable("takemode")?.options.first { $0.uppercased() == "M" }
        let modeOnCamera = properties["takemode"]?.value.uppercased() == "M"
        // In A, S or P the camera locks aperture or shutter; once the preset has switched to M they open up.
        let willBeManual = mode != nil || modeOnCamera
        func exposure(_ name: String) -> CameraProperty? {
            settable(name) ?? (willBeManual ? properties[name] : nil)
        }
        let modeStep = PresetStep(title: "Manual mode", detail: "So aperture and shutter can be set", property: "takemode",
                                  value: mode ?? (modeOnCamera ? "M" : nil),
                                  unavailable: "Turn the camera's mode dial to M: the app can't change the mode on this camera")

        let hasLiveComposite = properties["shutspeedvalue"]?.options.contains { $0.lowercased() == "livecomp" } ?? false
        let shutterDetail: String = plan.trails
            ? "Live Composite: stacks only new light, so stars draw trails"
            : String(format: "Longest that keeps stars sharp at %d mm (≤ %.1f s)", Int(plan.focalLength), plan.maxSeconds)
        let shutterUnavailable = plan.trails && !hasLiveComposite
            ? "Live Composite is an Olympus / OM System feature. For trails here, use the interval timer and stack the frames"
            : "Not offered by the camera over Wi-Fi"

        // About 4000 K keeps the night sky a neutral blue. Fluorescent is the nearest preset on most
        // bodies; LUMIX has none, so it falls back to Incandescent (about 3200 K, a cooler blue).
        let wbOptions = settable("wbvalue")?.options ?? []
        let wbStep: PresetStep = if wbOptions.contains("35") {
            PresetStep(title: "White balance ≈ 4000 K", detail: "Neutral-blue night sky (Fluorescent preset)",
                       property: "wbvalue", value: "35")
        } else if wbOptions.contains("20") {
            PresetStep(title: "White balance ≈ 3200 K",
                       detail: "Cool-blue night sky (Incandescent: this camera has no 4000 K preset)",
                       property: "wbvalue", value: "20")
        } else {
            PresetStep(title: "White balance ≈ 4000 K", detail: "Neutral-blue night sky", property: "wbvalue", value: nil,
                       unavailable: "Set about 4000 K on the camera, or shoot RAW and set it afterwards")
        }

        let drive = settable("drivemode")?.options.first { $0 == "lowvib-normal" }
        return [
            modeStep,
            PresetStep(title: "Widest aperture", detail: "Gather as much starlight as possible", property: "focalvalue",
                       value: exposure("focalvalue") == nil ? nil : widestAperture),
            PresetStep(title: "Shutter", detail: shutterDetail, property: "shutspeedvalue",
                       value: exposure("shutspeedvalue") == nil ? nil : astroShutter(for: plan),
                       unavailable: shutterUnavailable),
            PresetStep(title: "ISO", detail: "Bright enough for faint stars without too much noise", property: "isospeedvalue",
                       value: settable("isospeedvalue") == nil ? nil : nearestISO(to: plan.iso)),
            wbStep,
            PresetStep(title: "Anti-shock drive", detail: "Avoids shutter-shock blur on a tripod", property: "drivemode",
                       value: drive,
                       unavailable: "Use the camera's electronic shutter or a 2 s self-timer instead"),
        ]
    }

    /// Applies each step in order and records what the camera accepted.
    func applyAstro(_ plan: AstroPlan) async {
        guard !presetRunning else { return }
        presetRunning = true
        defer { presetRunning = false }
        presetSteps = astroSteps(for: plan)
        for index in presetSteps.indices {
            // Work the value out again now: switching to M changes what the camera offers.
            let fresh = astroSteps(for: plan)[index]
            presetSteps[index].value = fresh.value
            presetSteps[index].unavailable = fresh.unavailable
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
            var refused = "The camera refused \(PropertyFormat.display(step.property, value))"
            // In A, S or P the camera picks aperture or shutter itself; the mode dial is the likely cause.
            if !ok, ["focalvalue", "shutspeedvalue"].contains(step.property),
               case .skipped = presetSteps.first(where: { $0.property == "takemode" })?.state {
                refused += ". Is the camera's mode dial on M?"
            }
            presetSteps[index].state = ok ? .done : .failed(refused)
        }
    }
}

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
    /// Added to "The camera refused …" when the likely cause is a setting the app can't see.
    var hint: String?
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
    /// Slowest available shutter that still keeps stars round. For trails, Live Composite where the
    /// camera has it, else 30 s frames for the interval timer to shoot back to back.
    func astroShutter(for plan: AstroPlan) -> String? {
        if plan.trails, hasLiveComposite { return properties["shutspeedvalue"]?.options.first { $0.lowercased() == "livecomp" } }
        let longest = plan.trails ? 30 : plan.maxSeconds
        return timedShutters.filter { $0.1 <= longest }.max { $0.1 < $1.1 }?.0
    }

    var hasLiveComposite: Bool {
        properties["shutspeedvalue"]?.options.contains { $0.lowercased() == "livecomp" } ?? false
    }

    /// Star trails without Live Composite: about an hour of back-to-back frames, to stack afterwards.
    func trailsSeries(for plan: AstroPlan) -> IntervalPlan? {
        guard plan.trails, !hasLiveComposite else { return nil }
        let frame = astroShutter(for: plan).flatMap(PropertyFormat.seconds(fromShutter:)) ?? 30
        let every = (frame + 3).rounded()   // a few seconds to save each frame
        return IntervalPlan(count: Int((3600 / every).rounded()), seconds: every)
    }

    /// Starts the star-trail series, and leaves the same plan in the Interval panel.
    func startTrailsSeries(_ series: IntervalPlan) {
        UserDefaults.standard.set(series.count, forKey: "interval.count")
        UserDefaults.standard.set(series.seconds, forKey: "interval.seconds")
        UserDefaults.standard.set(false, forKey: "interval.ramp")
        startInterval(series)
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
            if ["DSCRX10", "RX10"].contains(where: { name.hasPrefix($0) }) { return 2.7 }
            if ["ILCE7", "ILCE9", "ILCE1", "A7", "A9", "A1", "DSCRX1", "RX1"].contains(where: { name.hasPrefix($0) }) { return 1 }
            return 1.5
        }
    }

    func astroSteps(for plan: AstroPlan) -> [PresetStep] {
        // In A, S or P the camera locks aperture or shutter; once the preset has switched to M they open up.
        let (mode, inM) = modeStep("M", why: "So aperture and shutter can be set")
        let shutterDetail: String = !plan.trails
            ? String(format: "Longest that keeps stars sharp at %d mm (≤ %.1f s)", Int(plan.focalLength), plan.maxSeconds)
            : hasLiveComposite ? "Live Composite: stacks only new light, so stars draw trails"
            : "One frame of the series: the interval timer shoots them back to back, then stack them"
        let shutterUnavailable = "Not offered by the camera over Wi-Fi"

        // About 4000 K keeps the night sky a neutral blue. Fluorescent is the nearest preset on most
        // bodies; LUMIX has none, so it falls back to Incandescent (about 3200 K, a cooler blue).
        let wbOptions = settableProperty("wbvalue")?.options ?? []
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

        return [
            mode,
            presetStep("Widest aperture", "Gather as much starlight as possible", "focalvalue", widestAperture,
                       mode: "M", inMode: inM),
            presetStep("Shutter", shutterDetail, "shutspeedvalue", astroShutter(for: plan), mode: "M", inMode: inM,
                       unavailable: shutterUnavailable),
            presetStep("ISO", "Bright enough for faint stars without too much noise", "isospeedvalue",
                       nearestISO(to: plan.iso)),
            wbStep,
            antiShockStep(),
        ]
    }

    /// Applies the night-sky settings; Undo in Presets puts the old ones back.
    @discardableResult
    func applyAstro(_ plan: AstroPlan) async -> Bool {
        await runPreset(id: PresetRecipe.astro.id, title: "Astro") { astroSteps(for: plan) }
    }
}

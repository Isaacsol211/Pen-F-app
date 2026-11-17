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
    let value: String?
    var state: State = .pending
}

/// Night-sky settings for a tripod-mounted PEN-F.
struct AstroPlan {
    var focalLength: Double = 17
    /// 300 rule (pin-sharp on a 20 MP sensor) instead of the classic 500 rule.
    var strict = true
    var iso = 1600
    /// Star trails with Live Composite instead of single exposures.
    var trails = false

    /// Longest exposure before stars visibly streak: rule ÷ (focal length × 2× crop).
    var maxSeconds: Double { (strict ? 300 : 500) / (focalLength * 2) }
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

    func astroSteps(for plan: AstroPlan) -> [PresetStep] {
        let mode = properties["takemode"]?.options.first { $0.uppercased() == "M" }
        let shutter = astroShutter(for: plan)
        let wb = properties["wbvalue"]?.options.first { $0 == "35" }
        let drive = properties["drivemode"]?.options.first { $0 == "lowvib-normal" }
        let shutterDetail: String = plan.trails
            ? "Live Composite: stacks only new light, so stars draw trails"
            : String(format: "Longest that keeps stars sharp at %d mm (≤ %.1f s)", Int(plan.focalLength), plan.maxSeconds)
        return [
            PresetStep(title: "Manual mode", detail: "So aperture and shutter can be set", property: "takemode", value: mode),
            PresetStep(title: "Widest aperture", detail: "Gather as much starlight as possible", property: "focalvalue", value: widestAperture),
            PresetStep(title: "Shutter", detail: shutterDetail, property: "shutspeedvalue", value: shutter),
            PresetStep(title: "ISO", detail: "Bright enough for faint stars without too much noise", property: "isospeedvalue", value: nearestISO(to: plan.iso)),
            PresetStep(title: "White balance ≈ 4000 K", detail: "Neutral-blue night sky (Fluorescent preset)", property: "wbvalue", value: wb),
            PresetStep(title: "Anti-shock drive", detail: "Avoids shutter-shock blur on a tripod", property: "drivemode", value: drive),
        ]
    }

    /// Applies each step in order and records what the camera accepted.
    func applyAstro(_ plan: AstroPlan) async {
        guard !presetRunning else { return }
        presetRunning = true
        defer { presetRunning = false }
        presetSteps = astroSteps(for: plan)
        for index in presetSteps.indices {
            let step = presetSteps[index]
            guard let value = step.value, properties[step.property] != nil else {
                presetSteps[index].state = .skipped("Not offered by the camera over Wi-Fi")
                continue
            }
            presetSteps[index].state = .running
            let ok = await setProperty(step.property, to: value, reportErrors: false)
            presetSteps[index].state = ok ? .done : .failed("The camera refused \(PropertyFormat.display(step.property, value))")
        }
    }
}

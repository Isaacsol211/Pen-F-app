import CoreGraphics
import CoreLocation
import Foundation
import Vision

// MARK: - Suggestions

/// One suggestion shown over live view. Nothing changes until the user taps its button.
struct SceneSuggestion: Equatable, Identifiable {
    enum Action: Equatable {
        case recipe(PresetRecipe)
        /// Sets one property, e.g. exposure compensation or (in M) the shutter speed.
        case setting(property: String, value: String)
        case exposeToTheRight
        case openND
        case openMotion
    }

    /// Stable per kind of suggestion, so "not now" keeps that kind away for a while.
    let id: String
    let icon: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: Action
}

/// What the assistant looks at for one frame.
struct SceneSignals: Equatable {
    /// Apple's scene classification labels with their confidence (0…1).
    var labels: [String: Float] = [:]
    /// Mean linear brightness of the frame (0…1).
    var brightness: Double = 0.2
    /// Share of the frame with blown highlights (0…1).
    var clipped: Double = 0
    /// From the iPhone's clock and last known location; nil without a location.
    var sky: Astronomy.Sky?

    func score(_ names: String...) -> Float {
        names.map { labels[$0] ?? 0 }.max() ?? 0
    }

    var isDaylight: Bool { sky.map { $0.sunAltitude > 0 } ?? (brightness > 0.08) }
    var isDark: Bool { sky.map { $0.sunAltitude < -6 } ?? (brightness < 0.03) }
}

extension CameraModel {
    /// The suggestions that fit a frame, most useful first. Pure: reads the camera's settings, changes nothing.
    func sceneSuggestions(for s: SceneSignals) -> [SceneSuggestion] {
        var out: [SceneSuggestion] = []
        let liveComposite = option("shutspeedvalue", in: ["livecomp"]) != nil

        func recipe(_ r: PresetRecipe, _ id: String, _ icon: String, _ title: String, _ detail: String) {
            out.append(SceneSuggestion(id: id, icon: icon, title: title, detail: detail,
                                       actionTitle: r.title, action: .recipe(r)))
        }

        if s.score("fireworks") >= 0.3 {
            recipe(.fireworks, "fireworks", "sparkles", "Fireworks",
                   liveComposite ? "Live Composite adds each burst without washing out the sky" : "M, f/8 and a 4 s exposure per burst")
        }
        if s.score("moon") >= 0.3, (s.sky?.moonAltitude ?? 1) > -2 {
            recipe(.moon, "moon", "moon.fill", "The moon",
                   "Auto exposure burns it out: M, f/8, 1/250 s keeps the craters")
        }
        if s.score("aurora") >= 0.3 {
            recipe(.astro, "aurora", "moon.stars.fill", "Aurora",
                   "Astro settings, then try 2–5 s so the curtains stay sharp")
        }
        let darkNight = (s.sky.map { $0.sunAltitude < -12 } ?? false) && s.brightness < 0.01
        if s.score("night_sky") >= 0.3 || darkNight {
            var detail = "Astro sets M, the widest aperture and the longest shutter that keeps stars round"
            if let sky = s.sky, sky.moonAltitude > 0, sky.moonIllumination > 0.5 {
                detail = "The moon is \(Int(sky.moonIllumination * 100))% full and up: expect fewer faint stars. " + detail
            }
            recipe(.astro, "astro", "moon.stars.fill", "Night sky", detail)
        }
        if s.score("lightning") >= 0.3, liveComposite {
            recipe(.fireworks, "lightning", "cloud.bolt.fill", "Lightning",
                   "Live Composite catches each strike as it happens")
        }
        if s.score("waterfall", "ocean", "water_body", "waterways") >= 0.35 {
            if s.isDaylight || s.brightness > 0.12 {
                out.append(SceneSuggestion(id: "water-nd", icon: "camera.filters", title: "Silky water",
                                           detail: "In daylight a long exposure needs an ND filter: work it out here",
                                           actionTitle: "ND filter", action: .openND))
            } else {
                recipe(.trails, "water", "water.waves", "Silky water", "M, f/11 and 15 s smooths the water")
            }
        }
        if s.score("cityscape", "car", "traffic_light") >= 0.3, s.isDark || s.brightness < 0.04 {
            recipe(.trails, "trails", "car.rear.fill", "Light trails", "M, f/11 and 15 s draws car lights into lines")
        }
        if s.score("bird") >= 0.35 {
            recipe(.action, "bird", "bird.fill", "Bird",
                   "1/1000 s freezes wings. For a feeder, the Motion trigger can wait for it")
        } else if s.score("animal", "sport", "motorsport", "watersport", "winter_sport") >= 0.35 {
            recipe(.action, "action", "figure.run", "Movement", "1/1000 s and fast bursts freeze the action")
        }
        if s.score("flower", "insect") >= 0.35 {
            recipe(.macro, "macro", "camera.macro", "Close-up",
                   capabilities.focusDrive ? "f/8 and steady, then a focus stack for more depth" : "f/8 and steady for more depth")
        }

        // Exposure, from the frame itself.
        if s.clipped > 0.02, let change = exposureChange(thirds: -2) {
            out.append(SceneSuggestion(id: "clipping", icon: "exclamationmark.triangle.fill",
                                       title: "Highlights clipping",
                                       detail: "\(Int((s.clipped * 100).rounded()))% of the picture is blown out",
                                       actionTitle: change.label, action: .setting(property: change.property, value: change.value)))
        }
        if s.score("snow") >= 0.4, s.clipped < 0.01, let change = exposureChange(thirds: 2) {
            out.append(SceneSuggestion(id: "snow", icon: "snowflake", title: "Snow",
                                       detail: "Snow fools the meter into grey: brighten it",
                                       actionTitle: change.label, action: .setting(property: change.property, value: change.value)))
        }
        let goldenHour = s.sky.map { (-4...6).contains($0.sunAltitude) } ?? false
        if s.score("sunset_sunrise") >= 0.3 || goldenHour, s.clipped > 0.003, let change = exposureChange(thirds: -1) {
            out.append(SceneSuggestion(id: "golden", icon: "sun.horizon.fill", title: "Golden hour",
                                       detail: "A little less exposure keeps the colour in the sky",
                                       actionTitle: change.label, action: .setting(property: change.property, value: change.value)))
        }
        if s.isDaylight, s.score("mountain", "beach", "forest", "hill", "land", "blue_sky", "snow") >= 0.35 {
            recipe(.landscape, "landscape", "mountain.2.fill", "Landscape",
                   "f/8 and the lowest ISO for front-to-back sharpness")
        }
        let nightLabels = s.score("night_sky", "moon", "fireworks", "aurora", "lightning") >= 0.3
        if s.brightness < 0.02, s.clipped < 0.001, !nightLabels, !s.isDark {
            out.append(SceneSuggestion(id: "dark", icon: "sun.max", title: "Underexposed",
                                       detail: "There's room to brighten without losing highlights",
                                       actionTitle: "Expose right", action: .exposeToTheRight))
        }
        return out
    }

    /// A change of `thirds` of a stop: exposure compensation in P/A/S, else the shutter in M.
    func exposureChange(thirds: Int) -> (property: String, value: String, label: String)? {
        if let ev = settableProperty("expcomp"), let current = Double(ev.value) {
            let target = current + Double(thirds) / 3
            let values = ev.options.compactMap { option in Double(option).map { (option, $0) } }
            guard let best = values.min(by: { abs($0.1 - target) < abs($1.1 - target) }),
                  abs(best.1 - current) > 0.1 else { return nil }
            return ("expcomp", best.0, "EV \(PropertyFormat.display("expcomp", best.0))")
        }
        // In M: shutter speeds are a third of a stop apart, so step along the list.
        if settableProperty("shutspeedvalue") != nil, !isOpenEndedShutter,
           let current = PropertyFormat.seconds(fromShutter: properties["shutspeedvalue"]?.value ?? "") {
            let sorted = timedShutters.sorted { $0.1 < $1.1 }
            guard let index = sorted.indices.min(by: { abs(log2(sorted[$0].1 / current)) < abs(log2(sorted[$1].1 / current)) })
            else { return nil }
            let target = min(max(index + thirds, 0), sorted.count - 1)
            guard target != index else { return nil }
            let value = sorted[target].0
            return ("shutspeedvalue", value, PropertyFormat.display("shutspeedvalue", value))
        }
        return nil
    }
}

// MARK: - Running it

nonisolated(unsafe) private var classifyFailureLogged = false

extension CameraModel {
    /// Looks at live view every ~1.5 s while the remote screen is up, and keeps `sceneSuggestion`
    /// current. Runs on-device; nothing leaves the iPhone.
    func runSceneAssistant() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            guard sceneAssistantOn, phase == .connected, mode == .rec, liveViewRunning, !isShooting,
                  !bracket.running, !interval.running, !presetRunning, !motion.armed, let frame = recentFrame else {
                if !sceneAssistantOn { sceneSuggestion = nil }
                continue
            }
            let labels = await Self.classify(frame)
            guard !Task.isCancelled else { return }
            var signals = SceneSignals(labels: labels, brightness: FrameMeter.brightness(frame) ?? 0.2,
                                       clipped: FrameMeter.clipped(frame) ?? 0)
            if let location = locationLog.lastKnown {
                signals.sky = Astronomy.sky(at: Date(), latitude: location.coordinate.latitude,
                                            longitude: location.coordinate.longitude)
            }
            sceneSignals = signals
            showBest(of: sceneSuggestions(for: signals))
        }
    }

    /// Apple's on-device scene classification, off the main thread.
    nonisolated static func classify(_ image: CGImage) async -> [String: Float] {
        await Task.detached(priority: .utility) {
            do {
                let observations = try await ClassifyImageRequest().perform(on: image)
                var labels: [String: Float] = [:]
                for observation in observations where observation.confidence > 0.1 {
                    labels[observation.identifier] = observation.confidence
                }
                return labels
            } catch {
                // The classifier's model doesn't run in the iOS Simulator; elsewhere this is rare. The
                // assistant still works from exposure and the time of day without labels.
                if !classifyFailureLogged {
                    classifyFailureLogged = true
                    debugLog("Scene classification unavailable: \(error.localizedDescription)")
                }
                #if DEBUG
                // `-sceneLabels night_sky:0.97,sky:0.9` stands in for the classifier, to try the assistant there.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-sceneLabels"), i + 1 < args.count {
                    return Dictionary(uniqueKeysWithValues: args[i + 1].split(separator: ",").compactMap { pair in
                        let parts = pair.split(separator: ":")
                        guard parts.count == 2, let value = Float(parts[1]) else { return nil }
                        return (String(parts[0]), value)
                    })
                }
                #endif
                return [:]
            }
        }.value
    }

    /// Shows a suggestion once it has topped two looks in a row (no flicker), and hides it after two without.
    private func showBest(of suggestions: [SceneSuggestion]) {
        let now = Date()
        sceneSnoozed = sceneSnoozed.filter { $0.value > now }
        let best = suggestions.first { sceneSnoozed[$0.id] == nil }
        if let best, best.id == sceneSuggestion?.id {
            sceneSuggestion = best
            sceneMisses = 0
            return
        }
        if let best, best.id == sceneCandidate {
            sceneSuggestion = best
            sceneMisses = 0
        } else {
            sceneCandidate = best?.id
            sceneMisses += 1
            if sceneMisses >= 2 { sceneSuggestion = nil }
        }
    }

    /// "Not now": that kind of suggestion stays away for ten minutes.
    func dismissSceneSuggestion() {
        guard let suggestion = sceneSuggestion else { return }
        sceneSnoozed[suggestion.id] = Date().addingTimeInterval(600)
        sceneSuggestion = nil
        sceneCandidate = nil
    }

    /// Runs a suggestion's action. Panels (ND, Motion) are opened by the view.
    func applySceneSuggestion(_ suggestion: SceneSuggestion) async {
        sceneSuggestion = nil
        sceneCandidate = nil
        switch suggestion.action {
        case .recipe(let recipe):
            sceneSnoozed[suggestion.id] = Date().addingTimeInterval(600)
            _ = await apply(recipe)
        case .setting(let property, let value):
            // Give the new exposure time to reach live view before judging it again.
            sceneSnoozed[suggestion.id] = Date().addingTimeInterval(20)
            if await setProperty(property, to: value) {
                showToast("\(PropertyFormat.title(for: property)) \(PropertyFormat.display(property, value))")
            }
        case .exposeToTheRight:
            sceneSnoozed[suggestion.id] = Date().addingTimeInterval(120)
            await exposeToTheRight()
        case .openND, .openMotion:
            sceneSnoozed[suggestion.id] = Date().addingTimeInterval(600)
        }
    }
}

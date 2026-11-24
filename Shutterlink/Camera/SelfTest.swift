#if DEBUG
import Foundation
import UIKit

/// Debug builds only: `-selfTest <brand|auto> <address>` runs one driver through the whole flow
/// against a mock camera and prints "SELFTEST PASS/FAIL …" lines to stderr. It takes pictures and
/// changes settings, so point it at a mock, never at a real camera.
///
///     xcrun simctl launch --console-pty booted com.apexcommerce.shutterlink -selfTest nikon 127.0.0.1:15740
@MainActor
enum DriverSelfTest {
    static func runIfRequested(_ camera: CameraModel) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-selfTest"), i + 2 < args.count else { return }
        let brand = args[i + 1], host = args[i + 2]
        guard host.hasPrefix("127.") || host.hasPrefix("localhost") else {
            debugLog("SELFTEST refused: \(host) is not a mock on this Mac")
            return
        }
        Task { await run(camera, brand: brand, host: host) }
    }

    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures += 1 }
        debugLog("SELFTEST \(ok ? "PASS" : "FAIL") \(name) \(detail())")
    }

    private static func wait(_ seconds: Double, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
    }

    static func run(_ camera: CameraModel, brand: String, host: String) async {
        failures = 0
        camera.setBrand(CameraBrand(rawValue: brand))   // nil (for "auto") = auto-detect
        camera.host = host
        await camera.connect()
        check("connect", camera.phase == .connected,
              "brand=\(camera.brand.rawValue) name=\(camera.cameraName ?? "-") error=\(camera.lastError ?? "-")")
        guard camera.phase == .connected else { return finish() }
        if brand != "auto" { check("brand", camera.brand.rawValue == brand, camera.brand.rawValue) }
        debugLog("SELFTEST INFO profile=\(camera.profile?.name ?? "none") support=\(camera.profile?.support.rawValue ?? "-") note=\(camera.cameraNote ?? "-")")

        await wait(8) { camera.liveFrame != nil && camera.fps > 2 }
        check("live view", camera.liveFrame != nil,
              "fps=\(camera.fps) frame=\(Int(camera.frameSize.width))x\(Int(camera.frameSize.height))")

        let props = camera.properties.values.sorted { $0.name < $1.name }
        check("settings read", !props.isEmpty,
              props.map { "\($0.name)=\($0.value)\($0.settable ? "" : "(ro)")[\($0.options.count)]" }.joined(separator: " "))
        for name in ["expcomp", "focalvalue", "shutspeedvalue", "isospeedvalue", "wbvalue"] {
            guard let p = camera.properties[name], p.settable,
                  let target = p.options.first(where: { $0 != p.value && !PropertyFormat.isOpenEnded(shutter: $0) && $0 != "auto" })
            else { continue }
            let ok = await camera.setProperty(name, to: target)
            check("set \(name)", ok && camera.properties[name]?.value == target,
                  "\(p.value) → \(target), now \(camera.properties[name]?.value ?? "-") \(camera.lastError ?? "")")
            camera.lastError = nil
        }

        if camera.capabilities.tapToFocus {
            await camera.tapFocus(normalized: CGPoint(x: 0.4, y: 0.6))
            check("tap focus", camera.lastError == nil, "afState=\(camera.liveInfo.afState) \(camera.lastError ?? "")")
            camera.lastError = nil
        }

        let shots = camera.shotCounter
        camera.lastShot = nil
        await camera.shutterPressed()
        await camera.shutterReleased()
        check("shoot", camera.shotCounter == shots + 1 && camera.lastError == nil, camera.lastError ?? "")
        camera.lastError = nil
        if camera.capabilities.lastShotReview {
            await wait(5) { camera.lastShot != nil }
            check("last-shot review", camera.lastShot != nil)
        }

        if camera.capabilities.movie {
            if camera.capabilities.videoSwitch { camera.videoMode = true }
            await camera.toggleMovie()
            let started = camera.isRecordingMovie
            try? await Task.sleep(for: .seconds(1))
            await camera.toggleMovie()
            check("movie", started && !camera.isRecordingMovie, camera.lastError ?? "")
            camera.lastError = nil
            camera.videoMode = false
        }

        // The settings test above leaves values at the ends of their ranges (30 s shutters, −5 EV).
        // Put back a quick exposure so the interval and bracket frames don't each take half a minute.
        if let shutter = camera.properties["shutspeedvalue"], shutter.settable,
           let quick = shutter.options
            .compactMap({ option in PropertyFormat.seconds(fromShutter: option).map { (option, $0) } })
            .min(by: { abs($0.1 - 1.0 / 250) < abs($1.1 - 1.0 / 250) })?.0 {
            _ = await camera.setProperty("shutspeedvalue", to: quick)
        }
        if let ev = camera.properties["expcomp"], ev.settable,
           let zero = ev.options.first(where: { Double($0) == 0 }) {
            _ = await camera.setProperty("expcomp", to: zero)
        }
        camera.lastError = nil

        // Interval timer: two frames, then it stops by itself.
        let beforeInterval = camera.shotCounter
        camera.startInterval(IntervalPlan(count: 2, seconds: 1.5))
        await wait(20) { !camera.interval.running }
        check("interval", camera.shotCounter == beforeInterval + 2 && camera.lastError == nil,
              "shots=\(camera.shotCounter - beforeInterval) running=\(camera.interval.running) \(camera.lastError ?? "")")
        camera.lastError = nil

        // Exposure bracket: three frames, then the setting goes back.
        let beforeBracket = camera.shotCounter
        let bracketPlan = BracketPlan()
        if case .success(let set) = camera.bracketSet(bracketPlan) {
            let original = camera.properties[set.property]?.value
            camera.startBracket(bracketPlan)
            await wait(30) { !camera.bracket.running }
            check("bracket", camera.shotCounter == beforeBracket + set.values.count && camera.lastError == nil
                    && camera.properties[set.property]?.value == original,
                  "\(set.property) \(set.values) shots=\(camera.shotCounter - beforeBracket) now=\(camera.properties[set.property]?.value ?? "-") \(camera.lastError ?? "")")
        } else if case .failure(let error) = camera.bracketSet(bracketPlan) {
            check("bracket", false, error.localizedDescription)
        }
        camera.lastError = nil

        // Focus stack: three frames with the focus stepped farther between them, where the camera can.
        if camera.capabilities.focusDrive {
            let beforeStack = camera.shotCounter
            camera.startFocusStack(frames: 3, step: .medium)
            await wait(30) { !camera.bracket.running }
            check("focus stack", camera.shotCounter == beforeStack + 3 && camera.lastError == nil,
                  "shots=\(camera.shotCounter - beforeStack) \(camera.lastError ?? "")")
            camera.lastError = nil
        } else {
            debugLog("SELFTEST INFO focus stack not offered by this camera")
        }

        // Astro preset: every step either takes or says why it was skipped; none is refused.
        await camera.applyAstro(AstroPlan(cropFactor: camera.cropFactor))
        debugLog("SELFTEST INFO astro crop factor \(camera.cropFactor) for \(camera.cameraName ?? "-")")
        for step in camera.presetSteps {
            debugLog("SELFTEST INFO astro \(step.title) → \(step.value.map { PropertyFormat.display(step.property, $0) } ?? "-") \(step.state)")
        }
        let refused = camera.presetSteps.filter { if case .failed = $0.state { true } else { false } }
        check("astro preset", refused.isEmpty, refused.map(\.title).joined(separator: ", "))

        // Scene assistant: sky positions against known dates, rules against known scenes, and live analysis.
        let iso = ISO8601DateFormatter()
        let noon = Astronomy.sky(at: iso.date(from: "2026-06-21T12:00:00Z")!, latitude: 51.48, longitude: 0)
        let fullMoon = Astronomy.sky(at: iso.date(from: "2026-11-24T15:00:00Z")!, latitude: 51.48, longitude: 0)
        let newMoon = Astronomy.sky(at: iso.date(from: "2026-11-09T12:00:00Z")!, latitude: 51.48, longitude: 0)
        check("sky positions", abs(noon.sunAltitude - 62) < 1.5 && fullMoon.moonIllumination > 0.95 && newMoon.moonIllumination < 0.05,
              String(format: "sun %.1f° (≈62), full %.2f, new %.2f", noon.sunAltitude, fullMoon.moonIllumination, newMoon.moonIllumination))
        func top(_ signals: SceneSignals) -> String { camera.sceneSuggestions(for: signals).first?.id ?? "-" }
        let night = top(SceneSignals(labels: ["night_sky": 0.97, "sky": 0.97], brightness: 0.004))
        let moon = top(SceneSignals(labels: ["moon": 0.8], brightness: 0.01))
        let water = top(SceneSignals(labels: ["waterfall": 0.8], brightness: 0.3))
        let bird = top(SceneSignals(labels: ["bird": 0.7], brightness: 0.25))
        let clipping = camera.sceneSuggestions(for: SceneSignals(brightness: 0.4, clipped: 0.06)).map(\.id)
        check("scene rules", night == "astro" && moon == "moon" && water == "water-nd" && bird == "bird"
                && (clipping.contains("clipping") || camera.exposureChange(thirds: -2) == nil),
              "night=\(night) moon=\(moon) water=\(water) bird=\(bird) clipping=\(clipping)")
        await wait(8) { camera.sceneSignals != nil }
        check("scene analysis", camera.sceneSignals != nil,
              (camera.sceneSignals?.labels.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \(String(format: "%.2f", $0.value))" } ?? []).joined(separator: ", ")
                + " suggestion=\(camera.sceneSuggestion?.id ?? "-")")

        // One-tap recipes: every step applies or says why it can't; none is refused.
        for recipe in PresetRecipe.allCases where recipe != .astro {
            let ok = await camera.apply(recipe)
            let summary = camera.presetSteps.map { step -> String in
                let value = step.value.map { PropertyFormat.display(step.property, $0) } ?? "-"
                switch step.state {
                case .done: return "\(step.property)=\(value)"
                case .skipped: return "\(step.property):skip"
                case .failed(let why): return "\(step.property):FAILED(\(why))"
                default: return "\(step.property):\(step.state)"
                }
            }.joined(separator: " ")
            check("preset \(recipe.id)", ok, summary)
        }

        // Undo puts the mode back.
        if let mode = camera.properties["takemode"], mode.settable {
            let before = mode.value
            _ = await camera.apply(.moon)
            await camera.undoPreset()
            check("preset undo", camera.properties["takemode"]?.value == before && camera.lastError == nil,
                  "mode \(before) → \(camera.properties["takemode"]?.value ?? "-") \(camera.lastError ?? "")")
            camera.lastError = nil
        }

        // Saved preset round trip.
        camera.saveCurrentSettings(as: "Self-test")
        if let saved = camera.savedPresetsForCamera.first {
            await camera.apply(saved)
            let refused = camera.presetSteps.filter { if case .failed = $0.state { true } else { false } }
            check("saved preset", refused.isEmpty && !saved.values.isEmpty,
                  "\(saved.values.count) values, refused: \(refused.map(\.property))")
            camera.deleteSavedPreset(saved)
        }

        // ND calculator: meter, 6 stops, set up.
        if let meter = camera.meteredExposure {
            let ok = await camera.runPreset(id: "nd", title: "ND filter") { camera.ndSteps(meter: meter, stops: 6) }
            let target = CameraModel.ndSeconds(metered: meter.seconds, stops: 6)
            check("nd setup", ok, "metered \(meter.seconds)s → \(target)s, shutter now \(camera.properties["shutspeedvalue"]?.value ?? "-")")
        } else {
            check("nd meter", false, "no metered exposure")
        }

        // The ND step left a Bulb shutter; the trigger needs a timed one.
        if let quick = camera.shutter(near: 1.0 / 250), camera.settableProperty("shutspeedvalue") != nil {
            _ = await camera.setProperty("shutspeedvalue", to: quick)
        }
        await wait(8) { camera.recentFrame != nil }

        // Motion trigger: the mock's frame number (bottom left) changes every frame, so a box over it must fire.
        camera.motion.region = CGRect(x: 0.17, y: 0.86, width: 0.18, height: 0.13)
        camera.motion.sensitivity = 1
        camera.motion.cooldown = 1
        let beforeMotion = camera.shotCounter
        camera.armMotion(true)
        var peak = 0.0
        let deadline = Date().addingTimeInterval(12)
        while camera.shotCounter == beforeMotion, Date() < deadline {
            peak = max(peak, camera.motionLevel)
            try? await Task.sleep(for: .milliseconds(100))
        }
        camera.armMotion(false)
        await wait(5) { !camera.isShooting }
        check("motion trigger", camera.shotCounter > beforeMotion,
              "shots=\(camera.shotCounter - beforeMotion) peak=\(String(format: "%.4f", peak)) threshold=\(camera.motion.threshold)")

        // Expose to the right: finishes, and leaves the setting as it found it if live view can't judge it.
        let evBefore = camera.properties["expcomp"]?.value
        await camera.exposeToTheRight()
        debugLog("SELFTEST INFO ettr ev \(evBefore ?? "-") → \(camera.properties["expcomp"]?.value ?? "-") \(camera.lastError ?? camera.toast ?? "")")
        check("ettr", !camera.ettrRunning)
        camera.lastError = nil

        check("battery", camera.liveInfo.battery != nil, "\(camera.liveInfo.battery.map(String.init) ?? "-")%")

        if camera.capabilities.cardBrowser {
            await camera.openGallery()
            check("card list", !camera.images.isEmpty && camera.galleryError == nil,
                  "\(camera.images.count) files in \(camera.cardFolders.map(\.name)) \(camera.galleryError ?? "")")
            if let first = camera.images.first(where: { ["JPG", "JPEG"].contains($0.fileExtension) }) {
                let thumb = await camera.thumbnail(for: first)
                check("thumbnail", thumb != nil, first.name)
                do {
                    let preview = try await camera.preview(for: first)
                    check("preview", preview.size.width > 0, "\(Int(preview.size.width))x\(Int(preview.size.height))")
                    let data = try await camera.downloadOriginal(first)
                    check("download", !data.isEmpty, "\(first.name) \(data.count) bytes")
                } catch {
                    check("preview/download", false, error.localizedDescription)
                }
            }
            if let raw = camera.images.first(where: { CameraModel.rawExtensions.contains($0.fileExtension) }) {
                let data = try? await camera.downloadOriginal(raw)
                check("download RAW", (data?.count ?? 0) > 100_000, "\(raw.name) \(data?.count ?? 0) bytes")
            }
            await camera.closeGallery()
            await wait(8) { camera.liveViewRunning && camera.fps > 2 }
            check("live view after card", camera.liveViewRunning && camera.fps > 0, "fps=\(camera.fps)")
        }

        await camera.disconnect()
        check("disconnect", camera.phase == .disconnected)
        finish()
    }

    private static func finish() {
        debugLog("SELFTEST DONE failures=\(failures)")
    }
}
#endif

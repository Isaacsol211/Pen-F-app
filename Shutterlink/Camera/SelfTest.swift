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
        // `-mockConnect <brand> <127.0.0.1:port>` just connects to a mock and stays, for looking at the UI.
        if let j = args.firstIndex(of: "-mockConnect"), j + 2 < args.count, args[j + 2].hasPrefix("127.") {
            camera.setBrand(CameraBrand(rawValue: args[j + 1]))
            camera.host = args[j + 2]
            Task { await camera.connect() }
            return
        }
        guard let i = args.firstIndex(of: "-selfTest"), i + 2 < args.count else { return }
        let brand = args[i + 1], host = args[i + 2]
        guard host.hasPrefix("127.") || host.hasPrefix("localhost") else {
            debugLog("SELFTEST refused: \(host) is not a mock on this Mac")
            return
        }
        Task { await run(camera, brand: brand, host: host) }
    }

    private static func wait(_ seconds: Double, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
    }

    static func run(_ camera: CameraModel, brand: String, host: String) async {
        var failures = 0
        defer { debugLog("SELFTEST DONE failures=\(failures)") }
        /// Logs one result and clears the camera's error, so each check sees only its own.
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            if !ok { failures += 1 }
            debugLog("SELFTEST \(ok ? "PASS" : "FAIL") \(name) \(detail())")
            camera.lastError = nil
        }
        /// Starts a run that should take `count` pictures and stop by itself; checks it did, without an error.
        func shoots(_ name: String, _ count: Int, also: () -> Bool = { true }, start: () -> Void) async {
            let before = camera.shotCounter
            start()
            await wait(30) { !camera.interval.running && !camera.bracket.running }
            check(name, camera.shotCounter == before + count && camera.lastError == nil && also(),
                  "shots=\(camera.shotCounter - before) \(camera.lastError ?? "")")
        }
        /// A quick timed exposure: the settings test leaves 30 s shutters and −5 EV, ND leaves Bulb.
        func quickExposure() async {
            if camera.settableProperty("shutspeedvalue") != nil, let quick = camera.shutter(near: 1.0 / 250) {
                _ = await camera.setProperty("shutspeedvalue", to: quick)
            }
            if camera.settableProperty("expcomp") != nil, let zero = camera.zeroEV {
                _ = await camera.setProperty("expcomp", to: zero)
            }
            camera.lastError = nil
        }
        /// The last preset's steps: "property=value", ":skip", or ":FAILED(why)" where the camera refused.
        func presetSummary() -> String {
            camera.presetSteps.map { step -> String in
                switch step.state {
                case .done: "\(step.property)=\(step.value.map { PropertyFormat.display(step.property, $0) } ?? "-")"
                case .skipped: "\(step.property):skip"
                case .failed(let why): "\(step.property):FAILED(\(why))"
                default: "\(step.property):\(step.state)"
                }
            }.joined(separator: " ")
        }

        camera.setBrand(CameraBrand(rawValue: brand))   // nil (for "auto") = auto-detect
        camera.host = host
        await camera.connect()
        check("connect", camera.phase == .connected,
              "brand=\(camera.brand.rawValue) name=\(camera.cameraName ?? "-") error=\(camera.lastError ?? "-")")
        guard camera.phase == .connected else { return }
        debugLog("SELFTEST INFO profile=\(camera.profile?.name ?? "none") support=\(camera.profile?.support.rawValue ?? "-") crop=\(camera.cropFactor) note=\(camera.cameraNote ?? "-")")

        await wait(8) { camera.liveFrame != nil && camera.fps > 2 }
        check("live view", camera.liveFrame != nil,
              "fps=\(camera.fps) frame=\(Int(camera.frameSize.width))x\(Int(camera.frameSize.height))")

        let props = camera.properties.values.sorted { $0.name < $1.name }
        check("settings read", !props.isEmpty,
              props.map { "\($0.name)=\($0.value)\($0.settable ? "" : "(ro)")[\($0.options.count)]" }.joined(separator: " "))
        let extras = camera.brand == .panasonic ? ["drivemode", "colormode", "afmode", LumixMenu.kelvinName] : []
        for name in ["expcomp", "focalvalue", "shutspeedvalue", "isospeedvalue", "wbvalue"] + extras {
            guard let p = camera.settableProperty(name),
                  let target = p.options.first(where: { $0 != p.value && !PropertyFormat.isOpenEnded(shutter: $0) && $0 != "auto" })
            else { continue }
            let ok = await camera.setProperty(name, to: target)
            check("set \(name)", ok && camera.properties[name]?.value == target,
                  "\(p.value) → \(target), now \(camera.properties[name]?.value ?? "-") \(camera.lastError ?? "")")
        }

        if camera.capabilities.tapToFocus {
            await camera.tapFocus(normalized: CGPoint(x: 0.4, y: 0.6))
            check("tap focus", camera.lastError == nil, "afState=\(camera.liveInfo.afState) \(camera.lastError ?? "")")
        }

        let shots = camera.shotCounter
        camera.lastShot = nil
        await camera.shoot()
        check("shoot", camera.shotCounter == shots + 1 && camera.lastError == nil, camera.lastError ?? "")
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
            camera.videoMode = false
        }

        // Interval (two frames), exposure bracket (the setting goes back after) and, where the camera can
        // drive focus, a three-frame focus stack.
        await quickExposure()
        await shoots("interval", 2) { camera.startInterval(IntervalPlan(count: 2, seconds: 1.5)) }
        let bracketPlan = BracketPlan()
        switch camera.bracketSet(bracketPlan) {
        case .success(let set):
            let original = camera.properties[set.property]?.value
            await shoots("bracket", set.values.count, also: { camera.properties[set.property]?.value == original }) {
                camera.startBracket(bracketPlan)
            }
        case .failure(let error):
            check("bracket", false, error.localizedDescription)
        }
        if camera.capabilities.focusDrive {
            await shoots("focus stack", 3) { camera.startFocusStack(frames: 3, step: .medium) }
        }

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

        // One-tap recipes (Astro with this body's crop factor): every step applies or says why it can't.
        for recipe in PresetRecipe.allCases {
            let ok = await camera.apply(recipe)
            check("preset \(recipe.id)", ok, presetSummary())
        }
        // Undo puts the mode back.
        if let before = camera.settableProperty("takemode")?.value {
            _ = await camera.apply(.moon)
            await camera.undoPreset()
            check("preset undo", camera.properties["takemode"]?.value == before && camera.lastError == nil,
                  "mode \(before) → \(camera.properties["takemode"]?.value ?? "-") \(camera.lastError ?? "")")
        }
        camera.saveCurrentSettings(as: "Self-test")
        if let saved = camera.savedPresetsForCamera.first {
            let ok = await camera.runPreset(id: saved.id.uuidString, title: saved.name) { camera.steps(for: saved) }
            check("saved preset", ok && !saved.values.isEmpty, "\(saved.values.count) values: \(presetSummary())")
            camera.deleteSavedPreset(saved)
        }

        // ND calculator: meter, 6 stops, set up.
        if let meter = camera.meteredExposure {
            let ok = await camera.runPreset(id: "nd", title: "ND filter") { camera.ndSteps(meter: meter, stops: 6) }
            let target = CameraModel.ndSeconds(metered: meter.seconds, stops: 6)
            check("nd setup", ok, "metered \(meter.seconds)s → \(target)s, shutter now \(camera.properties["shutspeedvalue"]?.value ?? "-")")
        } else {
            check("nd setup", false, "no metered exposure")
        }

        // Motion trigger: the mock's frame number (bottom left) changes every frame, so a box over it must fire.
        await quickExposure()
        await wait(8) { camera.recentFrame != nil }
        camera.motion.region = CGRect(x: 0.17, y: 0.86, width: 0.18, height: 0.13)
        camera.motion.sensitivity = 1
        camera.motion.cooldown = 1
        let beforeMotion = camera.shotCounter
        var peak = 0.0
        camera.armMotion(true)
        await wait(12) { peak = max(peak, camera.motionLevel); return camera.shotCounter != beforeMotion }
        camera.armMotion(false)
        await wait(5) { !camera.isShooting }
        check("motion trigger", camera.shotCounter > beforeMotion,
              "shots=\(camera.shotCounter - beforeMotion) peak=\(String(format: "%.4f", peak)) threshold=\(camera.motion.threshold)")

        // Expose to the right: finishes, and leaves the setting as it found it if live view can't judge it.
        let evBefore = camera.properties["expcomp"]?.value
        await camera.exposeToTheRight()
        check("ettr", !camera.ettrRunning,
              "ev \(evBefore ?? "-") → \(camera.properties["expcomp"]?.value ?? "-") \(camera.lastError ?? camera.toast ?? "")")

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
    }
}
#endif

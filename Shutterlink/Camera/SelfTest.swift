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

import Foundation
import UIKit

// Olympus / OM System over the camera's own Wi-Fi (the OI.Share / OM Image Share protocol).
// Same HTTP commands across OM-D, PEN, TG and OM System bodies; what differs per model is
// listed by the camera itself in get_commandlist.cgi (live-view sizes, takeready, getrecview…)
// and in the property list (get_camprop desclist). See CameraHTTPClient.swift for the transport.

@MainActor
final class OlympusDriver: CameraDriver {
    unowned let camera: CameraModel
    let client: CameraHTTPClient
    private var loggedDescList = false

    init(camera: CameraModel) {
        self.camera = camera
        client = camera.makeHTTPClient(userAgent: camera.userAgent)
    }

    var liveViewFormat: LiveViewFormat { .olympusRTP }

    var capabilities: CameraCapabilities {
        CameraCapabilities(liveViewSizes: liveViewSizes, tapToFocus: true, openEndedExposure: true, movie: true,
                           videoSwitch: false, lastShotReview: true, clockSync: true,
                           highResShot: camera.profile?.highResShot ?? camera.cameraName.map(Self.hasHighResShot) ?? true,
                           cardBrowser: true, powerOff: true, userAgentChoice: true)
    }

    private var commands: CommandList { camera.commands }

    var liveViewSizes: [String] {
        let fromCamera = commands.liveViewSizes
        return fromCamera.isEmpty ? CameraBrand.olympus.defaultLiveViewSizes : fromCamera
    }

    /// For bodies missing from ModelProfiles: High Res Shot is on the PEN-F, E-M5 II/III, E-M1 II/III/X and
    /// OM System bodies, not the E-M10, E-PL, E-P, TG or Stylus ones.
    static func hasHighResShot(_ model: String) -> Bool {
        let m = model.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if m.contains("EM10") || m.contains("EPL") || m.contains("EP5") || m.contains("EP7") || m.hasPrefix("TG")
            || m.hasPrefix("SH") || m.hasPrefix("STYLUS") || m == "EM1" { return false }
        return true
    }

    // MARK: - Connect

    func connect() async throws {
        // The first request can fail while iOS shows the Local Network prompt,
        // and the camera can be slow right after its Wi-Fi comes up, so retry a little.
        var reply: Data?
        var failure: Error?
        for attempt in 1...3 {
            do {
                reply = try await client.get("get_connectmode", timeout: 5)
                break
            } catch {
                failure = error
                guard attempt < 3, error is URLError else { break }
                camera.status = "No answer yet, retrying (\(attempt + 1)/3)…"
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
        guard let reply else { throw failure ?? CameraError("No reply from the camera.") }
        camera.connectMode = MiniXML.parse(reply)?.trimmedText

        camera.status = "Reading camera info…"
        if let info = try? await client.get("get_caminfo") {
            let reported = MiniXML.parse(info)?.value("model")
            camera.profile = ModelProfiles.find(.olympus, reported: reported)
            camera.cameraName = camera.profile?.name ?? reported
            debugLog("Olympus model \(reported ?? "?") → \(camera.profile?.name ?? "not in the model table")")
            if let reason = camera.profile?.unsupportedReason { throw CameraError(reason) }
        }
        if let list = try? await client.get("get_commandlist") {
            camera.rawCommandList = String(decoding: list, as: UTF8.self)
            camera.commands = CommandList(root: MiniXML.parse(list))
            debugLog("COMMANDLIST\n\(camera.rawCommandList)")
        }
        loggedDescList = false
        // A saved size this body doesn't offer (e.g. 1280×960 on an E-M10) would be refused.
        if !commands.liveViewSizes.isEmpty, !commands.liveViewSizes.contains(camera.liveViewQuality) {
            camera.liveViewQuality = commands.liveViewSizes.contains("0640x0480") ? "0640x0480"
                : commands.liveViewSizes.first ?? camera.liveViewQuality
        }
    }

    func teardown() {}

    func powerOff() async {
        _ = try? await client.get("switch_cammode", [("mode", "play")])
        _ = try? await client.get("exec_pwoff")
    }

    // MARK: - Modes & live view

    func enterRecMode() async {
        camera.isSwitchingMode = true
        defer { camera.isSwitchingMode = false }
        do {
            // The PEN-F ignores a new live-view size while it's already in recording mode,
            // so go through playback first.
            if camera.mode != .play {
                _ = try await client.get("switch_cammode", [("mode", "play")])
                try? await Task.sleep(for: .milliseconds(300))
            }
            var params: [(String, String)] = [("mode", "rec")]
            if commands.liveViewSizes.isEmpty || commands.liveViewSizes.contains(camera.liveViewQuality) {
                params.append(("lvqty", camera.liveViewQuality))
            }
            _ = try await client.get("switch_cammode", params)
            camera.mode = .rec
            try? await Task.sleep(for: .milliseconds(400))
            await camera.refreshProperties()
            await camera.startLiveView()
        } catch {
            camera.report(error)
        }
    }

    func startLiveView() async {
        do {
            let port = String(format: "%05d", Int(camera.udpPort))
            let reply = try await client.get("exec_takemisc", [("com", "startliveview"), ("port", port)])
            debugLog("STARTLIVEVIEW reply: \(String(decoding: reply, as: UTF8.self))")
        } catch {
            camera.liveViewRunning = false
            camera.report(error)
        }
    }

    func stopLiveView() async {
        _ = try? await client.get("exec_takemisc", [("com", "stopliveview")])
    }

    // MARK: - Settings

    func refreshProperties() async {
        do {
            let data = try await client.get("get_camprop", [("com", "desc"), ("propname", "desclist")])
            camera.rawDescList = String(decoding: data, as: UTF8.self)
            if !loggedDescList {
                loggedDescList = true
                debugLog("DESCLIST\n\(camera.rawDescList)")
            }
            guard let root = MiniXML.parse(data) else { return }
            var result: [String: CameraProperty] = [:]
            for desc in root.descendants(named: "desc") {
                guard let name = desc.value("propname"), !name.isEmpty else { continue }
                let options = (desc.value("enum") ?? "").split(separator: " ").map(String.init)
                result[name] = CameraProperty(name: name,
                                              settable: desc.value("attribute") == "getset",
                                              value: desc.value("value") ?? "",
                                              options: options)
            }
            camera.properties = result
        } catch {
            camera.report(error)
        }
    }

    func setProperty(_ name: String, to value: String, reportErrors: Bool) async -> Bool {
        // Sent verbatim (the camera's parser is simple; shutter values contain a literal ").
        let body = "<?xml version=\"1.0\"?>\r\n<set>\r\n<value>\(value)</value>\r\n</set>\r\n"
        let previous = camera.properties[name]?.value
        camera.properties[name]?.value = value
        var ok = true
        do {
            _ = try await client.post("set_camprop", [("com", "set"), ("propname", name)], xml: body)
            if name == "takemode" { try? await Task.sleep(for: .milliseconds(300)) }
        } catch {
            ok = false
            if let previous { camera.properties[name]?.value = previous }
            if reportErrors { camera.report(error) }
        }
        // Changing one setting can lock/unlock others (e.g. aperture in P vs A).
        await refreshProperties()
        return ok
    }

    // MARK: - Focus & shooting

    func focus(at normalized: CGPoint) async {
        let pointValue = CameraModel.pointString(camera.pixelPoint(normalized))
        debugLog("tap: point=\(pointValue) lvqty=\(camera.liveViewQuality) frame=\(camera.liveFrame.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "none") focusmode=\(camera.properties["focusmode"]?.value ?? "?")")
        // assignafframe moves the AF target; takeready is a half-press (AF) at that point.
        do {
            let reply = try await client.get("exec_takemotion", [("com", "assignafframe"), ("point", pointValue)])
            debugLog("assignafframe reply: \(String(decoding: reply, as: UTF8.self))")
        } catch {
            debugLog("assignafframe failed: \(error)")
        }
        guard commands.supports("exec_takemotion", "takeready") else { return }
        do {
            let reply = try await client.get("exec_takemotion", [("com", "takeready"), ("point", pointValue)])
            debugLog("takeready reply: \(String(decoding: reply, as: UTF8.self))")
        } catch {
            camera.report(error)
        }
    }

    func releaseFocus() async {
        _ = try? await client.get("exec_takemotion", [("com", "releaseafframe")])
    }

    /// Bodies whose command list has exec_shutter but no starttake shoot with a full press + release.
    private var usesShutterPush: Bool {
        !commands.isEmpty && !commands.subcommands(of: "exec_takemotion").contains("starttake")
            && commands.subcommands(of: "exec_shutter").contains("1st2ndpush")
    }

    /// Press = start taking. In continuous drive the camera keeps shooting until release.
    func shutterPressed() async {
        if usesShutterPush {
            camera.isShooting = true
            defer { camera.isShooting = false }
            do {
                _ = try await client.get("exec_shutter", [("com", "1st2ndpush")], timeout: 60)
                _ = try await client.get("exec_shutter", [("com", "2nd1strelease")], timeout: 30)
                camera.shotCounter += 1
                Task { await camera.fetchLastShot() }
            } catch {
                camera.report(error)
            }
            return
        }
        camera.isShooting = true
        var params: [(String, String)] = [("com", "starttake")]
        if let focusPoint = camera.focusPoint {
            params.append(("point", CameraModel.pointString(camera.pixelPoint(focusPoint))))
        }
        // Long exposures: the reply can take the exposure time plus the same again for noise reduction.
        let seconds = PropertyFormat.seconds(fromShutter: camera.properties["shutspeedvalue"]?.value ?? "") ?? 0
        if seconds >= 1 {
            camera.exposureStartedAt = Date()
            camera.exposureDuration = seconds
        }
        defer {
            camera.exposureStartedAt = nil
            camera.exposureDuration = nil
        }
        do {
            let reply = try await client.get("exec_takemotion", params, timeout: max(60, seconds * 2 + 30))
            debugLog("starttake reply: \(String(decoding: reply, as: UTF8.self))")
            camera.shotCounter += 1
            Task { await camera.fetchLastShot() }
        } catch {
            camera.isShooting = false
            camera.report(error)
            return
        }
        if !camera.isContinuousDrive { camera.isShooting = false }
    }

    func shutterReleased() async {
        guard camera.isShooting, camera.isContinuousDrive else { return }
        _ = try? await client.getUrgent("exec_takemotion", [("com", "stoptake")])
        camera.isShooting = false
    }

    func toggleOpenExposure() async {
        if camera.isShooting {
            _ = try? await client.getUrgent("exec_takemotion", [("com", "stoptake")])
            camera.isShooting = false
            camera.exposureStartedAt = nil
            camera.shotCounter += 1
            // Give the camera a moment to write the composite, then grab the review image.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await camera.fetchLastShot()
            }
            return
        }
        camera.isShooting = true
        camera.exposureStartedAt = Date()
        camera.exposureDuration = nil
        // Don't await here: the camera may hold this reply until the exposure is stopped.
        let client = client
        Task {
            do {
                let reply = try await client.get("exec_takemotion", [("com", "starttake")], timeout: 4 * 3600)
                debugLog("starttake (open-ended) reply: \(String(decoding: reply, as: UTF8.self))")
            } catch {
                camera.isShooting = false
                camera.exposureStartedAt = nil
                camera.report(error)
            }
        }
    }

    func toggleMovie() async {
        if camera.isRecordingMovie {
            _ = try? await client.getUrgent("exec_takemotion", [("com", "stopmovietake")])
            camera.isRecordingMovie = false
            camera.movieStartedAt = nil
            camera.shotCounter += 1
        } else {
            do {
                _ = try await client.get("exec_takemotion", [("com", "startmovietake")], timeout: 15)
                camera.isRecordingMovie = true
                camera.movieStartedAt = Date()
            } catch {
                camera.report(error)
            }
        }
    }

    /// Grabs a preview of the capture that just finished, for the review thumbnail.
    /// The PEN-F lists both `getrecview` and `getlastjpg`; try the first, fall back to the second.
    func fetchLastShot() async {
        for command in ["getrecview", "getlastjpg"] where commands.supports("exec_takemisc", command) {
            guard let data = try? await client.get("exec_takemisc", [("com", command)], timeout: 8),
                  let image = UIImage(data: data) else {
                debugLog("\(command): no image")
                continue
            }
            debugLog("\(command): \(Int(image.size.width))×\(Int(image.size.height))")
            camera.lastShot = image.preparingForDisplay() ?? image
            return
        }
    }

    /// Sets the camera's clock and time zone from the phone (needs playback mode, so live view blinks).
    func syncClock() async -> Bool {
        let wasLive = camera.liveViewRunning
        await camera.stopLiveView()
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyyMMdd'T'HHmmss"
        let offset = TimeZone.current.secondsFromGMT()
        let diff = String(format: "%@%02d%02d", offset >= 0 ? "%2B" : "-", abs(offset) / 3600, abs(offset) % 3600 / 60)
        var ok = false
        do {
            _ = try await client.get("switch_cammode", [("mode", "play")])
            camera.mode = .play
            _ = try await client.get("set_utctimediff", [("utctime", utc.string(from: Date())), ("diff", diff)])
            ok = true
        } catch {
            camera.report(error)
        }
        if wasLive || camera.mode == .play { await camera.enterRecMode() }
        return ok
    }

    // MARK: - Card

    func openGallery() async {
        do {
            if camera.mode != .play {
                _ = try await client.get("switch_cammode", [("mode", "play")])
                camera.mode = .play
                try? await Task.sleep(for: .milliseconds(300))
            }
            var found: [CameraImage] = []
            var folders: [CardFolder] = []
            for folder in try await listDirectory("/DCIM") where folder.isDirectory {
                var files = try await listDirectory(folder.path).filter { !$0.isDirectory }
                // The PEN-F's photo list skips another camera's folder; its built-in web page may not.
                if files.isEmpty { files = await webListedFiles(folder) }
                found += files
                folders.append(CardFolder(path: folder.path, name: folder.name, count: files.count))
            }
            camera.cardFolders = folders.sorted { $0.name > $1.name }
            camera.images = found.sorted { ($0.date, $0.name) > ($1.date, $1.name) }
        } catch {
            camera.galleryError = CameraModel.describe(error, host: camera.connectionHost)
        }
    }

    /// Reads the camera's built-in web page for a folder and pulls out any file names it links to.
    private func webListedFiles(_ folder: CameraImage) async -> [CameraImage] {
        guard let data = try? await client.download(path: folder.path + "/") else { return [] }
        let html = String(decoding: data, as: UTF8.self)
        debugLog("WEBLIST \(folder.path) (\(data.count) bytes)\n\(html.prefix(6000))")
        let pattern = #"[A-Za-z0-9_\-]+\.(?:jpe?g|rw2|orf|mp4|mov|cr2|cr3|nef|arw|raf|heic|dng)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        var names: [String] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let name = String(html[range])
            if !names.contains(name) { names.append(name) }
        }
        debugLog("WEBLIST \(folder.path): \(names.count) files \(names.prefix(10))")
        return names.map { CameraImage(directory: folder.path, name: $0, size: 0, attributes: 0, date: .distantPast) }
    }

    private func listDirectory(_ directory: String) async throws -> [CameraImage] {
        do {
            let data = try await client.get("get_imglist", [("DIR", directory)])
            return ImageListParser.parse(String(decoding: data, as: UTF8.self))
        } catch let error as CameraHTTPError where error.status == 404 {
            return [] // empty folder
        }
    }

    func thumbnail(for image: CameraImage) async -> UIImage? {
        guard let data = try? await client.get("get_thumbnail", [("DIR", image.path)], log: false) else { return nil }
        return UIImage(data: data)
    }

    func preview(for image: CameraImage) async throws -> UIImage {
        if image.fileExtension == "JPG",
           let data = try? await client.get("get_resizeimg", [("DIR", image.path), ("size", "1600")]),
           let resized = UIImage(data: data) {
            return resized
        }
        if let data = try? await client.get("get_thumbnail", [("DIR", image.path)]), let thumb = UIImage(data: data) {
            return thumb
        }
        // Files the camera doesn't index (another camera's) have no preview: fetch the file itself.
        guard ["JPG", "JPEG"].contains(image.fileExtension) else {
            throw CameraError("The camera has no preview for this \(image.fileExtension) file. Save it to Photos to view it.")
        }
        let data = try await client.download(path: image.path)
        guard let full = UIImage(data: data) else { throw CameraError("Couldn't decode the photo.") }
        return full.preparingThumbnail(of: CGSize(width: 2000, height: 2000)) ?? full
    }

    func downloadOriginal(_ image: CameraImage) async throws -> Data {
        try await client.download(path: image.path)
    }
}

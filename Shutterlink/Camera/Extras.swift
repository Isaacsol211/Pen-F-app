import Foundation
import Photos

// MARK: - Bracketing types

enum BracketTarget: String, CaseIterable, Identifiable {
    /// Shutter speed in M, exposure compensation otherwise.
    case auto
    case ev, shutter

    var id: String { rawValue }
    var title: String { self == .ev ? "EV" : rawValue.capitalized }
}

struct BracketPlan: Equatable {
    var frames = 3
    /// Step between frames, in thirds of a stop (1 = ⅓ EV … 6 = 2 EV).
    var thirds = 3
    var target: BracketTarget = .auto
}

struct BracketState: Equatable {
    var running = false
    var done = 0
    var total = 0
    /// What the frame being shot is set to, e.g. "−1 EV · 1/500".
    var label: String?
    /// A focus stack rather than an exposure bracket.
    var isFocusStack = false
}

/// The settings a bracket will shoot, worked out before it starts.
struct BracketSet: Equatable {
    let property: String
    let values: [String]
    let offsets: [Int]
    /// Some frames hit the end of the camera's range and repeat a value.
    let clamped: Bool
}

struct RawImportProgress: Equatable {
    var done = 0
    var total = 0
    var current: String?
    /// Set when finished: what happened, for the card browser to show.
    var message: String?
}

extension CameraModel {
    // MARK: - Shortcuts / Action button

    /// From the "Connect to Camera" shortcut: connect, giving iOS up to 30 s to join the camera's
    /// Wi-Fi (it rejoins a network it knows by itself once the camera's Wi-Fi is on).
    func connectFromShortcut() {
        switch phase {
        case .connected:
            showToast("Connected to \(cameraName ?? "the camera")")
        case .connecting:
            break
        case .disconnected:
            // The camera used last, joining its Wi-Fi first when Shutterlink joined it before.
            if let saved = savedCameras.first, saved.ssid != nil, saved.brand == brand {
                Task { await connect(to: saved, waitingUntil: Date().addingTimeInterval(30)) }
            } else {
                Task { await connect(waitingUntil: Date().addingTimeInterval(30)) }
            }
        }
    }

    // MARK: - Timed bulb

    /// Ends the open-ended exposure that just started after `seconds`, showing a countdown meanwhile.
    func scheduleOpenExposureStop(after seconds: Double) {
        exposureDuration = seconds
        let started = exposureStartedAt
        openExposureStopTask?.cancel()
        openExposureStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.isShooting, self.exposureStartedAt == started else { return }
            // Clear it first: toggleOpenExposure cancels this task, which would cancel the stop request.
            self.openExposureStopTask = nil
            await self.toggleOpenExposure()
        }
    }

    static func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let m = total / 60, s = total % 60
        return s == 0 ? "\(m) min" : String(format: "%d:%02d", m, s)
    }

    // MARK: - Exposure bracketing

    /// What a plan would shoot, or why it can't run with the current settings.
    func bracketSet(_ plan: BracketPlan) -> Result<BracketSet, CameraError> {
        // The setting a bracket varies: shutter speed in M, exposure compensation in P, A and S.
        let inM = properties["takemode"]?.value.uppercased() == "M"
        var name = switch plan.target {
        case .ev: "expcomp"
        case .shutter: "shutspeedvalue"
        case .auto: inM ? "shutspeedvalue" : "expcomp"
        }
        // Automatic: when that one can't be changed (a compact with a fixed shutter), use the other.
        if plan.target == .auto, properties[name]?.settable != true {
            let other = name == "expcomp" ? "shutspeedvalue" : "expcomp"
            if properties[other]?.settable == true { name = other }
        }
        let isEV = name == "expcomp"
        guard let property = properties[name] else {
            return .failure(CameraError("This camera doesn't offer \(isEV ? "exposure compensation" : "shutter speed") over Wi-Fi."))
        }
        guard property.settable else {
            let mode = PropertyFormat.display("takemode", properties["takemode"]?.value ?? "")
            let why = switch (isEV, inM || mode.isEmpty) {
            case (true, true): "Exposure compensation can't be changed from the phone here. Bracket the shutter instead."
            case (true, false): "Exposure compensation is locked in \(mode). Use P, A or S, or bracket the shutter in M."
            case (false, true): "This camera doesn't let the phone change the shutter speed. Bracket EV instead."
            case (false, false): "The shutter speed is locked in \(mode). Use S or M, or bracket EV instead."
            }
            return .failure(CameraError(why))
        }
        // In thirds of a stop, in the usual camera order: 0, −1, +1, −2, +2…
        let offsets = (0..<max(plan.frames, 1)).map { i in (i + 1) / 2 * plan.thirds * (i.isMultiple(of: 2) ? 1 : -1) }
        // Both in stops: EV as it is, the shutter as log2 of its length (a positive offset, more light, is longer).
        let stops: (String) -> Double? = isEV ? { Double($0) } : { PropertyFormat.seconds(fromShutter: $0).map(log2) }
        let options = property.options.compactMap { option in stops(option).map { (option, $0) } }
        guard let base = stops(property.value), !options.isEmpty else {
            return .failure(CameraError(isEV ? "Couldn't read the current exposure compensation."
                                             : "Bracketing needs a timed shutter speed, not Bulb or Live modes."))
        }
        var values: [String] = []
        var clamped = false
        for offset in offsets {
            let target = base + Double(offset) / 3
            guard let best = options.min(by: { abs($0.1 - target) < abs($1.1 - target) }) else { continue }
            if abs(best.1 - target) > 0.17 { clamped = true }
            values.append(best.0)
        }
        return .success(BracketSet(property: name, values: values, offsets: offsets, clamped: clamped))
    }

    static func offsetLabel(_ thirds: Int) -> String {
        if thirds == 0 { return "±0" }
        let sign = thirds > 0 ? "+" : "−"
        let whole = abs(thirds) / 3, rest = abs(thirds) % 3
        let fraction = rest == 0 ? "" : (rest == 1 ? "⅓" : "⅔")
        return "\(sign)\(whole > 0 ? "\(whole)" : "")\(fraction)"
    }

    var canBracket: Bool {
        mode == .rec && !bracket.running && !interval.running && !isOpenEndedShutter && !isMovieMode && !isShooting
    }

    /// Shoots the bracket, then puts the setting back the way it was.
    func startBracket(_ plan: BracketPlan) {
        guard canBracket else { return }
        let set: BracketSet
        do { set = try bracketSet(plan).get() } catch {
            lastError = error.localizedDescription
            return
        }
        let name = set.property
        let original = properties[name]?.value
        bracket = BracketState(running: true, done: 0, total: set.values.count)
        bracketTask = Task { [weak self] in
            guard let self else { return }
            for (index, value) in set.values.enumerated() {
                if Task.isCancelled { break }
                let offset = "\(Self.offsetLabel(set.offsets[index])) EV"
                self.bracket.label = name == "expcomp" ? offset : "\(offset) · \(PropertyFormat.display(name, value))"
                if self.properties[name]?.value != value {
                    guard await self.setProperty(name, to: value) else { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                if Task.isCancelled { break }
                await self.shoot()
                while self.isShooting, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
                self.bracket.done = index + 1
            }
            let finished = self.bracket.done
            // Put the setting back, even after Cancel (a new task, so it isn't cancelled too).
            if let original, self.phase == .connected, self.properties[name]?.value != original {
                await Task { _ = await self.setProperty(name, to: original, reportErrors: false) }.value
            }
            self.bracket = BracketState()
            self.bracketTask = nil
            if finished > 0 { self.showToast("Bracket: \(finished) of \(set.values.count) frames") }
        }
    }

    // MARK: - Focus stacking

    /// Where the user puts focus before starting, and what the lens switch has to be on.
    var focusStackSetup: String {
        switch brand {
        case .panasonic:
            "Set the camera to MF and focus on the nearest thing you want sharp. Each frame moves focus a step farther away."
        case .nikon, .canon:
            // The camera drives the lens's AF motor, so the lens has to stay on AF.
            "Leave the lens on AF, focus on the nearest thing you want sharp, and keep live view on. Each frame moves focus a step farther away."
        case .olympus, .sony:
            "Focus on the nearest thing you want sharp. Each frame moves focus a step farther away."
        }
    }

    /// Where to look instead, on cameras the app can't step the focus of.
    var focusStackUnavailable: String {
        switch brand {
        case .olympus:
            "Olympus and OM System cameras have no Wi-Fi command to move focus. Use Focus BKT, or Focus Stacking where the body has it, in the camera's Bracketing menu, then press the shutter here."
        case .sony:
            "Sony's Camera Remote API has no command to move focus. Use the camera's own Focus Bracket where it has one."
        case .panasonic, .nikon, .canon:
            "This camera doesn't offer a Wi-Fi command to move focus. Use its own focus bracketing from the camera's menu."
        }
    }

    var canFocusStack: Bool { capabilities.focusDrive && canBracket }

    /// Shoots a frame, steps focus farther, and repeats until the frame count or infinity. Uses the
    /// bracket's state, so its progress ring, Watch read-out and Cancel work for it too.
    func startFocusStack(frames: Int, step: FocusStepSize) {
        guard canFocusStack, let driver, frames > 0 else { return }
        bracket = BracketState(running: true, done: 0, total: frames, isFocusStack: true)
        bracketTask = Task { [weak self] in
            guard let self else { return }
            var reachedEnd = false
            var failure: String?
            for index in 0..<frames {
                if Task.isCancelled { break }
                self.bracket.label = "Focus \(index + 1) of \(frames)"
                let before = self.shotCounter
                await self.shoot()
                while self.isShooting, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
                guard self.shotCounter > before else {
                    failure = self.lastError ?? "The camera didn't take frame \(index + 1)."
                    break
                }
                self.bracket.done = index + 1
                if index == frames - 1 || Task.isCancelled { break }
                do {
                    if try await driver.driveFocus(farther: true, step: step) == .endOfTravel {
                        reachedEnd = true
                        break
                    }
                } catch {
                    failure = error.localizedDescription
                    break
                }
                // Let the lens settle before the next frame.
                try? await Task.sleep(for: .milliseconds(300))
            }
            let shot = self.bracket.done
            self.bracket = BracketState()
            self.bracketTask = nil
            if let failure {
                self.lastError = shot > 0 ? "Focus stack stopped after \(shot) frames: \(failure)" : failure
            } else if shot > 0 {
                self.showToast(reachedEnd ? "Focus stack: \(shot) frames, reached infinity" : "Focus stack: \(shot) of \(frames) frames")
            }
        }
    }

    func cancelBracket() {
        bracketTask?.cancel()
        if phase != .connected {
            bracketTask = nil
            bracket = BracketState()
        }
    }

    // MARK: - Smart import: stars and RAW download

    static let rawExtensions: Set<String> = ["ORF", "RW2", "DNG", "NEF", "NRW", "CR3", "CR2", "ARW", "RAF"]

    private static func starKey(_ image: CameraImage) -> String { "\(image.name)|\(image.size)" }

    func isStarred(_ image: CameraImage) -> Bool { starred.contains(Self.starKey(image)) }

    func toggleStar(_ image: CameraImage) {
        let key = Self.starKey(image)
        if starred.contains(key) { starred.remove(key) } else { starred.insert(key) }
    }

    /// The RAW file shot together with this JPEG (same name, same folder), or the file itself if it's a RAW.
    func rawCompanion(of image: CameraImage) -> CameraImage? {
        if Self.rawExtensions.contains(image.fileExtension) { return image }
        let base = (image.name as NSString).deletingPathExtension
        return images.first {
            $0.directory == image.directory && Self.rawExtensions.contains($0.fileExtension)
                && ($0.name as NSString).deletingPathExtension == base
        }
    }

    /// Fetches the RAW of every starred photo and adds it to Photos (geotagged when that's on).
    /// If Photos won't take a file, it goes to Files ▸ On My iPhone ▸ Shutterlink ▸ RAW instead.
    /// With `folder` (a folder picked in the Mac's open panel) the files go straight there instead,
    /// as they came off the card.
    func downloadStarredRAWs(to folder: URL? = nil) {
        guard rawImportTask == nil else { return }
        var raws: [CameraImage] = []
        var withoutRAW = 0
        for image in images where isStarred(image) && !image.isVideo {
            if let raw = rawCompanion(of: image) {
                if !raws.contains(raw) { raws.append(raw) }
            } else {
                withoutRAW += 1
            }
        }
        guard !raws.isEmpty else {
            rawImport = RawImportProgress(message: withoutRAW > 0
                ? "None of the starred photos has a RAW file next to it. Shoot RAW+JPEG to use this."
                : "Star some photos first: \(Platform.isMac ? "right-click" : "tap and hold") a photo, or use the star when viewing it.")
            return
        }
        rawImport = RawImportProgress(done: 0, total: raws.count)
        rawImportTask = Task { [weak self] in
            guard let self else { return }
            // A folder from the open panel is only ours while we hold its security scope.
            let scoped = folder?.startAccessingSecurityScopedResource() ?? false
            defer { if scoped { folder?.stopAccessingSecurityScopedResource() } }
            var photosAllowed = false
            if folder == nil {
                let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                photosAllowed = access == .authorized || access == .limited
            }
            var toPhotos = 0, toFiles = 0, toFolder = 0, failed = 0, tagged = 0
            for raw in raws {
                if Task.isCancelled { break }
                self.rawImport?.current = raw.name
                do {
                    let data = try await self.downloadOriginal(raw)
                    if let folder {
                        try Self.save(data, name: raw.name, in: folder)
                        toFolder += 1
                    } else if photosAllowed, let didTag = try? await self.addToPhotos(data, for: raw) {
                        toPhotos += 1
                        if didTag { tagged += 1 }
                    } else {
                        try Self.saveToFiles(data, name: raw.name)
                        toFiles += 1
                    }
                } catch {
                    debugLog("RAW download \(raw.name): \(error.localizedDescription)")
                    failed += 1
                }
                self.rawImport?.done += 1
            }
            var parts: [String] = []
            if toPhotos > 0 { parts.append("\(toPhotos) to Photos\(tagged > 0 ? " (\(tagged) geotagged)" : "")") }
            if toFiles > 0 { parts.append("\(toFiles) to Files ▸ Shutterlink ▸ RAW") }
            if toFolder > 0, let folder { parts.append("\(toFolder) to \(folder.lastPathComponent)") }
            var message = parts.isEmpty ? "No RAW files were saved." : "Saved \(parts.joined(separator: ", "))."
            if failed > 0 { message += " \(failed) couldn't be downloaded." }
            if withoutRAW > 0 { message += " \(withoutRAW) starred photo\(withoutRAW == 1 ? " has" : "s have") no RAW." }
            if Task.isCancelled { message = "Stopped. " + message }
            self.rawImport = RawImportProgress(done: toPhotos + toFiles + toFolder, total: raws.count, message: message)
            self.rawImportTask = nil
        }
    }

    func cancelRawImport() {
        rawImportTask?.cancel()
    }

    /// Writes into `folder` under the card's file name, adding " 2", " 3"… rather than replacing a
    /// different file of the same name (cameras restart their numbering).
    static func save(_ data: Data, name: String, in folder: URL) throws {
        let fm = FileManager.default
        var target = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: target.path) {
            // The same file saved before: nothing to do.
            if let size = (try? fm.attributesOfItem(atPath: target.path))?[.size] as? Int, size == data.count { return }
            target = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        try data.write(to: target, options: .atomic)
    }

    /// Writes into the app's Documents/RAW folder, which the Files app shows.
    static func saveToFiles(_ data: Data, name: String) throws {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RAW", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}

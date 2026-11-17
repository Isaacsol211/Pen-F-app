import UIKit
import WatchConnectivity

/// The iPhone end of the Apple Watch remote. The iPhone stays connected to the camera; this sends
/// the Watch what the camera is doing, carries out its button presses, and while the Watch app is
/// open streams small live-view frames (~3 per second) to it.
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private weak var camera: CameraModel?
    private var lastSent: WatchStatus?
    private var lastSentAt = Date.distantPast
    private var lastContextAt = Date.distantPast
    private var previewOn = false
    private var lastPreviewAt = Date.distantPast
    private var loop: Task<Void, Never>?
    private var selfTimer: Task<Void, Never>?
    private var selfTimerEnds: Date?
    private var message: (text: String, until: Date)?

    func start(camera: CameraModel) {
        guard WCSession.isSupported(), loop == nil else { return }
        self.camera = camera
        let session = WCSession.default
        session.delegate = self
        session.activate()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                self?.tick()
            }
        }
    }

    private var session: WCSession { WCSession.default }

    private var watchAvailable: Bool {
        session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    // MARK: - Sending

    private func tick() {
        guard watchAvailable, let camera else { return }
        let status = makeStatus(camera)
        let now = Date()
        // Send changes straight away, and a heartbeat every few seconds so the Watch knows the
        // iPhone is still there.
        if status != lastSent || now.timeIntervalSince(lastSentAt) > 4 {
            send(status)
            lastSent = status
            lastSentAt = now
        }
        if previewOn, session.isReachable, now.timeIntervalSince(lastPreviewAt) > 0.33,
           camera.phase == .connected, let frame = camera.liveFrame, let data = Self.smallJPEG(frame) {
            lastPreviewAt = now
            session.sendMessageData(data, replyHandler: nil) { error in
                debugLog("watch preview: \(error.localizedDescription)")
            }
        }
        if !session.isReachable { previewOn = false }
    }

    private func send(_ status: WatchStatus) {
        guard let data = status.encoded() else { return }
        if session.isReachable {
            session.sendMessage([WatchKey.status: data], replyHandler: nil) { error in
                debugLog("watch status: \(error.localizedDescription)")
            }
        }
        // The application context is what the Watch app sees when it next opens.
        if Date().timeIntervalSince(lastContextAt) > 2 || status.connected != lastSent?.connected {
            lastContextAt = Date()
            try? session.updateApplicationContext([WatchKey.status: data])
        }
    }

    private func makeStatus(_ camera: CameraModel) -> WatchStatus {
        var s = WatchStatus()
        s.connected = camera.phase == .connected
        guard s.connected else {
            s.message = camera.phase == .connecting ? "Connecting…" : nil
            return s
        }
        s.cameraName = camera.cameraName
        s.battery = camera.liveInfo.battery
        s.shotsLeft = camera.liveInfo.shotsRemaining
        func shown(_ name: String) -> String? {
            camera.properties[name] == nil ? nil : camera.stripValue(name)
        }
        s.aperture = shown("focalvalue").map { $0.hasPrefix("F") ? $0 : "F\($0)" }
        s.shutter = shown("shutspeedvalue")
        s.iso = shown("isospeedvalue")
        s.ev = shown("expcomp")
        if let ev = camera.properties["expcomp"] {
            s.evOptions = ev.options
            s.evValue = ev.value
            s.evSettable = ev.settable && !camera.isBusyExposing
        }
        s.movieMode = camera.isMovieMode
        s.recording = camera.isRecordingMovie
        s.movieStart = camera.movieStartedAt
        s.openEnded = camera.isOpenEndedShutter
        s.shooting = camera.isShooting
        s.exposureStart = camera.exposureStartedAt
        s.exposureDuration = camera.exposureDuration
        s.selfTimerEnds = selfTimerEnds
        if camera.interval.running {
            s.sequence = "Interval \(camera.interval.done)" + (camera.interval.total > 0 ? "/\(camera.interval.total)" : "")
        } else if camera.bracket.running {
            s.sequence = "Bracket \(camera.bracket.done)/\(camera.bracket.total)"
        }
        s.shots = camera.shotCounter
        s.canShoot = camera.mode == .rec && !camera.isSwitchingMode && !camera.bracket.running
            && !camera.interval.running && !camera.galleryLoading
        if let message, message.until > Date() {
            s.message = message.text
        } else if camera.mode != .rec {
            s.message = "The iPhone is browsing the card"
        } else if !camera.liveViewRunning || camera.liveFrame == nil {
            s.message = "Keep PEN-F Remote open on the iPhone"
        }
        return s
    }

    /// About 200×150, small enough for a few frames a second over the Watch link.
    private static func smallJPEG(_ image: UIImage) -> Data? {
        let width: CGFloat = 200
        let size = CGSize(width: width, height: (width * image.size.height / max(image.size.width, 1)).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.45)
    }

    // MARK: - Commands from the Watch

    private func handle(_ command: WatchCommand, delay: Double, value: String?, on: Bool) {
        guard let camera else { return }
        if command != .preview && command != .hello { debugLog("watch: \(command.rawValue) delay=\(delay) value=\(value ?? "-")") }
        switch command {
        case .hello:
            lastSent = nil   // send everything again
        case .preview:
            previewOn = on
            lastPreviewAt = .distantPast
        case .cancel:
            selfTimer?.cancel()
            selfTimer = nil
            selfTimerEnds = nil
            camera.stopInterval()
            camera.cancelBracket()
        case .setEV:
            guard let value, camera.properties["expcomp"]?.settable == true else { return }
            Task { _ = await camera.setProperty("expcomp", to: value, reportErrors: true) }
        case .shutter:
            guard camera.phase == .connected else {
                flash("The iPhone isn't connected to the camera")
                return
            }
            // A press while an exposure or video runs stops it, without a self-timer.
            let busy = camera.isRecordingMovie || (camera.isShooting && camera.isOpenEndedShutter)
            if delay > 0, !busy {
                selfTimer?.cancel()
                selfTimerEnds = Date().addingTimeInterval(delay)
                selfTimer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard let self, !Task.isCancelled else { return }
                    self.selfTimerEnds = nil
                    self.selfTimer = nil
                    await self.press(camera)
                }
            } else {
                Task { await press(camera) }
            }
        }
    }

    private func press(_ camera: CameraModel) async {
        guard camera.mode == .rec, !camera.isSwitchingMode else {
            flash("The camera isn't ready to shoot")
            return
        }
        if camera.isMovieMode {
            await camera.toggleMovie()
        } else if camera.isOpenEndedShutter {
            await camera.toggleOpenExposure()
        } else if !camera.isShooting {
            await camera.shutterPressed()
            await camera.shutterReleased()
        }
    }

    private func flash(_ text: String) {
        message = (text, Date().addingTimeInterval(3))
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error { debugLog("watch session: \(error.localizedDescription)") }
        Task { @MainActor in self.lastSent = nil }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another Watch: start talking to the new one.
        WCSession.default.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            if reachable { self.lastSent = nil } else { self.previewOn = false }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.lastSent = nil }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        Task { @MainActor in
            let data = self.camera.map(self.makeStatus)?.encoded() ?? WatchStatus().encoded()
            replyHandler(data.map { [WatchKey.status: $0] } ?? [:])
        }
    }

    private nonisolated func receive(_ message: [String: Any]) {
        guard let raw = message[WatchKey.command] as? String, let command = WatchCommand(rawValue: raw) else { return }
        let delay = message[WatchKey.delay] as? Double ?? 0
        let value = message[WatchKey.value] as? String
        let on = message[WatchKey.on] as? Bool ?? false
        Task { @MainActor in self.handle(command, delay: delay, value: value, on: on) }
    }
}

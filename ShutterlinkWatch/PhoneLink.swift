import SwiftUI
import WatchConnectivity
import WatchKit

/// The Watch end of the remote: talks to Shutterlink on the paired iPhone.
@MainActor
@Observable
final class PhoneLink: NSObject, WCSessionDelegate {
    var status = WatchStatus()
    /// Small live-view frame from the iPhone, while the preview is on.
    var preview: UIImage?
    var reachable = false
    /// When the last status arrived; old news means the iPhone app isn't running.
    var updatedAt: Date?
    /// Nothing heard from the iPhone for a while (it sends a heartbeat every few seconds).
    var stale = true

    /// The iPhone app is running and connected to the camera: show the remote.
    var phoneActive: Bool { status.connected && !stale }

    @ObservationIgnored private var watchdog: Task<Void, Never>?

    @ObservationIgnored private var wantPreview = false
    @ObservationIgnored private var previewAt = Date.distantPast

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let old = self.updatedAt.map { Date().timeIntervalSince($0) > 9 } ?? true
                if old != self.stale {
                    self.stale = old
                    if old { self.preview = nil }
                }
            }
        }
    }

    // MARK: - Commands

    func shutter(delay: Int) {
        send(.shutter, [WatchKey.delay: Double(delay)])
        WKInterfaceDevice.current().play(.click)
    }

    func cancel() {
        send(.cancel)
        WKInterfaceDevice.current().play(.stop)
    }

    func setEV(_ value: String) {
        send(.setEV, [WatchKey.value: value])
    }

    /// Live view costs battery on both devices, so it only runs while the Watch app is on screen.
    func setPreview(_ on: Bool) {
        wantPreview = on
        if !on { preview = nil }
        send(.preview, [WatchKey.on: on])
    }

    private func send(_ command: WatchCommand, _ extra: [String: Any] = [:]) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            print("[Shutterlink watch] \(command.rawValue) not sent: iPhone not reachable")
            return
        }
        var message = extra
        message[WatchKey.command] = command.rawValue
        session.sendMessage(message, replyHandler: { [weak self] reply in
            let status = WatchStatus.decode(reply[WatchKey.status] as? Data)
            Task { @MainActor in if let status { self?.apply(status) } }
        }, errorHandler: { error in
            print("[Shutterlink watch] \(command.rawValue): \(error.localizedDescription)")
        })
    }

    /// `fresh` is false for the status saved from the iPhone's last run: show it, but don't treat
    /// the iPhone as live until it answers.
    private func apply(_ new: WatchStatus, fresh: Bool = true) {
        // A tap on the wrist for every photo taken, and when an exposure or video starts or ends.
        if new.shots > status.shots, status.connected {
            WKInterfaceDevice.current().play(.success)
        } else if new.recording != status.recording || (new.openEnded && new.shooting != status.shooting) {
            WKInterfaceDevice.current().play(new.recording || new.shooting ? .start : .stop)
        }
        status = new
        guard fresh else { return }
        updatedAt = Date()
        stale = false
        if !new.connected { preview = nil }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = WatchStatus.decode(session.receivedApplicationContext[WatchKey.status] as? Data)
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            if let context { self.apply(context, fresh: false) }
            self.send(.hello)
            if self.wantPreview { self.setPreview(true) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            if reachable {
                self.send(.hello)
                if self.wantPreview { self.setPreview(true) }
            } else {
                self.preview = nil
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let status = WatchStatus.decode(message[WatchKey.status] as? Data)
        Task { @MainActor in if let status { self.apply(status) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let status = WatchStatus.decode(context[WatchKey.status] as? Data)
        Task { @MainActor in if let status { self.apply(status) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData data: Data) {
        guard let image = UIImage(data: data) else { return }
        Task { @MainActor in
            if self.wantPreview { self.preview = image }
        }
    }
}

import SwiftUI
import UIKit
import CoreHaptics
import AVFoundation

/// One entry point for haptics and sound (docs/design/04-motion-sound-haptics.md §4). Views never call a
/// feedback generator or an audio player: they say what happened, `Feedback.play(.shutter)`, and this
/// looks up the haptic and the sound, checks More › Haptics, Sounds and Quiet on tripod, and plays them.
///
/// Every moment also shows on screen; sound is never the only signal.
@MainActor
enum Feedback {
    enum Moment: Equatable {
        /// The dial passed a third stop (or any value of a dial without stops).
        case dialTick
        /// The dial entered a full stop, or 0 EV: a firmer click.
        case dialStop
        /// A chip, toggle or segment changed.
        case select
        /// The shutter half press, on touch: the hand gets its answer before the camera's.
        case press
        /// The camera locked focus (AF confirmed, or the loupe's focus peak reached).
        case focusLock
        /// The shutter released, on touch.
        case shutter
        /// The camera refused or failed a request.
        case refused
        /// A Bulb / Live exposure, a long exposure, a movie or a series started.
        case exposureStart
        /// It stopped.
        case exposureStop
        /// An interval series, bracket or focus stack finished all its frames.
        case seriesComplete
        /// Connected to the camera.
        case connected
        /// Lost contact with the camera.
        case lostContact
    }

    /// Settings keys (More › Feedback); the defaults are registered in `registerDefaults()`.
    enum Key {
        static let haptics = "feedback.haptics"
        static let sounds = "feedback.sounds"
        static let quietOnTripod = "feedback.quietOnTripod"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [Key.haptics: true, Key.sounds: false, Key.quietOnTripod: true])
    }

    /// Set by `FeedbackObserver` while the shutter is open (Bulb, a long exposure, a series frame): with
    /// Quiet on tripod on, nothing plays then, so the phone on the tripod doesn't shake the picture.
    static var exposureOpen = false

    static func play(_ m: Moment) {
        let d = UserDefaults.standard
        if exposureOpen, d.bool(forKey: Key.quietOnTripod) { return }
        if d.bool(forKey: Key.haptics) { Haptics.shared.play(m) }
        if d.bool(forKey: Key.sounds) { Sound.shared.play(m) }
    }

    /// Gets the Taptic Engine ready for a gesture that is about to give feedback (the dial, the shutter).
    static func prepare() { Haptics.shared.prepare() }
}

// MARK: - Haptics

@MainActor
private final class Haptics {
    static let shared = Haptics()

    private let selection = UISelectionFeedbackGenerator()
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let notice = UINotificationFeedbackGenerator()
    private var engine: CHHapticEngine?
    private var engineFailed = false
    private var lastTick = Date.distantPast

    func prepare() { selection.prepare(); rigid.prepare(); light.prepare() }

    func play(_ m: Feedback.Moment) {
        switch m {
        case .dialTick, .dialStop:
            // At most one per 60 ms, so a fast drag doesn't buzz; a full stop gets the firmer click.
            guard Date.now.timeIntervalSince(lastTick) > 0.06 else { return }
            lastTick = .now
            if m == .dialStop { rigid.impactOccurred(intensity: 0.85) } else { selection.selectionChanged() }
            selection.prepare()
        case .select: selection.selectionChanged()
        case .press: light.impactOccurred(intensity: 0.5)
        case .focusLock: light.impactOccurred(intensity: 0.8)
        case .refused: notice.notificationOccurred(.error)
        case .lostContact: notice.notificationOccurred(.warning)
        case .seriesComplete, .connected: notice.notificationOccurred(.success)
        case .shutter:
            // The curtain closes (1.0, 0.9) and opens again (0.6, 0.7) 45 ms later.
            pattern([(0, 1.0, 0.9), (0.045, 0.6, 0.7)]) { [rigid] in
                rigid.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { rigid.impactOccurred(intensity: 0.6) }
            }
        case .exposureStart:
            // Rising: soft then firm.
            pattern([(0, 0.4, 0.3), (0.08, 0.9, 0.6)]) { [light, rigid] in
                light.impactOccurred(intensity: 0.5)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { rigid.impactOccurred(intensity: 0.9) }
            }
        case .exposureStop:
            // Falling: firm then soft.
            pattern([(0, 0.9, 0.6), (0.08, 0.4, 0.3)]) { [light, rigid] in
                rigid.impactOccurred(intensity: 0.9)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { light.impactOccurred(intensity: 0.5) }
            }
        }
    }

    /// Transients (time, intensity, sharpness) on Core Haptics where the hardware has it, else the fallback.
    private func pattern(_ transients: [(Double, Float, Float)], fallback: () -> Void) {
        guard let engine = makeEngine() else { return fallback() }
        let events = transients.map { t, i, s in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: s),
            ], relativeTime: t)
        }
        do {
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }

    /// Created on first use; where it can't be (no Taptic Engine, simulator, iPad, Mac) the UIKit fallback
    /// is used from then on.
    private func makeEngine() -> CHHapticEngine? {
        if let engine { return engine }
        guard !engineFailed, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { engineFailed = true; return nil }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true
            e.playsHapticsOnly = true
            e.resetHandler = { [weak e] in try? e?.start() }
            engine = e
            return e
        } catch {
            engineFailed = true
            return nil
        }
    }
}

// MARK: - Sound

/// Six short sounds (Shutterlink/Sounds, made by scripts/make-sounds.py). The session is `.ambient` with
/// `.mixWithOthers`: the Ring/Silent switch silences it, other audio keeps playing and is never ducked.
/// The app has no other audio session (the QR scanner captures video only). Skipped while another app's
/// audio asks for priority and while the app is in the background.
@MainActor
private final class Sound {
    static let shared = Sound()

    enum Name: String, CaseIterable { case tick, shutter, start, stop, chime, connect }

    private var players: [Name: AVAudioPlayer] = [:]
    private var configured = false
    private var lastTick = Date.distantPast

    func play(_ m: Feedback.Moment) {
        let name: Name
        switch m {
        case .dialTick, .dialStop: name = .tick
        case .shutter: name = .shutter
        case .exposureStart: name = .start
        case .exposureStop: name = .stop
        case .seriesComplete: name = .chime
        case .connected: name = .connect
        case .select, .press, .focusLock, .refused, .lostContact: return
        }
        guard UIApplication.shared.applicationState == .active else { return }
        configure()
        if AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint { return }
        if name == .tick {
            guard Date.now.timeIntervalSince(lastTick) > 0.06 else { return }
            lastTick = .now
        }
        guard let p = player(name) else { return }
        // ±3 % pitch on the one repeating sound, so it doesn't machine-gun.
        p.rate = name == .tick ? Float.random(in: 0.97...1.03) : 1
        p.currentTime = 0
        p.play()
    }

    private func configure() {
        guard !configured else { return }
        configured = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for n in Name.allCases { _ = player(n) }
    }

    private func player(_ n: Name) -> AVAudioPlayer? {
        if let p = players[n] { return p }
        guard let url = Bundle.main.url(forResource: "sfx-\(n.rawValue)", withExtension: "caf"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.enableRate = true
        p.prepareToPlay()
        players[n] = p
        return p
    }
}

// MARK: - In views

extension View {
    /// Plays a moment when `trigger` changes (where `condition` holds). Use instead of `sensoryFeedback`,
    /// so the settings apply.
    func feedback<T: Equatable>(_ moment: Feedback.Moment, trigger: T,
                                condition: @escaping (T, T) -> Bool = { _, _ in true }) -> some View {
        onChange(of: trigger) { old, new in
            if condition(old, new) { Feedback.play(moment) }
        }
    }
}

/// Watches the camera for the moments that come from it rather than from a touch: connected, lost contact,
/// refused, focus lock, exposures and series starting, stopping and completing. Also keeps
/// `Feedback.exposureOpen` up to date for Quiet on tripod. Put once at the root.
struct FeedbackObserver: ViewModifier {
    @Environment(CameraModel.self) private var camera

    private var exposureOpen: Bool {
        camera.exposureStartedAt != nil || (camera.isShooting && (camera.interval.running || camera.bracket.running))
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: camera.phase) { old, new in
                if new == .connected { Feedback.play(.connected) }
                // A drop the driver reported already played from `lastError`.
                else if old == .connected, let e = camera.lastError, !e.hasPrefix("Lost contact") { Feedback.play(.lostContact) }
            }
            .onChange(of: camera.lastError) { _, error in
                guard let error, camera.phase == .connected else { return }
                Feedback.play(error.hasPrefix("Lost contact") ? .lostContact : .refused)
            }
            .onChange(of: camera.liveInfo.afState == 1) { _, locked in
                if locked { Feedback.play(.focusLock) }
            }
            .onChange(of: exposureOpen, initial: true) { _, open in Feedback.exposureOpen = open }
            .onChange(of: camera.exposureStartedAt != nil) { _, open in
                // Series frames are counted by the series, not one by one. With Quiet on tripod the start
                // is held back (the shutter is open by then); the stop plays once it has closed.
                guard !camera.interval.running, !camera.bracket.running else { return }
                Feedback.exposureOpen = exposureOpen
                Feedback.play(open ? .exposureStart : .exposureStop)
            }
            .onChange(of: camera.isRecordingMovie) { _, on in Feedback.play(on ? .exposureStart : .exposureStop) }
            .onChange(of: camera.interval) { old, new in series(old.running, new.running, done: old.done, total: old.total) }
            .onChange(of: camera.bracket) { old, new in series(old.running, new.running, done: old.done, total: old.total) }
    }

    /// A series started, or ended: complete when every frame was shot (the state is reset at the end, so
    /// the count comes from before), stopped otherwise.
    private func series(_ was: Bool, _ now: Bool, done: Int, total: Int) {
        guard was != now else { return }
        Feedback.exposureOpen = exposureOpen
        if now { Feedback.play(.exposureStart) }
        else { Feedback.play(total > 0 && done >= total ? .seriesComplete : .exposureStop) }
    }
}

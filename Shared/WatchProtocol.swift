import Foundation

// What the iPhone app and the Watch app say to each other over WatchConnectivity.
// The iPhone stays connected to the camera; the Watch is a remote for the iPhone app.

/// The camera as the iPhone sees it, sent to the Watch whenever it changes.
struct WatchStatus: Codable, Equatable {
    /// The iPhone app is connected to a camera.
    var connected = false
    var cameraName: String?
    var battery: Int?
    var shotsLeft: Int?
    /// Exposure values as the iPhone's strip shows them ("F2.8", "1/250", "400", "+0.3").
    var aperture: String?
    var shutter: String?
    var iso: String?
    var ev: String?
    /// Exposure compensation choices for the Digital Crown, and whether it can be changed now.
    var evOptions: [String] = []
    var evValue: String?
    var evSettable = false
    /// The shutter button records video.
    var movieMode = false
    var recording = false
    var movieStart: Date?
    /// Bulb / Live modes: the shutter starts the exposure and a second press ends it.
    var openEnded = false
    var shooting = false
    var exposureStart: Date?
    /// Length of the exposure in progress, when known (timed shutter or timed Bulb).
    var exposureDuration: Double?
    /// The Watch's self-timer is counting down to this moment.
    var selfTimerEnds: Date?
    /// "Interval 3/60", "Bracket 2/5"…: something the Watch can cancel.
    var sequence: String?
    /// Counts every capture, so the Watch can tap your wrist.
    var shots = 0
    var canShoot = false
    /// A short problem report ("Camera is busy"), cleared when it goes away.
    var message: String?
}

enum WatchKey {
    static let command = "cmd"
    static let status = "status"
    static let delay = "delay"
    static let value = "value"
    static let on = "on"
}

enum WatchCommand: String {
    /// Press the shutter (or start/stop Bulb or video), after `delay` seconds.
    case shutter
    /// Stop the self-timer, an interval run or a bracket.
    case cancel
    /// Set exposure compensation to `value`.
    case setEV
    /// Start (`on` = true) or stop sending small live-view frames.
    case preview
    /// Ask for the current status straight away.
    case hello
}

extension WatchStatus {
    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data?) -> WatchStatus? {
        data.flatMap { try? JSONDecoder().decode(WatchStatus.self, from: $0) }
    }
}

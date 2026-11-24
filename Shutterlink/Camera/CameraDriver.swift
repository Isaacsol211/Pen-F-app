import Foundation
import UIKit

/// What a connected camera can do from the app. The UI hides anything that is false.
struct CameraCapabilities: Equatable {
    /// Live-view sizes the user can choose between ("0640x0480"); empty hides the picker.
    var liveViewSizes: [String] = []
    /// Tap on live view moves the AF point / focuses there.
    var tapToFocus = true
    /// Bulb (or Live Time / Live Composite) started and stopped from the app.
    var openEndedExposure = false
    /// Movie recording from the shutter button.
    var movie = false
    /// The camera's photo/video mode can't be read, so the app shows its own Video switch.
    var videoSwitch = false
    /// A preview of the last shot is fetched after each capture.
    var lastShotReview = false
    /// The camera's clock can be set from the phone.
    var clockSync = false
    /// Olympus High Res Shot guide.
    var highResShot = false
    /// The card can be browsed and photos saved.
    var cardBrowser = true
    /// The camera can be switched off from the app.
    var powerOff = false
    /// Olympus: the User-Agent can be switched under Advanced.
    var userAgentChoice = false
    /// The lens can be stepped nearer or farther from the app, for focus stacking.
    var focusDrive = false
}

/// How far one focus-stacking step moves the lens.
enum FocusStepSize: Int, CaseIterable, Identifiable, Codable {
    case fine = 1, medium = 2, coarse = 3

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .fine: "Fine"
        case .medium: "Medium"
        case .coarse: "Coarse"
        }
    }
}

enum FocusDriveResult: Equatable {
    case moved
    /// The lens is already at the end of its travel in that direction (infinity or the closest point).
    case endOfTravel
}

/// One camera brand's protocol. The model owns all state the UI shows; a driver reads and
/// writes it through `camera`, and only talks to the camera in its own way.
///
/// Settings use the app's common property names and spellings (the Olympus ones):
///   focalvalue "5.6" · shutspeedvalue "250" (1/250 s), "2.5\"" (2.5 s), "bulb" ·
///   isospeedvalue "auto", "400" · expcomp "+0.3", "0.0" · wbvalue "0" (auto), "18" (daylight)… ·
///   takemode "P", "A", "S", "M", "iAuto", "movie".
@MainActor
protocol CameraDriver: AnyObject {
    var capabilities: CameraCapabilities { get }
    /// How live-view frames reach the phone.
    var liveViewFormat: LiveViewFormat { get }

    /// Says hello, pairs if needed, reads the camera's name and what it supports.
    func connect() async throws
    /// Polite goodbye before the connection is dropped (best effort).
    func disconnect() async
    /// Stops background tasks and closes sockets; called once the model forgets the camera.
    func teardown()
    func powerOff() async

    /// Shooting mode with live view; also called after browsing the card.
    func enterRecMode() async
    func startLiveView() async
    func stopLiveView() async

    func refreshProperties() async
    /// Returns false (and reports why, when asked) if the camera refused the value.
    func setProperty(_ name: String, to value: String, reportErrors: Bool) async -> Bool

    /// `normalized` is 0…1 over the live-view frame.
    func focus(at normalized: CGPoint) async
    func releaseFocus() async
    func shutterPressed() async
    func shutterReleased() async
    /// Bulb / Live modes: the first call opens the shutter, the second closes it.
    func toggleOpenExposure() async
    func toggleMovie() async
    func fetchLastShot() async
    func syncClock() async -> Bool
    /// Steps manual focus nearer or farther (focus stacking). Only called when `capabilities.focusDrive`.
    func driveFocus(farther: Bool, step: FocusStepSize) async throws -> FocusDriveResult

    /// Fills `camera.images` and `camera.cardFolders`.
    func openGallery() async
    func thumbnail(for image: CameraImage) async -> UIImage?
    func preview(for image: CameraImage) async throws -> UIImage
    func downloadOriginal(_ image: CameraImage) async throws -> Data
}

extension CameraDriver {
    func disconnect() async {}
    func powerOff() async {}
    func releaseFocus() async {}
    func shutterReleased() async {}
    func toggleOpenExposure() async {}
    func toggleMovie() async {}
    func fetchLastShot() async {}
    func syncClock() async -> Bool { false }
    func driveFocus(farther: Bool, step: FocusStepSize) async throws -> FocusDriveResult {
        throw CameraError("This camera can't move its focus over Wi-Fi.")
    }
}

extension CameraBrand {
    /// A new driver for this brand, talking to `camera` at `camera.host`.
    @MainActor
    func makeDriver(for camera: CameraModel) -> CameraDriver {
        switch self {
        case .olympus: OlympusDriver(camera: camera)
        case .panasonic: PanasonicDriver(camera: camera)
        case .nikon: NikonDriver(camera: camera)
        case .canon: CanonDriver(camera: camera)
        case .sony: SonyDriver(camera: camera)
        }
    }
}

/// Shared helpers for drivers that map a camera's own values onto the app's spellings.
enum ExposureText {
    /// 1/250 s → "250", 2.5 s → "2.5\"", 1/2.5 s → "2.5", 1 s → "1\"".
    static func shutter(seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        if seconds >= 1 - 0.001 { return clean(seconds) + "\"" }
        return clean(1 / seconds)
    }

    /// 125.0 → "125", 2.5 → "2.5", 1.333 → "1.3".
    static func clean(_ value: Double) -> String {
        if value >= 10 || abs(value - value.rounded()) < 0.05 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }

    /// f/5.6 → "5.6", f/11 → "11".
    static func aperture(_ f: Double) -> String {
        f >= 10 ? String(format: "%.0f", f) : String(format: "%.1f", f)
    }

    /// Thirds of a stop → "+0.3", "-1.0", "0.0".
    static func ev(thirds: Int) -> String {
        thirds == 0 ? "0.0" : String(format: "%+.1f", Double(thirds) / 3)
    }

    /// EV as a number → nearest third ("+0.7" from 0.6667).
    static func ev(_ value: Double) -> String {
        ev(thirds: Int((value * 3).rounded()))
    }

    /// "+0.3" → 1 (thirds), "-1.7" → -5.
    static func thirds(fromEV text: String) -> Int {
        Int(((Double(text) ?? 0) * 3).rounded())
    }

    /// Panasonic-style white-balance names → the app's codes (which have labels and icons).
    static let whiteBalanceCodes: [String: String] = [
        "auto": "0", "daylight": "18", "sunny": "18", "shade": "16", "cloudy": "17",
        "incandescent": "20", "tungsten": "20", "halogen": "20", "fluorescent": "35",
        "underwater": "64", "flash": "23", "custom": "256", "preset": "256", "color_temp": "512", "kelvin": "512",
    ]
}

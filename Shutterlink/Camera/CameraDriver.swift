import UIKit

/// What a connected camera can do from the app. The UI hides anything that is false.
struct CameraCapabilities: Equatable {
    /// Live-view sizes the user can choose between ("0640x0480"); empty hides the picker.
    var liveViewSizes: [String] = []
    /// Tap on live view moves the AF point / focuses there.
    var tapToFocus = true
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
    /// The lens can be stepped nearer or farther from the app, for focus stacking.
    var focusDrive = false
}

/// How far one focus-stacking step moves the lens.
enum FocusStepSize: Int, CaseIterable, Identifiable {
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

enum FocusDriveResult {
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
    var camera: CameraModel { get }
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
    func teardown() {}
    func powerOff() async {}
    /// Nothing to switch on the camera: read the settings and start live view.
    func enterRecMode() async {
        camera.isSwitchingMode = true
        defer { camera.isSwitchingMode = false }
        camera.mode = .rec
        await camera.refreshProperties()
        await camera.startLiveView()
    }
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

    /// Panasonic-style white-balance names → the app's codes (which have labels and icons).
    static let whiteBalanceCodes: [String: String] = [
        "auto": "0", "daylight": "18", "sunny": "18", "shade": "16", "cloudy": "17",
        "incandescent": "20", "tungsten": "20", "halogen": "20", "fluorescent": "35",
        "underwater": "64", "flash": "23", "custom": "256", "preset": "256", "color_temp": "512", "kelvin": "512",
    ]
}

/// Steps the drivers share.
extension CameraModel {
    /// Runs a driver's first request up to 3 times: it can fail while iOS shows the Local Network
    /// prompt, and a camera can be slow right after its Wi-Fi comes up.
    @discardableResult
    func retryingConnect<T>(when retryable: (Error) -> Bool = { $0 is URLError },
                            _ request: () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do { return try await request() } catch {
                guard attempt < 3, retryable(error) else { throw error }
                attempt += 1
                status = "No answer yet, retrying (\(attempt)/3)…"
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    /// Marks a shot as running, with a countdown when it lasts 1 s or more; returns the exposure
    /// time in seconds (0 if unknown). `endShot()` clears it again.
    func beginShot() -> Double {
        isShooting = true
        let seconds = PropertyFormat.seconds(fromShutter: properties["shutspeedvalue"]?.value ?? "") ?? 0
        if seconds >= 1 {
            exposureStartedAt = Date()
            exposureDuration = seconds
        }
        return seconds
    }

    func endShot() {
        isShooting = false
        exposureStartedAt = nil
        exposureDuration = nil
    }

    /// The camera started or stopped recording a movie (a finished movie counts as a shot).
    func setRecordingMovie(_ recording: Bool) {
        isRecordingMovie = recording
        movieStartedAt = recording ? Date() : nil
        if !recording { shotCounter += 1 }
    }

    /// Shows `value` at once and sends it; puts the old value back (and reports why, when asked) if
    /// the camera refuses. The caller re-reads the settings afterwards.
    func optimisticallySet(_ name: String, to value: String, reportErrors: Bool,
                           send: () async throws -> Void) async -> Bool {
        let previous = properties[name]?.value
        properties[name]?.value = value
        do {
            try await send()
            return true
        } catch {
            if let previous { properties[name]?.value = previous }
            if reportErrors { report(error) }
            return false
        }
    }
}

/// Card files that come with their own addresses (LUMIX UPnP, Sony avContent).
extension CameraHTTPClient {
    func thumbnail(for image: CameraImage) async -> UIImage? {
        let urls = image.urls
        return (try? await fetch(urls?.thumbnail ?? urls?.preview ?? urls?.original, log: false)).flatMap { UIImage(data: $0) }
    }

    func preview(for image: CameraImage) async throws -> UIImage {
        let urls = image.urls
        guard let picture = UIImage(data: try await fetch(urls?.preview ?? urls?.thumbnail ?? urls?.original)) else {
            throw CameraError("Couldn't decode the preview.")
        }
        return picture
    }
}

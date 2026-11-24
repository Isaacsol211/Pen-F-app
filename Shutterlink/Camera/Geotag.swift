import CoreLocation
import Foundation

/// One logged position.
struct TrackPoint: Codable, Equatable {
    let time: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let accuracy: Double
}

/// Logs where the phone is while it's connected to the camera (When In Use only), so photos saved
/// to Photos later can be given the location nearest their capture time.
///
/// Points are kept for two weeks in Application Support. While the phone stays still (say, on a
/// tripod all night) Core Location sends nothing new, so the last position is repeated every
/// minute: a photo then always has a point within a minute or so of its capture time.
@MainActor
final class LocationLog: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var points: [TrackPoint] = []
    private var logging = false
    private var unsaved = 0
    private var heartbeat: Task<Void, Never>?
    /// Called when the user has turned Location off for the app.
    var onDenied: (() -> Void)?

    private static let keepFor: TimeInterval = 14 * 24 * 3600
    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("location-log.json")
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
        load()
    }

    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    var isDenied: Bool {
        [.denied, .restricted].contains(manager.authorizationStatus)
    }

    /// Asks for When In Use access if iOS hasn't asked yet.
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func start() {
        guard !logging else { return }
        logging = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()   // updates start once it's granted
        case .denied, .restricted:
            onDenied?()
        default:
            beginUpdates()
        }
    }

    func stop() {
        guard logging else { return }
        logging = false
        manager.stopUpdatingLocation()
        heartbeat?.cancel()
        heartbeat = nil
        save()
    }

    /// Roughly where the iPhone is, without asking for anything: the system's last fix when Location is
    /// already allowed, or the last logged point. Good enough for where the sun and moon are.
    var lastKnown: CLLocation? {
        if isAuthorized, let location = manager.location { return location }
        return points.last.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// The logged position closest in time to `date`, if one is within `window` seconds.
    func location(near date: Date, within window: TimeInterval = 600) -> CLLocation? {
        guard date > .distantPast,
              let best = points.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }),
              abs(best.time.timeIntervalSince(date)) <= window else { return nil }
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: best.latitude, longitude: best.longitude),
                          altitude: best.altitude ?? 0,
                          horizontalAccuracy: best.accuracy,
                          verticalAccuracy: best.altitude == nil ? -1 : 10,
                          timestamp: best.time)
    }

    // MARK: - Core Location

    private func beginUpdates() {
        manager.startUpdatingLocation()
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled, let last = self.points.last else { continue }
                if Date().timeIntervalSince(last.time) >= 55 {
                    self.append(TrackPoint(time: Date(), latitude: last.latitude, longitude: last.longitude,
                                           altitude: last.altitude, accuracy: last.accuracy))
                }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.logging else { return }
            if self.isAuthorized {
                self.beginUpdates()
            } else if self.isDenied {
                self.onDenied?()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fresh = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 200 }
        Task { @MainActor in
            for location in fresh {
                self.append(TrackPoint(time: location.timestamp,
                                       latitude: location.coordinate.latitude,
                                       longitude: location.coordinate.longitude,
                                       altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                                       accuracy: location.horizontalAccuracy))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        debugLog("location: \(error.localizedDescription)")
    }

    // MARK: - Storage

    private func append(_ point: TrackPoint) {
        points.append(point)
        unsaved += 1
        if unsaved >= 5 { save() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let saved = try? JSONDecoder().decode([TrackPoint].self, from: data) else { return }
        points = saved.filter { Date().timeIntervalSince($0.time) < Self.keepFor }
    }

    private func save() {
        unsaved = 0
        points.removeAll { Date().timeIntervalSince($0.time) >= Self.keepFor }
        if let data = try? JSONEncoder().encode(points) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}

extension CameraModel {
    /// Logs location only while connected and geotagging is on.
    func updateLocationLogging() {
        locationLog.onDenied = { [weak self] in
            self?.lastError = "Location is off for Shutterlink, so photos can't be geotagged. Turn it on in Settings ▸ Privacy & Security ▸ Location Services."
        }
        if geotagging { locationLog.requestPermission() }
        if geotagging && phase == .connected {
            locationLog.start()
        } else {
            locationLog.stop()
        }
    }
}

import Foundation

/// A camera this iPhone has connected to, for one-tap reconnecting from the home screen.
struct SavedCamera: Codable, Identifiable, Hashable {
    /// Brand and model, e.g. "olympus|PEN-F".
    var id: String { brand.rawValue + "|" + name }
    let brand: CameraBrand
    /// What the camera called itself (or its model-table name), e.g. "PEN-F", "LUMIX GH5".
    let name: String
    /// The address it answered at; empty for the brand's usual one.
    var host: String
    var lastUsed: Date
    /// The camera's Wi-Fi network when Shutterlink joined it itself (password in the Keychain).
    var ssid: String?

    private static let key = "savedCameras"

    static func load() -> [SavedCamera] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cameras = try? JSONDecoder().decode([SavedCamera].self, from: data) else { return [] }
        return cameras.sorted { $0.lastUsed > $1.lastUsed }
    }

    static func save(_ cameras: [SavedCamera]) {
        if let data = try? JSONEncoder().encode(cameras) { UserDefaults.standard.set(data, forKey: key) }
    }
}

extension CameraBrand: Codable {}

extension CameraModel {
    /// Called once a connection succeeds: adds the camera to the home screen, or moves it to the top,
    /// with the Wi-Fi network it's on.
    func rememberConnectedCamera() async {
        let name = (cameraName?.isEmpty == false ? cameraName : nil) ?? brand.title
        let address = activeHost ?? host
        var saved = SavedCamera(brand: brand, name: name,
                                host: address == brand.defaultHost ? "" : address, lastUsed: Date())
        // `joinedNetwork` is the last network Shutterlink joined, but the phone may have moved to
        // another camera's network in Settings since, or iOS may not have switched at all. It belongs
        // to this camera only if the phone is on it now or, when iOS won't say, if this is the camera
        // it was joined for.
        let current = await CameraWiFi.current()
        let joined = joinedNetwork.flatMap { network -> CameraNetwork? in
            if let current { return current.ssid == network.ssid ? network : nil }
            return connectingTo.map { $0.id == saved.id } ?? true ? network : nil
        }
        if let joined {
            saved.ssid = joined.ssid
            CameraWiFiPasswords.save(joined.password, for: joined.ssid)
        } else if let current {
            // Joined in Settings: Shutterlink can rejoin it if it's open or the password is known.
            let rejoinable = !current.secure || CameraWiFiPasswords.password(for: current.ssid) != nil
            saved.ssid = rejoinable ? current.ssid : nil
        } else {
            saved.ssid = savedCameras.first { $0.id == saved.id }?.ssid
        }
        savedCameras = [saved] + savedCameras.filter { $0.id != saved.id }
        SavedCamera.save(savedCameras)
    }

    func forget(_ saved: SavedCamera) {
        if let ssid = saved.ssid, !savedCameras.contains(where: { $0.id != saved.id && $0.ssid == ssid }) {
            CameraWiFiPasswords.delete(for: ssid)
            CameraWiFi.remove(ssid: ssid)
        }
        savedCameras.removeAll { $0.id == saved.id }
        SavedCamera.save(savedCameras)
    }

    /// Reconnects to a camera from the home screen: its brand and address, no auto-detect. When
    /// Shutterlink joined the camera's Wi-Fi before, it joins it again first, so one tap does it all.
    /// `waitingUntil` gives iOS time to rejoin by itself (the Action button).
    func connect(to saved: SavedCamera, waitingUntil deadline: Date? = nil) async {
        guard phase == .disconnected else { return }
        brand = saved.brand
        autoDetectBrand = false
        host = saved.host.isEmpty ? saved.brand.defaultHost : saved.host
        capabilities = saved.brand.defaultCapabilities
        connectingTo = saved
        defer { connectingTo = nil }
        if let network = savedNetwork(for: saved) {
            guard await join(network) else { return }
            await connect(waitingUntil: max(deadline ?? .distantPast, Date().addingTimeInterval(30)))
        } else {
            await connect(waitingUntil: deadline)
        }
        // Without a network to join, whichever camera of that brand the phone is on answers.
        if phase == .connected, let other = savedCameras.first, other.id != saved.id {
            showToast("This is the \(other.name), not the \(saved.name)")
        }
    }
}

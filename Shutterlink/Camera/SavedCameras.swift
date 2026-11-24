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
    /// Called once a connection succeeds: adds the camera to the home screen, or moves it to the top.
    func rememberConnectedCamera() {
        let name = (cameraName?.isEmpty == false ? cameraName : nil) ?? brand.title
        let address = activeHost ?? host
        var saved = SavedCamera(brand: brand, name: name,
                                host: address == brand.defaultHost ? "" : address, lastUsed: Date())
        if let network = joinedNetwork {
            saved.ssid = network.ssid
            CameraWiFiPasswords.save(network.password, for: network.ssid)
        } else {
            saved.ssid = savedCameras.first { $0.id == saved.id }?.ssid
        }
        var list = savedCameras.filter { $0.id != saved.id }
        list.insert(saved, at: 0)
        savedCameras = list
        SavedCamera.save(list)
    }

    func forget(_ saved: SavedCamera) {
        if let ssid = saved.ssid, !savedCameras.contains(where: { $0.id != saved.id && $0.ssid == ssid }) {
            CameraWiFiPasswords.delete(for: ssid)
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
        if let network = savedNetwork(for: saved) {
            guard await join(network) else { return }
            await connect(waitingUntil: max(deadline ?? .distantPast, Date().addingTimeInterval(30)))
        } else {
            await connect(waitingUntil: deadline)
        }
    }
}

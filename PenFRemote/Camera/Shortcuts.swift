import AppIntents

/// "Connect to Camera" for Shortcuts, Siri and the Action button. It opens the app and connects,
/// waiting up to 30 s while iOS rejoins the camera's Wi-Fi.
///
/// Joining the camera's network from inside the app (NEHotspotConfiguration) would make this a
/// true one-tap action, but that needs the Hotspot capability, which Apple only signs for paid
/// developer accounts. iOS rejoins a camera network you've joined once by itself, as soon as the
/// camera's Wi-Fi is on, so the shortcut just has to wait for it.
struct ConnectCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect to Camera"
    static let description = IntentDescription("Opens PEN-F Remote and connects to your camera over its Wi-Fi.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CameraModel.shared.connectFromShortcut()
        return .result()
    }
}

struct PenFRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConnectCameraIntent(),
                    phrases: [
                        "Connect to my camera with \(.applicationName)",
                        "Connect \(.applicationName)",
                    ],
                    shortTitle: "Connect to Camera",
                    systemImageName: "camera.aperture")
    }
}

import SwiftUI

@main
struct PenFRemoteApp: App {
    @State private var camera = CameraModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(camera)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch camera.phase {
            case .disconnected, .connecting:
                ConnectView()
            case .connected:
                RemoteView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: camera.phase)
        .onChange(of: scenePhase) { _, newPhase in
            camera.scenePhaseChanged(newPhase)
        }
        .task { WatchBridge.shared.start(camera: camera) }
        #if DEBUG
        // `-connectFromShortcut` runs what the "Connect to Camera" shortcut runs, for testing in the
        // Simulator, which has no Shortcuts app.
        .task {
            if ProcessInfo.processInfo.arguments.contains("-connectFromShortcut") { camera.connectFromShortcut() }
        }
        #endif
    }
}

enum Theme {
    static let accent = Color(red: 0.98, green: 0.66, blue: 0.24)
    static let panel = Color(white: 0.11)
    static let hairline = Color.white.opacity(0.08)
}

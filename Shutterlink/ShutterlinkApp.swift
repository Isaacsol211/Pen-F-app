import SwiftUI

@main
struct ShutterlinkApp: App {
    @State private var camera = CameraModel.shared

    init() {
        #if targetEnvironment(macCatalyst)
        // Start finding out which interface is Wi-Fi (not always en0 on a Mac).
        _ = WiFiInterface.shared
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(camera)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
        #if targetEnvironment(macCatalyst)
        // Big enough for the workspace layouts (the iPad ones); see `MacWindow`.
        .defaultSize(width: MacWindow.defaultSize.width, height: MacWindow.defaultSize.height)
        #endif
        .commands {
            CameraCommands()
            #if targetEnvironment(macCatalyst)
            // One window: there's one camera connection, and every window would run its own live
            // view analysis.
            CommandGroup(replacing: .newItem) {}
            #endif
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
        .background(Theme.background.ignoresSafeArea())
        .overlay { LaunchHandoff() }
        .onChange(of: scenePhase) { _, newPhase in
            camera.scenePhaseChanged(newPhase)
        }
        #if targetEnvironment(macCatalyst)
        .background(WindowSceneReader { MacWindow.configure($0) })
        #else
        .task { WatchBridge.shared.start(camera: camera) }
        #endif
        #if DEBUG
        // `-connectFromShortcut` runs what the "Connect to Camera" shortcut runs, for testing in the
        // Simulator, which has no Shortcuts app.
        .task {
            if ProcessInfo.processInfo.arguments.contains("-connectFromShortcut") { camera.connectFromShortcut() }
            // `-selfTest <brand|auto> <127.0.0.1:port>` runs a driver through everything against a mock.
            DriverSelfTest.runIfRequested(camera)
        }
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// The Mac window: resizable, but never smaller than the workspace layouts need (a short side of
/// `Workspace.workspaceSide`), so the Mac always gets the iPad layouts and never the phone ones.
enum MacWindow {
    static let defaultSize = CGSize(width: 1280, height: 860)
    static let minimumSize = CGSize(width: 980, height: 740)

    static func configure(_ scene: UIWindowScene?) {
        guard let scene else { return }
        scene.sizeRestrictions?.minimumSize = minimumSize
    }
}
#endif

import SwiftUI

@main
struct ShutterlinkApp: App {
    @State private var camera = CameraModel.shared
    #if targetEnvironment(macCatalyst)
    @UIApplicationDelegateAdaptor(MacAppDelegate.self) private var macDelegate
    #endif

    init() {
        ShutterlinkPro.shared.start()
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
        // Big enough for the workspace layouts (the iPad ones).
        .defaultSize(width: 1280, height: 860)
        #endif
        .commands { CameraCommands() }
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
        .onChange(of: scenePhase) { camera.scenePhaseChanged($1) }
        #if targetEnvironment(macCatalyst)
        // The Mac window is resizable, but never smaller than the workspace layouts need (a short side of
        // `Workspace.workspaceSide`), so the Mac always gets the iPad layouts and never the phone ones.
        .background(WindowSceneReader { $0?.sizeRestrictions?.minimumSize = CGSize(width: 980, height: 740) })
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
/// Trims the menu bar UIKit gives every Mac Catalyst app (SwiftUI's `CommandGroup(replacing:)`
/// doesn't reach these items there).
final class MacAppDelegate: UIResponder, UIApplicationDelegate {
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        // One window: there's one camera connection, and every window would run its own live view
        // analysis. Closing the window and clicking the Dock icon brings it back.
        builder.remove(menu: .newItem)
        // Duplicate, Move, Rename, Export As…: there are no documents.
        builder.remove(menu: .document)
    }
}
#endif

import SwiftUI

@main
struct PenFRemoteWatchApp: App {
    @State private var link = PhoneLink()

    var body: some Scene {
        WindowGroup {
            WatchRemoteView()
                .environment(link)
                .task { link.start() }
        }
    }
}

enum WatchTheme {
    static let accent = Color(red: 0.98, green: 0.66, blue: 0.24)
}

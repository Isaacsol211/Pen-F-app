import SwiftUI

@main
struct ShutterlinkWatchApp: App {
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
    static let accent = Color(red: 1.0, green: 0.69, blue: 0.16)   // same as the iPhone app's Theme.accent
}

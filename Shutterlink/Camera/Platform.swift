import UIKit

/// The few words and behaviours that differ between the iPhone/iPad app and the Mac app (Mac
/// Catalyst, same target). On iOS every value is what the app always said, so copy that uses these
/// reads exactly as before there.
enum Platform {
    #if targetEnvironment(macCatalyst)
    static let isMac = true
    /// "this Mac isn't on Wi-Fi"
    static let device = "Mac"
    static let os = "macOS"
    static let settings = "System Settings"
    /// Where the user turns Photos access back on.
    static let photosSettings = "System Settings ▸ Privacy & Security ▸ Photos"
    static let tap = "click"
    #else
    static let isMac = false
    static let device = "iPhone"
    static let os = "iOS"
    static let settings = "Settings"
    static let photosSettings = "Settings ▸ Shutterlink ▸ Photos"
    static let tap = "tap"
    #endif
}

/// Keeps the device awake while connected to a camera.
///
/// iPhone/iPad: the screen stays on, since iOS stops the app's Wi-Fi when the device locks.
/// Mac: the display may sleep, but the Mac must not (sleep drops Wi-Fi too), and App Nap must not
/// throttle the app while its window is covered, or interval timers and live view stall.
@MainActor
enum KeepAwake {
    #if targetEnvironment(macCatalyst)
    private static var activity: NSObjectProtocol?
    #endif

    static func set(_ on: Bool) {
        #if targetEnvironment(macCatalyst)
        if on, activity == nil {
            // .userInitiated includes .idleSystemSleepDisabled and opts out of App Nap.
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated,
                                                             reason: "Connected to a camera")
        } else if !on, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
        #else
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }
}

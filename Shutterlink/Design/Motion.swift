import SwiftUI
import UIKit

/// The app's springs, each with one fixed use (docs/design/04-motion-sound-haptics.md §4). Use these
/// instead of ad-hoc springs. With Reduce Motion on, every one becomes a 0.2 s ease-in-out dissolve;
/// haptics stay as they are.
enum Motion {
    /// Response and damping of a named spring.
    struct Token {
        let response: Double
        let damping: Double
    }

    /// Selection, panels, chips, dialogs: quick and dry.
    static let shutterToken = Token(response: 0.28, damping: 0.9)
    /// The release after a drag or pinch, where the content goes back to rest.
    static let mirrorToken = Token(response: 0.35, damping: 0.68)
    /// Whole-screen cross-fades (connect ⇄ remote).
    static let developToken = Token(response: 0.6, damping: 1.0)
    /// Following the finger.
    static let trackToken = Token(response: 0.15, damping: 0.86)

    static var shutter: Animation { animation(shutterToken) }
    static var mirror: Animation { animation(mirrorToken) }
    static var develop: Animation { animation(developToken) }
    static var track: Animation { animation(trackToken) }

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    private static func animation(_ t: Token) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: t.response, dampingFraction: t.damping)
    }
}

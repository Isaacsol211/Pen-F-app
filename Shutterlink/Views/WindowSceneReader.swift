import SwiftUI
import UIKit

/// Reports the window scene a SwiftUI view is shown in, and reports again when it, or the screen it's
/// on, changes. Use it instead of `UIApplication.shared.connectedScenes`, whose first scene may not
/// be the one showing the view (iPad multitasking, or an iPhone Duo that was folded or unfolded,
/// which moves the scene to the other screen). Attach it as a background so it takes the view's size
/// and is laid out again when the scene resizes.
struct WindowSceneReader: UIViewRepresentable {
    var onChange: (UIWindowScene?) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((UIWindowScene?) -> Void)?
        private weak var lastScene: UIWindowScene?
        private weak var lastScreen: UIScreen?
        private var reported = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            let scene = window?.windowScene
            let screen = scene?.screen
            guard !reported || scene !== lastScene || screen !== lastScreen else { return }
            reported = true
            lastScene = scene
            lastScreen = screen
            // This can run during a SwiftUI update; changing state then is not allowed.
            DispatchQueue.main.async { [onChange] in onChange?(scene) }
        }
    }
}

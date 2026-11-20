import CoreImage
import QuartzCore

/// Focus peaking: marks the sharpest edges in the live-view frame with colour, like a camera's
/// manual-focus assist. Runs on its own queue at up to ~12 fps and drops frames while busy, so the
/// live view itself never waits for it.
final class FocusPeaker: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false, .priorityRequestLow: false])
    private let queue = DispatchQueue(label: "focus peaking", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var lastStart: CFTimeInterval = 0
    private let minimumGap: CFTimeInterval = 1.0 / 12

    /// Calls `done` on the peaking queue with the overlay, unless a frame is already being processed
    /// or one was started very recently (then the frame is skipped and `done` isn't called).
    func submit(_ frame: CGImage, done: @escaping (CGImage?) -> Void) {
        let accept: Bool = lock.withLock {
            let now = CACurrentMediaTime()
            guard !busy, now - lastStart >= minimumGap else { return false }
            busy = true
            lastStart = now
            return true
        }
        guard accept else { return }
        queue.async { [self] in
            let overlay = Self.overlay(for: frame, context: context)
            lock.withLock { busy = false }
            done(overlay)
        }
    }

    /// Coloured edge pixels on a transparent background, the same size as the frame.
    static func overlay(for frame: CGImage, context: CIContext) -> CGImage? {
        let input = CIImage(cgImage: frame)
        let extent = input.extent
        let edges = input
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 5.0])
            // Keep only strong edges: in-focus detail has much more contrast than blur.
            .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.3])
            // Thicken them a little so they read on a phone screen.
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1])
            .cropped(to: extent)
        let colour = CIImage(color: CIColor(red: 1, green: 0.18, blue: 0.22)).cropped(to: extent)
        let clear = CIImage(color: .clear).cropped(to: extent)
        let output = colour.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: edges,
        ])
        return context.createCGImage(output, from: extent)
    }
}

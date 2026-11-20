import Foundation
import SwiftUI
import UIKit

/// Interval timer (time-lapse / star stacking) settings.
struct IntervalPlan: Equatable, Codable {
    /// Number of frames; 0 = keep going until stopped.
    var count = 60
    /// Seconds from the start of one shot to the start of the next.
    var seconds = 20.0
}

struct IntervalState: Equatable {
    var running = false
    var done = 0
    var total = 0
    var nextShotAt: Date?
    var startedAt: Date?
}

extension CameraModel {
    // MARK: - Interval timer

    func startInterval(_ plan: IntervalPlan) {
        guard !interval.running, mode == .rec, !isOpenEndedShutter else { return }
        interval = IntervalState(running: true, done: 0, total: plan.count, nextShotAt: Date(), startedAt: Date())
        intervalTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.interval.running,
                  plan.count == 0 || self.interval.done < plan.count {
                let shotStart = Date()
                self.interval.nextShotAt = nil
                await self.shutterPressed()
                await self.shutterReleased()
                self.interval.done += 1
                if plan.count != 0 && self.interval.done >= plan.count { break }
                // Interval is measured start-to-start; never fire faster than the camera can finish.
                let wait = max(0.5, plan.seconds - Date().timeIntervalSince(shotStart))
                self.interval.nextShotAt = Date().addingTimeInterval(wait)
                try? await Task.sleep(for: .seconds(wait))
            }
            self.interval.running = false
            self.interval.nextShotAt = nil
        }
    }

    func stopInterval() {
        intervalTask?.cancel()
        intervalTask = nil
        interval.running = false
        interval.nextShotAt = nil
    }

    // MARK: - Focus loupe

    /// The loupe needs detail: switch to 1280×960 while it's open, then go back.
    func setLoupe(_ on: Bool) async {
        let sharp = "1280x0960"
        if on, liveViewQuality != sharp, availableLiveViewSizes.contains(sharp) {
            liveViewBeforeLoupe = liveViewQuality
            await changeLiveViewQuality(sharp)
        } else if !on, let previous = liveViewBeforeLoupe {
            liveViewBeforeLoupe = nil
            await changeLiveViewQuality(previous)
        }
    }

    /// Measure sharpness inside this normalised region (the loupe's view); nil stops measuring.
    func setFocusMeterRegion(_ region: CGRect?) {
        receiver?.setMeterRegion(region)
        focusScore = nil
        focusPeak = 0
        focusFloor = .infinity
    }

    func updateFocusMeter(_ value: Double) {
        let smoothed = focusScore.map { $0 * 0.55 + value * 0.45 } ?? value
        focusScore = smoothed
        focusPeak = max(focusPeak, smoothed)
        focusFloor = min(focusFloor, smoothed)
    }

    // MARK: - Toasts

    func showToast(_ text: String) {
        withAnimation(.bouncy) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toast == text { withAnimation(.smooth) { toast = nil } }
        }
    }


}

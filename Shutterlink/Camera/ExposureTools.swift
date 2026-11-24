import CoreGraphics
import Foundation
import UIKit

// MARK: - Frame measurements

enum FrameMeter {
    /// sRGB code value → linear light, so averages and ratios are in stops.
    private static let linear: [Double] = (0..<256).map { pow(Double($0) / 255, 2.2) }

    /// The frame (or a normalised region of it) drawn into a small greyscale buffer.
    static func grey(_ image: CGImage, region: CGRect? = nil, width: Int, height: Int) -> [UInt8]? {
        var source = image
        if let region {
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let rect = CGRect(x: region.minX * w, y: region.minY * h, width: region.width * w, height: region.height * h)
                .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
            guard rect.width >= 2, rect.height >= 2, let cropped = image.cropping(to: rect) else { return nil }
            source = cropped
        }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Mean linear brightness, 0…1.
    static func brightness(_ image: CGImage) -> Double? {
        guard let pixels = grey(image, width: 32, height: 24) else { return nil }
        return pixels.reduce(0) { $0 + linear[Int($1)] } / Double(pixels.count)
    }

    /// Share of pixels at the very top of the range (blown highlights in the JPEG), 0…1.
    static func clipped(_ image: CGImage) -> Double? {
        guard let pixels = grey(image, width: 80, height: 60) else { return nil }
        return Double(pixels.filter { $0 >= 250 }.count) / Double(pixels.count)
    }
}

extension PropertyFormat {
    /// Seconds for a shutter as shown or as the camera lists it: `1/250`, `2"`, `2.5"`, `250`, `60"`.
    static func seconds(fromDisplay text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("1/"), let d = Double(t.dropFirst(2)), d > 0 { return 1 / d }
        return seconds(fromShutter: t)
    }
}

extension CameraModel {
    /// The latest live-view frame, if one arrived in the last few seconds.
    var recentFrame: CGImage? {
        guard let lastFrameAt, Date().timeIntervalSince(lastFrameAt) < 3 else { return nil }
        return liveFrame?.cgImage
    }

    /// One step brighter or darker for `name`: the next EV option, or the next shutter speed.
    func adjacentValue(_ name: String, brighter: Bool) -> String? {
        guard let property = properties[name] else { return nil }
        switch name {
        case "expcomp":
            let values = property.options.compactMap { option in Double(option).map { (option, $0) } }.sorted { $0.1 < $1.1 }
            guard let current = Double(property.value) else { return nil }
            return brighter ? values.first { $0.1 > current + 0.01 }?.0 : values.last { $0.1 < current - 0.01 }?.0
        case "shutspeedvalue":
            let values = timedShutters.sorted { $0.1 < $1.1 }
            guard let current = PropertyFormat.seconds(fromShutter: property.value) else { return nil }
            return brighter ? values.first { $0.1 > current * 1.1 }?.0 : values.last { $0.1 < current / 1.1 }?.0
        case "isospeedvalue":
            let values = property.options.compactMap { option in Int(option).map { (option, $0) } }.sorted { $0.1 < $1.1 }
            guard let current = Int(property.value) else { return nil }
            return brighter ? values.first { $0.1 > current }?.0 : values.last { $0.1 < current }?.0
        default:
            return nil
        }
    }
}

// MARK: - ND filter calculator

/// The exposure metered without the filter on.
struct NDMeter: Equatable {
    var seconds: Double
    /// The camera's aperture value ("8.0"), when known.
    var aperture: String?
    /// A fixed ISO ("200"); nil when the camera chose it and didn't say.
    var iso: String?
}

extension CameraModel {
    /// What the camera meters now: the shutter, aperture and ISO it chose in an auto mode (from
    /// live view where the camera reports them), or what is set.
    var meteredExposure: NDMeter? {
        let shownShutter = liveInfo.shutter
            ?? properties["shutspeedvalue"].map { PropertyFormat.display("shutspeedvalue", $0.value) }
        guard let seconds = shownShutter.flatMap(PropertyFormat.seconds(fromDisplay:)) else { return nil }
        let apertureNumber = liveInfo.aperture.flatMap { Double($0.filter { $0.isNumber || $0 == "." }) }
        let aperture = apertureNumber.flatMap { aperture(near: $0) } ?? properties["focalvalue"]?.value
        let liveISO = liveInfo.iso.flatMap { Int($0.filter(\.isNumber)) }
        let setISO = properties["isospeedvalue"].flatMap { Int($0.value) }
        let iso = (setISO ?? liveISO).flatMap { nearestISO(to: $0) }
        return NDMeter(seconds: seconds, aperture: aperture, iso: iso)
    }

    static func ndSeconds(metered: Double, stops: Int) -> Double {
        metered * pow(2, Double(stops))
    }

    /// Bulb, or the Live mode that works like it, for exposures longer than the camera's timed ones.
    var bulbShutter: String? {
        let options = properties["shutspeedvalue"]?.options ?? []
        return ["bulb", "livetime", "livebulb"].lazy.compactMap { wanted in
            options.first { $0.lowercased() == wanted }
        }.first
    }

    /// The shutter the ND exposure needs: a timed speed when the camera has one long enough, else Bulb.
    func ndShutter(seconds: Double) -> (value: String?, timedByApp: Bool) {
        let longest = timedShutters.map(\.1).max() ?? 0
        if seconds <= longest * 1.12 { return (shutter(near: seconds), false) }
        if let bulb = bulbShutter { return (bulb, true) }
        return (timedShutters.max { $0.1 < $1.1 }?.0, false)
    }

    func ndSteps(meter: NDMeter, stops: Int) -> [PresetStep] {
        let target = Self.ndSeconds(metered: meter.seconds, stops: stops)
        let (mode, inM) = modeStep("M", why: "Keeps the exposure you metered")
        let (shutterValue, timed) = ndShutter(seconds: target)
        let shutterDetail = timed
            ? "Bulb, stopped by the app after \(Self.durationLabel(target))"
            : "\(Self.durationLabel(target)) through a \(stops)-stop filter"
        return [
            mode,
            presetStep("Aperture as metered", "Keeps the depth of field you metered at", "focalvalue", meter.aperture,
                       mode: "M", inMode: inM),
            presetStep("Shutter", shutterDetail, "shutspeedvalue", shutterValue, mode: "M", inMode: inM),
            presetStep("ISO as metered", "Fixed, so the exposure doesn't drift", "isospeedvalue", meter.iso,
                       unavailable: "Set a fixed ISO (not Auto) on the camera and meter again"),
            antiShockStep(),
        ]
    }

    /// Shoots the long exposure: a timed shutter as usual, or Bulb stopped by the app.
    func shootND(seconds: Double) async {
        if isOpenEndedShutter {
            await toggleOpenExposure()
            if isShooting { scheduleOpenExposureStop(after: seconds) }
        } else {
            await shutterPressed()
            await shutterReleased()
        }
    }
}

// MARK: - Day-to-night ramping

extension CameraModel {
    /// Nudges the exposure a third of a stop towards the brightness live view had when the interval
    /// started: a longer shutter first (up to what the interval leaves room for), then a higher ISO,
    /// and back the other way as it gets lighter. Returns what changed, for the progress card.
    func rampExposure(towards target: Double, plan: IntervalPlan, baseISO: Int?) async -> String? {
        guard let frame = recentFrame, let now = FrameMeter.brightness(frame), now > 0.0002, target > 0.0002 else { return nil }
        let stops = log2(target / now)          // > 0: darker than at the start
        guard abs(stops) >= 0.33 else { return nil }
        let longest = max(0.5, plan.seconds - 1.5)
        if stops > 0 {
            if settableProperty("shutspeedvalue") != nil, let next = adjacentValue("shutspeedvalue", brighter: true),
               let s = PropertyFormat.seconds(fromShutter: next), s <= longest,
               await setProperty("shutspeedvalue", to: next, reportErrors: false) {
                return "Darker: shutter \(PropertyFormat.display("shutspeedvalue", next))"
            }
            if settableProperty("isospeedvalue") != nil, let next = adjacentValue("isospeedvalue", brighter: true),
               (Int(next) ?? .max) <= plan.maxISO,
               await setProperty("isospeedvalue", to: next, reportErrors: false) {
                return "Darker: ISO \(next)"
            }
            return "At the limit: \(PropertyFormat.display("shutspeedvalue", properties["shutspeedvalue"]?.value ?? "")), ISO \(properties["isospeedvalue"]?.value ?? "")"
        }
        if settableProperty("isospeedvalue") != nil, let next = adjacentValue("isospeedvalue", brighter: false),
           (Int(next) ?? 0) >= (baseISO ?? 0),
           await setProperty("isospeedvalue", to: next, reportErrors: false) {
            return "Lighter: ISO \(next)"
        }
        if settableProperty("shutspeedvalue") != nil, let next = adjacentValue("shutspeedvalue", brighter: false),
           await setProperty("shutspeedvalue", to: next, reportErrors: false) {
            return "Lighter: shutter \(PropertyFormat.display("shutspeedvalue", next))"
        }
        return nil
    }

    /// Ramping changes the shutter, so the camera has to let the app set it (M or S).
    var canRampExposure: Bool { settableProperty("shutspeedvalue") != nil }
}

// MARK: - Motion trigger

struct MotionTrigger: Equatable {
    var armed = false
    /// The box watched for movement, normalised to the frame.
    var region = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
    /// 0…1: higher fires on smaller changes.
    var sensitivity = 0.6
    /// Seconds to wait after a shot before firing again.
    var cooldown: Double = 3
    var shots = 0
    var lastTrigger: Date?
    /// The panel is open: show the box on live view even while disarmed, so it can be placed.
    var editing = false

    /// Share of the box (0…1) that has to change between frames to count as movement: 1% at the most
    /// sensitive, 15% at the least.
    var threshold: Double { 0.01 + (1 - sensitivity) * 0.14 }

    mutating func resize(to scale: Double) {
        let center = CGPoint(x: region.midX, y: region.midY)
        let size = CGSize(width: scale, height: scale)
        region = CGRect(x: min(max(center.x - size.width / 2, 0), 1 - size.width),
                        y: min(max(center.y - size.height / 2, 0), 1 - size.height),
                        width: size.width, height: size.height)
    }
}

extension CameraModel {
    /// Arms or disarms the trigger. It needs a timed shutter: Bulb and Live modes don't end on their own.
    func armMotion(_ on: Bool) {
        motion.armed = on && mode == .rec && !isOpenEndedShutter
        motionPrevious = nil
        motionLevel = 0
        if on { motion.shots = 0 }
    }

    /// Compares the trigger box with the last frame a few times a second and shoots when it changes.
    func analyzeMotion(_ image: UIImage) {
        let now = CACurrentMediaTime()
        guard now - motionAnalyzedAt > 0.12, let cg = image.cgImage else { return }
        motionAnalyzedAt = now
        guard let pixels = FrameMeter.grey(cg, region: motion.region, width: 32, height: 24) else { return }
        let previous = motionPrevious
        motionPrevious = pixels
        guard let previous, previous.count == pixels.count else { return }
        // The share of cells that clearly changed: a small subject counts as much as a big one
        // moving slightly, and JPEG noise (a few levels) doesn't count at all.
        let changed = zip(previous, pixels).reduce(0) { $0 + (abs(Int($1.0) - Int($1.1)) > 16 ? 1 : 0) }
        let change = Double(changed) / Double(pixels.count)
        if abs(change - motionLevel) > 0.005 { motionLevel = change }
        guard motion.armed, mode == .rec, !isShooting, !bracket.running, !interval.running, now >= motionQuietUntil,
              change > motion.threshold else { return }
        motion.shots += 1
        motion.lastTrigger = Date()
        // Live view hiccups around a capture; don't let that count as movement.
        motionQuietUntil = now + max(1.5, motion.cooldown)
        motionPrevious = nil
        Task {
            await shutterPressed()
            await shutterReleased()
        }
    }
}

// MARK: - Expose to the right

extension CameraModel {
    /// Raises the exposure until the brightest parts of live view are about to clip, then stops a
    /// step short: the most light the sensor can take without losing highlights. Uses exposure
    /// compensation (P, A, S) or the shutter speed (M).
    func exposeToTheRight() async {
        guard !ettrRunning, mode == .rec, !isShooting else { return }
        let name: String
        if settableProperty("expcomp") != nil {
            name = "expcomp"
        } else if settableProperty("shutspeedvalue") != nil {
            guard !isOpenEndedShutter else {
                lastError = "Expose to the right needs a timed shutter speed, not Bulb or a Live mode."
                return
            }
            name = "shutspeedvalue"
        } else {
            lastError = "Expose to the right needs exposure compensation (P, A or S) or a shutter speed the app can set (M)."
            return
        }
        ettrRunning = true
        defer { ettrRunning = false }
        let start = properties[name]?.value
        let limit = 0.004

        func measure() async -> (clip: Double, light: Double)? {
            // Let the change reach live view; after a shot it can take a few seconds to come back.
            try? await Task.sleep(for: .milliseconds(900))
            for _ in 0..<20 where recentFrame == nil { try? await Task.sleep(for: .milliseconds(200)) }
            guard let frame = recentFrame, let clip = FrameMeter.clipped(frame),
                  let light = FrameMeter.brightness(frame) else { return nil }
            return (clip, light)
        }
        func restore() async {
            if let start, properties[name]?.value != start { _ = await setProperty(name, to: start, reportErrors: false) }
        }

        guard let first = await measure() else {
            lastError = "Expose to the right needs live view."
            return
        }
        let firstLight = first.light
        let brighter = first.clip <= limit
        var steps = 0
        while steps < 15 {
            guard let next = adjacentValue(name, brighter: brighter) else { break }
            guard await setProperty(name, to: next, reportErrors: false) else { break }
            steps += 1
            guard let now = await measure() else { break }
            // Live view that doesn't follow the exposure can't show clipping.
            if brighter, steps == 2, now.light < firstLight * 1.08 {
                await restore()
                lastError = "Live view doesn't get brighter with the exposure, so the highlights can't be judged. Turn off Live View Boost (or exposure preview) on the camera and try again."
                return
            }
            if brighter, now.clip > limit {
                if let back = adjacentValue(name, brighter: false) { _ = await setProperty(name, to: back, reportErrors: false) }
                break
            }
            if !brighter, now.clip <= limit { break }
        }
        let value = PropertyFormat.display(name, properties[name]?.value ?? "")
        showToast(steps == 0 ? "Already at the limit: \(value)" : "Exposed to the right: \(value)")
    }
}

import SwiftUI

// Small read-outs and overlays that sit on top of live view.

/// Battery, shots left and warnings, from the camera's per-frame metadata.
struct CameraStatusRow: View {
    @Environment(CameraModel.self) private var camera

    var body: some View {
        let info = camera.liveInfo
        HStack(spacing: 10) {
            if let battery = info.battery {
                HStack(spacing: 4) {
                    Image(systemName: Self.batterySymbol(battery))
                        .symbolRenderingMode(.hierarchical)
                        .contentTransition(.symbolEffect(.replace))
                    Text("\(battery)%")
                        .contentTransition(.numericText(value: Double(battery)))
                }
                .foregroundStyle(battery <= 15 ? Color.red : .primary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Camera battery \(battery) percent")
            }
            if let shots = info.shotsRemaining {
                HStack(spacing: 4) {
                    Image(systemName: "photo.stack")
                    Text("\(shots)").contentTransition(.numericText(value: Double(shots)))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(shots) shots left on the card")
            }
            if info.temperatureWarning {
                Image(systemName: "thermometer.high")
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse)
                    .accessibilityLabel("Camera is hot")
            }
        }
        .font(.caption.monospacedDigit().weight(.medium))
        .animation(.snappy, value: info.battery)
        .animation(.snappy, value: info.shotsRemaining)
    }

    static func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// Live luminance histogram, drawn as a soft filled curve.
struct HistogramView: View {
    let values: [Float]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, v) in values.enumerated() {
                path.addLine(to: CGPoint(x: CGFloat(i) * step, y: size.height * (1 - CGFloat(min(max(v, 0), 1)))))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.85), .white.opacity(0.25)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            // Clipping warnings at either end.
            if let first = values.first, first > 0.6 {
                context.fill(Path(CGRect(x: 0, y: 0, width: 3, height: size.height)), with: .color(.blue.opacity(0.8)))
            }
            if let last = values.last, last > 0.6 {
                context.fill(Path(CGRect(x: size.width - 3, y: 0, width: 3, height: size.height)), with: .color(.red.opacity(0.8)))
            }
        }
        .accessibilityLabel("Histogram")
    }
}

/// Rule-of-thirds grid plus a horizon line, for composing.
struct CompositionGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for i in 1...2 {
                let x = size.width * CGFloat(i) / 3, y = size.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 0.75)
        }
        .allowsHitTesting(false)
    }
}

/// Interval timer (time-lapse / star stacking) setup and progress: in a sheet on a phone, in the
/// inspector on a large canvas.
struct IntervalPanel: View {
    @Environment(CameraModel.self) private var camera
    @AppStorage("interval.count") private var count = 60
    @AppStorage("interval.seconds") private var seconds = 20.0
    @AppStorage("interval.ramp") private var ramp = false
    @AppStorage("interval.maxISO") private var maxISO = 3200

    private var plan: IntervalPlan {
        IntervalPlan(count: count, seconds: seconds, ramp: ramp && camera.canRampExposure, maxISO: maxISO)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if camera.interval.running {
                progressCard
            } else {
                setupCards
            }
        }
        .animation(.smooth, value: camera.interval.running)
    }

    @ViewBuilder private var setupCards: some View {
        HStack(spacing: 8) {
            preset("Star stack", count: 30, seconds: 22)
            preset("Time-lapse", count: 240, seconds: 5)
            preset("Trails", count: 120, seconds: 32)
        }
        .padding(.bottom, 6)
        BigNumber(label: "Every", value: "\(Int(seconds)) s", caption: count == 0 ? "until you stop it" : "for \(count) frames", size: 88)
        VStack(spacing: 0) {
            Stepper(value: $seconds, in: 1...600, step: seconds < 10 ? 1 : 5) {
                LabeledContent("Every", value: "\(Int(seconds)) s")
            }
            .hairRow(minHeight: 56)
            Stepper(value: $count, in: 0...9999, step: count < 20 ? 1 : 10) {
                LabeledContent("Frames", value: count == 0 ? "Until stopped" : "\(count)")
            }
            .hairRow(minHeight: 56)
            note(summary)
            if let shutter = PropertyFormat.seconds(fromShutter: camera.properties["shutspeedvalue"]?.value ?? ""),
               shutter + 1 > seconds {
                Label("The interval is shorter than the exposure (\(Int(shutter)) s). Shots will run back to back.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .hairRow()
            }
            Toggle(isOn: $ramp) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow the light")
                    Text("Day to night (or night to day)").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
            .tint(Theme.accent)
            .disabled(!camera.canRampExposure)
            .hairRow(minHeight: 62)
            if ramp && camera.canRampExposure {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Highest ISO").font(.subheadline).foregroundStyle(Theme.secondary)
                    Picker("Highest ISO", selection: $maxISO) {
                        ForEach([1600, 3200, 6400, 12800], id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 12)
                .hairRow()
            }
            note(camera.canRampExposure
                 ? "Keeps live view as bright as when you start: as it gets dark the shutter gets longer (up to what the interval leaves room for), then the ISO goes up, a third of a stop at a time, and back at sunrise. Needs live view to show the exposure (Live View Boost off)."
                 : "Switch the camera to M so the app can change the shutter speed.")
        }
        Button {
            camera.startInterval(plan)
        } label: {
            Text("Start")
        }
        .buttonStyle(.accent)
        .disabled(camera.mode != .rec || camera.isOpenEndedShutter)
        .padding(.top, 8)
        if camera.isOpenEndedShutter {
            note("Interval shooting needs a timed shutter speed, not Live Composite/Time/Bulb.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .hairRow()
    }

    private var progressCard: some View {
        VStack(spacing: 18) {
            ProgressRing(text: "\(camera.interval.done)",
                         sub: camera.interval.total == 0 ? "shooting until stopped" : "of \(camera.interval.total)",
                         fraction: camera.interval.total > 0 ? Double(camera.interval.done) / Double(camera.interval.total) : 0)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let next = camera.interval.nextShotAt {
                    let left = max(0, Int(next.timeIntervalSince(context.date).rounded(.up)))
                    BigNumber(value: String(format: "%d:%02d", left / 60, left % 60),
                              caption: "Next shot in \(left) s", size: 72)
                } else {
                    BigNumber(value: "…", caption: "Exposing…", size: 72)
                }
            }
            if let note = camera.interval.rampNote {
                Text(note).font(.footnote).foregroundStyle(Theme.accent)
            }
            Button(role: .destructive) {
                camera.stopInterval()
            } label: {
                Text("Stop")
            }
            .buttonStyle(.outline)
        }
        .frame(maxWidth: .infinity)
    }

    private var summary: String {
        if count == 0 { return "Shoots every \(Int(seconds)) s until you tap Stop." }
        let total = Double(count) * seconds
        let duration = Duration.seconds(total).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
        return "\(count) frames over about \(duration). At 25 fps that's a \(String(format: "%.1f", Double(count) / 25)) s clip."
    }

    private func preset(_ title: String, count: Int, seconds: Double) -> some View {
        let on = self.count == count && self.seconds == seconds
        return Button(title) {
            withAnimation(.snappy) {
                self.count = count
                self.seconds = seconds
            }
        }
        .buttonStyle(ChipStyle(selected: on))
    }
}

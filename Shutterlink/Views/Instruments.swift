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
                    .foregroundStyle(.orange)
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

/// Interval timer (time-lapse / star stacking) setup and progress.
struct IntervalView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @AppStorage("interval.count") private var count = 60
    @AppStorage("interval.seconds") private var seconds = 20.0

    private var plan: IntervalPlan { IntervalPlan(count: count, seconds: seconds) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if camera.interval.running {
                        progressCard
                    } else {
                        setupCards
                    }
                }
                .padding(16)
                .animation(.smooth, value: camera.interval.running)
            }
            .navigationTitle("Interval timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var setupCards: some View {
        glassCard {
            Text("Presets").font(.headline)
            HStack(spacing: 8) {
                preset("Star stack", count: 30, seconds: 22)
                preset("Time-lapse", count: 240, seconds: 5)
                preset("Trails", count: 120, seconds: 32)
            }
        }
        glassCard {
            Stepper(value: $seconds, in: 1...600, step: seconds < 10 ? 1 : 5) {
                LabeledContent("Every", value: "\(Int(seconds)) s")
            }
            Stepper(value: $count, in: 0...9999, step: count < 20 ? 1 : 10) {
                LabeledContent("Frames", value: count == 0 ? "Until stopped" : "\(count)")
            }
            Text(summary).font(.footnote).foregroundStyle(.secondary)
            if let shutter = PropertyFormat.seconds(fromShutter: camera.properties["shutspeedvalue"]?.value ?? ""),
               shutter + 1 > seconds {
                Label("The interval is shorter than the exposure (\(Int(shutter)) s). Shots will run back to back.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        Button {
            camera.startInterval(plan)
        } label: {
            Label("Start", systemImage: "timer")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.accent)
        .tint(Theme.accent)
        .disabled(camera.mode != .rec || camera.isOpenEndedShutter)
        if camera.isOpenEndedShutter {
            Text("Interval shooting needs a timed shutter speed, not Live Composite/Time/Bulb.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var progressCard: some View {
        glassCard {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: camera.interval.total > 0
                              ? CGFloat(camera.interval.done) / CGFloat(camera.interval.total) : 0)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: camera.interval.done)
                    Text("\(camera.interval.done)")
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText(value: Double(camera.interval.done)))
                }
                .frame(width: 86, height: 86)
                VStack(alignment: .leading, spacing: 4) {
                    Text(camera.interval.total == 0 ? "Shooting until stopped" : "\(camera.interval.done) of \(camera.interval.total)")
                        .font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let next = camera.interval.nextShotAt {
                            Text("Next shot in \(max(0, Int(next.timeIntervalSince(context.date).rounded(.up)))) s")
                        } else {
                            Text("Exposing…")
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            Button(role: .destructive) {
                camera.stopInterval()
            } label: {
                Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.surface)
        }
    }

    private var summary: String {
        if count == 0 { return "Shoots every \(Int(seconds)) s until you tap Stop." }
        let total = Double(count) * seconds
        let duration = Duration.seconds(total).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
        return "\(count) frames over about \(duration). At 25 fps that's a \(String(format: "%.1f", Double(count) / 25)) s clip."
    }

    private func preset(_ title: String, count: Int, seconds: Double) -> some View {
        Button(title) {
            withAnimation(.snappy) {
                self.count = count
                self.seconds = seconds
            }
        }
        .buttonStyle(.surface)
        .controlSize(.small)
    }

    private func glassCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(.regular, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

import SwiftUI

/// The Watch remote: a small live view, the exposure, a self-timer and a big shutter.
/// The Digital Crown changes exposure compensation when the camera allows it.
struct WatchRemoteView: View {
    @Environment(PhoneLink.self) private var link
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selfTimer") private var selfTimer = 0
    @State private var crown = 0.0
    /// EV chosen with the crown and not yet confirmed by the camera.
    @State private var pendingEV: String?
    @State private var evSend: Task<Void, Never>?
    /// Self-timer started on this Watch: counts down at once, before the iPhone confirms it.
    @State private var localTimerEnds: Date?

    private var status: WatchStatus { link.status }

    var body: some View {
        Group {
            if link.phoneActive {
                remote
            } else {
                notConnected
            }
        }
        .onAppear { link.setPreview(true) }
        .onDisappear { link.setPreview(false) }
        .onChange(of: scenePhase) { _, phase in link.setPreview(phase == .active) }
        .onChange(of: status.evValue) { _, value in
            if pendingEV == nil || pendingEV == value { syncCrown(to: value) }
            if pendingEV == value { pendingEV = nil }
        }
    }

    // MARK: - Connected

    private var remote: some View {
        VStack(spacing: 5) {
            // Full width, up under the clock: the live view is the point of the screen.
            viewfinder
            values.padding(.horizontal, 4)
            controls.padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
        .focusable(status.evSettable)
        .digitalCrownRotation($crown, from: 0, through: Double(max(status.evOptions.count - 1, 1)), by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in crownMoved(to: value) }
        .onAppear { syncCrown(to: status.evValue) }
        #if DEBUG
        // `-crownSteps 2` turns the crown two clicks once EV can be set: the Simulator can't turn it.
        .task(id: status.evSettable) {
            let steps = UserDefaults.standard.integer(forKey: "crownSteps")
            guard steps != 0, status.evSettable else { return }
            try? await Task.sleep(for: .seconds(2))
            crown += Double(steps)
        }
        #endif
    }

    private var viewfinder: some View {
        ZStack {
            Color(white: 0.08)
            if let preview = link.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                Image(systemName: "camera.aperture")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            countdown
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomLeading) { readouts.padding(5) }
        .overlay(alignment: .top) {
            if let message = status.message ?? status.sequence {
                Text(message)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: .capsule)
                    .padding(.top, 34)   // below the clock
                    .padding(.horizontal, 6)
            }
        }
        .animation(.smooth, value: link.preview == nil)
    }

    private var readouts: some View {
        HStack(spacing: 6) {
            if let battery = status.battery {
                Label("\(battery)%", systemImage: battery < 20 ? "battery.25" : "battery.75")
            }
            if let shots = status.shotsLeft {
                Label("\(shots)", systemImage: "photo.stack")
            }
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize()
        .font(.system(size: 9, weight: .semibold).monospacedDigit())
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.black.opacity(0.55), in: .capsule)
    }

    /// Self-timer, exposure and video clocks, over the live view.
    @ViewBuilder private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            if let text = clockText(at: context.date) {
                Text(text)
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(status.recording ? Color.red : WatchTheme.accent)
                    .shadow(color: .black.opacity(0.7), radius: 3)
                    .contentTransition(.numericText(countsDown: true))
            }
        }
    }

    private func clockText(at now: Date) -> String? {
        if let ends = status.selfTimerEnds ?? localTimerEnds {
            let left = Int(ends.timeIntervalSince(now).rounded(.up))
            return left > 0 ? "\(left)" : nil
        }
        if status.recording, let start = status.movieStart { return clock(now.timeIntervalSince(start)) }
        if let start = status.exposureStart {
            if let duration = status.exposureDuration {
                let left = duration - now.timeIntervalSince(start)
                return left > 0 ? clock(left.rounded(.up)) : nil
            }
            return clock(now.timeIntervalSince(start))
        }
        return nil
    }

    private func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return total < 60 ? "\(total)" : String(format: "%d:%02d", total / 60, total % 60)
    }

    private var values: some View {
        HStack(spacing: 0) {
            value(status.aperture)
            value(status.shutter)
            value(status.iso.map { "ISO \($0)" })
            value(pendingEV.map(evLabel) ?? status.ev, highlighted: status.evSettable)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func value(_ text: String?, highlighted: Bool = false) -> some View {
        Text(text ?? "–")
            .foregroundStyle(highlighted ? WatchTheme.accent : .primary)
            .frame(maxWidth: .infinity)
            .accessibilityHint(highlighted ? "Turn the Digital Crown to change exposure compensation" : "")
    }

    private var controls: some View {
        HStack {
            Button {
                selfTimer = selfTimer == 0 ? 2 : (selfTimer == 2 ? 10 : 0)
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: selfTimer == 0 ? "timer" : "timer.circle.fill")
                    Text(selfTimer == 0 ? "Off" : "\(selfTimer)s").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(selfTimer == 0 ? Color.secondary : WatchTheme.accent)
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selfTimer == 0 ? "Self-timer off" : "Self-timer \(selfTimer) seconds")

            Spacer(minLength: 0)
            shutterButton
            Spacer(minLength: 0)

            Button {
                localTimerEnds = nil
                link.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .opacity(cancellable ? 1 : 0)
            .disabled(!cancellable)
            .accessibilityLabel("Cancel")
            .onChange(of: status.shots) { localTimerEnds = nil }
        }
    }

    private var cancellable: Bool {
        status.sequence != nil || status.selfTimerEnds != nil || (localTimerEnds.map { $0 > .now } ?? false)
    }

    /// A press stops a running Bulb exposure or video; otherwise it takes a picture.
    private var stops: Bool { status.recording || (status.openEnded && status.shooting) }

    private var shutterButton: some View {
        Button {
            let delay = stops ? 0 : selfTimer
            if delay > 0 { localTimerEnds = Date().addingTimeInterval(Double(delay)) }
            link.shutter(delay: delay)
        } label: {
            ZStack {
                Circle().stroke(.white.opacity(0.85), lineWidth: 3)
                if stops {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 20, height: 20)
                } else {
                    Circle()
                        .fill(status.movieMode ? Color.red : (status.shooting ? WatchTheme.accent : Color.white))
                        .padding(5)
                }
            }
            .frame(width: 50, height: 50)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!stops && !status.canShoot)
        .opacity(!stops && !status.canShoot ? 0.4 : 1)
        .accessibilityLabel(stops ? "Stop" : (status.movieMode ? "Record video" : "Take picture"))
    }

    // MARK: - Not connected

    private var notConnected: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 30))
                .foregroundStyle(WatchTheme.accent)
            Text(link.reachable && !link.stale
                 ? (status.message ?? "Connect PEN-F Remote on your iPhone to the camera.")
                 : "Open PEN-F Remote on your iPhone and connect to the camera.")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Text("The iPhone talks to the camera; this is its remote.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Digital Crown → EV

    private func syncCrown(to value: String?) {
        guard let value, let index = status.evOptions.firstIndex(of: value) else { return }
        if Int(crown.rounded()) != index { crown = Double(index) }
    }

    private func crownMoved(to position: Double) {
        guard status.evSettable, !status.evOptions.isEmpty else { return }
        let index = min(max(Int(position.rounded()), 0), status.evOptions.count - 1)
        let value = status.evOptions[index]
        guard value != (pendingEV ?? status.evValue) else { return }
        pendingEV = value
        // Wait until the crown stops before telling the camera.
        evSend?.cancel()
        evSend = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            link.setEV(value)
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled, pendingEV == value { pendingEV = nil }
        }
    }

    private func evLabel(_ value: String) -> String {
        Double(value) == 0 ? "±0.0" : value
    }
}

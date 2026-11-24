import SwiftUI
import UIKit

// MARK: - Exposure bracketing

struct BracketView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                BracketPanel()
                    .padding(16)
            }
            .navigationTitle("Bracketing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

/// The bracketing cards: in a sheet on a phone, in the inspector on a large canvas.
struct BracketPanel: View {
    @Environment(CameraModel.self) private var camera
    @AppStorage("bracket.frames") private var frames = 3
    @AppStorage("bracket.thirds") private var thirds = 3
    @AppStorage("bracket.target") private var targetRaw = BracketTarget.auto.rawValue
    @AppStorage("bracket.focus") private var focusMode = false
    @AppStorage("focusStack.frames") private var focusFrames = 10
    @AppStorage("focusStack.step") private var focusStepRaw = FocusStepSize.fine.rawValue

    private var plan: BracketPlan {
        BracketPlan(frames: frames, thirds: thirds, target: BracketTarget(rawValue: targetRaw) ?? .auto)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if camera.bracket.running {
                progressCard
            } else {
                Picker("Bracket", selection: $focusMode) {
                    Label("Exposure", systemImage: "plusminus.circle").tag(false)
                    Label("Focus", systemImage: "scope").tag(true)
                }
                .pickerStyle(.segmented)
                if focusMode {
                    focusCards
                } else {
                    setupCards
                }
            }
        }
        .animation(.smooth, value: camera.bracket.running)
    }

    @ViewBuilder private var setupCards: some View {
        glassCard {
            Text("Frames").font(.headline)
            Picker("Frames", selection: $frames) {
                ForEach([3, 5, 7, 9], id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Step").font(.headline)
            Picker("Step", selection: $thirds) {
                ForEach(1...6, id: \.self) { Text(BracketPanel.stepLabel($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Vary").font(.headline)
            Picker("Vary", selection: $targetRaw) {
                ForEach(BracketTarget.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Text(camera.properties["takemode"] == nil
                 ? "Auto varies EV. In M, choose Shutter: the app can't read this camera's mode dial."
                 : "Auto varies the shutter speed in M and exposure compensation in P, A and S.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        glassCard {
            Text("Will shoot").font(.headline)
            switch camera.bracketSet(plan) {
            case .success(let set):
                FlowRow(items: Array(zip(set.offsets, set.values).enumerated()), spacing: 6) { item in
                    let (offset, value) = item.element
                    VStack(spacing: 2) {
                        Text(CameraModel.offsetLabel(offset)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(PropertyFormat.display(set.property, value)).font(.caption.monospaced().weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .surface(.regular, in: .rect(cornerRadius: 10, style: .continuous))
                }
                if set.clamped {
                    Label("Some frames reach the end of the camera's range and repeat a value.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Text("The setting goes back to \(PropertyFormat.display(set.property, camera.properties[set.property]?.value ?? "")) afterwards.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        Button {
            camera.startBracket(plan)
        } label: {
            Label("Shoot \(frames) frames", systemImage: "square.stack.3d.down.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.accent)
        .tint(Theme.accent)
        .disabled(!camera.canBracket || (try? camera.bracketSet(plan).get()) == nil)
        if camera.isOpenEndedShutter {
            Text("Bracketing needs a timed shutter speed, not Bulb or Live modes.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Focus stacking

    @ViewBuilder private var focusCards: some View {
        if camera.capabilities.focusDrive {
            glassCard {
                Stepper(value: $focusFrames, in: 2...200) {
                    HStack {
                        Text("Frames").font(.headline)
                        Spacer()
                        Text("\(focusFrames)").font(.body.monospacedDigit().weight(.semibold))
                    }
                }
                Text("Step").font(.headline)
                Picker("Step", selection: $focusStepRaw) {
                    ForEach(FocusStepSize.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Text("Fine for macro and wide apertures, coarser for landscapes and stopped-down lenses. The stack stops early if the lens reaches infinity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            glassCard {
                Label("Before you start", systemImage: "lightbulb").font(.headline)
                Text(camera.focusStackSetup)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label("Not yet tried on a real camera of this brand: shoot a short stack first.", systemImage: "flask")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                camera.startFocusStack(frames: focusFrames, step: FocusStepSize(rawValue: focusStepRaw) ?? .fine)
            } label: {
                Label("Shoot \(focusFrames)-frame focus stack", systemImage: "square.stack.3d.forward.dottedline")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.accent)
            .tint(Theme.accent)
            .disabled(!camera.canFocusStack)
            if camera.isOpenEndedShutter {
                Text("Focus stacking needs a timed shutter speed, not Bulb or Live modes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            glassCard {
                Label("Use the camera's own focus bracketing", systemImage: "scope").font(.headline)
                Text(camera.focusStackUnavailable)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressCard: some View {
        glassCard {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: camera.bracket.total > 0
                              ? CGFloat(camera.bracket.done) / CGFloat(camera.bracket.total) : 0)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: camera.bracket.done)
                    Text("\(camera.bracket.done)/\(camera.bracket.total)")
                        .font(.headline.monospacedDigit())
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text(camera.bracket.isFocusStack ? "Focus stack" : "Bracketing").font(.headline)
                    if let label = camera.bracket.label {
                        Text(label).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    }
                    Button("Cancel", systemImage: "xmark", role: .destructive) { camera.cancelBracket() }
                        .buttonStyle(.surface)
                }
            }
        }
    }

    static func stepLabel(_ thirds: Int) -> String {
        switch thirds {
        case 1: "⅓"
        case 2: "⅔"
        case 3: "1"
        case 4: "1⅓"
        case 5: "1⅔"
        default: "2"
        }
    }

    private func glassCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(.regular, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// Simple wrapping row of chips.
private struct FlowRow<Item, Content: View>: View {
    let items: [Item]
    var spacing: CGFloat = 6
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        WrapLayout(spacing: spacing) {
            ForEach(items.indices, id: \.self) { content(items[$0]) }
        }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Timed bulb

/// "Stop after" for Bulb, Live Time and Live Composite: presets plus a custom length.
struct BulbTimerControl: View {
    @Environment(CameraModel.self) private var camera
    @State private var showCustom = false
    private let presets: [Double] = [0, 30, 60, 120, 300, 600]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STOP AFTER")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { seconds in
                        chip(seconds == 0 ? "Off" : Self.short(seconds), on: camera.bulbTimer == seconds) {
                            camera.bulbTimer = seconds
                        }
                    }
                    chip(presets.contains(camera.bulbTimer) ? "Other…" : Self.short(camera.bulbTimer),
                         on: !presets.contains(camera.bulbTimer)) { showCustom = true }
                }
            }
            .scrollClipDisabled()
        }
        .sensoryFeedback(.selection, trigger: camera.bulbTimer)
        .disabled(camera.isShooting)
        .sheet(isPresented: $showCustom) {
            BulbTimerSheet(seconds: camera.bulbTimer) { camera.bulbTimer = $0 }
                .presentationDetents([.height(320)])
        }
    }

    /// "30s", "2m", "2m30".
    static func short(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        return total % 60 == 0 ? "\(total / 60)m" : String(format: "%dm%02d", total / 60, total % 60)
    }

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(on ? Color.black : Color.white.opacity(0.8))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.1)), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct BulbTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    @State private var seconds: Int
    let onSet: (Double) -> Void

    init(seconds total: Double, onSet: @escaping (Double) -> Void) {
        let value = Int(total.rounded())
        _minutes = State(initialValue: value / 60)
        _seconds = State(initialValue: value % 60)
        self.onSet = onSet
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Minutes", selection: $minutes) {
                    ForEach(0...120, id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Seconds", selection: $seconds) {
                    ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { Text("\($0) s").tag($0) }
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle("Stop the exposure after")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set", systemImage: "checkmark") {
                        onSet(Double(minutes * 60 + seconds))
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Pocket mode

/// A black screen with a dim red read-out, for long night sessions with the phone in a pocket or
/// face up on the ground. The screen has to stay on: iOS stops the app's Wi-Fi when the phone locks.
struct PocketModeView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @State private var savedBrightness: CGFloat?
    /// The screen that was dimmed: on iPhone Duo, folding or unfolding moves the app to the other one.
    @State private var dimmedScreen: UIScreen?
    @State private var showHint = true

    private let red = Color(red: 0.75, green: 0.05, blue: 0.05)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 14) {
                    Text(headline(at: context.date))
                        .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
                    Text(detail(at: context.date))
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(red.opacity(0.55))
                .padding(.horizontal, 30)

                VStack {
                    Spacer()
                    if showHint {
                        Text("Keep the screen on: iOS pauses the app's Wi-Fi when the iPhone locks. For hours-long star trails, use the camera's own Live Composite or interval shooting instead.\n\nDouble-tap to leave.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(red.opacity(0.45))
                            .padding(.horizontal, 30)
                            .transition(.opacity)
                    } else {
                        Text("Double-tap to leave").font(.caption).foregroundStyle(red.opacity(0.25))
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { dismiss() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .background(WindowSceneReader { dim($0?.screen) })
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            if let savedBrightness, let dimmedScreen { dimmedScreen.brightness = savedBrightness }
        }
        .task {
            try? await Task.sleep(for: .seconds(8))
            withAnimation(.smooth(duration: 1.5)) { showHint = false }
        }
        .accessibilityAction(named: "Leave pocket mode") { dismiss() }
    }

    /// Dims the screen showing this view. When the scene moves to another screen (folding or
    /// unfolding an iPhone Duo), the old screen gets its brightness back and the new one is dimmed.
    private func dim(_ screen: UIScreen?) {
        guard screen !== dimmedScreen else { return }
        if let savedBrightness, let dimmedScreen { dimmedScreen.brightness = savedBrightness }
        savedBrightness = screen?.brightness
        dimmedScreen = screen
        screen?.brightness = 0.02
    }

    private func headline(at now: Date) -> String {
        if let started = camera.exposureStartedAt {
            let elapsed = now.timeIntervalSince(started)
            if let duration = camera.exposureDuration { return clock(max(0, duration - elapsed)) }
            return clock(elapsed)
        }
        if camera.isRecordingMovie, let started = camera.movieStartedAt { return clock(now.timeIntervalSince(started)) }
        if camera.interval.running, let next = camera.interval.nextShotAt { return clock(max(0, next.timeIntervalSince(now))) }
        if camera.bracket.running { return "\(camera.bracket.done)/\(camera.bracket.total)" }
        return "—"
    }

    private func detail(at now: Date) -> String {
        if camera.phase != .connected { return "Disconnected" }
        if camera.exposureStartedAt != nil {
            return camera.exposureDuration != nil ? "exposure left" : "exposing · tap the shutter to stop"
        }
        if camera.isRecordingMovie { return "recording" }
        if camera.interval.running {
            let total = camera.interval.total > 0 ? " of \(camera.interval.total)" : ""
            return "next frame · \(camera.interval.done)\(total) taken"
        }
        if camera.bracket.running { return "bracketing" }
        return "Ready · \(camera.liveInfo.battery.map { "battery \($0)%" } ?? "")"
    }

    private func clock(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded(.up)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

// MARK: - RAW download progress (card browser)

struct RawImportBar: View {
    @Environment(CameraModel.self) private var camera

    var body: some View {
        if let progress = camera.rawImport {
            HStack(spacing: 12) {
                if let message = progress.message {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Text(message).font(.footnote)
                    Spacer(minLength: 0)
                    Button("Close", systemImage: "xmark") { camera.rawImport = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.surfaceCircle)
                } else {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RAW \(min(progress.done + 1, progress.total)) of \(progress.total)").font(.footnote.weight(.semibold))
                        if let current = progress.current {
                            Text(current).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Stop", systemImage: "stop.fill", role: .destructive) { camera.cancelRawImport() }
                        .buttonStyle(.surface)
                }
            }
            .padding(12)
            .surface(.regular, in: .rect(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

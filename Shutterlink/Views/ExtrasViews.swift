import SwiftUI
import UIKit

// MARK: - Exposure bracketing

/// The bracketing cards: in a sheet on a phone, in the inspector on a large canvas.
struct BracketPanel: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
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
        VStack(alignment: .leading, spacing: 0) {
            if camera.bracket.running {
                progressCard
            } else {
                // 304/305: Exposure and Focus as two chips, white when chosen.
                HStack(spacing: 8) {
                    Button("Exposure") { withAnimation(.snappy) { focusMode = false } }
                        .buttonStyle(ChipStyle(selected: !focusMode))
                    Button("Focus") { withAnimation(.snappy) { focusMode = true } }
                        .buttonStyle(ChipStyle(selected: focusMode))
                }
                .padding(.bottom, 14)
                if focusMode {
                    focusCards
                } else {
                    setupCards
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.smooth, value: camera.bracket.running)
        .sensoryFeedback(.selection, trigger: focusMode)
    }

    @ViewBuilder private var setupCards: some View {
        BigNumber(value: "\(frames) × \(BracketPanel.stepLabel(thirds))",
                  caption: "\(frames) frames, \(BracketPanel.stepLabel(thirds)) stop\(thirds == 3 ? "" : "s") apart", size: 104)
            .padding(.bottom, 14)
        VStack(spacing: 0) {
            SegRow(label: "Frames", options: [3, 5, 7, 9], selection: $frames) { "\($0)" }
            SegRow(label: "Step", options: Array(1...6), selection: $thirds) { BracketPanel.stepLabel($0) }
            SegRow(label: "Vary", options: BracketTarget.allCases.map(\.rawValue), selection: $targetRaw) {
                BracketTarget(rawValue: $0)?.title ?? $0
            }
            NoteRow(camera.properties["takemode"] == nil
                    ? "Auto varies EV. In M, choose Shutter: the app can't read this camera's mode dial."
                    : "Auto varies the shutter speed in M and exposure compensation in P, A and S.")
        }
        .overlay(alignment: .top) { Hairline() }
        SectionLabel("Will shoot")
        switch camera.bracketSet(plan) {
        case .success(let set):
            // One box per frame: the offset over the value, the metered one outlined in the accent.
            HStack(spacing: 6) {
                ForEach(Array(zip(set.offsets, set.values).enumerated()), id: \.offset) { item in
                    let (offset, value) = item.element
                    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                    VStack(spacing: 2) {
                        Text(CameraModel.offsetLabel(offset)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Text(PropertyFormat.display(set.property, value)).font(.num(18)).foregroundStyle(Theme.text)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .overlay(shape.stroke(offset == 0 ? Theme.accent : Theme.outline, lineWidth: 1))
                }
            }
            NoteRow(set.clamped
                    ? "The setting goes back to \(PropertyFormat.display(set.property, camera.properties[set.property]?.value ?? "")) afterwards. Some frames reach the end of the camera's range and repeat a value."
                    : "The setting goes back to \(PropertyFormat.display(set.property, camera.properties[set.property]?.value ?? "")) afterwards.")
        case .failure(let error):
            NoteRow(error.localizedDescription, warning: true)
        }
        if camera.isOpenEndedShutter {
            NoteRow("Bracketing needs a timed shutter speed, not Bulb or Live modes.")
        }
        Spacer(minLength: 20)
        Button("Shoot \(frames) frames") { camera.startBracket(plan) }
            .buttonStyle(.accent)
            .disabled(!camera.canBracket || (try? camera.bracketSet(plan).get()) == nil)
            .padding(.bottom, 14)
    }

    // MARK: Focus stacking

    @ViewBuilder private var focusCards: some View {
        if camera.capabilities.focusDrive {
            BigNumber(value: "\(focusFrames)", caption: "frames, from where you focused towards infinity", size: 104)
                .padding(.bottom, 14)
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Frames").font(.system(size: 16, weight: .medium))
                        Text("2 to 200").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Stepper("Frames", value: $focusFrames, in: 2...200).labelsHidden()
                    Text("\(focusFrames)").font(.num(22, weight: .medium)).frame(minWidth: 36, alignment: .trailing)
                        .contentTransition(.numericText())
                }
                .frame(minHeight: 58)
                .overlay(alignment: .bottom) { Hairline() }
                SegRow(label: "Step", options: FocusStepSize.allCases.map(\.rawValue), selection: $focusStepRaw) {
                    FocusStepSize(rawValue: $0)?.title ?? "\($0)"
                }
                NoteRow("Fine for macro and wide apertures, coarser for landscapes and stopped-down lenses. The stack stops early if the lens reaches infinity.")
            }
            .overlay(alignment: .top) { Hairline() }
            SectionLabel("Before you start")
            NoteRow(camera.focusStackSetup)
            NoteRow("Not yet tried on a real camera of this brand: shoot a short stack first.", warning: true)
            if camera.isOpenEndedShutter {
                NoteRow("Focus stacking needs a timed shutter speed, not Bulb or Live modes.")
            }
            Spacer(minLength: 20)
            Button("Shoot \(focusFrames)-frame focus stack") {
                camera.startFocusStack(frames: focusFrames, step: FocusStepSize(rawValue: focusStepRaw) ?? .fine)
            }
            .buttonStyle(.accent)
            .disabled(!camera.canFocusStack)
            .padding(.bottom, 14)
        } else {
            // 307: the camera does it itself.
            SolidHeadline("Use the camera's own\nfocus bracketing", size: 44)
                .padding(.vertical, 12)
            Text(camera.focusStackUnavailable)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 20)
            Button("Done") { dismiss() }
                .buttonStyle(.outline)
                .padding(.bottom, 14)
        }
    }

    private var progressCard: some View {
        // 306: the frames as a fanned stack (the done ones lit), "3 of 10", the bars, Cancel at the bottom.
        VStack(spacing: 0) {
            if camera.bracket.isFocusStack {
                FocusStackArt(done: camera.bracket.done, total: max(1, camera.bracket.total))
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
            } else {
                ProgressRing(text: "\(camera.bracket.done)", sub: "of \(camera.bracket.total)",
                             fraction: camera.bracket.total > 0 ? Double(camera.bracket.done) / Double(camera.bracket.total) : 0)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            BigNumber(value: "\(camera.bracket.done) of \(camera.bracket.total)",
                      caption: camera.bracket.label ?? (camera.bracket.isFocusStack ? "Focus stack" : "Bracketing"), size: 72)
                .padding(.top, 8)
            FrameBars(done: camera.bracket.done, total: camera.bracket.total)
                .padding(.vertical, 18)
            Spacer(minLength: 20)
            Button(role: .destructive) { camera.cancelBracket() } label: { Text("Cancel") }
                .buttonStyle(.outline)
                .padding(.bottom, 14)
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
}

/// The frames of a focus stack fanned from near to far (306), the done ones in the accent.
struct FocusStackArt: View {
    let done: Int
    let total: Int

    var body: some View {
        Canvas { ctx, size in
            let count = min(total, 10)
            let w = size.width * 0.42, h = w * 0.62
            for i in (0..<count).reversed() {
                let t = Double(i) / Double(max(1, count - 1))
                let rect = CGRect(x: size.width * 0.18 + t * size.width * 0.34, y: size.height * 0.62 - t * size.height * 0.5 - h / 2,
                                  width: w, height: h)
                let lit = Int((Double(done) / Double(max(1, total)) * Double(count)).rounded(.down))
                let path = Path(roundedRect: rect, cornerRadius: 8)
                ctx.fill(path, with: .color(Theme.background))
                ctx.stroke(path, with: .color(i < lit ? Theme.accent : Theme.text.opacity(0.45 - t * 0.2)),
                           lineWidth: i < lit ? 2 : 1.2)
            }
            ctx.draw(Text("Near").font(.system(size: 11)).foregroundColor(Theme.secondary),
                     at: CGPoint(x: size.width * 0.16, y: size.height * 0.92))
            ctx.draw(Text("Far").font(.system(size: 11)).foregroundColor(Theme.secondary),
                     at: CGPoint(x: size.width * 0.86, y: size.height * 0.06))
        }
        .accessibilityHidden(true)
    }
}

/// Lays its views out in rows, wrapping to a new row when one is full.
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
        // 210: "STOP AFTER" in the accent, centred, over a row of chips (white when chosen).
        VStack(spacing: 8) {
            Text("STOP AFTER")
                .font(.system(size: 11, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Theme.accent)
            ViewThatFits(in: .horizontal) {
                chips
                ScrollView(.horizontal, showsIndicators: false) { chips }.scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: camera.bulbTimer)
        .disabled(camera.isShooting)
        .dPanelCover(isPresented: $showCustom, title: "Stop the exposure after") {
            BulbTimerSheet(seconds: camera.bulbTimer, onSet: { camera.bulbTimer = $0 }, close: { showCustom = false })
        }
    }

    private var chips: some View {
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

    /// "30s", "2m", "2m30".
    static func short(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        return total % 60 == 0 ? "\(total / 60)m" : String(format: "%dm%02d", total / 60, total % 60)
    }

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: on ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(on ? Theme.background : Theme.text)
                .padding(.horizontal, 10)
                .frame(minWidth: 34, minHeight: 34)
                .background(on ? AnyShapeStyle(Theme.text) : AnyShapeStyle(Color.black.opacity(0.25)), in: .capsule)
                .overlay(Capsule().stroke(on ? Color.clear : Theme.text.opacity(0.35), lineWidth: 1))
                .contentShape(.capsule.inset(by: -5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct BulbTimerSheet: View {
    @State private var minutes: Int?
    @State private var seconds: Int?
    let onSet: (Double) -> Void
    let close: () -> Void

    init(seconds total: Double, onSet: @escaping (Double) -> Void, close: @escaping () -> Void) {
        let value = Int(total.rounded())
        _minutes = State(initialValue: value / 60)
        _seconds = State(initialValue: (value % 60) / 5 * 5)
        self.onSet = onSet
        self.close = close
    }

    // 211: two Barlow wheels (minutes, seconds) between hairlines, then Set and Cancel.
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                WheelColumn(values: Array(0...120), unit: "min", selection: $minutes)
                WheelColumn(values: Array(stride(from: 0, through: 55, by: 5)), unit: "s", selection: $seconds)
            }
            .frame(height: 170)
            .overlay {
                VStack(spacing: 0) {
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    Spacer().frame(height: 46)
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                }
                .allowsHitTesting(false)
            }
            .padding(.top, 6)
            VStack(spacing: 10) {
                Button("Set") {
                    onSet(Double((minutes ?? 0) * 60 + (seconds ?? 0)))
                    close()
                }
                .buttonStyle(.accent)
                Button("Cancel", action: close)
                    .buttonStyle(.outline)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

/// One wheel of values: the chosen one large in Barlow in the middle, its neighbours smaller and dim.
struct WheelColumn: View {
    let values: [Int]
    let unit: String
    @Binding var selection: Int?
    /// What 0 reads as ("Until stopped"), where it means something else.
    var zeroText: String?
    private let row: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        let on = value == selection
                        Text(value == 0 && zeroText != nil ? zeroText! : (unit.isEmpty ? "\(value)" : "\(value) \(unit)"))
                            .font(.num(on ? 34 : 20, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? Theme.text : Theme.secondary)
                            .frame(maxWidth: .infinity, minHeight: row)
                            .id(value)
                            .onTapGesture { withAnimation(.snappy) { selection = value } }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.vertical, (geo.size.height - row) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection, anchor: .center)
            .sensoryFeedback(.selection, trigger: selection)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                                         .init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .accessibilityElement()
        .accessibilityLabel(unit == "min" ? "Minutes" : "Seconds")
        .accessibilityValue("\(selection ?? 0)")
        .accessibilityAdjustableAction { direction in
            guard let i = values.firstIndex(of: selection ?? 0) else { return }
            let next = direction == .increment ? i + 1 : i - 1
            if values.indices.contains(next) { selection = values[next] }
        }
    }
}

// MARK: - Pocket mode

/// A black screen with a dim red read-out, for long night sessions with the phone in a pocket or
/// face up on the ground. The screen has to stay on: iOS stops the app's Wi-Fi when the phone locks.
struct PocketModeView: View {
    @Environment(CameraModel.self) private var camera
    @Environment(\.dismiss) private var dismiss
    #if !targetEnvironment(macCatalyst)
    @State private var savedBrightness: CGFloat?
    /// The screen that was dimmed: on iPhone Duo, folding or unfolding moves the app to the other one.
    @State private var dimmedScreen: UIScreen?
    #endif
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
                        Text(Self.hint)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(red.opacity(0.45))
                            .padding(.horizontal, 30)
                            .transition(.opacity)
                    } else {
                        Text(Self.leave).font(.caption).foregroundStyle(red.opacity(0.25))
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { dismiss() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #if !targetEnvironment(macCatalyst)
        // A Mac app can't set the display's brightness; the black screen is as dark as it gets.
        .background(WindowSceneReader { dim($0?.screen) })
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            if let savedBrightness, let dimmedScreen { dimmedScreen.brightness = savedBrightness }
        }
        #endif
        .task {
            try? await Task.sleep(for: .seconds(8))
            withAnimation(.smooth(duration: 1.5)) { showHint = false }
        }
        .accessibilityAction(named: "Leave pocket mode") { dismiss() }
    }

    #if targetEnvironment(macCatalyst)
    private static let hint = "The Mac stays awake while Shutterlink is connected; the display may sleep. For hours-long star trails, use the camera's own Live Composite or interval shooting instead.\n\nDouble-click to leave."
    private static let leave = "Double-click to leave"
    #else
    private static let hint = "Keep the screen on: iOS pauses the app's Wi-Fi when the iPhone locks. For hours-long star trails, use the camera's own Live Composite or interval shooting instead.\n\nDouble-tap to leave."
    private static let leave = "Double-tap to leave"

    /// Dims the screen showing this view. When the scene moves to another screen (folding or
    /// unfolding an iPhone Duo), the old screen gets its brightness back and the new one is dimmed.
    private func dim(_ screen: UIScreen?) {
        guard screen !== dimmedScreen else { return }
        if let savedBrightness, let dimmedScreen { dimmedScreen.brightness = savedBrightness }
        savedBrightness = screen?.brightness
        dimmedScreen = screen
        screen?.brightness = 0.02
    }
    #endif

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
                            Text(current).font(.caption.monospaced()).foregroundStyle(Theme.secondary)
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

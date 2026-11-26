import SwiftUI

// Shutterlink's look, direction D: near-black, one warm accent for whatever is selected or live,
// Barlow Condensed for every number, hairlines instead of cards, capsule buttons, and nothing to tap
// smaller than 44 pt. The spec is docs/design/d-full-app/D-SPEC.md.

enum Theme {
    /// The one accent: selected, active, live, the primary button.
    static let accent = Color(hex: 0xF2C46D)
    /// Text and icons on the accent.
    static let onAccent = Color(hex: 0x0A0A0A)
    static let background = Color(hex: 0x0A0A0A)
    /// Dialogs, sheets, cards.
    static let surface = Color(hex: 0x161614)
    static let surfaceRaised = Color(hex: 0x1F1F1D)
    /// Hairline between rows; `outline` for a stronger edge (chips, outline buttons).
    static let stroke = Color(hex: 0x2C2C2A)
    static let outline = Color(hex: 0x3A3A37)
    static let text = Color(hex: 0xF4F1EA)
    static let secondary = Color(hex: 0xA9A8A2)
    static let tertiary = Color(hex: 0x8F8E88)
    /// Connected, done.
    static let green = Color(hex: 0x6CD39B)
    /// Recording, destructive, night.
    static let red = Color(hex: 0xFF5B4F)
    /// Astro screens.
    static let astroBackground = Color(hex: 0x05070D)
    static let astroText = Color(hex: 0xEEF1F7)
    static let astroAccent = Color(hex: 0x9CC0FF)

    /// Minimum touch target.
    static let target: CGFloat = 44
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Type

extension Font {
    /// Barlow Condensed for numbers, readouts and big headings (600 or 500).
    static func num(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(weight == .semibold || weight == .bold || weight == .heavy ? "BarlowCondensed-SemiBold" : "BarlowCondensed-Medium",
                size: size, relativeTo: style)
    }
}

/// Small-caps label above a readout ("SHUTTER", "ISO"): 11 pt, tracked, scales with Dynamic Type.
struct CapsLabel: View {
    let text: String
    var color: Color = Theme.secondary
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 11

    init(_ text: String, color: Color = Theme.secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .medium))
            .tracking(1.5)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// The app's wordmark: tracked capitals, as on a camera's top plate.
struct Wordmark: View {
    var size: CGFloat = 22

    var body: some View {
        Text("SHUTTERLINK")
            .font(.num(size * 1.15))
            .tracking(size * 0.2)
            .foregroundStyle(Theme.text)
            .accessibilityLabel("Shutterlink")
    }
}

/// The big number that opens a tool panel: a label in the accent, a very large Barlow value, a caption.
struct BigNumber: View {
    var label: String?
    let value: String
    var caption: String?
    var size: CGFloat = 104
    var color: Color = Theme.text
    var accent: Color = Theme.accent

    var body: some View {
        VStack(spacing: 4) {
            if let label { CapsLabel(label, color: accent) }
            Text(value)
                .font(.num(size))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Progress ring with the running number inside, for tools that run.
struct ProgressRing: View {
    let text: String
    var sub: String?
    var fraction: Double
    var color: Color = Theme.accent
    var size: CGFloat = 220

    var body: some View {
        ZStack {
            Circle().stroke(Theme.stroke, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: fraction)
            VStack(spacing: 2) {
                Text(text).font(.num(size * 0.345)).contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.4)
                if let sub { Text(sub).font(.footnote) }
            }
            .padding(.horizontal, 20)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text) \(sub ?? "")")
    }
}

// MARK: - Surfaces

/// How a surface is filled; mirrors the shape of SwiftUI's Glass API so call sites read the same.
struct SurfaceStyle {
    var tint: Color?
    /// Over the live image: darker and see-through, so the picture stays readable around it.
    var overImage = false

    static let regular = SurfaceStyle()
    /// For controls drawn on top of the live view.
    static let clear = SurfaceStyle(overImage: true)

    func tint(_ color: Color) -> SurfaceStyle {
        var style = self
        style.tint = color
        return style
    }
}

extension View {
    /// A flat surface with a hairline edge, in `shape`: for dialogs, chips and overlays.
    func surface<S: Shape>(_ style: SurfaceStyle = .regular, in shape: S) -> some View {
        background {
            ZStack {
                shape.fill(style.overImage ? Color.black.opacity(0.55) : Theme.surface)
                if let tint = style.tint { shape.fill(tint) }
                shape.stroke(Theme.stroke, lineWidth: 1)
            }
        }
    }

    /// A hairline under this row (the D replacement for cards).
    func hairRow(minHeight: CGFloat = 0) -> some View {
        frame(minHeight: minHeight)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    /// The sheet look: rounded top, near-black, a grabber. `ambient` puts the blurred live view behind
    /// it (as the design's full-height pages have), instead of flat black.
    func dSheet(ambient: Bool = false) -> some View {
        modifier(DSheet(ambient: ambient))
    }
}

/// The blurred live view behind a page when a camera is connected; plain black otherwise (Connect, Pro
/// from the connect screen).
struct AmbientBackground: View {
    @Environment(CameraModel.self) private var camera: CameraModel?

    var body: some View {
        if camera != nil {
            LiveBackdrop(style: .page)
        } else {
            Theme.background.ignoresSafeArea()
        }
    }
}

private struct DSheet: ViewModifier {
    let ambient: Bool
    func body(content: Content) -> some View {
        content
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground {
                if ambient { AmbientBackground() } else { Theme.background }
            }
    }
}

/// A block of controls: no card, just padding and a hairline under it, so panels read as lists.
func card<Content: View>(spacing: CGFloat = 12, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: spacing, content: content)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
}

// MARK: - Buttons

/// A secondary button: capsule, or circle for icon-only buttons. At least 44 × 44 pt.
struct SurfaceButtonStyle: ButtonStyle {
    var circle = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = circle ? AnyShape(Circle()) : AnyShape(Capsule())
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, circle ? 0 : 18)
            .frame(minWidth: Theme.target, minHeight: Theme.target)
            .background(shape.fill(configuration.isPressed ? Theme.surfaceRaised : Color.clear)
                .overlay(shape.stroke(Theme.outline, lineWidth: 1)))
            .contentShape(shape)
    }
}

/// The one filled button per screen: accent capsule, 54 pt.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Capsule().fill(isEnabled ? Theme.accent : Theme.accent.opacity(0.4)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.capsule)
    }
}

/// The alternative to the primary: a 54 pt capsule with a 1.5 pt outline.
struct OutlineButtonStyle: ButtonStyle {
    var color: Color = Theme.text
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 54)
            .overlay(Capsule().stroke(color, lineWidth: 1.5))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == SurfaceButtonStyle {
    static var surface: SurfaceButtonStyle { SurfaceButtonStyle() }
    static var surfaceCircle: SurfaceButtonStyle { SurfaceButtonStyle(circle: true) }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
}

/// A selectable chip: white-on-black when chosen, outlined when not.
struct ChipStyle: ButtonStyle {
    let selected: Bool
    /// Off inside a joined pill, which draws one outline round all its chips.
    var outlined = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.background : Theme.secondary)
            .padding(.horizontal, 16)
            .frame(minHeight: Theme.target)
            .background(Capsule().fill(selected ? Theme.text : Color.clear))
            .overlay(Capsule().stroke(selected || !outlined ? Color.clear : Theme.outline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.capsule)
    }
}

// MARK: - The curved dial

/// The one dial for every setting: a ruler bent along a big arc across the bottom of the screen, the
/// centre value under an accent pointer.
///
/// Feel (docs/design/04-motion-sound-haptics.md, item 1): the ruler follows the finger 1:1, coasts on
/// after a flick with the momentum projected from the release speed, and settles on a value with a
/// spring that doesn't bounce (a slight bounce only after a flick). A selection tick for every value it
/// passes, a firmer rigid tap on full stops and on 0 EV. With Reduce Motion it goes straight to the
/// nearest value. The value is committed once the dial has settled. Tap a label to go to it.
struct CurvedDial: View {
    /// The values, in order; `label` turns one into its text.
    let options: [String]
    let label: (String) -> String
    /// Whether a value is a full stop (longer tick, firmer haptic).
    var isMajor: (String) -> Bool = { _ in false }
    /// A value that gets the firm haptic as well (0 EV).
    var isAnchor: (String) -> Bool = { _ in false }
    @Binding var selection: String
    let onCommit: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the ruler is, in values (0 = first); nil when it rests on `selection`.
    @State private var position: Double?
    @State private var dragStart: Double?
    @State private var coast: Task<Void, Never>?
    @State private var haptics = DialHaptics()
    @State private var canvasWidth: CGFloat?

    private let radius: CGFloat = 420
    private let tickRadiusInset: CGFloat = 0
    /// Degrees between values: wider for named values (white balance, mode…) so their labels fit.
    /// Full stops among third stops (shutter, aperture, ISO, EV): full stops 10° apart and labelled,
    /// thirds as ticks between (201–204).
    private var stopScale: Bool { options.contains { isMajor($0) } && options.contains { !isMajor($0) } }

    private var step: Double {
        if stopScale { return 10.0 / 3 }
        let numeric = options.allSatisfy { label($0).contains { $0.isNumber } }
        if numeric { return 8 }
        // Named values 10° apart, as designed (206, 207); wider only when most labels are long. A label that
        // would still touch its neighbour is left out when drawn.
        let lengths = options.map { label($0).count }.sorted()
        let typical = lengths.isEmpty ? 4 : lengths[lengths.count / 2]
        // About 8.5 pt a character in Barlow Condensed 19 pt, 6.7 pt a degree at the label radius.
        return min(12, max(10, (Double(typical) * 8.5 + 14) / 6.7))
    }
    /// Finger travel for one value: the arc length between two ticks, so the ruler moves with the finger.
    private var pointsPerValue: CGFloat { radius * CGFloat(step * .pi / 180) }

    private var index: Int { options.firstIndex(of: selection) ?? 0 }
    private var current: Double { position ?? Double(index) }
    private var maxIndex: Double { Double(max(0, options.count - 1)) }

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size: size) }
            .frame(height: 112)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { canvasWidth = $0 }
            .contentShape(.rect)
            .gesture(drag)
            .simultaneousGesture(SpatialTapGesture().onEnded { tap($0.location) })
            .onDisappear { coast?.cancel() }
            .accessibilityElement()
            .accessibilityLabel("Dial")
            .accessibilityValue(label(selection))
            .accessibilityAdjustableAction { direction in
                let next = direction == .increment ? index + 1 : index - 1
                guard options.indices.contains(next) else { return }
                selection = options[next]
                haptics.passed(options[next], major: firm(options[next]))
                onCommit(selection)
            }
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let cx = size.width / 2
        let centre = CGPoint(x: cx, y: 26 + radius)
        let total = options.count
        let minor = max(0, Int((step / 2).rounded()) - 1)   // ticks about 2° apart, as designed
        func at(_ angle: Double, _ r: CGFloat) -> CGPoint {
            let rad = (angle - 90) * .pi / 180
            return CGPoint(x: centre.x + r * cos(rad), y: centre.y + r * sin(rad))
        }
        guard total > 0 else { return }
        let span = Int(62 / step) + 2
        let first = max(0, Int(current) - span), last = min(total - 1, Int(current) + span)
        if first <= last {
            for i in first...last {
                for m in 0...minor {
                    let value = Double(i) + Double(m) / Double(minor + 1)
                    if value > Double(total - 1) { continue }
                    let angle = (value - current) * step
                    if abs(angle) > 62 { continue }
                    let major = m == 0 && isMajor(options[i])
                    let len: CGFloat = m == 0 ? (major ? 16 : 13) : 9
                    var path = Path(); path.move(to: at(angle, radius - len)); path.addLine(to: at(angle, radius))
                    let fade = max(0.2, 1 - max(0, abs(angle) - 22) / 40)
                    ctx.stroke(path, with: .color(Theme.text.opacity((m == 0 ? 0.8 : 0.5) * fade)),
                               lineWidth: m == 0 ? 1.8 : 1.4)
                }
            }
        }
        // Labels, nearest the pointer first; one that would touch a label already drawn is left out,
        // so long names never run into each other. The value under the pointer is always drawn.
        var taken: [ClosedRange<Double>] = []
        let order = (first...max(first, last)).sorted { abs(Double($0) - current) < abs(Double($1) - current) }
        let labelRadius = radius - 40
        for i in order where i < total {
            let angle = (Double(i) - current) * step
            // Labels within about ±24° of the pointer, as designed; ticks run on to the edges.
            if abs(angle) > 25 { continue }
            let near = abs(Double(i) - current) < 0.5
            if stopScale, !near, !isMajor(options[i]) { continue }
            let text = ctx.resolve(Text(label(options[i]))
                .font(.num(near ? 22 : 19, weight: near ? .semibold : .medium))
                .foregroundColor(near ? Theme.text : Color(hex: 0xC9C5BA).opacity(max(0.5, 1 - abs(angle) / 50))))
            let width = text.measure(in: CGSize(width: 400, height: 60)).width
            let half = Double(width / 2 + 7) / Double(labelRadius * .pi / 180)
            let range = (angle - half)...(angle + half)
            if !near, taken.contains(where: { $0.overlaps(range) }) { continue }
            taken.append(range)
            var inner = ctx
            let pt = at(angle, labelRadius)
            inner.translateBy(x: pt.x, y: pt.y)
            inner.rotate(by: .degrees(angle))
            inner.draw(text, at: .zero, anchor: .center)
        }
        var tri = Path()
        tri.move(to: CGPoint(x: cx, y: 24)); tri.addLine(to: CGPoint(x: cx - 8, y: 2)); tri.addLine(to: CGPoint(x: cx + 8, y: 2)); tri.closeSubpath()
        ctx.fill(tri, with: .color(Theme.accent))
    }

    // MARK: Gestures

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { drag in
                if dragStart == nil {
                    coast?.cancel()
                    dragStart = current
                    haptics.prepare()
                }
                var p = (dragStart ?? 0) - Double(drag.translation.width / pointsPerValue)
                // Past either end the ruler gives a little, with resistance.
                if p < 0 { p = -rubber(-p) } else if p > maxIndex { p = maxIndex + rubber(p - maxIndex) }
                move(to: p)
            }
            .onEnded { drag in
                dragStart = nil
                let velocity = -Double(drag.velocity.width / pointsPerValue)   // values a second
                settle(from: current, velocity: velocity)
            }
    }

    /// A tap on a label turns the dial to it: the tap's angle from the arc's centre says which value.
    private func tap(_ location: CGPoint) {
        guard dragStart == nil, location.y > 30, let width = canvasWidth else { return }
        let dx = Double(location.x - width / 2), dy = Double(26 + radius - location.y)
        let angle = atan2(dx, dy) * 180 / .pi
        let target = min(maxIndex, max(0, (current + angle / step).rounded()))
        guard target != current.rounded() else { return }
        haptics.prepare()
        settle(from: current, velocity: 0, to: target)
    }

    /// A firm tap on full stops and 0 EV; a dial with no stops (white balance, mode) only ticks.
    private func firm(_ value: String) -> Bool {
        isAnchor(value) || (isMajor(value) && options.contains { !isMajor($0) })
    }

    private func rubber(_ over: Double) -> Double { 0.6 * (1 - 1 / (over * 0.8 + 1)) }

    /// Moves the ruler, with a haptic for each value it passes and the selection following.
    private func move(to p: Double) {
        let before = Int(current.rounded())
        position = p
        let now = Int(min(maxIndex, max(0, p)).rounded())
        guard now != before, options.indices.contains(now) else { return }
        // One tick per value passed, even when a fast drag skips several in a frame.
        let range = now > before ? Array((before + 1)...now) : Array((now...(before - 1)).reversed())
        for i in range.suffix(3) where options.indices.contains(i) {
            haptics.passed(options[i], major: firm(options[i]))
        }
        selection = options[now]
    }

    /// After a release: coast on the projected momentum, then spring onto a value and commit it.
    private func settle(from start: Double, velocity: Double, to fixed: Double? = nil) {
        coast?.cancel()
        let flick = abs(velocity) > 6
        // Where a scroll view would stop (deceleration rate 0.998 per ms), then the nearest value.
        let projected = reduceMotion ? start : start + velocity * 0.35
        let target = fixed ?? Double(Int(min(maxIndex, max(0, projected)).rounded()))
        if reduceMotion {
            move(to: target)
            position = nil
            commit()
            return
        }
        coast = Task { @MainActor in
            // A spring from where the finger left it, at the finger's speed: critically damped,
            // or a little under after a flick so it overshoots once and comes back.
            let response = flick ? 0.55 : 0.32
            let damping = flick ? 0.78 : 1.0
            let omega = 2 * Double.pi / response
            var x = start, v = velocity
            let dt = 1.0 / 120
            var clock = ContinuousClock.now
            for _ in 0..<480 {
                let a = -omega * omega * (x - target) - 2 * damping * omega * v
                v += a * dt
                x += v * dt
                move(to: x)
                if abs(x - target) < 0.002 && abs(v) < 0.02 { break }
                clock = clock.advanced(by: .milliseconds(8))
                try? await Task.sleep(until: clock, clock: .continuous)
                if Task.isCancelled { return }
            }
            move(to: target)
            position = nil
            commit()
        }
    }

    private func commit() {
        haptics.settled()
        onCommit(selection)
    }
}

/// The dial's haptics: a selection tick for each value, a rigid tap for full stops and 0 EV. Untested
/// on a phone so far (the simulator has no Taptic Engine).
@MainActor
final class DialHaptics {
    #if os(iOS)
    private let tick = UISelectionFeedbackGenerator()
    private let firm = UIImpactFeedbackGenerator(style: .rigid)
    private var lastFired = Date.distantPast
    #endif

    func prepare() {
        #if os(iOS)
        tick.prepare(); firm.prepare()
        #endif
    }

    func passed(_ value: String, major: Bool) {
        #if os(iOS)
        // The Taptic Engine blurs ticks closer than ~12 ms together; skip those rather than queue them.
        let now = Date()
        guard now.timeIntervalSince(lastFired) > 0.012 else { return }
        lastFired = now
        if major { firm.impactOccurred(intensity: 0.8) } else { tick.selectionChanged() }
        tick.prepare()
        #endif
    }

    func settled() {}
}

/// The big readout above the dial: the selected value's label in the accent and the value at 68 pt.
struct DialReadout: View {
    let label: String
    let value: String
    var locked = false

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .medium))
                .tracking(1.7)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
            Text(value)
                .font(.num(68))
                .foregroundStyle(locked ? Theme.secondary : Theme.text)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Full size always (design: 68 pt); only a very long value narrows it.
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 70)
        }
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
    }
}

private struct AstroPaletteKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Set inside the Astro sheet: its night-blue palette.
    var astroPalette: Bool {
        get { self[AstroPaletteKey.self] }
        set { self[AstroPaletteKey.self] = newValue }
    }
}

extension View {
    /// Lists in the app: no grouped grey, rows on the app background with hairline separators.
    func listRowBackgroundClear(ambient: Bool = false) -> some View {
        scrollContentBackground(.hidden)
            .background { if ambient { AmbientBackground() } else { Theme.background.ignoresSafeArea() } }
            .listRowSeparatorTint(Theme.stroke)
    }
}

// MARK: - Panels, screens and dialogs (drawn by the app, as designed)

/// The design's bottom panel (208, 209, 211, 219–221): edge to edge, rounded top corners, a grabber, a
/// hairline edge, the live view still visible above under a light scrim. Drawn by the app rather than
/// a system sheet, which iOS 26 floats with side margins. Drag the top down, tap above it or press
/// Escape to close; VoiceOver treats it as modal and its escape gesture closes it.
struct BottomPanel<Content: View>: View {
    var title: String?
    /// The scrim and its tap; off where the picture above must stay usable (the motion trigger).
    var dimsBehind = true
    let onClose: () -> Void
    @ViewBuilder var content: Content
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            if dimsBehind {
                LiveBackdrop.wash.opacity(0.3)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Capsule().fill(Color(hex: 0x4A4946)).frame(width: 40, height: 5).padding(.top, 8)
                    if let title {
                        HStack {
                            Text(title).font(.num(26)).foregroundStyle(Theme.text)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button(action: onClose) {
                                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                                    .frame(width: Theme.target, height: Theme.target)
                            }
                            .accessibilityLabel("Close")
                        }
                        .padding(.leading, 20).padding(.trailing, 8)
                        .frame(minHeight: 48)
                    }
                }
                .contentShape(.rect)
                .gesture(DragGesture()
                    .onChanged { drag = max(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height > 90 || value.predictedEndTranslation.height > 220 { onClose() }
                        withAnimation(.spring(duration: 0.3, bounce: 0)) { drag = 0 }
                    })
                // As tall as the content, scrolling only when it can't fit.
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView { content }.scrollIndicators(.hidden)
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .fill(Theme.background)
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                        .stroke(Theme.outline, lineWidth: 1))
                    .frame(maxWidth: 640)
                    .ignoresSafeArea(edges: .bottom)
            }
            .offset(y: drag)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onClose)
            .transition(.move(edge: .bottom))
            // Never so tall that the live view goes from above it.
            .padding(.top, 120)
        }
        .onKeyPress(.escape) { onClose(); return .handled }
    }
}

extension View {
    /// Shows `content` in the app's bottom panel while `isPresented`.
    func dPanel<Content: View>(isPresented: Binding<Bool>, title: String? = nil, dimsBehind: Bool = true,
                               @ViewBuilder content: @escaping () -> Content) -> some View {
        overlay {
            ZStack {
                if isPresented.wrappedValue {
                    BottomPanel(title: title, dimsBehind: dimsBehind,
                                onClose: { withAnimation(.spring(duration: 0.32, bounce: 0)) { isPresented.wrappedValue = false } },
                                content: content)
                }
            }
            .animation(.spring(duration: 0.32, bounce: 0), value: isPresented.wrappedValue)
        }
    }

    /// A design screen (3xx, 4xx, 105, 106): full screen on a phone, a page-sized sheet on a large canvas.
    func dScreen<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(DScreen(isPresented: isPresented, screen: content))
    }

    func dScreen<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        dScreen(isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })) {
            if let value = item.wrappedValue { content(value) }
        }
    }
}

extension View {
    /// The bottom panel from anywhere: a clear full-screen cover hosting the same panel, for controls
    /// nested deep in a screen (Stop after's custom time).
    func dPanelCover<Content: View>(isPresented: Binding<Bool>, title: String? = nil,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        fullScreenCover(isPresented: isPresented) {
            PanelCoverHost(title: title, close: { isPresented.wrappedValue = false }, content: content)
                .presentationBackground(.clear)
        }
        .transaction { $0.disablesAnimations = true }
    }
}

private struct PanelCoverHost<Content: View>: View {
    let title: String?
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var shown = false

    var body: some View {
        ZStack {
            if shown {
                BottomPanel(title: title, onClose: dismiss, content: content)
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0), value: shown)
        .onAppear { shown = true }
    }

    private func dismiss() {
        shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction, close)
        }
    }
}

private struct DScreen<Screen: View>: ViewModifier {
    @Binding var isPresented: Bool
    let screen: () -> Screen
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.sheet(isPresented: $isPresented) {
                screen().presentationSizing(.page).presentationBackground(Theme.background)
            }
        } else {
            content.fullScreenCover(isPresented: $isPresented) { screen() }
        }
    }
}

/// The header of a design screen: the title on the left in 15 pt semibold, an action on the right
/// (Done, Close), 44 pt tall. Optional leading item (Back, Reload, Cancel).
struct ScreenHeader<Leading: View, Trailing: View>: View {
    let title: String
    var centred = false
    var titleSize: CGFloat = 15
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            if centred {
                Text(title).font(.system(size: titleSize, weight: .semibold)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: 12) {
                leading
                if !centred {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                trailing
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: Theme.target)
    }
}

extension ScreenHeader {
    init(_ title: String, centred: Bool = false, titleSize: CGFloat = 15,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.centred = centred; self.titleSize = titleSize
        self.leading = leading(); self.trailing = trailing()
    }
}

extension ScreenHeader where Leading == EmptyView {
    init(_ title: String, centred: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.centred = centred; self.leading = EmptyView(); self.trailing = trailing()
    }
}

/// A plain text button for headers: 15 pt, white (or secondary), 44 pt target.
struct HeaderButton: View {
    let title: String
    var color: Color = Theme.text
    let action: () -> Void

    init(_ title: String, color: Color = Theme.text, action: @escaping () -> Void) {
        self.title = title; self.color = color; self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 15))
            .foregroundStyle(color)
            .frame(minWidth: Theme.target, minHeight: Theme.target)
            .contentShape(.rect)
            .buttonStyle(.plain)
    }
}

/// The design's dialog card (226): a dark card over a scrim, Barlow title, message, a coloured
/// capsule for the action and Cancel under it. Modal for VoiceOver; Escape or the scrim cancels.
struct DialogCard: View {
    let title: String
    var message: String?
    let action: String
    var actionColor: Color = Theme.red
    /// The compact form (Disconnect): title and a small white button on one line.
    var compact = false
    let onAction: () -> Void
    let onCancel: () -> Void
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        ZStack {
            LiveBackdrop.wash.opacity(0.7).ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            Group {
                if compact {
                    HStack(spacing: 12) {
                        Text(title).font(.num(24)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($focused)
                        Spacer(minLength: 0)
                        Button(action: onAction) {
                            Text(action).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.background)
                                .padding(.horizontal, 18).frame(minHeight: Theme.target)
                                .background(Capsule().fill(Theme.text))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    // As designed there's no Cancel button: a tap outside, Escape, or VoiceOver's
                    // escape gesture (or this action) cancels.
                    .accessibilityAction(named: "Cancel", onCancel)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title).font(.num(28)).foregroundStyle(Theme.text)
                            .accessibilityFocused($focused)
                        if let message {
                            Text(message).font(.system(size: 15)).foregroundStyle(Theme.secondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer().frame(height: 6)
                        Button(action: onAction) {
                            Text(action).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.background)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Capsule().fill(actionColor))
                        }
                        .buttonStyle(.plain)
                        Button(action: onCancel) {
                            Text("Cancel").font(.system(size: 16)).foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                }
            }
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.outline, lineWidth: 1))
            .frame(maxWidth: 420)
            .padding(.horizontal, 28)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onCancel)
            // The compact card sits near the top (226), the full one a little above the middle.
            .frame(maxHeight: .infinity, alignment: compact ? .top : .center)
            .padding(.top, compact ? 66 : 0)
            .padding(.bottom, compact ? 0 : 60)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onAppear { focused = true }
    }
}

/// A Barlow headline set solid (line height about 0.9, as the designs' big headings): one line per
/// `\n`, pulled together, since SwiftUI ignores negative line spacing.
struct SolidHeadline: View {
    let text: String
    let size: CGFloat
    var color: Color = Theme.text
    var leading: CGFloat = 0.9

    init(_ text: String, size: CGFloat, color: Color = Theme.text, leading: CGFloat = 0.9) {
        self.text = text; self.size = size; self.color = color; self.leading = leading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.num(size, relativeTo: .largeTitle))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(height: size * leading, alignment: .center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " "))
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Rows of the tool screens (dkit: seg, pair, row)

/// A setting with a few choices on one hairline row (304: Frames 3 5 7 9): the label left in 13 pt,
/// the choices right in Barlow, the chosen one in the accent with an accent underline.
struct SegRow<Value: Hashable>: View {
    let label: String
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    let on = option == selection
                    Button { withAnimation(.snappy) { selection = option } } label: {
                        Text(title(option))
                            .font(.num(18, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? Theme.accent : Theme.secondary)
                            .padding(.horizontal, 9)
                            .frame(minHeight: Theme.target)
                            .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.accent).frame(height: 2) } }
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label) \(title(option))")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) { Hairline() }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Two or three values side by side (301: Every 5 s · Frames 240): a 12 pt label over a 30 pt Barlow value.
struct PairRow: View {
    struct Cell: Identifiable {
        let label: String
        let value: String
        var action: (() -> Void)?
        var id: String { label }
    }
    let cells: [Cell]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                let alignment: HorizontalAlignment = index == 0 ? .leading : (index == cells.count - 1 ? .trailing : .center)
                let content = VStack(alignment: alignment, spacing: 2) {
                    Text(cell.label).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Text(cell.value).font(.num(30)).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                if let action = cell.action {
                    Button(action: action) { content.contentShape(.rect) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(cell.label) \(cell.value)")
                        .accessibilityHint("Changes it")
                } else {
                    content.accessibilityElement(children: .combine)
                }
            }
        }
        .frame(minHeight: 78)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// A plain note between hairlines (dkit `note`): 13 pt secondary.
struct NoteRow: View {
    let text: String
    var color: Color = Theme.secondary
    var warning = false

    init(_ text: String, color: Color = Theme.secondary, warning: Bool = false) {
        self.text = text; self.color = color; self.warning = warning
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if warning {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 14, weight: .semibold))
            }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13))
        .lineSpacing(2)
        .foregroundStyle(warning ? Theme.accent : color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// A section label inside a tool screen ("WILL SHOOT"): 11 pt tracked capitals, space above.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        CapsLabel(text).padding(.top, 18).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

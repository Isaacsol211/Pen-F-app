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

    /// The sheet look: rounded top, near-black, a strong hairline edge, a grabber.
    func dSheet() -> some View {
        presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(Theme.background)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.background : Theme.secondary)
            .padding(.horizontal, 16)
            .frame(minHeight: Theme.target)
            .background(Capsule().fill(selected ? Theme.text : Color.clear))
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.outline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.capsule)
    }
}

// MARK: - The curved dial

/// The one dial for every setting: a ruler bent along a big arc across the bottom of the screen, the
/// centre value under an accent pointer. Drag or tap to move; the value is committed when you let go.
struct CurvedDial: View {
    /// The values, in order; `label` turns one into its text.
    let options: [String]
    let label: (String) -> String
    /// Whether a value is a full stop (gets a longer tick).
    var isMajor: (String) -> Bool = { _ in false }
    @Binding var selection: String
    let onCommit: (String) -> Void

    @State private var position: Double?
    @State private var dragStart: Double?

    private let step = 8.0           // degrees between values
    private let minorPerStep = 3     // extra ticks between values
    private let radius: CGFloat = 420
    private let pointsPerValue: CGFloat = 38

    private var index: Int { options.firstIndex(of: selection) ?? 0 }
    private var current: Double { position ?? Double(index) }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = 26 + radius
            let centre = CGPoint(x: cx, y: cy)
            // Ticks
            let total = options.count
            let first = max(0, Int(current) - 14), last = min(total - 1, Int(current) + 14)
            if total > 0, first <= last {
                for i in first...last {
                    for m in 0..<minorPerStep + 1 {
                        let value = Double(i) + Double(m) / Double(minorPerStep + 1)
                        if value > Double(total - 1) { continue }
                        let angle = (value - current) * step
                        if abs(angle) > 62 { continue }
                        let rad = (angle - 90) * .pi / 180
                        let major = m == 0 && isMajor(options[i])
                        let len: CGFloat = m == 0 ? (major ? 16 : 11) : 6
                        let p0 = CGPoint(x: centre.x + (radius - len) * cos(rad), y: centre.y + (radius - len) * sin(rad))
                        let p1 = CGPoint(x: centre.x + radius * cos(rad), y: centre.y + radius * sin(rad))
                        var path = Path(); path.move(to: p0); path.addLine(to: p1)
                        let fade = max(0.15, 1 - abs(angle) / 70)
                        ctx.stroke(path, with: .color(Theme.text.opacity((m == 0 ? 0.75 : 0.4) * fade)), lineWidth: m == 0 ? 1.6 : 1)
                    }
                    // Label
                    let angle = (Double(i) - current) * step
                    if abs(angle) <= 28 {
                        let rad = (angle - 90) * .pi / 180
                        let r = radius - 38
                        let pt = CGPoint(x: centre.x + r * cos(rad), y: centre.y + r * sin(rad))
                        let near = abs(Double(i) - current) < 0.5
                        let text = Text(label(options[i]))
                            .font(.num(near ? 22 : 19, weight: near ? .semibold : .medium))
                            .foregroundColor(near ? Theme.text : Color(hex: 0xC9C5BA).opacity(max(0.25, 1 - abs(angle) / 30)))
                        var inner = ctx
                        inner.translateBy(x: pt.x, y: pt.y)
                        inner.rotate(by: .degrees(angle))
                        inner.draw(ctx.resolve(text), at: .zero, anchor: .center)
                    }
                }
            }
            // Pointer
            var tri = Path()
            tri.move(to: CGPoint(x: cx, y: 24)); tri.addLine(to: CGPoint(x: cx - 8, y: 2)); tri.addLine(to: CGPoint(x: cx + 8, y: 2)); tri.closeSubpath()
            ctx.fill(tri, with: .color(Theme.accent))
        }
        .frame(height: 140)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { drag in
                    if dragStart == nil { dragStart = Double(index) }
                    let moved = -Double(drag.translation.width / pointsPerValue)
                    position = min(Double(options.count - 1), max(0, (dragStart ?? 0) + moved))
                    if let p = position {
                        let i = Int(p.rounded())
                        if options.indices.contains(i), options[i] != selection { selection = options[i] }
                    }
                }
                .onEnded { _ in
                    dragStart = nil
                    withAnimation(.snappy(duration: 0.2)) { position = nil }
                    onCommit(selection)
                }
        )
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.snappy(duration: 0.18), value: selection)
        .accessibilityElement()
        .accessibilityLabel("Dial")
        .accessibilityValue(label(selection))
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment ? index + 1 : index - 1
            guard options.indices.contains(next) else { return }
            selection = options[next]
            onCommit(selection)
        }
    }
}

/// The big readout above the dial: the selected value's label in the accent and the value at 68 pt.
struct DialReadout: View {
    let label: String
    let value: String
    var locked = false

    var body: some View {
        VStack(spacing: 2) {
            CapsLabel(label, color: Theme.accent)
            Text(value)
                .font(.num(68))
                .foregroundStyle(locked ? Theme.secondary : Theme.text)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
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
    func listRowBackgroundClear() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
            .listRowSeparatorTint(Theme.stroke)
    }
}

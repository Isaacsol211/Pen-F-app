import SwiftUI

// Shutterlink's look: a pro-camera instrument panel. Pure black, solid surfaces with a hairline
// edge instead of glass, one accent colour (amber) for whatever is selected or live, big
// monospaced readouts, small-caps labels, and nothing to tap smaller than 44 pt.

enum Theme {
    /// The one accent: selected, active, live.
    static let accent = Color(red: 1.0, green: 0.69, blue: 0.16)
    /// Text and icons on the accent.
    static let onAccent = Color.black
    static let background = Color.black
    /// Panels, cells and buttons.
    static let surface = Color(white: 0.085)
    static let surfaceRaised = Color(white: 0.13)
    static let stroke = Color.white.opacity(0.13)
    /// Secondary text: 0.74 white keeps it above 4.5:1 on the surfaces.
    static let secondary = Color.white.opacity(0.74)
    static let tertiary = Color.white.opacity(0.55)

    // Older names, kept so every view reads the same tokens.
    static let panel = surface
    static let hairline = stroke

    /// Minimum touch target.
    static let target: CGFloat = 44
}

// MARK: - Surfaces (the app's replacement for glass)

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

    /// Accepted for symmetry with Glass; surfaces don't change while pressed.
    func interactive(_ isEnabled: Bool = true) -> SurfaceStyle { self }
}

extension View {
    /// A solid instrument-panel surface with a hairline edge, in `shape`.
    func surface<S: Shape>(_ style: SurfaceStyle = .regular, in shape: S) -> some View {
        background {
            ZStack {
                shape.fill(style.overImage ? Color.black.opacity(0.62) : Theme.surface)
                if let tint = style.tint { shape.fill(tint) }
                shape.stroke(Theme.stroke, lineWidth: 1)
            }
        }
    }
}

// MARK: - Buttons

/// A dark surface button: capsule, or circle for icon-only buttons. At least 44 × 44 pt.
struct SurfaceButtonStyle: ButtonStyle {
    var circle = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, circle ? 0 : 16)
            .frame(minWidth: Theme.target, minHeight: Theme.target)
            .background {
                if circle {
                    Circle().fill(configuration.isPressed ? Theme.surfaceRaised : Theme.surface)
                        .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                } else {
                    Capsule().fill(configuration.isPressed ? Theme.surfaceRaised : Theme.surface)
                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                }
            }
            .contentShape(circle ? AnyShape(Circle()) : AnyShape(Capsule()))
    }
}

/// The one filled button per screen: amber with black text.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 20)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEnabled ? Theme.accent : Theme.accent.opacity(0.45))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.rect(cornerRadius: 16))
    }
}

extension ButtonStyle where Self == SurfaceButtonStyle {
    static var surface: SurfaceButtonStyle { SurfaceButtonStyle() }
    static var surfaceCircle: SurfaceButtonStyle { SurfaceButtonStyle(circle: true) }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}

// MARK: - Type

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
            .font(.system(size: size, weight: .semibold))
            .tracking(1.1)
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
            .font(.system(size: size, weight: .heavy))
            .tracking(size * 0.16)
            .foregroundStyle(.white)
            .accessibilityLabel("Shutterlink")
    }
}

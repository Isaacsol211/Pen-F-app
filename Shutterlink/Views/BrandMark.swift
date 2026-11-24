import SwiftUI

/// The Shutterlink aperture mark: the same flat drawing as the app icon and launch screen
/// (tools/make_icon.swift), drawn live so it stays sharp at any size.
struct ApertureMark: View {
    /// Opening radius as a fraction of the blade radius (0.41 is the icon).
    var opening: Double = 0.41
    /// The amber Wi-Fi arcs off the ring's top-right.
    var showsLink = true
    /// Outline-only rendering in one colour (for faint backgrounds).
    var monochrome: Color?

    private static let seam = Color.black
    private static let lightBlade = Color(red: 0.95, green: 0.953, blue: 0.96)
    private static let darkBlade = Color(red: 0.80, green: 0.82, blue: 0.85)

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            // Same layout as the launch mark: drawn in a 1024 box, mark centred at 45.5 %, y up.
            let k = side / 1024 * 1.12
            ctx.translateBy(x: (size.width - side) / 2, y: (size.height + side) / 2)
            ctx.scaleBy(x: 1, y: -1)
            draw(in: &ctx, center: CGPoint(x: side * 0.455, y: side * 0.455), k: k)
        }
        .accessibilityHidden(true)
    }

    private func draw(in ctx: inout GraphicsContext, center c: CGPoint, k: CGFloat) {
        func circle(_ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: c.x - r * k, y: c.y - r * k, width: 2 * r * k, height: 2 * r * k))
        }
        let accent = monochrome ?? Theme.accent
        if monochrome == nil { ctx.fill(circle(340), with: .color(Self.seam)) }
        ctx.stroke(circle(312), with: .color(accent), lineWidth: (monochrome == nil ? 30 : 10) * k)

        let outer = 276 * k
        let inner = outer * max(0.05, min(opening, 0.6))
        let rotation = Double.pi / 12
        let vertices = (0..<6).map { i -> CGPoint in
            let a = rotation + Double(i) * .pi / 3
            return CGPoint(x: c.x + inner * cos(a), y: c.y + inner * sin(a))
        }
        func rim(_ i: Int) -> CGPoint {
            let a = vertices[(i + 5) % 6], b = vertices[i]
            let len = hypot(b.x - a.x, b.y - a.y)
            let d = CGPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len)
            let p = CGPoint(x: b.x - c.x, y: b.y - c.y)
            let dot = p.x * d.x + p.y * d.y
            let t = -dot + sqrt(max(0, dot * dot - (p.x * p.x + p.y * p.y - outer * outer)))
            return CGPoint(x: b.x + t * d.x, y: b.y + t * d.y)
        }
        for i in 0..<6 {
            let p0 = rim(i), p1 = rim((i + 1) % 6)
            var blade = Path()
            blade.move(to: vertices[i])
            blade.addLine(to: p0)
            blade.addArc(center: c, radius: outer, startAngle: .radians(atan2(p0.y - c.y, p0.x - c.x)),
                         endAngle: .radians(atan2(p1.y - c.y, p1.x - c.x)), clockwise: false)
            blade.addLine(to: vertices[(i + 1) % 6])
            blade.closeSubpath()
            if let monochrome {
                ctx.stroke(blade, with: .color(monochrome), lineWidth: 6 * k)
                continue
            }
            ctx.fill(blade, with: .color(i % 2 == 0 ? Self.lightBlade : Self.darkBlade))
            ctx.stroke(blade, with: .color(Self.seam), style: StrokeStyle(lineWidth: 12 * k, lineJoin: .round))
        }
        if monochrome == nil {
            var hole = Path()
            hole.addLines(vertices)
            hole.closeSubpath()
            ctx.fill(hole, with: .color(accent))
            ctx.stroke(hole, with: .color(Self.seam), lineWidth: 12 * k)
        }
        if showsLink {
            let origin = CGPoint(x: c.x + 250 * k, y: c.y + 250 * k)
            for r in [104.0, 176.0] {
                var arc = Path()
                arc.addArc(center: origin, radius: r * k, startAngle: .radians(.pi * 0.06),
                           endAngle: .radians(.pi * 0.44), clockwise: false)
                ctx.stroke(arc, with: .color(accent), style: StrokeStyle(lineWidth: 46 * k, lineCap: .round))
            }
        }
    }
}

/// Mark + wordmark, as at the top of the Connect screen.
struct BrandLockup: View {
    var markSize: CGFloat = 48

    var body: some View {
        HStack(spacing: 12) {
            ApertureMark()
                .frame(width: markSize, height: markSize)
            Wordmark(size: markSize * 0.42)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shutterlink")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Continues the launch screen: the same mark, same place, on the same black, then fades away so
/// the app appears without the mark jumping.
struct LaunchHandoff: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shown once per launch.
    @MainActor static var shown = false
    @State private var visible = !LaunchHandoff.shown
    @State private var leaving = false

    var body: some View {
        if visible {
            ZStack {
                Theme.background.ignoresSafeArea()
                ApertureMark()
                    .frame(width: 180, height: 180)
                    .scaleEffect(leaving && !reduceMotion ? 0.82 : 1)
            }
            .opacity(leaving ? 0 : 1)
            .allowsHitTesting(!leaving)
            .task {
                LaunchHandoff.shown = true
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.45)) { leaving = true }
                try? await Task.sleep(for: .milliseconds(500))
                visible = false
            }
        }
    }
}

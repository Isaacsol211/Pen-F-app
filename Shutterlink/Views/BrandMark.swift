import SwiftUI

/// The Shutterlink "Finder" mark: four frame corners round an accent focus point. The same drawing as the
/// app icon and launch screen (tools/make_finder_icon.swift), drawn live so it stays sharp at any size.
/// (Still called ApertureMark so every place that shows the mark keeps working.)
struct ApertureMark: View {
    /// Unused now; kept so existing call sites compile.
    var opening: Double = 0.41
    var showsLink = true
    /// One colour for the whole mark (for faint backgrounds).
    var monochrome: Color?

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let k = side / 120
            ctx.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            ctx.scaleBy(x: k, y: k)
            var corners = Path()
            corners.move(to: CGPoint(x: 22, y: 46)); corners.addLine(to: CGPoint(x: 22, y: 22)); corners.addLine(to: CGPoint(x: 46, y: 22))
            corners.move(to: CGPoint(x: 74, y: 22)); corners.addLine(to: CGPoint(x: 98, y: 22)); corners.addLine(to: CGPoint(x: 98, y: 46))
            corners.move(to: CGPoint(x: 98, y: 74)); corners.addLine(to: CGPoint(x: 98, y: 98)); corners.addLine(to: CGPoint(x: 74, y: 98))
            corners.move(to: CGPoint(x: 46, y: 98)); corners.addLine(to: CGPoint(x: 22, y: 98)); corners.addLine(to: CGPoint(x: 22, y: 74))
            ctx.stroke(corners, with: .color(monochrome ?? Theme.text),
                       style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: 49, y: 49, width: 22, height: 22)), with: .color(monochrome ?? Theme.accent))
        }
        .accessibilityHidden(true)
    }
}

/// Mark + wordmark, as at the top of the Connect screen.
struct BrandLockup: View {
    var markSize: CGFloat = 48

    var body: some View {
        // The design's lockup: the mark at 28 pt and the name in 18 pt semibold (a little larger on
        // the workspace home).
        let scale = max(1, markSize / 44)
        HStack(spacing: 10) {
            ApertureMark()
                .frame(width: 28 * scale, height: 28 * scale)
            Text("Shutterlink")
                .font(.system(size: 18 * scale, weight: .semibold))
                .foregroundStyle(Theme.text)
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
    @State private var sceneIn = false

    var body: some View {
        if visible {
            ZStack {
                Theme.background.ignoresSafeArea()
                // The design's launch (101): the dusk picture behind the mark, dimmed, and the name.
                ZStack {
                    DuskScene()
                    LinearGradient(colors: [LiveBackdrop.wash.opacity(0.25), LiveBackdrop.wash.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea()
                .opacity(sceneIn ? 1 : 0)
                ApertureMark()
                    .frame(width: 180, height: 180)
                    .scaleEffect(leaving && !reduceMotion ? 0.82 : 1)
                    .overlay(alignment: .bottom) {
                        Text("Shutterlink")
                            .font(.num(40))
                            .tracking(0.8)
                            .foregroundStyle(Theme.text)
                            .fixedSize()
                            .offset(y: 46)
                            .opacity(sceneIn ? 1 : 0)
                    }
            }
            .opacity(leaving ? 0 : 1)
            .allowsHitTesting(!leaving)
            .task {
                LaunchHandoff.shown = true
                withAnimation(.easeOut(duration: 0.3)) { sceneIn = true }
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.45)) { leaving = true }
                try? await Task.sleep(for: .milliseconds(500))
                visible = false
            }
        }
    }
}

/// The design's sample picture, dusk over a lake (dkit.py `scene`), for screens with no live view:
/// the first-run cover, and blurred behind the camera list and connecting screens. Drawn in the
/// design's 390 × 292 space and cropped to fill, like the SVG's `slice`.
struct DuskScene: View {
    var night = false

    var body: some View {
        Canvas { ctx, size in
            let w = 390.0, h = 292.0
            let k = max(size.width / w, size.height / h)
            ctx.translateBy(x: (size.width - w * k) / 2, y: (size.height - h * k) / 2)
            ctx.scaleBy(x: k, y: k)
            func c(_ hex: UInt32) -> Color { Color(hex: hex) }
            let sky: [Gradient.Stop] = night
                ? [.init(color: c(0x04060F), location: 0), .init(color: c(0x0F1530), location: 0.7), .init(color: c(0x1D2347), location: 1)]
                : [.init(color: c(0x0E1430), location: 0), .init(color: c(0x4B4470), location: 0.42),
                   .init(color: c(0xC77F6E), location: 0.7), .init(color: c(0xF3B36F), location: 0.82)]
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: 226)),
                     with: .linearGradient(Gradient(stops: sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: 226)))
            let stars: [(Double, Double, Double)] = night
                ? [(22, 30, 1.1), (60, 70, 0.8), (96, 22, 1.4), (130, 96, 0.8), (168, 48, 1.1), (204, 120, 0.9), (236, 30, 1.3),
                   (270, 84, 0.9), (306, 46, 1.2), (340, 110, 0.8), (368, 26, 1), (44, 130, 0.9), (150, 150, 0.7), (290, 150, 0.8)]
                : [(40, 30, 1.1), (110, 18, 1), (170, 54, 1.2), (250, 26, 1), (330, 60, 1.1), (70, 84, 0.8), (300, 100, 0.8)]
            for (x, y, r) in stars {
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(.white))
            }
            if night {
                ctx.fill(Path(ellipseIn: CGRect(x: 291, y: 51, width: 18, height: 18)), with: .color(c(0xC9D3E8)))
                ctx.fill(Path(ellipseIn: CGRect(x: 288, y: 49, width: 16, height: 16)), with: .color(c(0x0A0E20)))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: 216, y: 144, width: 92, height: 92)), with: .color(c(0xFFE2A6).opacity(0.22)))
                ctx.fill(Path(ellipseIn: CGRect(x: 245, y: 173, width: 34, height: 34)), with: .color(c(0xFFE2A6)))
            }
            func poly(_ pts: [(Double, Double)]) -> Path {
                var p = Path(); p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
                for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
                p.closeSubpath(); return p
            }
            ctx.fill(poly([(0, 206), (50, 168), (92, 192), (150, 140), (204, 188), (256, 160), (310, 196), (390, 170), (390, 226), (0, 226)]),
                     with: .color(night ? c(0x141A36) : c(0x3A3460)))
            ctx.fill(poly([(0, 222), (70, 200), (140, 216), (210, 194), (290, 218), (390, 204), (390, 226), (0, 226)]),
                     with: .color(night ? c(0x0A0D1C) : c(0x1B1C33)))
            ctx.fill(Path(CGRect(x: 0, y: 224, width: w, height: 68)),
                     with: .linearGradient(Gradient(colors: night ? [c(0x141A36), c(0x05070D)] : [c(0xB97C66), c(0x14172B)]),
                                           startPoint: CGPoint(x: 0, y: 224), endPoint: CGPoint(x: 0, y: 292)))
            if !night {
                var refl = Path()
                refl.move(to: CGPoint(x: 240, y: 234)); refl.addLine(to: CGPoint(x: 284, y: 234))
                refl.move(to: CGPoint(x: 230, y: 247)); refl.addLine(to: CGPoint(x: 294, y: 247))
                refl.move(to: CGPoint(x: 246, y: 262)); refl.addLine(to: CGPoint(x: 278, y: 262))
                ctx.stroke(refl, with: .color(c(0xFFE2A6).opacity(0.6)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The design's backdrop with no live view (103, 104): the dusk picture blurred and dimmed, fading to
/// near-black at the bottom.
struct DuskBackdrop: View {
    var dim = 0.35

    var body: some View {
        ZStack {
            Theme.background
            DuskScene()
                .scaleEffect(1.2)
                .blur(radius: 36, opaque: true)
                .opacity(dim)
            LinearGradient(stops: [.init(color: LiveBackdrop.wash.opacity(0), location: 0.44),
                                   .init(color: LiveBackdrop.wash.opacity(0.96), location: 0.81)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

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

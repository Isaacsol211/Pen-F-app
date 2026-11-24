// Renders the Shutterlink artwork (flat, on black): the app icon (light, dark and tinted variants, 1024×1024), the
// Watch icon, and the aperture mark the launch screen shows.
// Usage: swift tools/make_icon.swift <repo-root>
//   writes Shutterlink/Assets.xcassets/AppIcon.appiconset/AppIcon{,-Dark,-Tinted}.png,
//          ShutterlinkWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png and
//          Shutterlink/Assets.xcassets/LaunchMark.imageset/LaunchMark.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, a])!
}

enum Variant { case light, dark, tinted, mark }

/// Six aperture blades around a hexagonal opening. Each hexagon edge, extended until it meets the
/// outer circle, is the boundary between two blades (the classic iris drawing).
struct Iris {
    let center: CGPoint
    let outer: CGFloat
    let inner: CGFloat
    let rotation: CGFloat

    var vertices: [CGPoint] {
        (0..<6).map { i in
            let a = rotation + CGFloat(i) * .pi / 3
            return CGPoint(x: center.x + inner * cos(a), y: center.y + inner * sin(a))
        }
    }

    /// Where the edge arriving at vertex i, carried on past it, meets the outer circle.
    func rim(_ i: Int) -> CGPoint {
        let v = vertices
        let a = v[(i + 5) % 6], b = v[i]
        var d = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let len = hypot(d.x, d.y)
        d = CGPoint(x: d.x / len, y: d.y / len)
        let p = CGPoint(x: b.x - center.x, y: b.y - center.y)
        let dot = p.x * d.x + p.y * d.y
        let t = -dot + sqrt(dot * dot - (p.x * p.x + p.y * p.y - outer * outer))
        return CGPoint(x: b.x + t * d.x, y: b.y + t * d.y)
    }

    func blade(_ i: Int) -> CGPath {
        let v = vertices
        let path = CGMutablePath()
        let p0 = rim(i), p1 = rim((i + 1) % 6)
        path.move(to: v[i])
        path.addLine(to: p0)
        path.addArc(center: center, radius: outer, startAngle: atan2(p0.y - center.y, p0.x - center.x),
                    endAngle: atan2(p1.y - center.y, p1.x - center.x), clockwise: false)
        path.addLine(to: v[(i + 1) % 6])
        path.closeSubpath()
        return path
    }

    var opening: CGPath {
        let path = CGMutablePath()
        path.addLines(between: vertices)
        path.closeSubpath()
        return path
    }
}

func drawMark(_ ctx: CGContext, center c: CGPoint, scale k: CGFloat, variant: Variant) {
    // Flat, bold: amber ring and opening, light blades with black seams, on black.
    let tinted = variant == .tinted
    let amber = tinted ? rgb(0xFFFFFF) : rgb(0xFFB029)
    let seam = rgb(0x000000)
    ctx.setFillColor(seam)
    ctx.fillEllipse(in: CGRect(x: c.x - 340 * k, y: c.y - 340 * k, width: 680 * k, height: 680 * k))
    ctx.setStrokeColor(amber)
    ctx.setLineWidth(30 * k)
    ctx.strokeEllipse(in: CGRect(x: c.x - 312 * k, y: c.y - 312 * k, width: 624 * k, height: 624 * k))

    // Blades and opening: filled, with black seams.
    let iris = Iris(center: c, outer: 276 * k, inner: 112 * k, rotation: .pi / 12)
    ctx.setStrokeColor(seam)
    ctx.setLineWidth(12 * k)
    ctx.setLineJoin(.round)
    for i in 0..<6 {
        // Two flat tones, alternating, so the blades read as separate leaves.
        let tone: UInt32 = tinted ? (i % 2 == 0 ? 0x6E6E6E : 0x5A5A5A) : (i % 2 == 0 ? 0xF2F3F5 : 0xCDD1D9)
        ctx.setFillColor(rgb(tone))
        ctx.addPath(iris.blade(i))
        ctx.drawPath(using: .fillStroke)
    }
    ctx.setFillColor(amber)
    ctx.addPath(iris.opening)
    ctx.drawPath(using: .fillStroke)

    // Two thick Wi-Fi arcs off the ring's top-right: the link.
    let origin = CGPoint(x: c.x + 250 * k, y: c.y + 250 * k)
    ctx.setStrokeColor(amber)
    ctx.setLineCap(.round)
    ctx.setLineWidth(46 * k)
    for r in [104.0, 176.0] {
        ctx.addArc(center: origin, radius: CGFloat(r) * k, startAngle: .pi * 0.06, endAngle: .pi * 0.44, clockwise: false)
        ctx.strokePath()
    }
}

func render(_ variant: Variant, size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let S = CGFloat(size)
    // Pure black behind the light icon; dark, tinted and the launch mark are transparent
    // (iOS supplies the backdrop).
    if variant == .light {
        ctx.setFillColor(rgb(0x000000))
        ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    }
    let k = S / 1024
    let center = CGPoint(x: S * 0.455, y: S * 0.455)
    drawMark(ctx, center: center, scale: variant == .mark ? k * 1.12 : k * 1.08, variant: variant)
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: root).appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}

let icons = "Shutterlink/Assets.xcassets/AppIcon.appiconset/"
try write(render(.light, size: 1024), to: icons + "AppIcon.png")
try write(render(.dark, size: 1024), to: icons + "AppIcon-Dark.png")
try write(render(.tinted, size: 1024), to: icons + "AppIcon-Tinted.png")
try write(render(.light, size: 1024), to: "ShutterlinkWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
// 180 pt at 3x for the launch screen.
try write(render(.mark, size: 540), to: "Shutterlink/Assets.xcassets/LaunchMark.imageset/LaunchMark.png")

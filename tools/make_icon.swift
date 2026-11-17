// Renders the PEN-F Remote app icon (light, dark and tinted variants) at 1024×1024.
// Usage: swift tools/make_icon.swift <output-dir>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, a])!
}

enum Variant { case light, dark, tinted }

func render(_ variant: Variant) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    let S = CGFloat(size)
    let amber = rgb(0xFAA83D)

    // Background (dark/tinted variants are transparent: iOS supplies the backdrop).
    if variant == .light {
        let bg = CGGradient(colorsSpace: space, colors: [rgb(0x2C3150), rgb(0x0A0A10)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFAA83D, 0.55), rgb(0xFAA83D, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.82, y: S * 0.86), startRadius: 0,
                               endCenter: CGPoint(x: S * 0.82, y: S * 0.86), endRadius: S * 0.62, options: [])
        // A few stars.
        for (x, y, r) in [(0.14, 0.88, 5.0), (0.26, 0.80, 3.0), (0.40, 0.92, 4.0), (0.08, 0.70, 3.0), (0.56, 0.84, 2.5)] {
            ctx.setFillColor(rgb(0xFFFFFF, 0.85))
            ctx.fillEllipse(in: CGRect(x: S * x - r, y: S * y - r, width: r * 2, height: r * 2))
        }
    }

    // Camera body.
    let body = CGRect(x: S * 0.13, y: S * 0.22, width: S * 0.74, height: S * 0.44)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 70, cornerHeight: 70, transform: nil)

    // Shutter dial sitting on the top plate (drawn first so the body overlaps its base).
    let dial = CGRect(x: body.maxX - 250, y: body.maxY - 10, width: 160, height: 52)
    ctx.addPath(CGPath(roundedRect: dial, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(variant == .tinted ? rgb(0xBDBDBD) : rgb(0xC9CBD2))
    ctx.fillPath()
    ctx.setStrokeColor(rgb(0x7E818B, 0.8))
    ctx.setLineWidth(4)
    for i in stride(from: dial.minX + 16, to: dial.maxX - 8, by: 16) {
        ctx.move(to: CGPoint(x: i, y: dial.minY + 14))
        ctx.addLine(to: CGPoint(x: i, y: dial.maxY - 8))
    }
    ctx.strokePath()

    // Black leatherette lower half.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.setFillColor(variant == .tinted ? rgb(0x262626) : rgb(0x18181D))
    ctx.fill(body)
    // Silver top plate.
    let plate = CGRect(x: body.minX, y: body.maxY - body.height * 0.40, width: body.width, height: body.height * 0.40)
    let silver = CGGradient(colorsSpace: space,
                            colors: (variant == .tinted ? [rgb(0xF2F2F2), rgb(0xA8A8A8)] : [rgb(0xF4F5F8), rgb(0xA9ADB8)]) as CFArray,
                            locations: [0, 1])!
    ctx.saveGState()
    ctx.clip(to: plate)
    ctx.drawLinearGradient(silver, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
    ctx.restoreGState()
    // Seam between plate and body.
    ctx.setFillColor(rgb(0x000000, 0.35))
    ctx.fill(CGRect(x: plate.minX, y: plate.minY - 4, width: plate.width, height: 6))
    ctx.restoreGState()
    // Thin edge light so the black body separates from the dark background.
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.16))
    ctx.setLineWidth(5)
    ctx.strokePath()

    // Viewfinder window, top-left like a rangefinder.
    let finder = CGRect(x: body.minX + 64, y: plate.minY + 52, width: 150, height: 78)
    ctx.addPath(CGPath(roundedRect: finder, cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.setFillColor(rgb(0x23252D))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: finder.insetBy(dx: 14, dy: 14), cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.setFillColor(variant == .tinted ? rgb(0x5A5A5A) : rgb(0x3D4A6E))
    ctx.fillPath()

    // Lens.
    let c = CGPoint(x: body.midX + 30, y: body.midY - 6)
    func disc(_ r: CGFloat, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
    disc(212, variant == .tinted ? rgb(0xD0D0D0) : rgb(0xD6D8DE))    // silver mount
    disc(196, rgb(0x0E0E12))                                          // barrel
    // Amber focus ring.
    ctx.setStrokeColor(variant == .tinted ? rgb(0xFFFFFF) : amber)
    ctx.setLineWidth(14)
    ctx.strokeEllipse(in: CGRect(x: c.x - 166, y: c.y - 166, width: 332, height: 332))
    // Glass.
    let glass = CGGradient(colorsSpace: space,
                           colors: (variant == .tinted ? [rgb(0x6A6A6A), rgb(0x101010)] : [rgb(0x4B5BA8), rgb(0x0B0D1C)]) as CFArray,
                           locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - 140, y: c.y - 140, width: 280, height: 280))
    ctx.clip()
    ctx.drawRadialGradient(glass, startCenter: CGPoint(x: c.x - 40, y: c.y + 50), startRadius: 0,
                           endCenter: c, endRadius: 150, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    // Reflections.
    ctx.setFillColor(rgb(0xFFFFFF, 0.55))
    ctx.fillEllipse(in: CGRect(x: c.x - 82, y: c.y + 36, width: 58, height: 36))
    ctx.setFillColor(rgb(0xFFFFFF, 0.22))
    ctx.fillEllipse(in: CGRect(x: c.x + 46, y: c.y - 80, width: 30, height: 20))

    // Wi-Fi arcs from the top-right corner of the camera.
    let origin = CGPoint(x: body.maxX - 100, y: body.maxY + 130)
    ctx.setStrokeColor(variant == .tinted ? rgb(0xFFFFFF) : amber)
    ctx.setLineCap(.round)
    for (i, r) in [44.0, 92.0, 140.0].enumerated() {
        ctx.setLineWidth(i == 0 ? 0 : 22)
        if i == 0 {
            ctx.setFillColor(variant == .tinted ? rgb(0xFFFFFF) : amber)
            ctx.fillEllipse(in: CGRect(x: origin.x - 20, y: origin.y - 20, width: 40, height: 40))
            continue
        }
        ctx.addArc(center: origin, radius: CGFloat(r), startAngle: .pi * 0.08, endAngle: .pi * 0.58, clockwise: false)
        ctx.strokePath()
    }
    return ctx.makeImage()!
}

try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (variant, name) in [(Variant.light, "AppIcon.png"), (.dark, "AppIcon-Dark.png"), (.tinted, "AppIcon-Tinted.png")] {
    let url = URL(fileURLWithPath: out).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, render(variant), nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}

// Renders the "Finder" mark (four frame corners round an accent focus point) for the Shutterlink D test build:
// the app icon (light, dark and tinted, 1024×1024) and the mark the launch screen shows (540×540).
// Usage: swift tools/make_finder_icon.swift <repo-root>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, 1])!
}

/// Draws the mark in a 120-unit square scaled to `size` px, y down like the design's SVG.
func render(size: Int, corners: CGColor, dot: CGColor, background: CGColor) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(background)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let k = CGFloat(size) / 120
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: k, y: -k)
    ctx.setStrokeColor(corners)
    ctx.setLineWidth(8)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    func line(_ pts: [(CGFloat, CGFloat)]) {
        ctx.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
        ctx.strokePath()
    }
    line([(22, 46), (22, 22), (46, 22)])
    line([(74, 22), (98, 22), (98, 46)])
    line([(98, 74), (98, 98), (74, 98)])
    line([(46, 98), (22, 98), (22, 74)])
    ctx.setFillColor(dot)
    ctx.fillEllipse(in: CGRect(x: 60 - 11, y: 60 - 11, width: 22, height: 22))
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: root).appendingPathComponent(path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let bg = rgb(0x0A0A0A), cream = rgb(0xF4F1EA), gold = rgb(0xF2C46D)
let icons = "Shutterlink/Assets.xcassets/AppIcon.appiconset/"
write(render(size: 1024, corners: cream, dot: gold, background: bg), to: icons + "AppIcon.png")
write(render(size: 1024, corners: cream, dot: gold, background: bg), to: icons + "AppIcon-Dark.png")
write(render(size: 1024, corners: rgb(0xFFFFFF), dot: rgb(0xFFFFFF), background: rgb(0x000000)), to: icons + "AppIcon-Tinted.png")
write(render(size: 540, corners: cream, dot: gold, background: bg), to: "Shutterlink/Assets.xcassets/LaunchMark.imageset/LaunchMark.png")

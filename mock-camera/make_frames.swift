// Renders the fake live-view frames the mock camera streams.
// Usage: swift make_frames.swift <output-dir>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "frames"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let width = 640, height = 480, count = 60
let space = CGColorSpaceCreateDeviceRGB()

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

func text(_ s: String, size: CGFloat, at p: CGPoint, alpha: Double, in ctx: CGContext) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let attrs = [kCTFontAttributeName as NSAttributedString.Key: font,
                 kCTForegroundColorAttributeName as NSAttributedString.Key: color(1, 1, 1, alpha)] as [NSAttributedString.Key: Any]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    ctx.textPosition = p
    CTLineDraw(line, ctx)
}

for i in 0..<count {
    let t = Double(i) / Double(count)
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError() }
    // CoreGraphics origin is bottom-left.
    let sky = CGGradient(colorsSpace: space, colors: [color(0.99, 0.70, 0.42), color(0.26, 0.38, 0.62)] as CFArray,
                         locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 150), end: CGPoint(x: 0, y: height), options: [.drawsBeforeStartLocation])

    // Sun drifting across the sky.
    let sunX = 70 + 500 * t
    let sunY = 230 + 140 * sin(.pi * t)
    ctx.setFillColor(color(1, 0.93, 0.70))
    ctx.fillEllipse(in: CGRect(x: sunX - 34, y: sunY - 34, width: 68, height: 68))

    // Clouds sliding the other way.
    ctx.setFillColor(color(1, 1, 1, 0.55))
    for (k, y) in [(0.0, 380.0), (0.45, 330.0), (0.8, 410.0)] {
        let x = (1 - (t + k).truncatingRemainder(dividingBy: 1)) * 760 - 80
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: 120, height: 34))
        ctx.fillEllipse(in: CGRect(x: x + 30, y: y + 14, width: 80, height: 34))
    }

    // Hills.
    ctx.setFillColor(color(0.13, 0.22, 0.20))
    ctx.move(to: CGPoint(x: 0, y: 0))
    for x in stride(from: 0, through: width, by: 8) {
        let y = 150 + 40 * sin(Double(x) / 90) + 25 * sin(Double(x) / 37 + 1)
        ctx.addLine(to: CGPoint(x: Double(x), y: y))
    }
    ctx.addLine(to: CGPoint(x: width, y: 0))
    ctx.closePath()
    ctx.fillPath()

    text("MOCK PEN-F", size: 40, at: CGPoint(x: 24, y: 40), alpha: 0.9, in: ctx)
    text(String(format: "live view frame %02d", i), size: 18, at: CGPoint(x: 26, y: 18), alpha: 0.7, in: ctx)

    let url = URL(fileURLWithPath: outDir).appendingPathComponent(String(format: "frame_%03d.jpg", i))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
    CGImageDestinationFinalize(dest)
}
print("wrote \(count) frames to \(outDir)")

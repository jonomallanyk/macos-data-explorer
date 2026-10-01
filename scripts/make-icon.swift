// Draws the app icon (a storage "donut" chart with a magnifying glass) and writes an
// .iconset folder for iconutil. Used by build-app.sh:
//
//   swift scripts/make-icon.swift build/AppIcon.iconset
//   iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

/// Draws on a 1024×1024 canvas (origin bottom-left), scaled to the context's size.
func drawIcon(in context: CGContext, pixels: Int) {
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    // Rounded-square background with a soft shadow, following the macOS icon grid.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0, 0, 0, 0.35))
    context.addPath(tilePath)
    context.setFillColor(color(0.09, 0.12, 0.27))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0.20, 0.30, 0.66), color(0.07, 0.09, 0.24)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // A donut chart of storage categories.
    let center = CGPoint(x: 470, y: 560)
    let radius: CGFloat = 220
    let segments: [(fraction: CGFloat, color: CGColor)] = [
        (0.32, color(0.25, 0.56, 1.00)),
        (0.21, color(1.00, 0.62, 0.20)),
        (0.16, color(1.00, 0.84, 0.25)),
        (0.13, color(0.30, 0.82, 0.48)),
        (0.10, color(1.00, 0.38, 0.55)),
        (0.08, color(0.70, 0.72, 0.78)),
    ]
    var angle = CGFloat.pi / 2
    context.setLineWidth(118)
    context.setLineCap(.butt)
    for segment in segments {
        let end = angle - segment.fraction * 2 * .pi
        context.setStrokeColor(segment.color)
        context.addArc(center: center, radius: radius, startAngle: angle - 0.025, endAngle: end + 0.025, clockwise: true)
        context.strokePath()
        angle = end
    }

    // A magnifying glass over the lower right of the chart.
    let lens = CGPoint(x: 648, y: 380)
    let lensRadius: CGFloat = 128
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: color(0, 0, 0, 0.4))
    context.setLineCap(.round)
    context.setStrokeColor(color(0.96, 0.97, 1.0))
    context.setLineWidth(64)
    let handleStart = CGPoint(x: lens.x + lensRadius * 0.72, y: lens.y - lensRadius * 0.72)
    context.move(to: handleStart)
    context.addLine(to: CGPoint(x: 820, y: 210))
    context.strokePath()
    context.setFillColor(color(1, 1, 1, 0.18))
    context.addEllipse(in: CGRect(x: lens.x - lensRadius, y: lens.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2))
    context.fillPath()
    context.setLineWidth(40)
    context.addEllipse(in: CGRect(x: lens.x - lensRadius, y: lens.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2))
    context.strokePath()
}

func png(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    drawIcon(in: graphics.cgContext, pixels: pixels)
    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

do {
    try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
    for variant in variants {
        try png(pixels: variant.pixels).write(to: URL(fileURLWithPath: output).appendingPathComponent(variant.name + ".png"))
    }
} catch {
    FileHandle.standardError.write(Data("make-icon: \(error)\n".utf8))
    exit(1)
}

import Cocoa
import CoreGraphics

func generateAppIcon(outputPath: String) {
    let size: CGFloat = 1024
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    ctx.saveGState()

    // 1. Drop shadow behind the macOS squircle
    let shadowColor = NSColor.black.withAlphaComponent(0.30).cgColor
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 36, color: shadowColor)

    // macOS standard icon squircle bounds (inside 1024x1024 canvas)
    let margin: CGFloat = 100
    let squircleRect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let cornerRadius: CGFloat = 185
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(calibratedRed: 0.00, green: 0.40, blue: 0.90, alpha: 1.0).cgColor)
    ctx.fillPath()

    ctx.restoreGState()

    // 2. Main squircle background gradient (Signature vibrant Apple Blue)
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(calibratedRed: 0.12, green: 0.60, blue: 1.00, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.00, green: 0.48, blue: 0.95, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.00, green: 0.36, blue: 0.86, alpha: 1.0).cgColor
    ] as CFArray

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.45, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }

    // Top inset subtle light-catching edge
    ctx.setLineWidth(3.5)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.30).cgColor)
    ctx.addPath(squirclePath)
    ctx.strokePath()

    // 3. Central White Chart Bars Artwork (matching chart.bar.xaxis symbol)
    let barColor = NSColor.white.cgColor
    let baselineY: CGFloat = 330
    let barWidth: CGFloat = 78
    let corner: CGFloat = 26

    // Bar 1 (Lowest)
    let b1Height: CGFloat = 180
    let b1Rect = CGRect(x: 290, y: baselineY, width: barWidth, height: b1Height)
    let b1Path = CGPath(roundedRect: b1Rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Bar 2 (Medium High)
    let b2Height: CGFloat = 320
    let b2Rect = CGRect(x: 398, y: baselineY, width: barWidth, height: b2Height)
    let b2Path = CGPath(roundedRect: b2Rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Bar 3 (Medium)
    let b3Height: CGFloat = 240
    let b3Rect = CGRect(x: 506, y: baselineY, width: barWidth, height: b3Height)
    let b3Path = CGPath(roundedRect: b3Rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Bar 4 (Tallest)
    let b4Height: CGFloat = 430
    let b4Rect = CGRect(x: 614, y: baselineY, width: barWidth, height: b4Height)
    let b4Path = CGPath(roundedRect: b4Rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Axis horizontal bar at base
    let axisRect = CGRect(x: 260, y: baselineY - 45, width: 504, height: 26)
    let axisPath = CGPath(roundedRect: axisRect, cornerWidth: 13, cornerHeight: 13, transform: nil)

    // Draw with soft glow/shadow for crisp Apple look
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    ctx.setFillColor(barColor)

    ctx.addPath(b1Path)
    ctx.addPath(b2Path)
    ctx.addPath(b3Path)
    ctx.addPath(b4Path)
    ctx.addPath(axisPath)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState() // pop squircle clip

    image.unlockFocus()

    // Save 1024x1024 PNG
    if let tiffData = image.tiffRepresentation,
       let bitmapImage = NSBitmapImageRep(data: tiffData),
       let pngData = bitmapImage.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated clean blue icon at \(outputPath)")
    }
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon_1024.png"
generateAppIcon(outputPath: outputPath)

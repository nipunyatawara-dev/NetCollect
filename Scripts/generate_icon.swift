import Cocoa
import CoreGraphics

func generateAppIcon(outputPath: String) {
    let size: CGFloat = 1024
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    ctx.saveGState()

    // 1. Drop shadow behind the macOS squircle
    let shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 36, color: shadowColor)

    // macOS standard icon squircle bounds (inside 1024x1024 canvas)
    let margin: CGFloat = 100
    let squircleRect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let cornerRadius: CGFloat = 185
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.22, alpha: 1.0).cgColor)
    ctx.fillPath()

    ctx.restoreGState()

    // 2. Main squircle background gradient (Dark navy to deep midnight blue)
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.32, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.18, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.10, alpha: 1.0).cgColor
    ] as CFArray

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.6, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }

    // Subtle radial glow in center
    let glowColors = [
        NSColor(calibratedRed: 0.0, green: 0.50, blue: 1.0, alpha: 0.40).cgColor,
        NSColor(calibratedRed: 0.0, green: 0.50, blue: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    if let radialGlow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(radialGlow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 380, options: [])
    }

    // Top inset highlight (Apple light catching material edge)
    ctx.setLineWidth(3.0)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
    ctx.addPath(squirclePath)
    ctx.strokePath()

    // 3. Central Minimalist Network Rings
    let center = CGPoint(x: 512, y: 512)

    // Outer subtle orbit ring 4
    ctx.saveGState()
    ctx.setLineWidth(5.0)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.6, blue: 1.0, alpha: 0.20).cgColor)
    ctx.addArc(center: center, radius: 270, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Orbit ring 3
    ctx.saveGState()
    ctx.setLineWidth(7.0)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.15, green: 0.65, blue: 1.0, alpha: 0.45).cgColor)
    ctx.addArc(center: center, radius: 200, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Orbit ring 2
    ctx.saveGState()
    ctx.setLineWidth(9.0)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.75, blue: 1.0, alpha: 0.75).cgColor)
    ctx.addArc(center: center, radius: 130, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Inner ring 1
    ctx.saveGState()
    ctx.setLineWidth(11.0)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.85, blue: 1.0, alpha: 0.95).cgColor)
    ctx.addArc(center: center, radius: 65, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Center Glowing Core Node
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 32, color: NSColor(calibratedRed: 0.1, green: 0.7, blue: 1.0, alpha: 1.0).cgColor)

    let centerNodeRect = CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: centerNodeRect)
    ctx.restoreGState()

    ctx.restoreGState() // pop squircle clip

    image.unlockFocus()

    // Save 1024x1024 PNG
    if let tiffData = image.tiffRepresentation,
       let bitmapImage = NSBitmapImageRep(data: tiffData),
       let pngData = bitmapImage.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated clean icon at \(outputPath)")
    }
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon_1024.png"
generateAppIcon(outputPath: outputPath)

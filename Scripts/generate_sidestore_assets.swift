import AppKit
import CoreGraphics

func createSideStoreBanner(iconPath: String, outputPath: String) {
    let width: CGFloat = 1200
    let height: CGFloat = 675
    let size = NSSize(width: width, height: height)

    let image = NSImage(size: size)
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return
    }

    // 1. Deep Midnight Charcoal Gradient Background
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 16/255, green: 20/255, blue: 30/255, alpha: 1.0).cgColor,
        NSColor(red: 9/255, green: 11/255, blue: 18/255, alpha: 1.0).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
    }

    // 2. Ambient Flame Orange Radial Glow behind Icon
    let glowColors = [
        NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.28).cgColor,
        NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.0).cgColor
    ] as CFArray
    if let radialGlow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            radialGlow,
            startCenter: CGPoint(x: 270, y: 340),
            startRadius: 40,
            endCenter: CGPoint(x: 270, y: 340),
            endRadius: 360,
            options: []
        )
    }

    // 3. Subtle Hex Mesh / Grid Accent Lines
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.04).cgColor)
    ctx.setLineWidth(1.0)
    for x in stride(from: 0, to: width, by: 48) {
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: height))
    }
    for y in stride(from: 0, to: height, by: 48) {
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: width, y: y))
    }
    ctx.strokePath()

    // 4. Render Squircle App Icon with Drop Shadow
    if let iconImage = NSImage(contentsOfFile: iconPath) {
        ctx.saveGState()
        let iconRect = CGRect(x: 80, y: 147, width: 380, height: 380)
        let iconPath = CGPath(roundedRect: iconRect, cornerWidth: 84, cornerHeight: 84, transform: nil)

        // Drop shadow
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 36, color: NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.35).cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(iconPath)
        ctx.fillPath()

        // Clip and draw icon
        ctx.addPath(iconPath)
        ctx.clip()
        iconImage.draw(in: iconRect)

        // Subtle inner border
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.18).cgColor)
        ctx.setLineWidth(3)
        ctx.addPath(iconPath)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // 5. Typography on the Right Side
    let textX: CGFloat = 510

    // Top Category Pill: "OFFICIAL RELEASE"
    let pillRect = CGRect(x: textX, y: 495, width: 172, height: 32)
    let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
    ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.16).cgColor)
    ctx.addPath(pillPath)
    ctx.fillPath()
    ctx.setStrokeColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.40).cgColor)
    ctx.setLineWidth(1)
    ctx.addPath(pillPath)
    ctx.strokePath()

    let pillAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .bold),
        .foregroundColor: NSColor(red: 255/255, green: 120/255, blue: 40/255, alpha: 1.0)
    ]
    NSString(string: "OFFICIAL RELEASE").draw(at: CGPoint(x: textX + 16, y: 502), withAttributes: pillAttrs)

    // Main App Title: "TOTAL FACTOR"
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 52, weight: .black),
        .foregroundColor: NSColor.white
    ]
    NSString(string: "TOTAL FACTOR").draw(at: CGPoint(x: textX, y: 420), withAttributes: titleAttrs)

    // Subtitle Tagline
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium),
        .foregroundColor: NSColor(red: 203/255, green: 213/255, blue: 225/255, alpha: 1.0)
    ]
    NSString(string: "Adaptive Nutrition & Smart Strength Tracker").draw(at: CGPoint(x: textX, y: 382), withAttributes: subAttrs)

    // Feature highlights
    let bulletPoints = [
        ("⚡", "Dynamic Adaptive TDEE Expenditure Engine"),
        ("🥗", "The Plate Dock, Hourly Food Log & No-Scale Estimator"),
        ("🏋️", "MacroFactor-Grade Workout UI & Rest Live Activity"),
        ("🔒", "100% Offline • Private SwiftData • Zero Subscriptions")
    ]

    var currentY: CGFloat = 320
    for (icon, text) in bulletPoints {
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20),
            .foregroundColor: NSColor(red: 255/255, green: 110/255, blue: 20/255, alpha: 1.0)
        ]
        NSString(string: icon).draw(at: CGPoint(x: textX, y: currentY), withAttributes: iconAttrs)

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 19, weight: .regular),
            .foregroundColor: NSColor(red: 241/255, green: 245/255, blue: 249/255, alpha: 1.0)
        ]
        NSString(string: text).draw(at: CGPoint(x: textX + 36, y: currentY + 1), withAttributes: textAttrs)
        currentY -= 40
    }

    // Bottom Badge Pill
    let badgeText = "Native iOS 17+ • SwiftData • HealthKit • Apple Watch"
    let badgeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
        .foregroundColor: NSColor(red: 148/255, green: 163/255, blue: 184/255, alpha: 1.0)
    ]
    NSString(string: badgeText).draw(at: CGPoint(x: textX, y: 155), withAttributes: badgeAttrs)

    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to encode PNG")
        return
    }

    try? pngData.write(to: URL(fileURLWithPath: outputPath))
    print("✓ Successfully generated banner at: \(outputPath)")
}

let args = CommandLine.arguments
if args.count >= 3 {
    createSideStoreBanner(iconPath: args[1], outputPath: args[2])
} else {
    print("Usage: swift generate_sidestore_assets.swift <iconPath> <outputPath>")
}

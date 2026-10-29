import AppKit
import CoreGraphics

// Helper to draw status bar
func drawStatusBar(ctx: CGContext, width: CGFloat, height: CGFloat) {
    let timeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "9:41").draw(at: CGPoint(x: 100, y: height - 120), withAttributes: timeAttrs)

    // Dynamic Island Pill
    let islandRect = CGRect(x: width / 2 - 190, y: height - 130, width: 380, height: 95)
    let islandPath = CGPath(roundedRect: islandRect, cornerWidth: 47.5, cornerHeight: 47.5, transform: nil)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(islandPath)
    ctx.fillPath()

    // Battery / Wifi icons
    let sysAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 32, weight: .medium),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "􀐫  􀙇  􀛨").draw(at: CGPoint(x: width - 260, y: height - 118), withAttributes: sysAttrs)
}

// Helper to draw bottom Tab Bar
func drawTabBar(ctx: CGContext, width: CGFloat, activeIndex: Int) {
    let barHeight: CGFloat = 210
    let barRect = CGRect(x: 0, y: 0, width: width, height: barHeight)

    // Background blur simulation
    ctx.setFillColor(NSColor(white: 0.98, alpha: 0.94).cgColor)
    ctx.fill(barRect)

    // Divider line
    ctx.setStrokeColor(NSColor(white: 0.85, alpha: 1.0).cgColor)
    ctx.setLineWidth(1.0)
    ctx.move(to: CGPoint(x: 0, y: barHeight))
    ctx.addLine(to: CGPoint(x: width, y: barHeight))
    ctx.strokePath()

    let tabs = [
        ("Today", "bolt.heart.fill"),
        ("Food", "fork.knife"),
        ("Train", "dumbbell.fill"),
        ("Progress", "chart.xyaxis.line"),
        ("Settings", "gearshape.fill")
    ]

    let colWidth = width / CGFloat(tabs.count)
    for (i, tab) in tabs.enumerated() {
        let isSelected = (i == activeIndex)
        let color = isSelected ? NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0) : NSColor.systemGray

        let x = CGFloat(i) * colWidth + (colWidth / 2)

        // Pill background for active tab
        if isSelected {
            let pillRect = CGRect(x: x - 65, y: 80, width: 130, height: 75)
            let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 37.5, cornerHeight: 37.5, transform: nil)
            ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.14).cgColor)
            ctx.addPath(pillPath)
            ctx.fillPath()
        }

        let symbolAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: isSelected ? .bold : .regular),
            .foregroundColor: color
        ]
        let symbol = (i == 0 ? "⚡" : (i == 1 ? "🥗" : (i == 2 ? "🏋️" : (i == 3 ? "📈" : "⚙️"))))
        NSString(string: symbol).draw(at: CGPoint(x: x - 22, y: 92), withAttributes: symbolAttrs)

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: isSelected ? .bold : .medium),
            .foregroundColor: color
        ]
        let str = NSString(string: tab.0)
        let strSize = str.size(withAttributes: labelAttrs)
        str.draw(at: CGPoint(x: x - (strSize.width / 2), y: 48), withAttributes: labelAttrs)
    }
}

// 1. Generate Food Log Screen (screenshot_food.png)
func generateFoodScreen(outputPath: String) {
    let width: CGFloat = 1206
    let height: CGFloat = 2622
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    // Clean iOS Background
    ctx.setFillColor(NSColor(red: 246/255, green: 247/255, blue: 250/255, alpha: 1.0).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    drawStatusBar(ctx: ctx, width: width, height: height)

    // Header Title
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 48, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "Food Log").draw(at: CGPoint(x: width / 2 - 100, y: height - 230), withAttributes: titleAttrs)

    // Top Plate Button
    let plateBtnRect = CGRect(x: width - 240, y: height - 240, width: 170, height: 70)
    let platePath = CGPath(roundedRect: plateBtnRect, cornerWidth: 35, cornerHeight: 35, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(platePath)
    ctx.fillPath()
    let plateText = "🥗 The Plate"
    let plateAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
        .foregroundColor: NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0)
    ]
    NSString(string: plateText).draw(at: CGPoint(x: width - 225, y: height - 222), withAttributes: plateAttrs)

    // 7-Day Adherence Strip Card
    let stripCardRect = CGRect(x: 50, y: height - 480, width: width - 100, height: 210)
    let stripPath = CGPath(roundedRect: stripCardRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(stripPath)
    ctx.fillPath()

    let days = [
        ("S", "25", 0.95),
        ("M", "26", 1.0),
        ("T", "27", 0.92),
        ("W", "28", 1.05),
        ("T", "29", 0.70),
        ("F", "30", 0.0),
        ("S", "31", 0.0)
    ]
    let dayColW = (width - 140) / 7
    for (i, d) in days.enumerated() {
        let cx = 70 + CGFloat(i) * dayColW + (dayColW / 2)
        let isToday = (i == 4)

        // Day letter
        let dLAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor(white: 0.55, alpha: 1.0)
        ]
        NSString(string: d.0).draw(at: CGPoint(x: cx - 8, y: height - 330), withAttributes: dLAttrs)

        // Adherence Ring / Day number
        let ringRect = CGRect(x: cx - 44, y: height - 440, width: 88, height: 88)
        let ringPath = CGPath(ellipseIn: ringRect, transform: nil)

        if isToday {
            ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.12).cgColor)
            ctx.addPath(ringPath)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0).cgColor)
            ctx.setLineWidth(4)
            ctx.addPath(ringPath)
            ctx.strokePath()
        } else if d.2 > 0 {
            ctx.setStrokeColor(NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 0.85).cgColor)
            ctx.setLineWidth(4)
            ctx.addPath(ringPath)
            ctx.strokePath()
        } else {
            ctx.setStrokeColor(NSColor(white: 0.88, alpha: 1.0).cgColor)
            ctx.setLineWidth(2)
            ctx.addPath(ringPath)
            ctx.strokePath()
        }

        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 32, weight: isToday ? .heavy : .bold),
            .foregroundColor: isToday ? NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0) : NSColor.black
        ]
        NSString(string: d.1).draw(at: CGPoint(x: cx - 18, y: height - 410), withAttributes: numAttrs)
    }

    // Macro Energy Balance Target Card
    let targetCardRect = CGRect(x: 50, y: height - 760, width: width - 100, height: 250)
    let targetPath = CGPath(roundedRect: targetCardRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(targetPath)
    ctx.fillPath()

    let calTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 34, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "Calories Consumed").draw(at: CGPoint(x: 85, y: height - 560), withAttributes: calTitleAttrs)

    let calNumAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 48, weight: .black),
        .foregroundColor: NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0)
    ]
    NSString(string: "1,755").draw(at: CGPoint(x: width - 360, y: height - 570), withAttributes: calNumAttrs)

    let calGoalAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
        .foregroundColor: NSColor.systemGray
    ]
    NSString(string: "/ 2,504 kcal").draw(at: CGPoint(x: width - 215, y: height - 560), withAttributes: calGoalAttrs)

    // Calorie Progress Bar
    let barBgRect = CGRect(x: 85, y: height - 610, width: width - 170, height: 24)
    let barBgPath = CGPath(roundedRect: barBgRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.15).cgColor)
    ctx.addPath(barBgPath)
    ctx.fillPath()

    let barFillRect = CGRect(x: 85, y: height - 610, width: (width - 170) * 0.70, height: 24)
    let barFillPath = CGPath(roundedRect: barFillRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0).cgColor)
    ctx.addPath(barFillPath)
    ctx.fillPath()

    // 3 Macro Indicators (Protein, Carbs, Fat)
    let macros = [
        ("Protein", "165 / 185g", NSColor(red: 236/255, green: 72/255, blue: 153/255, alpha: 1.0), 0.89),
        ("Carbs", "175 / 245g", NSColor(red: 6/255, green: 182/255, blue: 212/255, alpha: 1.0), 0.71),
        ("Fat", "42 / 60g", NSColor(red: 234/255, green: 179/255, blue: 8/255, alpha: 1.0), 0.70)
    ]
    let mColW = (width - 170) / 3
    for (i, m) in macros.enumerated() {
        let mx = 85 + CGFloat(i) * mColW
        let mDotRect = CGRect(x: mx, y: height - 670, width: 18, height: 18)
        ctx.setFillColor(m.2.cgColor)
        ctx.fillEllipse(in: mDotRect)

        let mLAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: NSColor(white: 0.2, alpha: 1.0)
        ]
        NSString(string: m.0).draw(at: CGPoint(x: mx + 26, y: height - 675), withAttributes: mLAttrs)

        let mVAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .heavy),
            .foregroundColor: NSColor.black
        ]
        NSString(string: m.1).draw(at: CGPoint(x: mx, y: height - 720), withAttributes: mVAttrs)
    }

    // Action Strips: Hour-by-Hour, Day Note, AI Voice
    let actionButtons = [
        ("⏱ Hour-by-Hour", NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.12), NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0)),
        ("📝 Day Note", NSColor(white: 0.94, alpha: 1.0), NSColor.black),
        ("🎙 Describe / Voice", NSColor(red: 59/255, green: 130/255, blue: 246/255, alpha: 0.12), NSColor(red: 59/255, green: 130/255, blue: 246/255, alpha: 1.0))
    ]
    let abColW = (width - 120) / 3
    for (i, btn) in actionButtons.enumerated() {
        let bx = 50 + CGFloat(i) * abColW
        let btnRect = CGRect(x: bx, y: height - 850, width: abColW - 14, height: 65)
        let btnPath = CGPath(roundedRect: btnRect, cornerWidth: 20, cornerHeight: 20, transform: nil)
        ctx.setFillColor(btn.1.cgColor)
        ctx.addPath(btnPath)
        ctx.fillPath()

        let bAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: btn.2
        ]
        let str = NSString(string: btn.0)
        let sSize = str.size(withAttributes: bAttrs)
        str.draw(at: CGPoint(x: bx + ((abColW - 14) - sSize.width) / 2, y: height - 833), withAttributes: bAttrs)
    }

    // Hourly Timeline Meals
    let meals = [
        ("8:30 AM", "Breakfast", "Fage 0% Greek Yogurt with Honey & Berries", "250g • 230 kcal", "25P 18C 2F", "usda"),
        ("12:45 PM", "Lunch", "Double Chicken Burrito Bowl (Brown Rice, Fajitas)", "1 bowl • 740 kcal", "62P 68C 22F", "custom"),
        ("4:15 PM", "Post-Workout", "Gold Standard Whey & Banana Protein Shake", "1 shake • 320 kcal", "34P 38C 3F", "custom"),
        ("7:30 PM", "Dinner", "Pan-Seared Atlantic Salmon & Roasted Potatoes", "350g • 465 kcal", "44P 45C 15F", "usda")
    ]

    var mealY: CGFloat = height - 920
    for meal in meals {
        let mealCardRect = CGRect(x: 50, y: mealY - 140, width: width - 100, height: 125)
        let mealCardPath = CGPath(roundedRect: mealCardRect, cornerWidth: 28, cornerHeight: 28, transform: nil)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(mealCardPath)
        ctx.fillPath()

        // Time tag badge
        let timePillRect = CGRect(x: 75, y: mealY - 60, width: 140, height: 36)
        let timePath = CGPath(roundedRect: timePillRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.12).cgColor)
        ctx.addPath(timePath)
        ctx.fillPath()

        let tAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0)
        ]
        NSString(string: meal.0).draw(at: CGPoint(x: 90, y: mealY - 55), withAttributes: tAttrs)

        // Meal Title
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSString(string: meal.2).draw(at: CGPoint(x: 75, y: mealY - 102), withAttributes: nameAttrs)

        // Grams & Calories
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor(white: 0.45, alpha: 1.0)
        ]
        NSString(string: meal.3).draw(at: CGPoint(x: 75, y: mealY - 132), withAttributes: subAttrs)

        // Macro pill on right
        let macroAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .heavy),
            .foregroundColor: NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0)
        ]
        NSString(string: meal.4).draw(at: CGPoint(x: width - 260, y: mealY - 95), withAttributes: macroAttrs)

        mealY -= 150
    }

    // Floating Bottom Dock: "The Plate (3 Items Staged • 1-Tap Log)"
    let dockRect = CGRect(x: 70, y: 260, width: width - 140, height: 110)
    let dockPath = CGPath(roundedRect: dockRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 24, color: NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.35).cgColor)
    ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0).cgColor)
    ctx.addPath(dockPath)
    ctx.fillPath()

    let dockIconAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 38),
        .foregroundColor: NSColor.white
    ]
    NSString(string: "🥗").draw(at: CGPoint(x: 105, y: 295), withAttributes: dockIconAttrs)

    let dockTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 32, weight: .black),
        .foregroundColor: NSColor.white
    ]
    NSString(string: "The Plate • 3 Foods Staged").draw(at: CGPoint(x: 165, y: 322), withAttributes: dockTitleAttrs)

    let dockSubAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor(white: 1.0, alpha: 0.9)
    ]
    NSString(string: "Tap to review grams, batch commit, or convert units").draw(at: CGPoint(x: 165, y: 288), withAttributes: dockSubAttrs)

    // Reset shadow & draw Tab Bar
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    drawTabBar(ctx: ctx, width: width, activeIndex: 1)

    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

    try? pngData.write(to: URL(fileURLWithPath: outputPath))
    print("✓ Successfully generated food screen at: \(outputPath)")
}

let args = CommandLine.arguments
if args.count >= 2 {
    generateFoodScreen(outputPath: args[1])
}

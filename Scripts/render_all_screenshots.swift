import AppKit
import CoreGraphics

let width: CGFloat = 1206
let height: CGFloat = 2622
let orange = NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 1.0)

// Standard Apple iOS Status Bar
func drawCleanStatusBar(ctx: CGContext) {
    let timeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 42, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "9:41").draw(at: CGPoint(x: 105, y: height - 125), withAttributes: timeAttrs)

    // Dynamic Island
    let islandRect = CGRect(x: width / 2 - 190, y: height - 130, width: 380, height: 92)
    let islandPath = CGPath(roundedRect: islandRect, cornerWidth: 46, cornerHeight: 46, transform: nil)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(islandPath)
    ctx.fillPath()

    // 5G Label
    let netAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 32, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "5G").draw(at: CGPoint(x: width - 265, y: height - 120), withAttributes: netAttrs)

    // Battery Body
    let battBody = CGRect(x: width - 185, y: height - 120, width: 75, height: 38)
    let bPath = CGPath(roundedRect: battBody, cornerWidth: 10, cornerHeight: 10, transform: nil)
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineWidth(3.5)
    ctx.addPath(bPath)
    ctx.strokePath()

    // Battery Cap
    let cap = CGRect(x: width - 107, y: height - 108, width: 6, height: 14)
    let capPath = CGPath(roundedRect: cap, cornerWidth: 3, cornerHeight: 3, transform: nil)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(capPath)
    ctx.fillPath()

    // Battery Fill (Green 100%)
    let fillRect = CGRect(x: width - 180, y: height - 115, width: 65, height: 28)
    let fillPath = CGPath(roundedRect: fillRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
    ctx.setFillColor(NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1.0).cgColor)
    ctx.addPath(fillPath)
    ctx.fillPath()
}

// Standard Apple iOS Tab Bar
func drawCleanTabBar(ctx: CGContext, activeIndex: Int) {
    let barH: CGFloat = 210
    let barRect = CGRect(x: 0, y: 0, width: width, height: barH)

    // Glass Background
    ctx.setFillColor(NSColor(white: 0.98, alpha: 0.98).cgColor)
    ctx.fill(barRect)

    // Top subtle divider
    ctx.setStrokeColor(NSColor(white: 0.88, alpha: 1.0).cgColor)
    ctx.setLineWidth(1.0)
    ctx.move(to: CGPoint(x: 0, y: barH))
    ctx.addLine(to: CGPoint(x: width, y: barH))
    ctx.strokePath()

    let tabs = [
        ("Today", "⚡"),
        ("Food", "🥗"),
        ("Train", "🏋️"),
        ("Progress", "📈"),
        ("Settings", "⚙️")
    ]

    let colW = width / CGFloat(tabs.count)
    for (i, t) in tabs.enumerated() {
        let isSel = (i == activeIndex)
        let cx = CGFloat(i) * colW + (colW / 2)

        if isSel {
            let pillRect = CGRect(x: cx - 65, y: 75, width: 130, height: 75)
            let pPath = CGPath(roundedRect: pillRect, cornerWidth: 37.5, cornerHeight: 37.5, transform: nil)
            ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.14).cgColor)
            ctx.addPath(pPath)
            ctx.fillPath()
        }

        let symAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 40)
        ]
        NSString(string: t.1).draw(at: CGPoint(x: cx - 20, y: 88), withAttributes: symAttrs)

        let lblAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: isSel ? .bold : .medium),
            .foregroundColor: isSel ? orange : NSColor(white: 0.55, alpha: 1.0)
        ]
        let s = NSString(string: t.0)
        let size = s.size(withAttributes: lblAttrs)
        s.draw(at: CGPoint(x: cx - (size.width / 2), y: 44), withAttributes: lblAttrs)
    }
}

// MARK: - 1. Render Food Screen
func renderFoodScreen() {
    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    ctx.setFillColor(NSColor(red: 246/255, green: 247/255, blue: 250/255, alpha: 1.0).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    drawCleanStatusBar(ctx: ctx)

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 46, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "Food Log").draw(at: CGPoint(x: width / 2 - 95, y: height - 240), withAttributes: titleAttrs)

    let plateBtnRect = CGRect(x: width - 240, y: height - 248, width: 175, height: 65)
    let platePath = CGPath(roundedRect: plateBtnRect, cornerWidth: 32.5, cornerHeight: 32.5, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(platePath)
    ctx.fillPath()
    let plateAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .bold),
        .foregroundColor: orange
    ]
    NSString(string: "🥗 The Plate").draw(at: CGPoint(x: width - 220, y: height - 230), withAttributes: plateAttrs)

    // 7-Day Adherence Strip Card
    let stripCardRect = CGRect(x: 50, y: height - 480, width: width - 100, height: 205)
    let stripPath = CGPath(roundedRect: stripCardRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(stripPath)
    ctx.fillPath()

    let days = [
        ("S", "25", true), ("M", "26", true), ("T", "27", true),
        ("W", "28", true), ("T", "29", false), ("F", "30", false), ("S", "31", false)
    ]
    let dayColW = (width - 140) / 7
    for (i, d) in days.enumerated() {
        let cx = 70 + CGFloat(i) * dayColW + (dayColW / 2)
        let isToday = (i == 4)

        let dLAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor(white: 0.55, alpha: 1.0)
        ]
        NSString(string: d.0).draw(at: CGPoint(x: cx - 7, y: height - 325), withAttributes: dLAttrs)

        let ringRect = CGRect(x: cx - 42, y: height - 435, width: 84, height: 84)
        let ringPath = CGPath(ellipseIn: ringRect, transform: nil)

        if isToday {
            ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.12).cgColor)
            ctx.addPath(ringPath)
            ctx.fillPath()
            ctx.setStrokeColor(orange.cgColor)
            ctx.setLineWidth(4)
            ctx.addPath(ringPath)
            ctx.strokePath()
        } else if d.2 {
            ctx.setStrokeColor(NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 0.9).cgColor)
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
            .font: NSFont.systemFont(ofSize: 30, weight: isToday ? .heavy : .bold),
            .foregroundColor: isToday ? orange : NSColor.black
        ]
        NSString(string: d.1).draw(at: CGPoint(x: cx - 17, y: height - 408), withAttributes: numAttrs)
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
        .foregroundColor: orange
    ]
    NSString(string: "1,755").draw(at: CGPoint(x: width - 360, y: height - 570), withAttributes: calNumAttrs)

    let calGoalAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
        .foregroundColor: NSColor.systemGray
    ]
    NSString(string: "/ 2,504 kcal").draw(at: CGPoint(x: width - 215, y: height - 560), withAttributes: calGoalAttrs)

    let barBgRect = CGRect(x: 85, y: height - 610, width: width - 170, height: 24)
    let barBgPath = CGPath(roundedRect: barBgRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.15).cgColor)
    ctx.addPath(barBgPath)
    ctx.fillPath()

    let barFillRect = CGRect(x: 85, y: height - 610, width: (width - 170) * 0.70, height: 24)
    let barFillPath = CGPath(roundedRect: barFillRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.setFillColor(orange.cgColor)
    ctx.addPath(barFillPath)
    ctx.fillPath()

    let macros = [
        ("Protein", "165 / 185g", NSColor(red: 236/255, green: 72/255, blue: 153/255, alpha: 1.0)),
        ("Carbs", "175 / 245g", NSColor(red: 6/255, green: 182/255, blue: 212/255, alpha: 1.0)),
        ("Fat", "42 / 60g", NSColor(red: 234/255, green: 179/255, blue: 8/255, alpha: 1.0))
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

    let actionButtons = [
        ("⏱ Hour-by-Hour", NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.12), orange),
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

    // Hourly Meals
    let meals = [
        ("8:30 AM", "Fage 0% Greek Yogurt with Honey & Berries", "250g • 230 kcal", "25P 18C 2F"),
        ("12:45 PM", "Double Chicken Burrito Bowl (Brown Rice, Fajitas)", "1 bowl • 740 kcal", "62P 68C 22F"),
        ("4:15 PM", "Gold Standard Whey & Banana Protein Shake", "1 shake • 320 kcal", "34P 38C 3F"),
        ("7:30 PM", "Pan-Seared Atlantic Salmon & Roasted Potatoes", "350g • 465 kcal", "44P 45C 15F")
    ]

    var mealY: CGFloat = height - 920
    for meal in meals {
        let mealCardRect = CGRect(x: 50, y: mealY - 140, width: width - 100, height: 125)
        let mealCardPath = CGPath(roundedRect: mealCardRect, cornerWidth: 28, cornerHeight: 28, transform: nil)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(mealCardPath)
        ctx.fillPath()

        let timePillRect = CGRect(x: 75, y: mealY - 58, width: 140, height: 36)
        let timePath = CGPath(roundedRect: timePillRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.setFillColor(NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.12).cgColor)
        ctx.addPath(timePath)
        ctx.fillPath()

        let tAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: orange
        ]
        NSString(string: meal.0).draw(at: CGPoint(x: 90, y: mealY - 53), withAttributes: tAttrs)

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSString(string: meal.1).draw(at: CGPoint(x: 75, y: mealY - 100), withAttributes: nameAttrs)

        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor(white: 0.45, alpha: 1.0)
        ]
        NSString(string: meal.2).draw(at: CGPoint(x: 75, y: mealY - 130), withAttributes: subAttrs)

        let macroAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .heavy),
            .foregroundColor: orange
        ]
        NSString(string: meal.3).draw(at: CGPoint(x: width - 260, y: mealY - 95), withAttributes: macroAttrs)

        mealY -= 150
    }

    // Dock
    let dockRect = CGRect(x: 70, y: 260, width: width - 140, height: 110)
    let dockPath = CGPath(roundedRect: dockRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 24, color: NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.35).cgColor)
    ctx.setFillColor(orange.cgColor)
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

    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    drawCleanTabBar(ctx: ctx, activeIndex: 1) // Food tab active

    img.unlockFocus()
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "TotalFactor/Resources/SideStore/screenshot_food.png"))
        print("✓ Saved screenshot_food.png")
    }
}

// MARK: - 2. Render Training Screen
func renderTrainScreen() {
    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    ctx.setFillColor(NSColor(red: 246/255, green: 247/255, blue: 250/255, alpha: 1.0).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    drawCleanStatusBar(ctx: ctx)

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 46, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "Strength Tracker").draw(at: CGPoint(x: 50, y: height - 240), withAttributes: titleAttrs)

    let routinePill = CGRect(x: width - 340, y: height - 248, width: 290, height: 60)
    let routinePath = CGPath(roundedRect: routinePill, cornerWidth: 30, cornerHeight: 30, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(routinePath)
    ctx.fillPath()
    let routineAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .bold),
        .foregroundColor: orange
    ]
    NSString(string: "🏋️ Planet Fitness Split").draw(at: CGPoint(x: width - 320, y: height - 232), withAttributes: routineAttrs)

    // Live Workout Card in Progress
    let liveCardRect = CGRect(x: 50, y: height - 440, width: width - 100, height: 175)
    let livePath = CGPath(roundedRect: liveCardRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setFillColor(NSColor(red: 20/255, green: 24/255, blue: 33/255, alpha: 1.0).cgColor)
    ctx.addPath(livePath)
    ctx.fillPath()

    ctx.setFillColor(NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: 85, y: height - 330, width: 22, height: 22))

    let liveAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 26, weight: .bold),
        .foregroundColor: NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1.0)
    ]
    NSString(string: "ACTIVE SESSION • 42:18").draw(at: CGPoint(x: 120, y: height - 332), withAttributes: liveAttrs)

    let wTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 38, weight: .black),
        .foregroundColor: NSColor.white
    ]
    NSString(string: "Upper Body Hypertrophy A").draw(at: CGPoint(x: 85, y: height - 390), withAttributes: wTitleAttrs)

    let wMetaAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .medium),
        .foregroundColor: NSColor(white: 0.7, alpha: 1.0)
    ]
    NSString(string: "4 of 6 exercises completed • 14 total sets logged").draw(at: CGPoint(x: 85, y: height - 425), withAttributes: wMetaAttrs)

    // Exercise Card
    let exCardRect = CGRect(x: 50, y: height - 1220, width: width - 100, height: 750)
    let exCardPath = CGPath(roundedRect: exCardRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(exCardPath)
    ctx.fillPath()

    let exTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 36, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "Incline Dumbbell Bench Press").draw(at: CGPoint(x: 85, y: height - 515), withAttributes: exTitleAttrs)

    let exSubAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
        .foregroundColor: orange
    ]
    NSString(string: "Target: 4 sets • 8–10 reps @ 2 RIR").draw(at: CGPoint(x: 85, y: height - 550), withAttributes: exSubAttrs)

    let thY = height - 610
    let thAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .bold),
        .foregroundColor: NSColor(white: 0.55, alpha: 1.0)
    ]
    NSString(string: "SET").draw(at: CGPoint(x: 95, y: thY), withAttributes: thAttrs)
    NSString(string: "PREVIOUS").draw(at: CGPoint(x: 230, y: thY), withAttributes: thAttrs)
    NSString(string: "WEIGHT (LB)").draw(at: CGPoint(x: 470, y: thY), withAttributes: thAttrs)
    NSString(string: "REPS").draw(at: CGPoint(x: 750, y: thY), withAttributes: thAttrs)
    NSString(string: "RIR").draw(at: CGPoint(x: 950, y: thY), withAttributes: thAttrs)

    let setsData = [
        ("1", "70 lb × 10", "75", "10", "2", true),
        ("2", "70 lb × 9",  "75", "10", "2", true),
        ("3", "70 lb × 8",  "75", "9",  "1", true),
        ("4", "70 lb × 8",  "75", "8",  "0", false)
    ]

    var rowY = height - 690
    for s in setsData {
        let isDone = s.5
        let rowBg = CGRect(x: 75, y: rowY - 15, width: width - 150, height: 68)
        let rowPath = CGPath(roundedRect: rowBg, cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.setFillColor(isDone ? NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 0.08).cgColor : NSColor(white: 0.96, alpha: 1.0).cgColor)
        ctx.addPath(rowPath)
        ctx.fillPath()

        let setNumAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .black),
            .foregroundColor: isDone ? NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1.0) : NSColor.black
        ]
        NSString(string: s.0).draw(at: CGPoint(x: 105, y: rowY), withAttributes: setNumAttrs)

        let prevAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: NSColor(white: 0.5, alpha: 1.0)
        ]
        NSString(string: s.1).draw(at: CGPoint(x: 230, y: rowY), withAttributes: prevAttrs)

        let wtAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSString(string: s.2).draw(at: CGPoint(x: 520, y: rowY), withAttributes: wtAttrs)
        NSString(string: s.3).draw(at: CGPoint(x: 770, y: rowY), withAttributes: wtAttrs)

        let rirPillRect = CGRect(x: 935, y: rowY - 6, width: 85, height: 44)
        let rirPath = CGPath(roundedRect: rirPillRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.setFillColor(orange.cgColor)
        ctx.addPath(rirPath)
        ctx.fillPath()

        let rirAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .heavy),
            .foregroundColor: NSColor.white
        ]
        NSString(string: "@" + s.4).draw(at: CGPoint(x: 955, y: rowY), withAttributes: rirAttrs)

        rowY -= 82
    }

    // Rest Timer Bar
    let timerBarRect = CGRect(x: 50, y: height - 1420, width: width - 100, height: 170)
    let timerBarPath = CGPath(roundedRect: timerBarRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setFillColor(orange.cgColor)
    ctx.addPath(timerBarPath)
    ctx.fillPath()

    let tIconAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 44),
        .foregroundColor: NSColor.white
    ]
    NSString(string: "⏱").draw(at: CGPoint(x: 85, y: height - 1345), withAttributes: tIconAttrs)

    let tTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 34, weight: .black),
        .foregroundColor: NSColor.white
    ]
    NSString(string: "REST TIMER • 1:32 REMAINING").draw(at: CGPoint(x: 155, y: height - 1335), withAttributes: tTitleAttrs)

    let tSubAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor(white: 1.0, alpha: 0.9)
    ]
    NSString(string: "Live Activity active on Lock Screen & Apple Watch with haptic alert").draw(at: CGPoint(x: 155, y: height - 1375), withAttributes: tSubAttrs)

    // Muscle Targets
    let heatCardRect = CGRect(x: 50, y: 260, width: width - 100, height: 420)
    let heatCardPath = CGPath(roundedRect: heatCardRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(heatCardPath)
    ctx.fillPath()

    let heatTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 32, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "Hypertrophy Volume Targets").draw(at: CGPoint(x: 85, y: 620), withAttributes: heatTitleAttrs)

    let muscles = [
        ("Chest", "14 / 16 sets", "Optimal Zone", NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1.0)),
        ("Front Delts", "10 / 12 sets", "Optimal Zone", NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1.0)),
        ("Side / Rear Delts", "16 / 18 sets", "Peak Stimulus", orange),
        ("Triceps", "12 / 14 sets", "Optimal Zone", NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1.0))
    ]

    var mY: CGFloat = 550
    for m in muscles {
        let mLAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSString(string: m.0).draw(at: CGPoint(x: 85, y: mY), withAttributes: mLAttrs)

        let setsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .heavy),
            .foregroundColor: orange
        ]
        NSString(string: m.1).draw(at: CGPoint(x: width - 420, y: mY), withAttributes: setsAttrs)

        let zonePillRect = CGRect(x: width - 250, y: mY - 6, width: 170, height: 38)
        let zPath = CGPath(roundedRect: zonePillRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.setFillColor(m.3.withAlphaComponent(0.15).cgColor)
        ctx.addPath(zPath)
        ctx.fillPath()

        let zoneAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: m.3
        ]
        NSString(string: m.2).draw(at: CGPoint(x: width - 235, y: mY), withAttributes: zoneAttrs)

        mY -= 65
    }

    drawCleanTabBar(ctx: ctx, activeIndex: 2) // Train tab active

    img.unlockFocus()
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "TotalFactor/Resources/SideStore/screenshot_train.png"))
        print("✓ Saved screenshot_train.png")
    }
}

// MARK: - 3. Render Progress Screen
func renderProgressScreen() {
    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    ctx.setFillColor(NSColor(red: 246/255, green: 247/255, blue: 250/255, alpha: 1.0).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    drawCleanStatusBar(ctx: ctx)

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 46, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "Progress & Coaching").draw(at: CGPoint(x: 50, y: height - 240), withAttributes: titleAttrs)

    // Dynamic Expenditure TDEE Card
    let expCardRect = CGRect(x: 50, y: height - 600, width: width - 100, height: 330)
    let expPath = CGPath(roundedRect: expCardRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(expPath)
    ctx.fillPath()

    let expTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 32, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "Adaptive Expenditure (TDEE)").draw(at: CGPoint(x: 85, y: height - 330), withAttributes: expTitleAttrs)

    let expNumAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 64, weight: .black),
        .foregroundColor: NSColor(red: 147/255, green: 51/255, blue: 234/255, alpha: 1.0)
    ]
    NSString(string: "2,772 kcal").draw(at: CGPoint(x: 85, y: height - 425), withAttributes: expNumAttrs)

    let trendPillRect = CGRect(x: width - 340, y: height - 335, width: 250, height: 48)
    let trendPath = CGPath(roundedRect: trendPillRect, cornerWidth: 24, cornerHeight: 24, transform: nil)
    ctx.setFillColor(NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 0.14).cgColor)
    ctx.addPath(trendPath)
    ctx.fillPath()

    let trendAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .bold),
        .foregroundColor: NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1.0)
    ]
    NSString(string: "↗ +28 kcal / week").draw(at: CGPoint(x: width - 315, y: height - 323), withAttributes: trendAttrs)

    let expDescAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .medium),
        .foregroundColor: NSColor(white: 0.45, alpha: 1.0)
    ]
    NSString(string: "Calculated dynamically from real weight trend and nutrition intake without smartwatch calorie inaccuracies.").draw(at: CGPoint(x: 85, y: height - 490), withAttributes: expDescAttrs)

    let balRect = CGRect(x: 85, y: height - 570, width: width - 170, height: 50)
    let balPath = CGPath(roundedRect: balRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
    ctx.setFillColor(NSColor(red: 246/255, green: 247/255, blue: 250/255, alpha: 1.0).cgColor)
    ctx.addPath(balPath)
    ctx.fillPath()

    let balAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .bold),
        .foregroundColor: orange
    ]
    NSString(string: "Today's Net Deficit: -1,517 kcal (1,255 eaten • 2,772 burned)").draw(at: CGPoint(x: 110, y: height - 557), withAttributes: balAttrs)

    // Weight Trend Card
    let wtCardRect = CGRect(x: 50, y: height - 1280, width: width - 100, height: 640)
    let wtPath = CGPath(roundedRect: wtCardRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(wtPath)
    ctx.fillPath()

    let wtTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 32, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "Weight Trend & Scale Moving Average").draw(at: CGPoint(x: 85, y: height - 680), withAttributes: wtTitleAttrs)

    let wtNumAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 56, weight: .black),
        .foregroundColor: NSColor.black
    ]
    NSString(string: "180.5 lb").draw(at: CGPoint(x: 85, y: height - 760), withAttributes: wtNumAttrs)

    let wtDeltaAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 28, weight: .bold),
        .foregroundColor: NSColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1.0)
    ]
    NSString(string: "↘ -1.2 lb this week (0.66% / week)").draw(at: CGPoint(x: 350, y: height - 750), withAttributes: wtDeltaAttrs)

    // Chart Canvas
    let chartX: CGFloat = 85
    let chartY: CGFloat = height - 1220
    let chartW: CGFloat = width - 170
    let chartH: CGFloat = 380

    ctx.setStrokeColor(NSColor(white: 0.92, alpha: 1.0).cgColor)
    ctx.setLineWidth(1.5)
    for i in 0...4 {
        let gy = chartY + CGFloat(i) * (chartH / 4)
        ctx.move(to: CGPoint(x: chartX, y: gy))
        ctx.addLine(to: CGPoint(x: chartX + chartW, y: gy))
    }
    ctx.strokePath()

    let points: [CGPoint] = [
        CGPoint(x: chartX, y: chartY + 340),
        CGPoint(x: chartX + chartW * 0.15, y: chartY + 310),
        CGPoint(x: chartX + chartW * 0.30, y: chartY + 280),
        CGPoint(x: chartX + chartW * 0.45, y: chartY + 240),
        CGPoint(x: chartX + chartW * 0.60, y: chartY + 200),
        CGPoint(x: chartX + chartW * 0.80, y: chartY + 140),
        CGPoint(x: chartX + chartW, y: chartY + 90)
    ]

    let fillPath = CGMutablePath()
    fillPath.move(to: CGPoint(x: chartX, y: chartY))
    fillPath.addLine(to: points[0])
    for p in points.dropFirst() {
        fillPath.addLine(to: p)
    }
    fillPath.addLine(to: CGPoint(x: chartX + chartW, y: chartY))
    fillPath.closeSubpath()

    let gradColors = [
        NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.25).cgColor,
        NSColor(red: 255/255, green: 91/255, blue: 0/255, alpha: 0.0).cgColor
    ] as CFArray
    if let areaGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradColors, locations: [1.0, 0.0]) {
        ctx.saveGState()
        ctx.addPath(fillPath)
        ctx.clip()
        ctx.drawLinearGradient(areaGrad, start: CGPoint(x: 0, y: chartY + chartH), end: CGPoint(x: 0, y: chartY), options: [])
        ctx.restoreGState()
    }

    ctx.setStrokeColor(orange.cgColor)
    ctx.setLineWidth(5.0)
    let linePath = CGMutablePath()
    linePath.move(to: points[0])
    for p in points.dropFirst() {
        linePath.addLine(to: p)
    }
    ctx.addPath(linePath)
    ctx.strokePath()

    for p in points {
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
        ctx.setStrokeColor(orange.cgColor)
        ctx.setLineWidth(4)
        ctx.strokeEllipse(in: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
    }

    // Weekly Check-in Banner
    let checkinRect = CGRect(x: 50, y: 260, width: width - 100, height: 260)
    let checkinPath = CGPath(roundedRect: checkinRect, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.setFillColor(orange.cgColor)
    ctx.addPath(checkinPath)
    ctx.fillPath()

    let cIconAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 44),
        .foregroundColor: NSColor.white
    ]
    NSString(string: "🎯").draw(at: CGPoint(x: 85, y: 440), withAttributes: cIconAttrs)

    let cTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 34, weight: .black),
        .foregroundColor: NSColor.white
    ]
    NSString(string: "WEEKLY ADAPTIVE COACHING CHECK-IN").draw(at: CGPoint(x: 155, y: 450), withAttributes: cTitleAttrs)

    let cSubAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor(white: 1.0, alpha: 0.92)
    ]
    NSString(string: "Your metabolism increased by +28 kcal. Tap to review recommended calorie update and target progression for next week.").draw(at: CGPoint(x: 155, y: 360), withAttributes: cSubAttrs)

    drawCleanTabBar(ctx: ctx, activeIndex: 3) // Progress tab active

    img.unlockFocus()
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "TotalFactor/Resources/SideStore/screenshot_progress.png"))
        print("✓ Saved screenshot_progress.png")
    }
}

renderFoodScreen()
renderTrainScreen()
renderProgressScreen()
print("All clean screenshots generated successfully!")

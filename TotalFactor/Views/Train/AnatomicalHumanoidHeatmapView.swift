import SwiftUI

/// Spec MacroFactor Workouts Anatomical Humanoid Heatmap
/// Renders crisp vector front-and-back anatomical human silhouettes in SwiftUI `Canvas`,
/// illuminating worked muscle groups in vibrant MacroFactor royal blue (`#2F7CF6`).
struct AnatomicalHumanoidHeatmapView: View {
    let workedMuscles: Set<MuscleGroup>
    var accentColor: Color = Color(red: 0.18, green: 0.48, blue: 0.96) // MacroFactor Royal Blue
    var height: CGFloat = 260
    var showLabels: Bool = true

    init(
        workedMuscles: Set<MuscleGroup>,
        accentColor: Color = Color(red: 0.18, green: 0.48, blue: 0.96),
        height: CGFloat = 260,
        showLabels: Bool = true
    ) {
        self.workedMuscles = workedMuscles
        self.accentColor = accentColor
        self.height = height
        self.showLabels = showLabels
    }

    var body: some View {
        HStack(spacing: 24) {
            figureView(isFront: true, label: "Front")
            figureView(isFront: false, label: "Back")
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func figureView(isFront: Bool, label: String) -> some View {
        VStack(spacing: 6) {
            Canvas { context, size in
                drawHumanoid(in: &context, size: size, isFront: isFront)
            }
            .frame(width: height * 0.44, height: height * 0.88)

            if showLabels {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
            }
        }
    }

    private func isWorked(_ muscles: [MuscleGroup]) -> Bool {
        muscles.contains { workedMuscles.contains($0) }
    }

    private func color(for muscles: [MuscleGroup], baseInactive: Color) -> Color {
        if isWorked(muscles) {
            return accentColor
        }
        return baseInactive
    }

    private func drawHumanoid(in ctx: inout GraphicsContext, size: CGSize, isFront: Bool) {
        let w = size.width
        let h = size.height
        let cx = w / 2.0
        let baseInactive = Color(uiColor: .systemGray5).opacity(0.85)
        let strokeColor = Color.primary.opacity(0.08)

        func drawPill(
            x: CGFloat,
            y: CGFloat,
            width: CGFloat,
            height: CGFloat,
            cornerRadius: CGFloat,
            muscles: [MuscleGroup]?
        ) {
            let rect = CGRect(x: x - width / 2.0, y: y - height / 2.0, width: width, height: height)
            let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
            let fillColor = muscles != nil ? color(for: muscles!, baseInactive: baseInactive) : baseInactive
            ctx.fill(path, with: .color(fillColor))
            ctx.stroke(path, with: .color(strokeColor), lineWidth: 0.8)
        }

        func drawSymmetricPills(
            xOffset: CGFloat,
            y: CGFloat,
            width: CGFloat,
            height: CGFloat,
            cornerRadius: CGFloat,
            muscles: [MuscleGroup]? = nil
        ) {
            drawPill(x: cx - xOffset, y: y, width: width, height: height, cornerRadius: cornerRadius, muscles: muscles)
            drawPill(x: cx + xOffset, y: y, width: width, height: height, cornerRadius: cornerRadius, muscles: muscles)
        }

        // 1. Head & Neck
        drawPill(x: cx, y: h * 0.055, width: w * 0.22, height: h * 0.08, cornerRadius: w * 0.11, muscles: nil)
        drawPill(x: cx, y: h * 0.105, width: w * 0.12, height: h * 0.035, cornerRadius: 4, muscles: nil)

        // 2. Traps
        let trapColor = color(for: [.traps], baseInactive: baseInactive)
        var trapPath = Path()
        trapPath.move(to: CGPoint(x: cx - w * 0.06, y: h * 0.10))
        trapPath.addLine(to: CGPoint(x: cx - w * 0.20, y: h * 0.14))
        trapPath.addLine(to: CGPoint(x: cx + w * 0.20, y: h * 0.14))
        trapPath.addLine(to: CGPoint(x: cx + w * 0.06, y: h * 0.10))
        trapPath.closeSubpath()
        ctx.fill(trapPath, with: .color(trapColor))
        ctx.stroke(trapPath, with: .color(strokeColor), lineWidth: 0.8)

        // 3. Shoulders (Deltoids)
        let deltMuscles: [MuscleGroup] = isFront ? [.frontDelts, .sideDelts] : [.rearDelts, .sideDelts]
        drawSymmetricPills(
            xOffset: w * 0.25,
            y: h * 0.17,
            width: w * 0.17,
            height: h * 0.08,
            cornerRadius: 8,
            muscles: deltMuscles
        )

        // 4. Arms: Upper Arms (Biceps vs Triceps) & Forearms
        let upperArmMuscles: [MuscleGroup] = isFront ? [.biceps] : [.triceps]
        drawSymmetricPills(
            xOffset: w * 0.29,
            y: h * 0.26,
            width: w * 0.14,
            height: h * 0.10,
            cornerRadius: 7,
            muscles: upperArmMuscles
        )
        drawSymmetricPills(
            xOffset: w * 0.33,
            y: h * 0.38,
            width: w * 0.12,
            height: h * 0.12,
            cornerRadius: 6,
            muscles: [.forearms]
        )
        // Hands
        drawPill(x: cx - w * 0.36, y: h * 0.46, width: w * 0.08, height: h * 0.04, cornerRadius: 4, muscles: nil)
        drawPill(x: cx + w * 0.36, y: h * 0.46, width: w * 0.08, height: h * 0.04, cornerRadius: 4, muscles: nil)

        // 5. Torso
        if isFront {
            // Chest (Left & Right Pectorals)
            drawPill(x: cx - w * 0.10, y: h * 0.20, width: w * 0.18, height: h * 0.08, cornerRadius: 6, muscles: [.chest])
            drawPill(x: cx + w * 0.10, y: h * 0.20, width: w * 0.18, height: h * 0.08, cornerRadius: 6, muscles: [.chest])

            // Core / Abs (6-pack segments) & Obliques
            let abRows: [CGFloat] = [0.27, 0.33, 0.39]
            for r in abRows {
                drawPill(x: cx - w * 0.07, y: h * r, width: w * 0.12, height: h * 0.05, cornerRadius: 4, muscles: [.abs])
                drawPill(x: cx + w * 0.07, y: h * r, width: w * 0.12, height: h * 0.05, cornerRadius: 4, muscles: [.abs])
            }
            // Obliques
            drawSymmetricPills(xOffset: w * 0.16, y: h * 0.33, width: w * 0.07, height: h * 0.12, cornerRadius: 4, muscles: [.abs])
            // Pelvis
            drawPill(x: cx, y: h * 0.45, width: w * 0.32, height: h * 0.06, cornerRadius: 6, muscles: nil)
        } else {
            // Upper Back & Mid Traps
            drawPill(x: cx, y: h * 0.19, width: w * 0.32, height: h * 0.07, cornerRadius: 6, muscles: [.upperBack, .traps])

            // Lats (Left & Right)
            drawSymmetricPills(xOffset: w * 0.11, y: h * 0.28, width: w * 0.15, height: h * 0.10, cornerRadius: 6, muscles: [.lats])

            // Lower Back (Erectors)
            drawPill(x: cx, y: h * 0.36, width: w * 0.20, height: h * 0.06, cornerRadius: 5, muscles: [.upperBack])

            // Glutes (Left & Right Buttocks)
            drawSymmetricPills(xOffset: w * 0.10, y: h * 0.44, width: w * 0.18, height: h * 0.09, cornerRadius: 8, muscles: [.glutes])
        }

        // 6. Lower Body: Thighs (Quads vs Hamstrings) & Calves
        if isFront {
            // Quads (Vastus lateralis, rectus femoris, vastus medialis)
            drawSymmetricPills(xOffset: w * 0.12, y: h * 0.56, width: w * 0.18, height: h * 0.15, cornerRadius: 10, muscles: [.quads])
            // Knees
            drawSymmetricPills(xOffset: w * 0.12, y: h * 0.66, width: w * 0.11, height: h * 0.04, cornerRadius: 5, muscles: nil)
            // Shin / Calves
            drawSymmetricPills(xOffset: w * 0.12, y: h * 0.77, width: w * 0.14, height: h * 0.16, cornerRadius: 8, muscles: [.calves])
            // Feet
            drawSymmetricPills(xOffset: w * 0.14, y: h * 0.88, width: w * 0.12, height: h * 0.04, cornerRadius: 4, muscles: nil)
        } else {
            // Hamstrings
            drawSymmetricPills(xOffset: w * 0.12, y: h * 0.56, width: w * 0.18, height: h * 0.15, cornerRadius: 10, muscles: [.hamstrings])
            // Knee back
            drawSymmetricPills(xOffset: w * 0.12, y: h * 0.66, width: w * 0.11, height: h * 0.04, cornerRadius: 5, muscles: nil)
            // Calves (Gastrocnemius diamond split)
            drawSymmetricPills(xOffset: w * 0.12, y: h * 0.77, width: w * 0.15, height: h * 0.16, cornerRadius: 8, muscles: [.calves])
            // Heels / Feet
            drawSymmetricPills(xOffset: w * 0.12, y: h * 0.88, width: w * 0.10, height: h * 0.04, cornerRadius: 4, muscles: nil)
        }
    }
}

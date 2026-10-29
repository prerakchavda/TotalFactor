import SwiftUI
import SwiftData
import Charts

struct ProgressHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(HealthKitService.self) private var healthService

    @Query private var profiles: [UserProfile]
    @Query private var goals: [Goal]
    @Query(sort: \ExpenditureEstimate.date) private var expenditureHistory: [ExpenditureEstimate]
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]
    @Query private var sessions: [WorkoutSession]

    @State private var selectedRange: ProgressChartRange = .oneMonth
    @State private var selectedWeightChartDate: Date? = nil
    @State private var selectedMetricType: BodyMetricType = .waist
    @State private var addSheetMetricType: BodyMetricType = .waist
    @State private var showingAddMetricSheet: Bool = false
    @State private var showingPhotosSheet: Bool = false
    @State private var newMetricValue: Double = 32.0

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    var body: some View {
        let digest = CoachingCoordinator.cachedOrComputeDigest(context: modelContext)
        let filteredWeights = filterByRange(digest.weightSeries, datePath: \.date)
        let filteredCombined = filterByRange(digest.combinedWeightStrengthSeries, datePath: \.date)
        let filteredExpenditure = filterByRange(expenditureHistory, datePath: \.date)
        let allLBM = bodyMetrics.filter { $0.type == .leanBodyMass }
        let filteredLBM = filterByRange(allLBM, datePath: \.date)

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Range", selection: $selectedRange) {
                        ForEach(ProgressChartRange.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)

                    weightTrendCard(points: filteredWeights, summary: digest.weightSummary)

                    leanBodyMassCard(
                        points: filteredLBM,
                        latestOverall: allLBM.last,
                        currentTrendWeightKg: digest.weightSummary.latestTrendKg
                    )

                    combinedWeightStrengthCard(points: filteredCombined)

                    expenditureCard(estimates: filteredExpenditure, latest: digest.expenditure)

                    MuscleVolumeMapView(sessions: sessions)

                    bodyMetricsCard

                    Button {
                        showingPhotosSheet = true
                    } label: {
                        HStack {
                            Label("Progress Photos & Pose Slider", systemImage: "photo.on.rectangle.angled")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(16)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .padding(.bottom, 70)
            }
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.showingWeighInSheet = true
                    } label: {
                        Label("Log Weight", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingPhotosSheet) {
                PhotoCompareView(unitSystem: profile.unitSystem, currentWeightKg: digest.weightSummary.latestTrendKg)
            }
            .sheet(isPresented: $showingAddMetricSheet) {
                NavigationStack {
                    Form {
                        Picker("Measurement", selection: $addSheetMetricType) {
                            ForEach(BodyMetricType.allCases) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        HStack {
                            Text("Value (\(addSheetMetricType.unitLabel(for: profile.unitSystem)))")
                            Spacer()
                            TextField("0.0", value: $newMetricValue, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .navigationTitle("Log Body Metric")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAddMetricSheet = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let storedValue = addSheetMetricType.internalValue(fromDisplay: newMetricValue, system: profile.unitSystem)
                                let metric = BodyMetric(type: addSheetMetricType, value: storedValue)
                                modelContext.insert(metric)
                                try? modelContext.save()
                                if addSheetMetricType == .leanBodyMass {
                                    Task { await healthService.saveManualLeanBodyMass(metric) }
                                }
                                showingAddMetricSheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.height(280)])
            }
        }
    }

    // MARK: - Cards

    private func weightTrendCard(points: [DailyWeightPoint], summary: WeightTrendSummary) -> some View {
        let unit = profile.unitSystem
        let yValues = points.flatMap { pt -> [Double] in
            var arr = [UnitsFormatter.displayWeight(pt.trendKg, system: unit)]
            if let s = pt.scaleKg { arr.append(UnitsFormatter.displayWeight(s, system: unit)) }
            return arr
        }
        let yMin = (yValues.min() ?? 150) - 2.0
        let yMax = (yValues.max() ?? 180) + 2.0

        let activeGoal = goals.first
        var projectedGoalDateString: String? = nil
        if let g = activeGoal, let targetKg = g.targetWeightKg, let currentTrend = summary.latestTrendKg, g.ratePercentPerWeek > 0.05 {
            let diffKg = abs(targetKg - currentTrend)
            let weeklyRateKg = currentTrend * (g.ratePercentPerWeek / 100.0)
            if weeklyRateKg > 0.05 {
                let weeks = max(0.5, diffKg / weeklyRateKg)
                if let targetDate = Calendar.current.date(byAdding: .day, value: Int(weeks * 7), to: .now) {
                    let formattedDate = targetDate.formatted(date: .abbreviated, time: .omitted)
                    let wCount = Int(ceil(weeks))
                    projectedGoalDateString = "🎯 Goal Target: \(UnitsFormatter.formatWeight(targetKg, system: unit)) • Est. \(formattedDate) (\(wCount)w)"
                }
            }
        }

        return VStack(alignment: .leading, spacing: 14) {
            NavigationLink(destination: WeightDetailView()) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        AppleIconBadge(icon: "scalemass.fill", color: AppleTheme.trend, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Weight Trend")
                                    .font(.headline.weight(.bold))
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            if let proj = projectedGoalDateString {
                                Text(proj)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppleTheme.trend)
                            } else if let weekly = summary.weeklyRateKg {
                                Text("Velocity: \(UnitsFormatter.formatSignedWeightDelta(weekly, system: unit))/wk")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    if let latest = summary.latestTrendKg {
                        Text(UnitsFormatter.formatWeight(latest, system: unit))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppleTheme.trend)
                    }
                }
            }
            .buttonStyle(.plain)

            if points.isEmpty {
                Text("Log your first weigh-in to plot scale dots and smoothed trend weight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(points) { pt in
                        if let scale = pt.scaleKg {
                            PointMark(
                                x: .value("Date", pt.date),
                                y: .value("Scale", UnitsFormatter.displayWeight(scale, system: unit))
                            )
                            .foregroundStyle(Color.secondary.opacity(0.40))
                            .symbolSize(24)
                        }
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("Trend", UnitsFormatter.displayWeight(pt.trendKg, system: unit))
                        )
                        .foregroundStyle(AppleTheme.trend)
                        .lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round))
                    }

                    if let selectedWeightChartDate,
                       let matched = points.min(by: { abs($0.date.timeIntervalSince(selectedWeightChartDate)) < abs($1.date.timeIntervalSince(selectedWeightChartDate)) }) {
                        RuleMark(x: .value("Selected Date", matched.date))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .annotation(position: .top, spacing: 6) {
                                VStack(spacing: 2) {
                                    Text(matched.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2.weight(.bold))
                                    HStack(spacing: 6) {
                                        if let s = matched.scaleKg {
                                            Text("Scale: \(UnitsFormatter.formatWeight(s, system: unit))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text("Trend: \(UnitsFormatter.formatWeight(matched.trendKg, system: unit))")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(AppleTheme.trend)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.12), radius: 3)
                            }
                    }
                }
                .chartYScale(domain: yMin...yMax)
                .chartXSelection(value: $selectedWeightChartDate)
                .frame(height: 190)
            }

            HStack {
                deltaChip("7d", deltaKg: summary.change7dKg)
                deltaChip("14d", deltaKg: summary.change14dKg)
                deltaChip("30d", deltaKg: summary.change30dKg)
            }

            NavigationLink(destination: WeightDetailView()) {
                HStack {
                    Text("View Weigh-Ins by Date & Full History")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(AppleTheme.trend)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
        .appleHealthCard(padding: 18)
    }

    private func leanBodyMassCard(
        points: [BodyMetric],
        latestOverall: BodyMetric?,
        currentTrendWeightKg: Double?
    ) -> some View {
        let unit = profile.unitSystem
        let dispValues = points.map { UnitsFormatter.displayWeight($0.value, system: unit) }
        let yMin = (dispValues.min() ?? 120) - 2.5
        let yMax = (dispValues.max() ?? 160) + 2.5
        let rangeDeltaKg: Double? = (points.count >= 2) ? (points.last!.value - points.first!.value) : nil

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lean Body Mass (FFM)")
                        .font(.headline)
                    if let lbmKg = latestOverall?.value,
                       let bwKg = currentTrendWeightKg,
                       bwKg > 0 {
                        let ffmPct = min(98.0, max(40.0, (lbmKg / bwKg) * 100.0))
                        Text(String(format: "%.1f%% fat-free mass • Auto-imports from Apple Health", ffmPct))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Imports smart-scale / DEXA lean mass from Apple Health")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let latestKg = latestOverall?.value {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(UnitsFormatter.formatWeight(latestKg, system: unit))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.teal)
                        if let deltaKg = rangeDeltaKg {
                            Text(UnitsFormatter.formatSignedWeightDelta(deltaKg, system: unit))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("+ Log") {
                    openAddMetricSheet(for: .leanBodyMass, defaultKg: latestOverall?.value ?? ((currentTrendWeightKg ?? 80.0) * 0.82))
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if points.isEmpty {
                Text("Step on a smart scale synced with Apple Health or tap + Log to track fat-free mass retention across cuts and bulks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(points) { item in
                    let disp = UnitsFormatter.displayWeight(item.value, system: unit)
                    AreaMark(
                        x: .value("Date", item.date),
                        yStart: .value("Min", yMin),
                        yEnd: .value("Lean Mass", disp)
                    )
                    .foregroundStyle(Color.teal.opacity(0.14))

                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Lean Mass", disp)
                    )
                    .foregroundStyle(.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.2))

                    PointMark(
                        x: .value("Date", item.date),
                        y: .value("Lean Mass", disp)
                    )
                    .foregroundStyle(.teal)
                }
                .chartYScale(domain: yMin...yMax)
                .frame(height: 155)
            }
        }
        .appleHealthCard(padding: 18)
    }

    private func deltaChip(_ label: String, deltaKg: Double?) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(deltaKg.map { UnitsFormatter.formatSignedWeightDelta($0, system: profile.unitSystem) } ?? "—")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Spec §12 ("One chart"): Weight trend and strength trend (sum of top compound e1RMs) on the same timeline!
    private func combinedWeightStrengthCard(points: [CombinedTrendPoint]) -> some View {
        let strengthPoints = points.filter { $0.strengthIndexKg != nil }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Body Weight × Strength Index")
                        .font(.headline)
                    Text("Normalized % change from window start (Top 3 compound e1RM sum vs Trend BW)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if points.count < 2 || strengthPoints.isEmpty {
                Text("Log weigh-ins and compound lifts across sessions to compare body weight velocity against strength retention/gain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let baseBW = max(1.0, points.first?.trendWeightKg ?? 80.0)
                let baseStr = max(1.0, strengthPoints.first?.strengthIndexKg ?? 200.0)

                Chart {
                    ForEach(points) { pt in
                        let bwPct = ((pt.trendWeightKg - baseBW) / baseBW) * 100.0
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("% Change", bwPct),
                            series: .value("Metric", "Trend Weight")
                        )
                        .foregroundStyle(.blue)

                        if let s = pt.strengthIndexKg {
                            let strPct = ((s - baseStr) / baseStr) * 100.0
                            LineMark(
                                x: .value("Date", pt.date),
                                y: .value("% Change", strPct),
                                series: .value("Metric", "Strength Index")
                            )
                            .foregroundStyle(.green)
                        }
                    }
                }
                .chartForegroundStyleScale(["Trend Weight": Color.blue, "Strength Index": Color.green])
                .frame(height: 180)
            }
        }
        .appleHealthCard(padding: 18)
    }

    private func expenditureCard(estimates: [ExpenditureEstimate], latest: ExpenditureSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Adaptive Expenditure")
                    .font(.headline)
                Spacer()
                ConfidencePill(confidence: latest.confidence)
            }

            if estimates.count >= 2 {
                Chart(estimates) { est in
                    LineMark(
                        x: .value("Date", est.date),
                        y: .value("kcal", est.value)
                    )
                    .foregroundStyle(.orange)
                }
                .frame(height: 150)
            }

            Text(latest.confidence.explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .appleHealthCard(padding: 18)
    }

    private var bodyMetricsCard: some View {
        let filtered = filterByRange(bodyMetrics.filter { $0.type == selectedMetricType }, datePath: \.date)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Body Measurements")
                    .font(.headline)
                Spacer()
                Button("+ Log") {
                    openAddMetricSheet(for: selectedMetricType, defaultKg: nil)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Picker("Metric", selection: $selectedMetricType) {
                ForEach([BodyMetricType.waist, .bodyFat, .leanBodyMass, .chest, .arm, .thigh]) { m in
                    Text(m == .leanBodyMass ? "LBM" : m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)

            if filtered.isEmpty {
                Text("No \(selectedMetricType.displayName) entries in this window yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(filtered) { item in
                    let disp = item.type.displayValue(item.value, system: profile.unitSystem)
                    LineMark(x: .value("Date", item.date), y: .value("Value", disp))
                    PointMark(x: .value("Date", item.date), y: .value("Value", disp))
                }
                .frame(height: 140)
            }
        }
        .appleHealthCard(padding: 18)
    }

    private func openAddMetricSheet(for metricType: BodyMetricType, defaultKg: Double?) {
        addSheetMetricType = metricType
        if let latest = bodyMetrics.last(where: { $0.type == metricType }) {
            newMetricValue = (metricType.displayValue(latest.value, system: profile.unitSystem) * 10).rounded() / 10.0
        } else if metricType == .leanBodyMass, let kg = defaultKg {
            newMetricValue = (UnitsFormatter.displayWeight(kg, system: profile.unitSystem) * 10).rounded() / 10.0
        } else if metricType == .bodyFat {
            newMetricValue = 16.0
        } else {
            newMetricValue = profile.unitSystem == .imperial ? 32.0 : 81.0
        }
        showingAddMetricSheet = true
    }

    private func filterByRange<T>(_ items: [T], datePath: KeyPath<T, Date>) -> [T] {
        guard let days = selectedRange.daysBack,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else {
            return items
        }
        return items.filter { $0[keyPath: datePath] >= cutoff }
    }
}

import SwiftUI
import SwiftData
import Charts

struct WeightDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(HealthKitService.self) private var healthService

    @Query(sort: \WeighIn.date, order: .reverse) private var weighIns: [WeighIn]
    @Query private var profiles: [UserProfile]
    @Query private var goals: [Goal]

    @State private var selectedRange: ProgressChartRange = .oneMonth
    @State private var scrubbedDate: Date? = nil
    @State private var showingAddSheet: Bool = false
    @State private var editingWeighIn: WeighIn? = nil
    @State private var searchText: String = ""

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    private var unit: UnitSystem {
        profile.unitSystem
    }

    private var activeGoal: Goal? {
        goals.first(where: \.isActive) ?? goals.first
    }

    private var filteredWeighIns: [WeighIn] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return weighIns
        }
        let query = searchText.lowercased()
        return weighIns.filter { w in
            let dateStr = w.date.formatted(date: .complete, time: .shortened).lowercased()
            let weightStr = UnitsFormatter.formatWeight(w.weightKg, system: unit).lowercased()
            return dateStr.contains(query) || weightStr.contains(query) || w.dayKey.contains(query)
        }
    }

    var body: some View {
        let digest = CoachingCoordinator.cachedOrComputeDigest(context: modelContext)
        let filteredSeries = filterSeries(digest.weightSeries)
        let trendByDay = Dictionary(digest.weightSeries.map { ($0.dayKey, $0.trendKg) }, uniquingKeysWith: { first, _ in first })

        ScrollView {
            VStack(spacing: 20) {
                // 1. Hero KPI Card
                heroMetricsCard(summary: digest.weightSummary)

                // 2. Interactive Chart Card
                chartCard(series: filteredSeries)

                // 3. Weigh-In History List
                historySection(trendByDay: trendByDay)
            }
            .padding()
            .padding(.bottom, 60)
        }
        .navigationTitle("Weight Trend & History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Log Weight", systemImage: "plus")
                        .font(.headline)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWeighInSheet(defaultWeightKg: digest.weightSummary.latestScaleKg ?? profile.startingWeightKg, unitSystem: unit)
        }
        .sheet(item: $editingWeighIn) { w in
            EditWeighInSheet(weighIn: w, unitSystem: unit)
        }
    }

    // MARK: - Subviews

    private func heroMetricsCard(summary: WeightTrendSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        AppleIconBadge(icon: "scalemass.fill", color: AppleTheme.trend, size: 24)
                        Text("Current Weight Trend")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let trend = summary.latestTrendKg {
                        Text(UnitsFormatter.formatWeight(trend, system: unit))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    } else {
                        Text("No data")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let latestScale = summary.latestScaleKg {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Latest Scale")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(UnitsFormatter.formatWeight(latestScale, system: unit))
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(AppleTheme.trend)

                        if let firstDate = weighIns.first?.date {
                            Text(dateRelativeShort(firstDate))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            Divider()

            // 4 Mini KPIs
            let firstWeightKg = weighIns.last?.weightKg
            let allTimeDeltaKg = (summary.latestTrendKg != nil && firstWeightKg != nil)
                ? (summary.latestTrendKg! - firstWeightKg!)
                : nil

            HStack(spacing: 8) {
                metricTile(
                    title: "7-Day Rate",
                    value: summary.weeklyRateKg.map { UnitsFormatter.formatSignedWeightDelta($0, system: unit) + "/wk" } ?? "—",
                    color: AppleTheme.trend
                )
                metricTile(
                    title: "30-Day Change",
                    value: summary.change30dKg.map { UnitsFormatter.formatSignedWeightDelta($0, system: unit) } ?? "—",
                    color: AppleTheme.trend
                )
                metricTile(
                    title: "Total Change",
                    value: allTimeDeltaKg.map { UnitsFormatter.formatSignedWeightDelta($0, system: unit) } ?? "—",
                    color: allTimeDeltaKg != nil ? (allTimeDeltaKg! <= 0 ? .green : .orange) : .secondary
                )
            }

            if let g = activeGoal, let targetKg = g.targetWeightKg, let currentTrend = summary.latestTrendKg {
                let diffKg = currentTrend - targetKg
                let absDiff = abs(diffKg)
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .foregroundStyle(Color.accentColor)
                    Text("Goal Target: \(UnitsFormatter.formatWeight(targetKg, system: unit))")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.1f %@ to go", UnitsFormatter.displayWeight(absDiff, system: unit), unit.weightSymbol))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppleTheme.trend)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .appleHealthCard(padding: 18)
    }

    private func metricTile(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func chartCard(series: [DailyWeightPoint]) -> some View {
        let yValues = series.flatMap { pt -> [Double] in
            var arr = [UnitsFormatter.displayWeight(pt.trendKg, system: unit)]
            if let s = pt.scaleKg { arr.append(UnitsFormatter.displayWeight(s, system: unit)) }
            return arr
        }
        let yMin = (yValues.min() ?? 140) - 2.5
        let yMax = (yValues.max() ?? 180) + 2.5

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Trend & Scale Trajectory")
                    .font(.headline.weight(.bold))
                Spacer()
                Picker("Range", selection: $selectedRange) {
                    ForEach(ProgressChartRange.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            if series.isEmpty {
                Text("No weigh-ins in this timeframe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Chart {
                    ForEach(series) { pt in
                        // Trend Area
                        AreaMark(
                            x: .value("Date", pt.date),
                            yStart: .value("Min", yMin),
                            yEnd: .value("Trend", UnitsFormatter.displayWeight(pt.trendKg, system: unit))
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppleTheme.trend.opacity(0.25), AppleTheme.trend.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Trend Line
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("Trend", UnitsFormatter.displayWeight(pt.trendKg, system: unit))
                        )
                        .foregroundStyle(AppleTheme.trend)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        // Scale dots
                        if let scale = pt.scaleKg {
                            PointMark(
                                x: .value("Date", pt.date),
                                y: .value("Scale", UnitsFormatter.displayWeight(scale, system: unit))
                            )
                            .foregroundStyle(Color.secondary.opacity(0.45))
                            .symbolSize(28)
                        }
                    }

                    // Target line
                    if let targetKg = activeGoal?.targetWeightKg {
                        let targetDisp = UnitsFormatter.displayWeight(targetKg, system: unit)
                        RuleMark(y: .value("Target", targetDisp))
                            .foregroundStyle(Color.green.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .annotation(position: .trailing, alignment: .leading) {
                                Text("Goal")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                            }
                    }

                    // Interactive Scrubbing Rule
                    if let scrubbedDate,
                       let matched = series.min(by: { abs($0.date.timeIntervalSince(scrubbedDate)) < abs($1.date.timeIntervalSince(scrubbedDate)) }) {
                        RuleMark(x: .value("Selected", matched.date))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .annotation(position: .top, spacing: 6) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(matched.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2.weight(.bold))
                                    HStack(spacing: 8) {
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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.12), radius: 4)
                            }
                    }
                }
                .chartYScale(domain: yMin...yMax)
                .chartXSelection(value: $scrubbedDate)
                .frame(height: 210)

                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(AppleTheme.trend).frame(width: 8, height: 8)
                        Text("Smoothed Trend")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color.secondary.opacity(0.45)).frame(width: 8, height: 8)
                        Text("Scale Weigh-In")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Touch & scrub chart to inspect dates")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .appleHealthCard(padding: 18)
    }

    private func historySection(trendByDay: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weigh-Ins at Dates")
                        .font(.headline.weight(.bold))
                    Text("\(filteredWeighIns.count) recorded entries • Tap any entry to edit or view details")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if weighIns.count > 6 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search dates (e.g. Oct 28, 2026)...", text: $searchText)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if filteredWeighIns.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "scalemass")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.top, 16)
                    Text(searchText.isEmpty ? "No weigh-ins logged yet" : "No weigh-ins matching \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        showingAddSheet = true
                    } label: {
                        Text("Log First Weigh-In")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)
                .appleHealthCard(padding: 16)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(filteredWeighIns.enumerated()), id: \.element.id) { index, item in
                        let prevItem: WeighIn? = (index + 1 < filteredWeighIns.count) ? filteredWeighIns[index + 1] : nil
                        let deltaKg: Double? = prevItem.map { item.weightKg - $0.weightKg }
                        let dayTrendKg = trendByDay[item.dayKey]

                        weighInRow(
                            item: item,
                            deltaKg: deltaKg,
                            trendKg: dayTrendKg
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingWeighIn = item
                        }
                        .contextMenu {
                            Button {
                                editingWeighIn = item
                            } label: {
                                Label("Edit Weigh-In", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteWeighIn(item)
                            } label: {
                                Label("Delete Weigh-In", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func weighInRow(item: WeighIn, deltaKg: Double?, trendKg: Double?) -> some View {
        HStack(spacing: 12) {
            // Source icon
            Image(systemName: item.source == .healthKit ? "heart.fill" : "scalemass.fill")
                .font(.footnote)
                .foregroundStyle(item.source == .healthKit ? .red : AppleTheme.trend)
                .frame(width: 28, height: 28)
                .background((item.source == .healthKit ? Color.red : AppleTheme.trend).opacity(0.12), in: Circle())

            // Date & Time
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(dateFormattedHeader(item.date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if item.dayKey == DayKey.today {
                        Text("Today")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text(item.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let trend = trendKg {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Trend: \(UnitsFormatter.formatWeight(trend, system: unit))")
                            .font(.caption2)
                            .foregroundStyle(AppleTheme.trend)
                    }

                    if item.source == .healthKit {
                        Text("• Apple Health")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Scale Weight & Delta
            VStack(alignment: .trailing, spacing: 2) {
                Text(UnitsFormatter.formatWeight(item.weightKg, system: unit))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                if let delta = deltaKg {
                    HStack(spacing: 2) {
                        Image(systemName: delta <= 0 ? "arrow.down" : "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                        Text(UnitsFormatter.formatSignedWeightDelta(delta, system: unit))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                    }
                    .foregroundStyle(delta <= 0 ? .green : .orange)
                } else {
                    Text("Baseline")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(AppleTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers

    private func filterSeries(_ series: [DailyWeightPoint]) -> [DailyWeightPoint] {
        guard let days = selectedRange.daysBack else { return series }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return series.filter { $0.date >= cutoff }
    }

    private func dateFormattedHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private func dateRelativeShort(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func deleteWeighIn(_ item: WeighIn) {
        withAnimation {
            modelContext.delete(item)
            try? modelContext.save()
            _ = CoachingCoordinator.evaluate(context: modelContext)
        }
    }
}

// MARK: - Add Weigh-In Sheet

struct AddWeighInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let defaultWeightKg: Double
    let unitSystem: UnitSystem

    @State private var weightText: String = ""
    @State private var weighDate: Date = .now
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Button {
                            nudge(-0.2)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            TextField("0.0", text: $weightText)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                                .multilineTextAlignment(.center)
                                .focused($focused)

                            Text(unitSystem.weightSymbol)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            nudge(+0.2)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                } header: {
                    Text("Scale Weight")
                }

                Section {
                    DatePicker("Date & Time", selection: $weighDate)
                } header: {
                    Text("Recorded Time")
                } footer: {
                    Text("You can record past weigh-ins to backfill your trend history and expenditure tracking.")
                }

                Section {
                    Button {
                        saveWeighIn()
                    } label: {
                        Text("Save Weigh-In")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Log Weigh-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                let disp = UnitsFormatter.displayWeight(defaultWeightKg, system: unitSystem)
                weightText = String(format: "%.1f", disp)
                focused = true
            }
        }
    }

    private func nudge(_ delta: Double) {
        let current = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? UnitsFormatter.displayWeight(defaultWeightKg, system: unitSystem)
        weightText = String(format: "%.1f", max(30, current + delta))
    }

    private func saveWeighIn() {
        guard let val = Double(weightText.replacingOccurrences(of: ",", with: ".")), val > 20 else { return }
        let kg = UnitsFormatter.internalKg(fromDisplay: val, system: unitSystem)
        let entry = WeighIn(date: weighDate, weightKg: kg, source: .manual)
        modelContext.insert(entry)
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)
        Task {
            await HealthKitService.shared.saveManualWeighIn(entry)
        }
        dismiss()
    }
}

// MARK: - Edit Weigh-In Sheet

struct EditWeighInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let weighIn: WeighIn
    let unitSystem: UnitSystem

    @State private var weightText: String = ""
    @State private var weighDate: Date = .now
    @State private var showDeleteAlert: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Button {
                            nudge(-0.2)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            TextField("0.0", text: $weightText)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                                .multilineTextAlignment(.center)
                                .focused($focused)

                            Text(unitSystem.weightSymbol)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            nudge(+0.2)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                } header: {
                    Text("Scale Weight")
                }

                Section {
                    DatePicker("Date & Time", selection: $weighDate)
                } header: {
                    Text("Recorded Time")
                }

                Section {
                    HStack {
                        Text("Entry Source")
                        Spacer()
                        Text(weighIn.source == .healthKit ? "Apple Health" : "Manual")
                            .foregroundStyle(.secondary)
                    }
                    if let uuid = weighIn.healthKitUUID {
                        HStack {
                            Text("HealthKit ID")
                            Spacer()
                            Text(uuid.uuidString.prefix(8) + "...")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Save Changes") {
                        saveChanges()
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Weigh-In")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Weigh-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete Weigh-In?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteEntry()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove the scale entry recorded on \(weighIn.date.formatted(date: .abbreviated, time: .shortened)).")
            }
            .onAppear {
                let disp = UnitsFormatter.displayWeight(weighIn.weightKg, system: unitSystem)
                weightText = String(format: "%.1f", disp)
                weighDate = weighIn.date
            }
        }
    }

    private func nudge(_ delta: Double) {
        let current = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? UnitsFormatter.displayWeight(weighIn.weightKg, system: unitSystem)
        weightText = String(format: "%.1f", max(30, current + delta))
    }

    private func saveChanges() {
        guard let val = Double(weightText.replacingOccurrences(of: ",", with: ".")), val > 20 else { return }
        let kg = UnitsFormatter.internalKg(fromDisplay: val, system: unitSystem)
        weighIn.weightKg = kg
        weighIn.date = weighDate
        weighIn.dayKey = DayKey.from(weighDate)
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)
        dismiss()
    }

    private func deleteEntry() {
        modelContext.delete(weighIn)
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(context: modelContext)
        dismiss()
    }
}

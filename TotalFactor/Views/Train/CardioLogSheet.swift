import SwiftUI
import SwiftData

// MARK: - Cardio Log Sheet

/// Add or edit a cardio session (run, walk, incline walk, cycling, elliptical, stair climber,
/// rowing, swimming, other). Duration is required; distance, average heart rate, calories and
/// notes are optional. Saving writes to SwiftData and (re-)writes the Apple Health workout.
struct CardioLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// nil when logging a new session.
    let session: CardioSession?
    let unitSystem: UnitSystem

    static let lastKindDefaultsKey = "totalfactor.cardio.lastKind"
    private static let durationPresetsMinutes: [Int] = [10, 15, 20, 30, 45, 60, 90]

    @State private var kind: CardioKind
    @State private var start: Date
    @State private var hoursText: String
    @State private var minutesText: String
    @State private var secondsText: String
    @State private var distanceText: String
    @State private var heartRateText: String
    @State private var caloriesText: String
    @State private var notes: String
    @State private var showingDeleteConfirm: Bool = false

    init(session: CardioSession? = nil, unitSystem: UnitSystem, defaultKind: CardioKind? = nil) {
        self.session = session
        self.unitSystem = unitSystem

        let lastUsed = UserDefaults.standard.string(forKey: Self.lastKindDefaultsKey).flatMap { CardioKind(rawValue: $0) }
        let initialKind = session?.kind ?? defaultKind ?? lastUsed ?? .run
        let seconds = max(0, session?.durationSeconds ?? 30 * 60)

        _kind = State(initialValue: initialKind)
        _start = State(initialValue: session?.start ?? Date.now.addingTimeInterval(-TimeInterval(seconds)))
        _hoursText = State(initialValue: seconds >= 3600 ? "\(seconds / 3600)" : "")
        _minutesText = State(initialValue: "\((seconds % 3600) / 60)")
        _secondsText = State(initialValue: seconds % 60 > 0 ? "\(seconds % 60)" : "")

        var initialDistance = ""
        if let meters = session?.distanceMeters, meters > 0 {
            let unit = CardioDistanceUnit.preferred(for: initialKind, system: unitSystem)
            initialDistance = Self.inputString(unit.displayValue(fromMeters: meters), decimals: unit.displayDecimals)
        }
        _distanceText = State(initialValue: initialDistance)

        var initialHR = ""
        if let hr = session?.avgHeartRate, hr > 0 {
            initialHR = "\(Int(hr.rounded()))"
        }
        _heartRateText = State(initialValue: initialHR)

        var initialKcal = ""
        if let kcal = session?.activeCalories, kcal > 0 {
            initialKcal = "\(Int(kcal.rounded()))"
        }
        _caloriesText = State(initialValue: initialKcal)

        _notes = State(initialValue: session?.notes ?? "")
    }

    private var isEditing: Bool { session != nil }

    private var distanceUnit: CardioDistanceUnit {
        CardioDistanceUnit.preferred(for: kind, system: unitSystem)
    }

    private var totalSeconds: Int {
        let h = Self.parseInt(hoursText)
        let m = Self.parseInt(minutesText)
        let s = Self.parseInt(secondsText)
        return min(h * 3600 + m * 60 + s, 24 * 3600)
    }

    private var parsedDistanceMeters: Double? {
        guard let display = Self.parseDecimal(distanceText) else { return nil }
        return distanceUnit.meters(fromDisplay: min(display, 100_000))
    }

    private var parsedHeartRate: Double? {
        guard let hr = Self.parseDecimal(heartRateText), (25...250).contains(hr) else { return nil }
        return hr.rounded()
    }

    private var parsedCalories: Double? {
        guard let kcal = Self.parseDecimal(caloriesText) else { return nil }
        return min(kcal, 10_000).rounded()
    }

    var body: some View {
        NavigationStack {
            Form {
                if let source = session?.sourceLabel {
                    Section {
                        Label("Imported from \(source)", systemImage: "heart.text.square.fill")
                            .font(.subheadline.weight(.semibold))
                    } footer: {
                        Text("Edits stay in Total Factor; the original workout in Apple Health isn't changed.")
                    }
                }
                activitySection
                whenSection
                detailsSection
                Section("Notes") {
                    TextField("How did it feel? Route, machine settings...", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Cardio Session", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Cardio" : "Log Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(totalSeconds <= 0)
                }
            }
            .onChange(of: kind) { oldKind, newKind in
                convertDistanceText(from: oldKind, to: newKind)
            }
            .confirmationDialog(
                "Delete this cardio session?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteSession()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(session?.importedFromHealth == true
                     ? "It's removed from Total Factor and won't be imported again. The workout stays in Apple Health."
                     : "This can't be undone. The matching Apple Health workout is removed too.")
            }
        }
    }

    // MARK: - Sections

    private var activitySection: some View {
        Section("Activity") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(CardioKind.allCases) { option in
                    let isSelected = option == kind
                    Button {
                        kind = option
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option.sfSymbol)
                                .font(.title3)
                                .frame(height: 24)
                            Text(option.displayName)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(isSelected ? AppleTheme.background : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? Color.primary : AppleTheme.tertiarySurface)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var whenSection: some View {
        Section {
            DatePicker("Start", selection: $start, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])

            HStack(spacing: 4) {
                Text("Duration")
                Spacer(minLength: 8)
                durationField(text: $hoursText, unit: "h", width: 34)
                durationField(text: $minutesText, unit: "m", width: 40)
                durationField(text: $secondsText, unit: "s", width: 40)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.durationPresetsMinutes, id: \.self) { mins in
                        Button("\(mins) min") {
                            hoursText = mins >= 60 ? "\(mins / 60)" : ""
                            minutesText = "\(mins % 60)"
                            secondsText = ""
                        }
                        .buttonStyle(.mfChip)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("When")
        } footer: {
            if totalSeconds <= 0 {
                Text("Duration is required.")
            } else {
                Text("Ends \(start.addingTimeInterval(TimeInterval(totalSeconds)).formatted(date: .omitted, time: .shortened)) • \(CardioSession.formatDuration(seconds: totalSeconds))")
            }
        }
    }

    private var detailsSection: some View {
        Section {
            numericRow(title: "Distance", text: $distanceText, unit: distanceUnit.symbol, keyboard: .decimalPad)
            numericRow(title: "Avg Heart Rate", text: $heartRateText, unit: "bpm", keyboard: .numberPad)
            numericRow(title: "Active Calories", text: $caloriesText, unit: "kcal", keyboard: .numberPad)
            if let pace = paceText {
                HStack {
                    Text(kind == .cycling ? "Avg Speed" : "Avg Pace")
                    Spacer()
                    Text(pace)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Details (Optional)")
        } footer: {
            Text("Distance is shown in \(distanceUnit.symbol) based on your unit setting. Saved sessions are written to Apple Health as workouts.")
        }
    }

    private func durationField(text: Binding<String>, unit: String, width: CGFloat) -> some View {
        HStack(spacing: 2) {
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: width)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func numericRow(title: String, text: Binding<String>, unit: String, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 90)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    /// Pace per distance unit (per 100 m/yd for swimming) or speed for cycling.
    private var paceText: String? {
        guard let meters = parsedDistanceMeters, meters > 0, totalSeconds > 0 else { return nil }
        let unit = distanceUnit
        let distanceInUnit = unit.displayValue(fromMeters: meters)
        guard distanceInUnit > 0 else { return nil }

        switch kind {
        case .cycling:
            let speed = distanceInUnit / (Double(totalSeconds) / 3600.0)
            let label = unit == .miles ? "mph" : "km/h"
            return String(format: "%.1f %@", speed, label)
        case .swimming:
            let per100 = Double(totalSeconds) / (distanceInUnit / 100.0)
            return "\(Self.clockString(seconds: per100)) /100 \(unit.symbol)"
        default:
            let perUnit = Double(totalSeconds) / distanceInUnit
            return "\(Self.clockString(seconds: perUnit)) /\(unit.symbol)"
        }
    }

    // MARK: - Actions

    private func convertDistanceText(from oldKind: CardioKind, to newKind: CardioKind) {
        let oldUnit = CardioDistanceUnit.preferred(for: oldKind, system: unitSystem)
        let newUnit = CardioDistanceUnit.preferred(for: newKind, system: unitSystem)
        guard oldUnit != newUnit, let value = Self.parseDecimal(distanceText) else { return }
        let meters = oldUnit.meters(fromDisplay: value)
        distanceText = Self.inputString(newUnit.displayValue(fromMeters: meters), decimals: newUnit.displayDecimals)
    }

    private func save() {
        let seconds = totalSeconds
        guard seconds > 0 else { return }

        let target: CardioSession
        if let session {
            target = session
        } else {
            target = CardioSession()
            modelContext.insert(target)
        }
        let previousHealthKitUUID = target.healthKitWorkoutUUID

        target.kind = kind
        target.start = start
        target.dayKey = DayKey.from(start)
        target.durationSeconds = seconds
        target.distanceMeters = parsedDistanceMeters
        target.avgHeartRate = parsedHeartRate
        target.activeCalories = parsedCalories
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()

        UserDefaults.standard.set(kind.rawValue, forKey: Self.lastKindDefaultsKey)

        // Imported workouts belong to the app that recorded them; edits stay local.
        guard !target.importedFromHealth else { return }

        // Re-write the Apple Health workout (delete the old one first when editing).
        let context = modelContext
        Task { @MainActor in
            let health = HealthKitService.shared
            if let previousHealthKitUUID {
                await health.deleteCardioWorkout(uuid: previousHealthKitUUID)
                target.healthKitWorkoutUUID = nil
            }
            await health.saveCardioWorkout(target)
            try? context.save()
        }
    }

    private func deleteSession() {
        guard let session else { return }
        let context = modelContext
        let target = session
        let wasImported = session.importedFromHealth
        let healthKitUUID = session.healthKitWorkoutUUID
        if wasImported, let healthKitUUID {
            CardioImportPreference.dismiss(healthKitUUID)
        }
        dismiss()
        // Delete after the sheet closes so nothing renders a deleted model.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            context.delete(target)
            try? context.save()
            if !wasImported, let healthKitUUID {
                await HealthKitService.shared.deleteCardioWorkout(uuid: healthKitUUID)
            }
        }
    }

    // MARK: - Parsing & Formatting

    private static func parseInt(_ text: String) -> Int {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else { return 0 }
        return min(max(value, 0), 9_999)
    }

    private static func parseDecimal(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }

    /// "5.00" -> "5", "3.10" -> "3.1"
    private static func inputString(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// 512.4 -> "8:32", 3725 -> "1:02:05"
    static func clockString(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Cardio History Card

/// Train-tab card: this week's cardio minutes / distance / sessions, the last few sessions
/// (tap to edit) and a "Log Cardio" button.
struct CardioHistoryCard: View {
    let sessions: [CardioSession]
    let unitSystem: UnitSystem
    let onLog: () -> Void
    let onSelect: (CardioSession) -> Void
    /// Pulls new cardio from Apple Health (Apple Watch Workout app, Fitness, Strava…).
    var onSyncHealth: (() -> Void)? = nil
    var isSyncing: Bool = false

    private let calendar = Calendar.current

    var body: some View {
        let sorted = sessions.sorted { $0.start > $1.start }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
        let thisWeek = sorted.filter { $0.start >= weekStart }
        let weekSeconds = thisWeek.reduce(0) { $0 + max(0, $1.durationSeconds) }
        let weekMeters = thisWeek.reduce(0.0) { $0 + max(0, $1.distanceMeters ?? 0) }
        let longUnit: CardioDistanceUnit = unitSystem == .imperial ? .miles : .kilometers
        let recent = Array(sorted.prefix(5))

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cardio")
                    .font(.headline)
                Spacer()
                if let onSyncHealth {
                    Button {
                        onSyncHealth()
                    } label: {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.mfChip)
                    .disabled(isSyncing)
                }
                Button {
                    onLog()
                } label: {
                    Label("Log Cardio", systemImage: "plus")
                }
                .buttonStyle(.mfChip)
            }

            HStack(spacing: 8) {
                statTile(value: "\(weekSeconds / 60)", label: "Min This Week")
                statTile(
                    value: weekMeters > 0 ? longUnit.format(meters: weekMeters, includeUnit: false) : "—",
                    label: "\(longUnit.symbol) This Week"
                )
                statTile(value: "\(thisWeek.count)", label: "Sessions")
            }

            if recent.isEmpty {
                Text("Runs, walks and rides from your Apple Watch or the Fitness app show up here automatically. You can also log cardio by hand; it's saved to Apple Health.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recent) { s in
                    Button {
                        onSelect(s)
                    } label: {
                        row(s)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .appleHealthCard(padding: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ s: CardioSession) -> some View {
        HStack(spacing: 12) {
            AppleIconBadge(icon: s.kind.sfSymbol, color: AppleTheme.trend, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(s.kind.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(DayKey.displayTitle(for: s.dayKey)) • \(s.start.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if s.importedFromHealth {
                    Label(s.sourceName.isEmpty ? "Apple Health" : s.sourceName, systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(s.formattedDuration)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                if let distance = s.formattedDistance(system: unitSystem) {
                    Text(distance)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AppleTheme.tertiarySurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

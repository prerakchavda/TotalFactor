import SwiftUI
import SwiftData

struct FoodTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(HealthKitService.self) private var healthService

    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodLogEntry.timestamp, order: .forward) private var allEntries: [FoodLogEntry]
    @Query private var dailyNotes: [DailyNote]
    @Query private var allFoods: [Food]
    @Query private var customNutrientTargets: [NutrientTarget]

    @AppStorage("totalfactor.foodTimeline.groupByMeal") private var groupByMeal: Bool = false

    @State private var isSelecting: Bool = false
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var editingEntry: FoodLogEntry? = nil
    @State private var targetCopyDate: Date = .now
    @State private var showingCopyMoveSheet: Bool = false
    @State private var moveInsteadOfCopy: Bool = false
    @State private var showingCopyFromAnyDateSheet: Bool = false
    @State private var showingDailyNoteEditor: Bool = false
    @State private var showingSaveAsRecipeAlert: Bool = false
    @State private var newRecipeName: String = ""
    @State private var showingMicronutrients: Bool = false

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    private var activeDayKey: String {
        appState.selectedDayKey
    }

    private var dayEntries: [FoodLogEntry] {
        allEntries.filter { $0.dayKey == activeDayKey }
    }

    private var dayNote: DailyNote? {
        dailyNotes.first { $0.dayKey == activeDayKey }
    }

    private var dayNoteTrimmed: String {
        (dayNote?.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedMealGroups: [MealTag] {
        let standardSlots: [MealTag] = [.breakfast, .lunch, .dinner, .snack]
        let extraTags: [MealTag] = [.preWorkout, .postWorkout, .none]
        var ordered = standardSlots
        let presentTags = Set(dayEntries.map(\.mealTag))
        for tag in extraTags where presentTags.contains(tag) {
            ordered.append(tag)
        }
        return ordered
    }

    var body: some View {
        let digest = CoachingCoordinator.cachedOrComputeDigest(forDayKey: activeDayKey, context: modelContext)
        let targets = digest.todayTargets
        let eaten = sumNutrients(dayEntries)
        let zones = MacroTargetEngine.nutrientZones(
            for: targets,
            sex: profile.biologicalSex,
            customOverrides: customNutrientTargets.map(\.asStruct)
        )
        let zoneByName = Dictionary(zones.map { ($0.nutrient.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let calZone = zoneByName["calories"]

        NavigationStack {
            VStack(spacing: 0) {
                // Top Macro Zone Summary Header (§6)
                VStack(spacing: 10) {
                    HStack {
                        Button {
                            appState.selectedDayKey = DayKey.addingDays(-1, to: activeDayKey)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Text(DayKey.displayTitle(for: activeDayKey))
                            .font(.headline)
                        Spacer()
                        Button {
                            toggleComplete()
                        } label: {
                            let done = dayNote?.isComplete ?? false
                            Label(done ? "Complete" : "Mark Complete", systemImage: done ? "checkmark.circle.fill" : "circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(done ? .green : .secondary)
                        }
                        Button {
                            appState.selectedDayKey = DayKey.addingDays(1, to: activeDayKey)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                    }

                    MacroZoneBar(
                        title: "Calories",
                        current: eaten.calories,
                        unit: "kcal",
                        floor: calZone != nil ? calZone!.floor : (targets.calories * 0.92).rounded(),
                        target: calZone != nil ? calZone!.target : targets.calories,
                        ceiling: calZone != nil ? calZone!.ceiling : (targets.calories * 1.05).rounded(),
                        tint: .orange
                    )

                    HStack(spacing: 14) {
                        compactMacroPill(
                            "P",
                            current: eaten.protein,
                            target: zoneByName["protein"]?.target ?? targets.protein,
                            floor: zoneByName["protein"]?.floor ?? targets.proteinFloor,
                            color: .red
                        )
                        compactMacroPill(
                            "C",
                            current: eaten.carbs,
                            target: zoneByName["carbs"]?.target ?? targets.carbs,
                            floor: zoneByName["carbs"]?.floor,
                            color: .blue
                        )
                        compactMacroPill(
                            "F",
                            current: eaten.fat,
                            target: zoneByName["fat"]?.target ?? targets.fat,
                            floor: zoneByName["fat"]?.floor ?? targets.fatFloor,
                            color: .yellow
                        )
                    }

                    // View-mode toggle (Timeline vs By Meal), Day Note button, and Voice/Copy shortcuts
                    HStack(spacing: 8) {
                        Button {
                            groupByMeal.toggle()
                        } label: {
                            Label(
                                groupByMeal ? "Grouped by Meal" : "Timeline",
                                systemImage: groupByMeal ? "rectangle.grid.1x2.fill" : "clock"
                            )
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                groupByMeal ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.13),
                                in: Capsule()
                            )
                            .foregroundStyle(groupByMeal ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingDailyNoteEditor = true
                        } label: {
                            Label(
                                dayNoteTrimmed.isEmpty ? "Day Note" : "Edit Note",
                                systemImage: dayNoteTrimmed.isEmpty ? "note.text.badge.plus" : "note.text"
                            )
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                dayNoteTrimmed.isEmpty ? Color.secondary.opacity(0.13) : Color.orange.opacity(0.16),
                                in: Capsule()
                            )
                            .foregroundStyle(dayNoteTrimmed.isEmpty ? Color.primary : Color.orange)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            appState.openQuickAdd(tab: 5)
                        } label: {
                            Label("Describe / Voice", systemImage: "waveform.and.mic")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.06))

                if !dayNoteTrimmed.isEmpty {
                    dailyNotePreviewBanner
                }

                if isSelecting && !selectedEntryIDs.isEmpty {
                    multiSelectActionBar
                }

                if dayEntries.isEmpty && !groupByMeal {
                    ContentUnavailableView {
                        Label("No Foods Logged", systemImage: "fork.knife")
                    } description: {
                        Text("Tap + to log in 2 taps, dictate a full meal by voice, or copy meals from any date.")
                    } actions: {
                        VStack(spacing: 10) {
                            HStack {
                                Button("Add Food") {
                                    appState.openQuickAdd(tab: 0)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Describe / Voice") {
                                    appState.openQuickAdd(tab: 5)
                                }
                                .buttonStyle(.bordered)
                            }
                            HStack {
                                Button("Copy Yesterday") {
                                    copyDayEntries(from: DayKey.addingDays(-1, to: activeDayKey), to: activeDayKey)
                                }
                                .buttonStyle(.bordered)

                                Button("Copy From Date...") {
                                    showingCopyFromAnyDateSheet = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } else if groupByMeal {
                    mealGroupedListView
                } else {
                    chronologicalListView
                }
            }
            .navigationTitle("Food Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selectedEntryIDs.removeAll() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingMicronutrients = true
                        } label: {
                            Label("Micronutrients & Targets", systemImage: "pills.fill")
                        }
                        Button {
                            groupByMeal.toggle()
                        } label: {
                            Label(
                                groupByMeal ? "Switch to Chronological Timeline" : "Group by Meal Tag",
                                systemImage: groupByMeal ? "clock" : "rectangle.grid.1x2.fill"
                            )
                        }
                        Button {
                            showingDailyNoteEditor = true
                        } label: {
                            Label(dayNoteTrimmed.isEmpty ? "Add Day Note" : "Edit Day Note", systemImage: "note.text")
                        }
                        Divider()
                        Button {
                            copyDayEntries(from: DayKey.addingDays(-1, to: activeDayKey), to: activeDayKey)
                        } label: {
                            Label("Copy Yesterday to This Day", systemImage: "doc.on.doc")
                        }
                        Button {
                            showingCopyFromAnyDateSheet = true
                        } label: {
                            Label("Copy From Any Date...", systemImage: "calendar.badge.plus")
                        }
                        Divider()
                        Button {
                            appState.openQuickAdd(tab: 5)
                        } label: {
                            Label("Describe / Voice Meal", systemImage: "waveform.and.mic")
                        }
                        Button {
                            appState.openQuickAdd(tab: 1)
                        } label: {
                            Label("Scan Barcode", systemImage: "barcode.viewfinder")
                        }
                        Button {
                            appState.openQuickAdd(tab: 4)
                        } label: {
                            Label("Recipes", systemImage: "book.closed")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $editingEntry) { entry in
                EditLoggedFoodSheet(entry: entry)
            }
            .sheet(isPresented: $showingCopyMoveSheet) {
                NavigationStack {
                    Form {
                        DatePicker("Destination Day", selection: $targetCopyDate, displayedComponents: .date)
                        Button(moveInsteadOfCopy ? "Move \(selectedEntryIDs.count) Entries" : "Copy \(selectedEntryIDs.count) Entries") {
                            performBulkCopyOrMove()
                            showingCopyMoveSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .navigationTitle(moveInsteadOfCopy ? "Move Entries" : "Copy Entries")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingCopyMoveSheet = false }
                        }
                    }
                }
                .presentationDetents([.height(260)])
            }
            .sheet(isPresented: $showingCopyFromAnyDateSheet) {
                CopyFromAnyDateSheet(
                    destinationDayKey: activeDayKey,
                    allEntries: allEntries,
                    onCopyEntries: { entriesToCopy in
                        copySpecificEntries(entriesToCopy, to: activeDayKey)
                    }
                )
            }
            .sheet(isPresented: $showingDailyNoteEditor) {
                DailyNoteEditorSheet(
                    dayKey: activeDayKey,
                    initialNotes: dayNote?.notes ?? "",
                    onSave: { updatedText in
                        saveDailyNote(updatedText)
                    }
                )
            }
            .alert("Save Selected as Recipe", isPresented: $showingSaveAsRecipeAlert) {
                TextField("Recipe Name", text: $newRecipeName)
                Button("Save") { saveSelectedEntriesAsRecipe() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingMicronutrients) {
                MicronutrientDetailSheet(
                    dayKey: activeDayKey,
                    entries: dayEntries,
                    targets: targets,
                    sex: profile.biologicalSex
                )
            }
        }
    }

    // MARK: - Subviews

    private var dailyNotePreviewBanner: some View {
        Button {
            showingDailyNoteEditor = true
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "note.text")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                Text(dayNoteTrimmed)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.08))
        }
        .buttonStyle(.plain)
    }

    private var chronologicalListView: some View {
        List {
            if activeDayKey == DayKey.today && !healthService.todayExternalWorkouts.isEmpty {
                Section("Apple Fitness Workouts (Display Only)") {
                    ForEach(healthService.todayExternalWorkouts) { wk in
                        HStack(spacing: 12) {
                            Text(wk.emoji)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wk.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(wk.durationMinutes) min • \(Int(wk.activeCalories)) active kcal • \(wk.sourceAppName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(wk.startDate, format: .dateTime.hour().minute())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            ForEach(dayEntries) { entry in
                timelineRow(entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteEntry(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            duplicateEntryToNow(entry)
                        } label: {
                            Label("Repeat", systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                    }
            }
        }
        .listStyle(.plain)
    }

    private var mealGroupedListView: some View {
        List {
            ForEach(displayedMealGroups) { tag in
                let items = dayEntries.filter { $0.mealTag == tag }
                let subtotal = sumNutrients(items)

                Section {
                    if items.isEmpty {
                        Button {
                            appState.openQuickAdd(tab: 0, mealTag: tag)
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.accentColor)
                                Text("Add \(tag.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(items) { entry in
                            timelineRow(entry)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteEntry(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        duplicateEntryToNow(entry)
                                    } label: {
                                        Label("Repeat", systemImage: "plus.square.on.square")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                } header: {
                    HStack {
                        Text(tag.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                        if !items.isEmpty {
                            Text("• \(Int(subtotal.calories.rounded())) kcal • \(Int(subtotal.protein.rounded()))P \(Int(subtotal.carbs.rounded()))C \(Int(subtotal.fat.rounded()))F")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            appState.openQuickAdd(tab: 0, mealTag: tag)
                        } label: {
                            Label("Add", systemImage: "plus")
                                .font(.caption2.weight(.bold))
                                .labelStyle(.iconOnly)
                        }
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
    }

    private func compactMacroPill(_ label: String, current: Double, target: Double, floor: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption.weight(.bold)).foregroundStyle(color)
                Spacer()
                Text("\(Int(current.rounded()))/\(Int(target.rounded()))g")
                    .font(.caption.monospacedDigit())
            }
            ProgressView(value: min(1.0, current / max(1.0, target)))
                .tint(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var multiSelectActionBar: some View {
        HStack(spacing: 12) {
            Button("Copy") {
                moveInsteadOfCopy = false
                showingCopyMoveSheet = true
            }
            Button("Move") {
                moveInsteadOfCopy = true
                showingCopyMoveSheet = true
            }
            Button("Save Recipe") {
                newRecipeName = "Meal Recipe"
                showingSaveAsRecipeAlert = true
            }
            Spacer()
            Button(role: .destructive) {
                let toDelete = dayEntries.filter { selectedEntryIDs.contains($0.id) }
                for item in toDelete { deleteEntry(item) }
                selectedEntryIDs.removeAll()
                isSelecting = false
            } label: {
                Image(systemName: "trash")
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.12))
    }

    private func timelineRow(_ entry: FoodLogEntry) -> some View {
        let isSelected = selectedEntryIDs.contains(entry.id)
        return HStack(spacing: 10) {
            Button {
                if isSelecting {
                    if isSelected { selectedEntryIDs.remove(entry.id) }
                    else { selectedEntryIDs.insert(entry.id) }
                } else {
                    editingEntry = entry
                }
            } label: {
                HStack(spacing: 10) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    }

                    Text(entry.timestamp, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(entry.foodName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            FoodSourceBadge(source: entry.foodSource)
                        }
                        HStack(spacing: 6) {
                            Text("\(entry.servingLabel) (\(Int(entry.grams.rounded()))g)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int(entry.calories.rounded())) kcal")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppleTheme.calories)

                        HStack(spacing: 4) {
                            Text("\(Int(entry.protein.rounded()))P")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(AppleTheme.protein)
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(Int(entry.carbs.rounded()))C")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(AppleTheme.carbs)
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(Int(entry.fat.rounded()))F")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(AppleTheme.fat)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if !isSelecting {
                Menu {
                    Section("Assign Meal Tag") {
                        ForEach(MealTag.allCases) { tag in
                            Button {
                                entry.mealTag = tag
                                try? modelContext.save()
                            } label: {
                                if entry.mealTag == tag {
                                    Label(tag.displayName, systemImage: "checkmark")
                                } else {
                                    Text(tag.displayName)
                                }
                            }
                        }
                    }
                } label: {
                    Text(entry.mealTag == .none ? "Tag" : entry.mealTag.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            entry.mealTag == .none ? Color.secondary.opacity(0.11) : Color.accentColor.opacity(0.14),
                            in: Capsule()
                        )
                        .foregroundStyle(entry.mealTag == .none ? .secondary : Color.accentColor)
                }
                .accessibilityLabel("Change Meal Tag")
            }
        }
        .contextMenu {
            Menu("Meal Tag") {
                ForEach(MealTag.allCases) { tag in
                    Button {
                        entry.mealTag = tag
                        try? modelContext.save()
                    } label: {
                        if entry.mealTag == tag {
                            Label(tag.displayName, systemImage: "checkmark")
                        } else {
                            Text(tag.displayName)
                        }
                    }
                }
            }
            Button {
                duplicateEntryToNow(entry)
            } label: {
                Label("Repeat Today", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                deleteEntry(entry)
            } label: {
                Label("Delete Entry", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func toggleComplete() {
        if let existing = dayNote {
            existing.isComplete.toggle()
        } else {
            modelContext.insert(DailyNote(dayKey: activeDayKey, isComplete: true))
        }
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(forDayKey: activeDayKey, context: modelContext)
    }

    private func saveDailyNote(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = dayNote {
            existing.notes = cleaned
        } else if !cleaned.isEmpty {
            modelContext.insert(DailyNote(dayKey: activeDayKey, isComplete: false, notes: cleaned))
        }
        try? modelContext.save()
    }

    private func sumNutrients(_ entries: [FoodLogEntry]) -> NutrientsPer100g {
        var total = NutrientsPer100g()
        for e in entries {
            total.calories += e.calories
            total.protein += e.protein
            total.carbs += e.carbs
            total.fat += e.fat
        }
        return total
    }

    private func deleteEntry(_ entry: FoodLogEntry) {
        Task { await healthService.deleteFoodEntrySamples(entry) }
        modelContext.delete(entry)
        try? modelContext.save()
        _ = CoachingCoordinator.evaluate(forDayKey: activeDayKey, context: modelContext)
    }

    private func duplicateEntryToNow(_ entry: FoodLogEntry) {
        let copy = entry.duplicate(toTimestamp: .now, newDayKey: activeDayKey)
        modelContext.insert(copy)
        try? modelContext.save()
        Task { await healthService.syncFoodEntry(copy) }
        _ = CoachingCoordinator.evaluate(forDayKey: activeDayKey, context: modelContext)
    }

    private func copyDayEntries(from sourceKey: String, to destKey: String) {
        let sourceItems = allEntries.filter { $0.dayKey == sourceKey }
        copySpecificEntries(sourceItems, to: destKey)
    }

    private func copySpecificEntries(_ sourceItems: [FoodLogEntry], to destKey: String) {
        guard !sourceItems.isEmpty else { return }
        let destBaseDate = DayKey.date(from: destKey) ?? .now
        let cal = Calendar.current

        var created: [FoodLogEntry] = []
        for item in sourceItems {
            let timeComps = cal.dateComponents([.hour, .minute, .second], from: item.timestamp)
            let mergedTimestamp = cal.date(
                bySettingHour: timeComps.hour ?? 12,
                minute: timeComps.minute ?? 0,
                second: timeComps.second ?? 0,
                of: destBaseDate
            ) ?? destBaseDate

            let copy = item.duplicate(toTimestamp: mergedTimestamp, newDayKey: destKey)
            modelContext.insert(copy)
            created.append(copy)
        }
        try? modelContext.save()
        let toSync = created
        Task {
            for copy in toSync {
                await healthService.syncFoodEntry(copy)
            }
        }
        _ = CoachingCoordinator.evaluate(forDayKey: destKey, context: modelContext)
    }

    private func performBulkCopyOrMove() {
        let destKey = DayKey.from(targetCopyDate)
        let selected = dayEntries.filter { selectedEntryIDs.contains($0.id) }
        for item in selected {
            if moveInsteadOfCopy {
                item.dayKey = destKey
                item.timestamp = targetCopyDate
                Task { await healthService.syncFoodEntry(item) }
            } else {
                let copy = item.duplicate(toTimestamp: targetCopyDate, newDayKey: destKey)
                modelContext.insert(copy)
                Task { await healthService.syncFoodEntry(copy) }
            }
        }
        try? modelContext.save()
        selectedEntryIDs.removeAll()
        isSelecting = false
        _ = CoachingCoordinator.evaluate(forDayKey: activeDayKey, context: modelContext)
    }

    private func saveSelectedEntriesAsRecipe() {
        let selected = dayEntries.filter { selectedEntryIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let totalGrams = selected.reduce(0.0) { $0 + $1.grams }
        let recipe = Recipe(
            name: newRecipeName.isEmpty ? "Saved Meal" : newRecipeName,
            totalYieldGrams: max(50, totalGrams),
            servings: 1
        )
        modelContext.insert(recipe)

        let foodByID = Dictionary(allFoods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in selected {
            let backingFood: Food
            if let fid = item.foodID, let match = foodByID[fid] {
                backingFood = match
            } else {
                let synth = Food(
                    name: item.foodName,
                    brand: item.foodBrand,
                    source: .custom,
                    nutrientsPer100g: NutrientsPer100g(
                        calories: item.snapshotCaloriesPer100g,
                        protein: item.snapshotProteinPer100g,
                        carbs: item.snapshotCarbsPer100g,
                        fat: item.snapshotFatPer100g,
                        fiber: item.snapshotFiberPer100g,
                        sugar: item.snapshotSugarPer100g,
                        sodiumMg: item.snapshotSodiumMgPer100g
                    )
                )
                modelContext.insert(synth)
                backingFood = synth
            }
            let ing = RecipeIngredient(food: backingFood, grams: item.grams)
            ing.recipe = recipe
            modelContext.insert(ing)
        }

        let shadowFood = recipe.makeOrUpdateShadowFood()
        modelContext.insert(shadowFood)
        try? modelContext.save()
        selectedEntryIDs.removeAll()
        isSelecting = false
    }
}

// MARK: - Copy From Any Date Sheet

private struct CopyFromAnyDateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let destinationDayKey: String
    let allEntries: [FoodLogEntry]
    let onCopyEntries: ([FoodLogEntry]) -> Void

    @State private var sourceDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    @State private var mealFilterRaw: String = "all"

    private var sourceDayKey: String {
        DayKey.from(sourceDate)
    }

    private var matchingEntries: [FoodLogEntry] {
        let dayItems = allEntries.filter { $0.dayKey == sourceDayKey }
        guard mealFilterRaw != "all", let tag = MealTag(rawValue: mealFilterRaw) else {
            return dayItems
        }
        return dayItems.filter { $0.mealTag == tag }
    }

    private var previewTotals: (kcal: Double, p: Double, c: Double, f: Double) {
        var k = 0.0, p = 0.0, c = 0.0, f = 0.0
        for e in matchingEntries {
            k += e.calories
            p += e.protein
            c += e.carbs
            f += e.fat
        }
        return (k, p, c, f)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("Pick Source Day") {
                        DatePicker("Copy From Date", selection: $sourceDate, displayedComponents: .date)

                        Picker("Filter by Meal", selection: $mealFilterRaw) {
                            Text("Entire Day").tag("all")
                            ForEach(MealTag.allCases) { tag in
                                Text(tag.displayName).tag(tag.rawValue)
                            }
                        }
                    }

                    Section("Entries on \(DayKey.displayTitle(for: sourceDayKey))") {
                        if matchingEntries.isEmpty {
                            Text("No matching food entries logged on \(DayKey.displayTitle(for: sourceDayKey)).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            let totals = previewTotals
                            HStack {
                                Text("\(matchingEntries.count) items")
                                    .font(.caption.weight(.bold))
                                Spacer()
                                Text("\(Int(totals.kcal.rounded())) kcal • \(Int(totals.p.rounded()))P \(Int(totals.c.rounded()))C \(Int(totals.f.rounded()))F")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(matchingEntries) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.foodName)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Text("\(item.servingLabel)\(item.mealTag != .none ? " • \(item.mealTag.displayName)" : "")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(item.calories.rounded())) kcal")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                }
                            }
                        }
                    }
                }

                Divider()

                VStack {
                    Button {
                        onCopyEntries(matchingEntries)
                        dismiss()
                    } label: {
                        Text("Copy \(matchingEntries.count) \(matchingEntries.count == 1 ? "Entry" : "Entries") to \(DayKey.displayTitle(for: destinationDayKey))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(matchingEntries.isEmpty)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Copy From Any Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Daily Note Editor Sheet

private struct DailyNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let dayKey: String
    @State private var noteText: String
    let onSave: (String) -> Void

    init(dayKey: String, initialNotes: String, onSave: @escaping (String) -> Void) {
        self.dayKey = dayKey
        self._noteText = State(initialValue: initialNotes)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 140)
                } header: {
                    Text("Journal / Hunger / Digestion Notes • \(DayKey.displayTitle(for: dayKey))")
                } footer: {
                    Text("Track hunger levels, restaurant sodium, refeeds, travel, or energy notes alongside your food log.")
                }

                if !noteText.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            onSave("")
                            dismiss()
                        } label: {
                            Label("Clear Day Note", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Day Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(noteText)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Edit Logged Food Sheet

private struct EditLoggedFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    @Bindable var entry: FoodLogEntry
    @State private var calculator = InlineQuantityCalculator(initialText: "100", isPreselected: true)

    private var gramsInput: Double {
        max(0.1, calculator.evaluatedValue)
    }

    var body: some View {
        let preview = entry.loggedNutrients.scaled(forGrams: (gramsInput / max(0.1, entry.grams)) * 100.0)

        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(entry.foodName)
                            .font(.headline)

                        HStack(spacing: 8) {
                            editMacroBadge("Calories", "\(Int(preview.calories.rounded())) kcal", .orange)
                            editMacroBadge("Protein", "\(Int(preview.protein.rounded()))g", .red)
                            editMacroBadge("Carbs", "\(Int(preview.carbs.rounded()))g", .blue)
                            editMacroBadge("Fat", "\(Int(preview.fat.rounded()))g", .yellow)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                        Button {
                            calculator.reset(to: InlineQuantityCalculator.formatClean(gramsInput), preselected: true)
                            InlineFoodKeypadHaptics.lightTap()
                        } label: {
                            HStack {
                                Text("Amount (grams)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(calculator.expression)
                                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, calculator.isPreselected ? 10 : 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        calculator.isPreselected ? Color.accentColor.opacity(0.22) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        HStack {
                            Picker("Meal Tag", selection: $entry.mealTag) {
                                ForEach(MealTag.allCases) { tag in
                                    Text(tag.displayName).tag(tag)
                                }
                            }
                            Spacer()
                            DatePicker("", selection: $entry.timestamp, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .font(.subheadline)
                    }
                    .padding(16)
                }

                Divider()

                VStack(spacing: 10) {
                    InlineFoodKeypadView(calculator: $calculator)

                    Button {
                        entry.grams = gramsInput
                        entry.servingLabel = "\(Int(entry.grams.rounded())) g"
                        entry.dayKey = DayKey.from(entry.timestamp)
                        try? modelContext.save()
                        Task { await healthService.syncFoodEntry(entry) }
                        _ = CoachingCoordinator.evaluate(forDayKey: entry.dayKey, context: modelContext)
                        InlineFoodKeypadHaptics.lightTap()
                        dismiss()
                    } label: {
                        Text("Save (\(Int(preview.calories.rounded())) kcal)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                calculator.reset(to: InlineQuantityCalculator.formatClean(entry.grams), preselected: true)
            }
        }
        .presentationDetents([.large])
    }

    private func editMacroBadge(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

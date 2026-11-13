import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Structured health + workout payload imported via Apple Shortcuts (`totalfactor://health-sync` / AppIntents).
/// Allows free Apple ID / SideStore installs (where Apple blocks the HealthKit entitlement) to receive
/// Apple Health metrics and fitness workouts reliably with zero paid developer account required.
public struct BridgedHealthPayload: Codable, Equatable, Sendable {
    public var steps: Int?
    public var activeCalories: Double?
    public var basalCalories: Double?
    public var restingHeartRateBPM: Double?
    public var hrvSDNNMilliseconds: Double?
    public var currentHeartRateBPM: Double?
    public var minHeartRateBPM: Double?
    public var maxHeartRateBPM: Double?
    public var sleepHours: Double?
    public var weightKg: Double?

    public var workoutTitle: String?
    public var workoutKindRaw: String?
    public var workoutDurationSeconds: Int?
    public var workoutDistanceMeters: Double?
    public var workoutCalories: Double?
    public var workoutAvgHeartRate: Double?
    public var workoutSourceName: String?
    public var workoutStartDate: Date?
    public var workoutExternalID: String?

    public init(
        steps: Int? = nil,
        activeCalories: Double? = nil,
        basalCalories: Double? = nil,
        restingHeartRateBPM: Double? = nil,
        hrvSDNNMilliseconds: Double? = nil,
        currentHeartRateBPM: Double? = nil,
        minHeartRateBPM: Double? = nil,
        maxHeartRateBPM: Double? = nil,
        sleepHours: Double? = nil,
        weightKg: Double? = nil,
        workoutTitle: String? = nil,
        workoutKindRaw: String? = nil,
        workoutDurationSeconds: Int? = nil,
        workoutDistanceMeters: Double? = nil,
        workoutCalories: Double? = nil,
        workoutAvgHeartRate: Double? = nil,
        workoutSourceName: String? = nil,
        workoutStartDate: Date? = nil,
        workoutExternalID: String? = nil
    ) {
        self.steps = steps
        self.activeCalories = activeCalories
        self.basalCalories = basalCalories
        self.restingHeartRateBPM = restingHeartRateBPM
        self.hrvSDNNMilliseconds = hrvSDNNMilliseconds
        self.currentHeartRateBPM = currentHeartRateBPM
        self.minHeartRateBPM = minHeartRateBPM
        self.maxHeartRateBPM = maxHeartRateBPM
        self.sleepHours = sleepHours
        self.weightKg = weightKg
        self.workoutTitle = workoutTitle
        self.workoutKindRaw = workoutKindRaw
        self.workoutDurationSeconds = workoutDurationSeconds
        self.workoutDistanceMeters = workoutDistanceMeters
        self.workoutCalories = workoutCalories
        self.workoutAvgHeartRate = workoutAvgHeartRate
        self.workoutSourceName = workoutSourceName
        self.workoutStartDate = workoutStartDate
        self.workoutExternalID = workoutExternalID
    }
}

private struct ShortcutsDailyCache: Codable {
    var dayKey: String
    var stats: HealthDisplayDashboardStats
    var workouts: [ExternalFitnessWorkout]
    var lastSyncDate: Date
    var lastSummary: String
}

@MainActor
public enum ShortcutsHealthBridge {
    public static let healthSyncShortcutName = "Total Factor Health Sync"
    public static let workoutShortcutName = "Total Factor Log Cardio Workout"

    private static let cacheKey = "totalfactor.shortcutsBridge.dailyCache.v1"
    private static let importedWorkoutSignaturesKey = "totalfactor.shortcutsBridge.workoutSignatures.v1"
    private static let lbsToKgFactor = 0.45359237

    public static var syncShortcutURL: URL? {
        var comps = URLComponents(string: "shortcuts://run-shortcut")
        comps?.queryItems = [URLQueryItem(name: "name", value: healthSyncShortcutName)]
        return comps?.url
    }

    public static var workoutShortcutURL: URL? {
        var comps = URLComponents(string: "shortcuts://run-shortcut")
        comps?.queryItems = [URLQueryItem(name: "name", value: workoutShortcutName)]
        return comps?.url
    }

    public static func bundledShortcutURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "shortcut")
            ?? Bundle.main.url(forResource: name, withExtension: "shortcut", subdirectory: "Shortcuts")
    }

    // MARK: - URL Parsing (`totalfactor://health-sync?...` & `totalfactor://workout-sync?...`)

    public static func isBridgeURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "totalfactor" else { return false }
        let route = (url.host ?? url.pathComponents.dropFirst().first ?? "").lowercased()
        return route == "health-sync" || route == "workout-sync"
    }

    public static func parseURL(_ url: URL, defaultUnitSystem: UnitSystem = .imperial) -> BridgedHealthPayload? {
        guard isBridgeURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let items = components.queryItems ?? []
        var params: [String: String] = [:]
        for item in items {
            let key = item.name.lowercased()
            if let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                params[key] = value
            }
        }

        var payload = BridgedHealthPayload()

        if let s = parseFlexibleDouble(params["steps"]), s >= 0 {
            payload.steps = Int(s.rounded())
        }
        if let v = parseFlexibleDouble(params["active_kcal"] ?? params["active"] ?? params["active_calories"]), v >= 0 {
            payload.activeCalories = v.rounded()
        }
        if let v = parseFlexibleDouble(params["basal_kcal"] ?? params["basal"] ?? params["resting_kcal"] ?? params["resting_energy"]), v >= 0 {
            payload.basalCalories = v.rounded()
        }
        if let v = parseFlexibleDouble(params["rhr"] ?? params["resting_hr"]), v > 20, v < 220 {
            payload.restingHeartRateBPM = v.rounded()
        }
        if let v = parseFlexibleDouble(params["hrv"]), v > 0, v < 500 {
            payload.hrvSDNNMilliseconds = v.rounded()
        }
        if let v = parseFlexibleDouble(params["hr"] ?? params["heart_rate"]), v > 20, v < 250 {
            payload.currentHeartRateBPM = v.rounded()
        }
        if let v = parseFlexibleDouble(params["hr_min"] ?? params["min_hr"]), v > 20, v < 250 {
            payload.minHeartRateBPM = v.rounded()
        }
        if let v = parseFlexibleDouble(params["hr_max"] ?? params["max_hr"]), v > 20, v < 250 {
            payload.maxHeartRateBPM = v.rounded()
        }
        if let sleepH = parseFlexibleDouble(params["sleep_hr"] ?? params["sleep"]), sleepH >= 0, sleepH <= 24 {
            payload.sleepHours = (sleepH * 10).rounded() / 10.0
        } else if let sleepM = parseFlexibleDouble(params["sleep_min"]), sleepM >= 0, sleepM <= 1440 {
            payload.sleepHours = ((sleepM / 60.0) * 10).rounded() / 10.0
        }

        if let wKg = parseFlexibleDouble(params["weight_kg"]), wKg > 20, wKg < 400 {
            payload.weightKg = wKg
        } else if let wLb = parseFlexibleDouble(params["weight_lbs"] ?? params["weight_lb"]), wLb > 40, wLb < 900 {
            payload.weightKg = wLb * lbsToKgFactor
        } else if let rawW = params["weight"], let val = parseFlexibleDouble(rawW), val > 20, val < 900 {
            let unitHint = (params["weight_unit"] ?? params["unit"] ?? rawW).lowercased()
            if unitHint.contains("kg") {
                payload.weightKg = val
            } else if unitHint.contains("lb") || unitHint.contains("pound") {
                payload.weightKg = val * lbsToKgFactor
            } else {
                payload.weightKg = defaultUnitSystem == .imperial ? (val * lbsToKgFactor) : val
            }
        }

        // Optional workout / cardio payload
        let rawTitle = params["workout_title"] ?? params["title"] ?? params["workout_name"]
        let rawKind = params["workout_kind"] ?? params["kind"] ?? params["workout_type"]
        let durationMinutes = parseFlexibleDouble(params["workout_min"] ?? params["duration_min"] ?? params["minutes"])
        let durationSeconds = parseFlexibleDouble(params["workout_sec"] ?? params["duration_sec"])
            ?? durationMinutes.map { $0 * 60.0 }

        if rawTitle != nil || rawKind != nil || (durationSeconds ?? 0) > 0 {
            payload.workoutTitle = rawTitle ?? rawKind
            payload.workoutKindRaw = rawKind ?? rawTitle
            if let sec = durationSeconds, sec > 0 {
                payload.workoutDurationSeconds = Int(sec.rounded())
            }
            if let km = parseFlexibleDouble(params["workout_km"] ?? params["distance_km"]), km > 0 {
                payload.workoutDistanceMeters = km * 1000.0
            } else if let mi = parseFlexibleDouble(params["workout_mi"] ?? params["distance_mi"]), mi > 0 {
                payload.workoutDistanceMeters = mi * CardioDistanceUnit.metersPerMile
            } else if let m = parseFlexibleDouble(params["workout_m"] ?? params["distance_m"]), m > 0 {
                payload.workoutDistanceMeters = m
            }
            if let kcal = parseFlexibleDouble(params["workout_kcal"] ?? params["calories"]), kcal > 0 {
                payload.workoutCalories = kcal.rounded()
            }
            if let avgHR = parseFlexibleDouble(params["workout_hr"] ?? params["avg_hr"]), avgHR > 25, avgHR < 250 {
                payload.workoutAvgHeartRate = avgHR.rounded()
            }
            payload.workoutSourceName = params["workout_source"] ?? params["source"] ?? "Apple Fitness (Shortcuts)"
            payload.workoutExternalID = params["workout_id"]
            if let startStr = params["workout_start"] {
                payload.workoutStartDate = parseFlexibleDate(startStr)
            }
        }

        return payload
    }

    // MARK: - Applying & Persisting Bridged Payloads

    @discardableResult
    public static func apply(
        _ payload: BridgedHealthPayload,
        context: ModelContext?,
        healthService: HealthKitService = .shared
    ) -> String {
        var cache = loadTodayCache() ?? ShortcutsDailyCache(
            dayKey: DayKey.today,
            stats: healthService.todayStats,
            workouts: healthService.todayExternalWorkouts,
            lastSyncDate: .now,
            lastSummary: ""
        )

        var parts: [String] = []

        if let steps = payload.steps {
            cache.stats.stepsToday = max(cache.stats.stepsToday, steps)
            parts.append("\(steps.formatted()) steps")
        }
        if let active = payload.activeCalories {
            cache.stats.activeCaloriesDisplayOnly = max(cache.stats.activeCaloriesDisplayOnly, active)
            parts.append("\(Int(active.rounded())) kcal active")
        }
        if let basal = payload.basalCalories {
            cache.stats.basalCaloriesDisplayOnly = max(cache.stats.basalCaloriesDisplayOnly, basal)
        }
        if let rhr = payload.restingHeartRateBPM {
            cache.stats.restingHeartRateBPM = rhr
            parts.append("\(Int(rhr.rounded())) bpm RHR")
        }
        if let hrv = payload.hrvSDNNMilliseconds {
            cache.stats.hrvSDNNMilliseconds = hrv
            parts.append("\(Int(hrv.rounded())) ms HRV")
        }
        if let hr = payload.currentHeartRateBPM {
            cache.stats.currentHeartRateBPM = hr
        }
        if let minHR = payload.minHeartRateBPM {
            cache.stats.minHeartRateBPM = minHR
        }
        if let maxHR = payload.maxHeartRateBPM {
            cache.stats.maxHeartRateBPM = maxHR
        }
        if let sleepH = payload.sleepHours, sleepH > 0 {
            cache.stats.sleepHoursLastNight = sleepH
            parts.append(String(format: "%.1f hr sleep", sleepH))
        }

        var didMutateSwiftData = false

        if let weightKg = payload.weightKg, let context {
            if upsertBridgedWeighIn(weightKg: weightKg, context: context) {
                didMutateSwiftData = true
            }
            parts.append(String(format: "%.1f kg weigh-in", weightKg))
        }

        if let durationSeconds = payload.workoutDurationSeconds, durationSeconds >= 30 {
            let meta = resolveWorkoutPresentation(
                title: payload.workoutTitle,
                kindRaw: payload.workoutKindRaw
            )
            let startDate = payload.workoutStartDate ?? Date.now.addingTimeInterval(-TimeInterval(durationSeconds))
            let endDate = startDate.addingTimeInterval(TimeInterval(durationSeconds))
            let sourceName = (payload.workoutSourceName?.isEmpty == false)
                ? payload.workoutSourceName!
                : "Apple Fitness (Shortcuts)"

            let signature = payload.workoutExternalID ?? buildWorkoutSignature(
                kind: meta.kind,
                startDate: startDate,
                durationSeconds: durationSeconds,
                calories: payload.workoutCalories
            )

            var knownSignatures = Set(UserDefaults.standard.stringArray(forKey: importedWorkoutSignaturesKey) ?? [])
            if !knownSignatures.contains(signature) {
                knownSignatures.insert(signature)
                if knownSignatures.count > 250 {
                    knownSignatures = Set(knownSignatures.suffix(200))
                }
                UserDefaults.standard.set(Array(knownSignatures), forKey: importedWorkoutSignaturesKey)

                if let context {
                    let existingSessions = (try? context.fetch(FetchDescriptor<CardioSession>())) ?? []
                    let duplicateInDB = existingSessions.contains { existing in
                        abs(existing.start.timeIntervalSince(startDate)) < 180
                            && abs(existing.durationSeconds - durationSeconds) <= 120
                            && existing.kind == meta.kind
                    }
                    if !duplicateInDB {
                        let session = CardioSession(
                            kind: meta.kind,
                            start: startDate,
                            durationSeconds: durationSeconds,
                            distanceMeters: payload.workoutDistanceMeters,
                            avgHeartRate: payload.workoutAvgHeartRate,
                            activeCalories: payload.workoutCalories,
                            notes: meta.kind == .other ? meta.title : ""
                        )
                        session.importedFromHealth = true
                        session.sourceName = sourceName
                        context.insert(session)
                        didMutateSwiftData = true
                    }
                }

                if DayKey.from(startDate) == DayKey.today {
                    let extWorkout = ExternalFitnessWorkout(
                        id: UUID(),
                        title: meta.title,
                        sfSymbol: meta.sfSymbol,
                        emoji: meta.emoji,
                        durationMinutes: max(1, Int((Double(durationSeconds) / 60.0).rounded())),
                        activeCalories: (payload.workoutCalories ?? 0).rounded(),
                        startDate: startDate,
                        endDate: endDate,
                        sourceAppName: sourceName
                    )
                    cache.workouts.insert(extWorkout, at: 0)
                }

                parts.append("\(meta.title) (\(max(1, durationSeconds / 60)) min)")
            } else {
                parts.append("\(meta.title) already synced")
            }
        }

        if didMutateSwiftData, let context {
            try? context.save()
            _ = CoachingCoordinator.evaluate(context: context)
        }

        let summary = parts.isEmpty ? "Synced Apple Health stats via Shortcuts" : parts.joined(separator: " • ")
        cache.lastSyncDate = .now
        cache.lastSummary = summary
        cache.dayKey = DayKey.today
        saveTodayCache(cache)

        healthService.todayStats = mergeStats(primary: healthService.todayStats, bridged: cache.stats)
        mergeCachedWorkouts(into: &healthService.todayExternalWorkouts, cachedWorkouts: cache.workouts)
        healthService.lastSyncDate = cache.lastSyncDate
        healthService.lastShortcutsSyncDate = cache.lastSyncDate
        healthService.lastShortcutsSyncSummary = summary

        return summary
    }

    // MARK: - Cache Restoration & Merge Helpers

    public static func restoreCachedTodayTelemetry(
        into stats: inout HealthDisplayDashboardStats,
        workouts: inout [ExternalFitnessWorkout],
        lastShortcutsSyncDate: inout Date?,
        lastShortcutsSyncSummary: inout String?
    ) {
        guard let cache = loadTodayCache() else { return }
        stats = mergeStats(primary: stats, bridged: cache.stats)
        mergeCachedWorkouts(into: &workouts, cachedWorkouts: cache.workouts)
        lastShortcutsSyncDate = cache.lastSyncDate
        lastShortcutsSyncSummary = cache.lastSummary
    }

    public static func mergeCachedTelemetry(into stats: inout HealthDisplayDashboardStats) {
        guard let cache = loadTodayCache() else { return }
        stats = mergeStats(primary: stats, bridged: cache.stats)
    }

    public static func mergeCachedWorkouts(into workouts: inout [ExternalFitnessWorkout]) {
        guard let cache = loadTodayCache() else { return }
        mergeCachedWorkouts(into: &workouts, cachedWorkouts: cache.workouts)
    }

    private static func mergeCachedWorkouts(
        into workouts: inout [ExternalFitnessWorkout],
        cachedWorkouts: [ExternalFitnessWorkout]
    ) {
        for wk in cachedWorkouts {
            let duplicate = workouts.contains { existing in
                existing.id == wk.id ||
                (abs(existing.startDate.timeIntervalSince(wk.startDate)) < 120 && existing.title == wk.title)
            }
            if !duplicate {
                workouts.append(wk)
            }
        }
        workouts.sort { $0.startDate > $1.startDate }
    }

    private static func mergeStats(
        primary: HealthDisplayDashboardStats,
        bridged: HealthDisplayDashboardStats
    ) -> HealthDisplayDashboardStats {
        var out = primary
        out.stepsToday = max(primary.stepsToday, bridged.stepsToday)
        out.activeCaloriesDisplayOnly = max(primary.activeCaloriesDisplayOnly, bridged.activeCaloriesDisplayOnly)
        out.basalCaloriesDisplayOnly = max(primary.basalCaloriesDisplayOnly, bridged.basalCaloriesDisplayOnly)
        if out.restingHeartRateBPM == nil { out.restingHeartRateBPM = bridged.restingHeartRateBPM }
        if out.currentHeartRateBPM == nil { out.currentHeartRateBPM = bridged.currentHeartRateBPM }
        if out.minHeartRateBPM == nil { out.minHeartRateBPM = bridged.minHeartRateBPM }
        if out.maxHeartRateBPM == nil { out.maxHeartRateBPM = bridged.maxHeartRateBPM }
        if out.hrvSDNNMilliseconds == nil { out.hrvSDNNMilliseconds = bridged.hrvSDNNMilliseconds }
        if out.sleepHoursLastNight == nil { out.sleepHoursLastNight = bridged.sleepHoursLastNight }
        return out
    }

    private static func loadTodayCache() -> ShortcutsDailyCache? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode(ShortcutsDailyCache.self, from: data),
              decoded.dayKey == DayKey.today else {
            return nil
        }
        return decoded
    }

    private static func saveTodayCache(_ cache: ShortcutsDailyCache) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    // MARK: - Helpers

    private static func upsertBridgedWeighIn(weightKg: Double, context: ModelContext) -> Bool {
        let today = DayKey.today
        let existing = ((try? context.fetch(FetchDescriptor<WeighIn>())) ?? [])
            .filter { $0.dayKey == today }
        if let match = existing.first(where: { abs($0.weightKg - weightKg) < 0.05 }) {
            _ = match
            return false
        }
        if let previousHK = existing.first(where: { $0.source == .healthKit }) {
            previousHK.weightKg = weightKg
            previousHK.date = .now
            return true
        }
        let entry = WeighIn(date: .now, dayKey: today, weightKg: weightKg, source: .healthKit)
        context.insert(entry)
        return true
    }

    private static func buildWorkoutSignature(
        kind: CardioKind,
        startDate: Date,
        durationSeconds: Int,
        calories: Double?
    ) -> String {
        let minuteBucket = Int(startDate.timeIntervalSince1970 / 120.0)
        return "\(kind.rawValue)-\(minuteBucket)-\(durationSeconds / 60)-\(Int((calories ?? 0).rounded()))"
    }

    private static func resolveWorkoutPresentation(
        title: String?,
        kindRaw: String?
    ) -> (kind: CardioKind, title: String, sfSymbol: String, emoji: String) {
        let hint = (kindRaw ?? title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let kind: CardioKind = {
            if let exact = CardioKind(rawValue: hint) { return exact }
            if hint.contains("incline") || hint.contains("hike") { return .inclineWalk }
            if hint.contains("run") || hint.contains("jog") { return .run }
            if hint.contains("walk") { return .walk }
            if hint.contains("cycl") || hint.contains("bike") || hint.contains("spin") { return .cycling }
            if hint.contains("elliptical") { return .elliptical }
            if hint.contains("stair") || hint.contains("step") { return .stairClimber }
            if hint.contains("row") { return .rowing }
            if hint.contains("swim") { return .swimming }
            return .other
        }()

        let resolvedTitle = (title?.isEmpty == false) ? title! : kind.displayName
        let emoji: String = {
            switch kind {
            case .run: return "🏃"
            case .walk: return "🚶"
            case .inclineWalk: return "🥾"
            case .cycling: return "🚴"
            case .elliptical: return "🏃"
            case .stairClimber: return "🪜"
            case .rowing: return "🚣"
            case .swimming: return "🏊"
            case .other:
                if hint.contains("soccer") { return "⚽️" }
                if hint.contains("basketball") { return "🏀" }
                if hint.contains("tennis") { return "🎾" }
                if hint.contains("hiit") { return "🔥" }
                if hint.contains("yoga") { return "🧘" }
                if hint.contains("box") { return "🥊" }
                return "🏅"
            }
        }()

        return (kind, resolvedTitle, kind.sfSymbol, emoji)
    }

    /// Parses numbers even when Apple Shortcuts inserts commas or trailing units (e.g. `"10,432 steps"` -> `10432`).
    public static func parseFlexibleDouble(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if let direct = Double(cleaned) { return direct }

        let pattern = #"[-+]?\d+(?:\.\d+)?"#
        if let range = cleaned.range(of: pattern, options: .regularExpression) {
            return Double(cleaned[range])
        }
        return nil
    }

    private static func parseFlexibleDate(_ raw: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: raw) { return d }

        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }

        if let epoch = Double(raw) {
            return Date(timeIntervalSince1970: epoch)
        }
        return nil
    }
}

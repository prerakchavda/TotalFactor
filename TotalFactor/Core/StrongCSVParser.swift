import Foundation

public struct ParsedStrongSet: Equatable, Sendable {
    public var canonicalExerciseName: String
    public var rawExerciseName: String
    public var setOrder: Int
    public var setType: SetType
    public var weightKg: Double
    public var reps: Int
    public var rir: Int
    public var notes: String

    public init(
        canonicalExerciseName: String,
        rawExerciseName: String,
        setOrder: Int,
        setType: SetType,
        weightKg: Double,
        reps: Int,
        rir: Int,
        notes: String
    ) {
        self.canonicalExerciseName = canonicalExerciseName
        self.rawExerciseName = rawExerciseName
        self.setOrder = setOrder
        self.setType = setType
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.notes = notes
    }
}

public struct ParsedStrongSession: Equatable, Sendable {
    public var startDate: Date
    public var endDate: Date
    public var dayKey: String
    public var workoutName: String
    public var notes: String
    public var sets: [ParsedStrongSet]

    public init(
        startDate: Date,
        endDate: Date,
        dayKey: String,
        workoutName: String,
        notes: String,
        sets: [ParsedStrongSet]
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.dayKey = dayKey
        self.workoutName = workoutName
        self.notes = notes
        self.sets = sets
    }
}

/// Pure-Swift RFC-4180 parser for Strong / Hevy CSV workout exports.
/// Normalizes exercise names, converts display weights to internal `kg`, repairs swapped
/// weight/rep column typos, and caps runaway forgotten workout timers.
public enum StrongCSVParser {
    private static let strongAliasMap: [String: String] = [
        "ab wheel": "Ab Wheel Rollout",
        "arnold press (dumbbell)": "Arnold Press",
        "bent over one arm row (dumbbell)": "One-Arm Dumbbell Row",
        "bent over row (band)": "Band Bent-Over Row",
        "bicep curl (barbell)": "Barbell Curl",
        "bicep curl (cable)": "Cable Bicep Curl",
        "bicep curl (dumbbell)": "Dumbbell Bicep Curl",
        "bicep curl (machine)": "Machine Bicep Curl",
        "cable cross back": "Rear Delt Cable Crossover",
        "cable crossover": "Cable Chest Fly",
        "cable pulldown": "Straight-Arm Cable Pulldown",
        "calf press on leg press": "Calf Press on Leg Press",
        "calf press on seated leg press": "Calf Press on Leg Press",
        "chest dip": "Weighted Dip",
        "chest fly (dumbbell)": "Flat Dumbbell Chest Fly",
        "chest press (machine)": "Machine Chest Press",
        "crunch (machine)": "Abdominal Crunch Machine",
        "front raise (dumbbell)": "Dumbbell Front Raise",
        "front raise": "Dumbbell Front Raise",
        "hack squat": "Hack Squat Machine",
        "hammer curl (dumbbell)": "Dumbbell Hammer Curl",
        "hanging leg raise": "Hanging Leg Raise",
        "hip abductor (machine)": "Hip Abduction Machine",
        "hip adductor (machine)": "Hip Adduction Machine",
        "incline chest press (machine)": "Incline Machine Chest Press",
        "incline curl (dumbbell)": "Incline Dumbbell Curl",
        "iso-lateral chest press (machine)": "Iso-Lateral Machine Chest Press",
        "iso-lateral row (machine)": "Iso-Lateral Machine Row",
        "lat pulldown (cable)": "Wide-Grip Lat Pulldown",
        "lat pulldown (machine)": "Machine Lat Pulldown",
        "lateral raise (cable)": "Cable Lateral Raise",
        "lateral raise (dumbbell)": "Dumbbell Lateral Raise",
        "leg extension (machine)": "Leg Extension",
        "leg press": "Leg Press",
        "overhead press (barbell)": "Standing Barbell Overhead Press",
        "pec deck (machine)": "Pec Deck / Machine Fly",
        "preacher curl (dumbbell)": "Dumbbell Preacher Curl",
        "preacher curl (machine)": "Preacher Curl Machine",
        "pull up": "Pull-Up / Weighted Pull-Up",
        "pull up (assisted)": "Assisted Pull-Up Machine",
        "push up": "Push-Up",
        "rear delt": "Reverse Pec Deck (Rear Delt Fly)",
        "seated calf raise (machine)": "Seated Calf Raise",
        "seated calf raise (plate loaded)": "Seated Calf Raise",
        "seated leg curl (machine)": "Seated Leg Curl",
        "seated leg press (machine)": "Seated Leg Press Machine",
        "seated row (cable)": "Seated Cable Row",
        "seated row (machine)": "Seated Machine Row",
        "shoulder press (machine)": "Machine Shoulder Press",
        "skullcrusher (barbell)": "EZ-Bar Skullcrusher",
        "skullcrusher (dumbbell)": "Dumbbell Skullcrusher",
        "standing calf raise (machine)": "Standing Calf Raise",
        "triceps dip": "Triceps Dip",
        "triceps dip (assisted)": "Assisted Dip Machine",
        "triceps extension (barbell)": "Overhead Barbell / EZ-Bar Triceps Extension",
        "triceps extension (machine)": "Machine Triceps Extension",
        "triceps pushdown (cable - straight bar)": "Cable Triceps Pushdown (Rope/Bar)",
        "upright row (dumbbell)": "Dumbbell Upright Row",
        "cable tricep kickback": "Cable Triceps Kickback",
        "calf extension": "Calf Extension Machine",
        "overhead tricep extension": "Overhead Cable Triceps Extension",
        "shoulder push": "Pike Push-Up",
        "supline press": "Supine Machine Chest Press",
        "supine press": "Supine Machine Chest Press",
        "tricep press": "Seated Triceps Press Machine"
    ]

    public static func canonicalExerciseName(for rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased()
        if let mapped = strongAliasMap[key] {
            return mapped
        }
        return trimmed.isEmpty ? "Custom Exercise" : trimmed
    }

    public static func parse(
        csvContent: String,
        sourceUnitSystem: UnitSystem = .imperial,
        calendar: Calendar = .current
    ) -> [ParsedStrongSession] {
        let cleaned = csvContent.replacingOccurrences(of: "\u{FEFF}", with: "")
        let rows = parseCSVRows(cleaned)
        guard rows.count > 1 else { return [] }

        let headers = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func colIndex(_ candidates: [String]) -> Int? {
            for c in candidates {
                if let idx = headers.firstIndex(of: c) { return idx }
            }
            return nil
        }

        guard let dateIdx = colIndex(["date", "start_time"]),
              let workoutIdx = colIndex(["workout name", "title"]),
              let exIdx = colIndex(["exercise name", "exercise_title"]) else {
            return []
        }

        let durIdx = colIndex(["duration"])
        let setOrderIdx = colIndex(["set order", "set_index"])
        let weightIdx = colIndex(["weight", "weight (lbs)", "weight_lbs", "weight (kg)"])
        let repsIdx = colIndex(["reps"])
        let notesIdx = colIndex(["notes"])
        let workoutNotesIdx = colIndex(["workout notes"])
        let rpeIdx = colIndex(["rpe"])

        let detectedMetric = headers.contains("weight (kg)") || headers.contains("weight_kg")
        let effectiveUnits: UnitSystem = detectedMetric ? .metric : sourceUnitSystem

        struct SessionBucket {
            var dateStr: String
            var startDate: Date
            var workoutName: String
            var durationStr: String
            var workoutNotes: String
            var sets: [ParsedStrongSet]
        }

        var bucketsByKey: [String: SessionBucket] = [:]
        var orderedKeys: [String] = []

        for row in rows.dropFirst() {
            guard row.count > max(dateIdx, max(workoutIdx, exIdx)) else { continue }
            let dateStr = row[dateIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawExercise = row[exIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dateStr.isEmpty, !rawExercise.isEmpty else { continue }

            let workoutNameRaw = row[workoutIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let workoutName = workoutNameRaw.isEmpty ? "Strength Session" : workoutNameRaw
            let durStr = durIdx.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
            let wNotes = workoutNotesIdx.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let setOrderStr = setOrderIdx.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1"

            // Skip pure rest timer note lines in Strong ("Rest Timer")
            if setOrderStr.lowercased().contains("rest") { continue }

            var rawWeight = Double(weightIdx.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0.0
            var rawReps = Double(repsIdx.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0.0

            // Repair accidental Weight <-> Reps column swaps (e.g., 7.0 lb x 140 reps on Seated Row)
            if rawWeight > 0, rawWeight <= 12, rawReps >= 50 {
                swap(&rawWeight, &rawReps)
            }

            let repsInt = max(0, Int(rawReps.rounded()))
            guard repsInt > 0 || rawWeight > 0 else { continue }

            let setType: SetType = {
                switch setOrderStr.uppercased() {
                case "W": return .warmup
                case "D": return .drop
                case "F": return .failure
                default: return .working
                }
            }()

            let rpeVal = Double(rpeIdx.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            let rir: Int = {
                if setType == .failure { return 0 }
                if setType == .warmup { return 4 }
                if let rpeVal, rpeVal >= 4, rpeVal <= 10 {
                    return max(0, min(6, Int((10.0 - rpeVal).rounded())))
                }
                return 2
            }()

            let weightKg = max(0, UnitsFormatter.internalKg(fromDisplay: rawWeight, system: effectiveUnits))
            let canonicalName = canonicalExerciseName(for: rawExercise)
            let notes = notesIdx.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let bucketKey = "\(dateStr)|\(workoutName)"
            if bucketsByKey[bucketKey] == nil {
                guard let parsedStart = parseStrongDate(dateStr, calendar: calendar) else { continue }
                bucketsByKey[bucketKey] = SessionBucket(
                    dateStr: dateStr,
                    startDate: parsedStart,
                    workoutName: workoutName,
                    durationStr: durStr,
                    workoutNotes: wNotes,
                    sets: []
                )
                orderedKeys.append(bucketKey)
            }

            let nextOrder = bucketsByKey[bucketKey]?.sets.count ?? 0
            bucketsByKey[bucketKey]?.sets.append(
                ParsedStrongSet(
                    canonicalExerciseName: canonicalName,
                    rawExerciseName: rawExercise,
                    setOrder: nextOrder,
                    setType: setType,
                    weightKg: weightKg,
                    reps: max(1, repsInt),
                    rir: rir,
                    notes: notes
                )
            )
            if !wNotes.isEmpty, (bucketsByKey[bucketKey]?.workoutNotes.isEmpty ?? false) {
                bucketsByKey[bucketKey]?.workoutNotes = wNotes
            }
        }

        return orderedKeys.compactMap { key -> ParsedStrongSession? in
            guard let b = bucketsByKey[key], !b.sets.isEmpty else { return nil }
            let durSec = normalizedDurationSeconds(b.durationStr, setCount: b.sets.count)
            let endDate = b.startDate.addingTimeInterval(TimeInterval(durSec))
            return ParsedStrongSession(
                startDate: b.startDate,
                endDate: endDate,
                dayKey: DayKey.from(b.startDate, calendar: calendar),
                workoutName: b.workoutName,
                notes: b.workoutNotes,
                sets: b.sets
            )
        }.sorted { $0.startDate < $1.startDate }
    }

    /// Parses Strong duration strings (`"32m"`, `"1h 31m"`, `"43s"`, `"93h 58m"`) and replaces
    /// runaway forgotten timers (>4 hours) or <2m stubs with a realistic gym duration.
    public static func normalizedDurationSeconds(_ raw: String, setCount: Int) -> Int {
        let fallback = max(15 * 60, min(90 * 60, setCount * 155))
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return fallback }

        var totalSeconds = 0
        let parts = lower.split(separator: " ")
        for part in parts {
            if part.hasSuffix("h"), let h = Int(part.dropLast()) {
                totalSeconds += h * 3600
            } else if part.hasSuffix("m"), let m = Int(part.dropLast()) {
                totalSeconds += m * 60
            } else if part.hasSuffix("s"), let s = Int(part.dropLast()) {
                totalSeconds += s
            }
        }

        if totalSeconds < 120 || totalSeconds > 4 * 3600 {
            return fallback
        }
        return totalSeconds
    }

    private static func parseStrongDate(_ text: String, calendar: Calendar) -> Date? {
        // Format: "YYYY-MM-DD HH:mm:ss" or ISO8601
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let spaceParts = trimmed.split(separator: " ")
        if spaceParts.count >= 2 {
            let dParts = spaceParts[0].split(separator: "-")
            let tParts = spaceParts[1].split(separator: ":")
            if dParts.count == 3, tParts.count >= 2,
               let y = Int(dParts[0]), let mo = Int(dParts[1]), let d = Int(dParts[2]),
               let h = Int(tParts[0]), let mi = Int(tParts[1]) {
                let sec = tParts.count >= 3 ? (Int(tParts[2]) ?? 0) : 0
                var comps = DateComponents()
                comps.year = y
                comps.month = mo
                comps.day = d
                comps.hour = h
                comps.minute = mi
                comps.second = sec
                return calendar.date(from: comps)
            }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    /// Zero-dependency RFC-4180 CSV tokenizer handling quoted commas & escaped quotes.
    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == "," {
                    currentRow.append(currentField)
                    currentField = ""
                } else if ch == "\n" {
                    currentRow.append(currentField)
                    currentField = ""
                    if !(currentRow.count == 1 && currentRow[0].isEmpty) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                } else if ch == "\r" {
                    // Ignore CR in CRLF
                } else {
                    currentField.append(ch)
                }
            }
            i += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows
    }
}

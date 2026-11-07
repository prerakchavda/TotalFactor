import Foundation
import SwiftData

// MARK: - Cardio Kind

/// Cardio modalities supported by the cardio logger (MacroFactor Workouts-style).
/// HealthKit activity-type mapping lives in `HealthKitService` so this file stays HealthKit-free.
public enum CardioKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case run
    case walk
    case inclineWalk
    case cycling
    case elliptical
    case stairClimber
    case rowing
    case swimming
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .run: return "Run"
        case .walk: return "Walk"
        case .inclineWalk: return "Incline Walk"
        case .cycling: return "Cycling"
        case .elliptical: return "Elliptical"
        case .stairClimber: return "Stair Climber"
        case .rowing: return "Rowing"
        case .swimming: return "Swimming"
        case .other: return "Other Cardio"
        }
    }

    /// SF Symbol name (all available on iOS 16+).
    public var sfSymbol: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .inclineWalk: return "figure.hiking"
        case .cycling: return "figure.outdoor.cycle"
        case .elliptical: return "figure.elliptical"
        case .stairClimber: return "figure.stair.stepper"
        case .rowing: return "figure.rower"
        case .swimming: return "figure.pool.swim"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Swimming distances read naturally in meters / yards rather than km / mi.
    public var usesShortDistanceUnits: Bool {
        self == .swimming
    }
}

// MARK: - Distance Units

/// Display unit for cardio distance. Distance is always stored internally in meters.
public enum CardioDistanceUnit: String, Sendable {
    case kilometers
    case miles
    case meters
    case yards

    public static let metersPerMile: Double = 1609.344
    public static let metersPerYard: Double = 0.9144

    public var symbol: String {
        switch self {
        case .kilometers: return "km"
        case .miles: return "mi"
        case .meters: return "m"
        case .yards: return "yd"
        }
    }

    public var metersPerUnit: Double {
        switch self {
        case .kilometers: return 1000
        case .miles: return Self.metersPerMile
        case .meters: return 1
        case .yards: return Self.metersPerYard
        }
    }

    /// Decimal places used when showing a distance in this unit.
    public var displayDecimals: Int {
        switch self {
        case .kilometers, .miles: return 2
        case .meters, .yards: return 0
        }
    }

    public static func preferred(for kind: CardioKind, system: UnitSystem) -> CardioDistanceUnit {
        if kind.usesShortDistanceUnits {
            return system == .imperial ? .yards : .meters
        }
        return system == .imperial ? .miles : .kilometers
    }

    public func displayValue(fromMeters meters: Double) -> Double {
        meters / metersPerUnit
    }

    public func meters(fromDisplay value: Double) -> Double {
        value * metersPerUnit
    }

    public func format(meters: Double, includeUnit: Bool = true) -> String {
        let num = String(format: "%.\(displayDecimals)f", displayValue(fromMeters: meters))
        return includeUnit ? "\(num) \(symbol)" : num
    }
}

// MARK: - Cardio Session

@Model
public final class CardioSession {
    public var id: UUID = UUID()
    public var kindRaw: String = CardioKind.run.rawValue
    public var start: Date = Date()
    public var durationSeconds: Int = 0
    /// Always stored in meters regardless of the user's unit system.
    public var distanceMeters: Double? = nil
    public var avgHeartRate: Double? = nil
    public var activeCalories: Double? = nil
    public var notes: String = ""
    public var dayKey: String = ""
    public var healthKitWorkoutUUID: UUID? = nil

    public init(
        kind: CardioKind = .run,
        start: Date = .now,
        durationSeconds: Int = 0,
        distanceMeters: Double? = nil,
        avgHeartRate: Double? = nil,
        activeCalories: Double? = nil,
        notes: String = ""
    ) {
        self.kindRaw = kind.rawValue
        self.start = start
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.avgHeartRate = avgHeartRate
        self.activeCalories = activeCalories
        self.notes = notes
        self.dayKey = DayKey.from(start)
    }

    public var kind: CardioKind {
        get { CardioKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    public var end: Date {
        start.addingTimeInterval(TimeInterval(max(0, durationSeconds)))
    }

    public var durationMinutes: Double {
        Double(max(0, durationSeconds)) / 60.0
    }

    /// e.g. "3.10 mi" / "5.00 km" / "1500 m", or nil when no distance was logged.
    public func formattedDistance(system: UnitSystem) -> String? {
        guard let meters = distanceMeters, meters > 0 else { return nil }
        return CardioDistanceUnit.preferred(for: kind, system: system).format(meters: meters)
    }

    /// e.g. "45 min" / "1h 05m".
    public var formattedDuration: String {
        Self.formatDuration(seconds: durationSeconds)
    }

    public static func formatDuration(seconds: Int) -> String {
        let totalMinutes = max(0, seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return "\(minutes) min"
    }
}

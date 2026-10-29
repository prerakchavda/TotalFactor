import Foundation

/// Timezone-stable calendar day identifier formatted as `"YYYY-MM-DD"`.
/// Using canonical day strings prevents midnight timezone drift when traveling
/// and makes SwiftData `#Predicate` queries fast and deterministic.
public enum DayKey {
    private static var posixCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    public static func from(_ date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    public static var today: String {
        from(.now)
    }

    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else {
            return nil
        }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12 // Noon avoids DST boundary edge cases
        return calendar.date(from: comps)
    }

    public static func addingDays(_ delta: Int, to key: String, calendar: Calendar = .current) -> String {
        guard let base = date(from: key, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: delta, to: base) else {
            return key
        }
        return from(shifted, calendar: calendar)
    }

    public static func daysBetween(_ startKey: String, _ endKey: String, calendar: Calendar = .current) -> Int {
        guard let start = date(from: startKey, calendar: calendar),
              let end = date(from: endKey, calendar: calendar) else {
            return 0
        }
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: s, to: e).day ?? 0
    }

    public static func range(from startKey: String, to endKey: String, calendar: Calendar = .current) -> [String] {
        let count = daysBetween(startKey, endKey, calendar: calendar)
        guard count >= 0 else { return [] }
        return (0...count).map { addingDays($0, to: startKey, calendar: calendar) }
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    public static func displayTitle(for key: String, calendar: Calendar = .current) -> String {
        let todayKey = from(.now, calendar: calendar)
        if key == todayKey { return "Today" }
        if key == addingDays(-1, to: todayKey, calendar: calendar) { return "Yesterday" }
        if key == addingDays(1, to: todayKey, calendar: calendar) { return "Tomorrow" }
        guard let dt = date(from: key, calendar: calendar) else { return key }
        return displayDateFormatter.string(from: dt)
    }

    /// 1 = Sunday ... 7 = Saturday (matches Foundation Calendar).
    public static func weekday(for key: String, calendar: Calendar = .current) -> Int {
        guard let dt = date(from: key, calendar: calendar) else { return 2 }
        return calendar.component(.weekday, from: dt)
    }
}

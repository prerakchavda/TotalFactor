import Foundation
import SwiftData
import ImageIO
#if canImport(Photos)
import Photos
#endif

/// Helper to extract native camera & camera roll metadata (capture date & historical weigh-in matching) for Progress Photos.
public enum PhotoMetadataHelper {

    /// Attempts to extract the original capture date from raw image Data (JPEG/HEIC) via EXIF / TIFF properties.
    public static func extractCaptureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let rawDateString = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)

        guard let dateString = rawDateString?.trimmingCharacters(in: .whitespacesAndNewlines), !dateString.isEmpty else {
            return nil
        }

        // Standard EXIF format: "yyyy:MM:dd HH:mm:ss"
        let exifFormatter = DateFormatter()
        exifFormatter.locale = Locale(identifier: "en_US_POSIX")
        exifFormatter.timeZone = TimeZone.current
        exifFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

        if let parsed = exifFormatter.date(from: dateString) {
            return parsed
        }

        // Alternative ISO 8601 fallback
        let isoFormatter = ISO8601DateFormatter()
        if let isoParsed = isoFormatter.date(from: dateString) {
            return isoParsed
        }

        return nil
    }

    /// Queries the user's logged weigh-ins to find the closest weigh-in sample to the given capture date.
    /// Prefers an exact day match, or the closest weigh-in within ±7 days.
    @MainActor
    public static func findClosestWeighInWeightKg(to date: Date, in context: ModelContext) -> Double? {
        let targetDayKey = DayKey.from(date)
        let weighIns = (try? context.fetch(FetchDescriptor<WeighIn>())) ?? []
        guard !weighIns.isEmpty else { return nil }

        // 1. Exact dayKey match
        if let exact = weighIns.first(where: { $0.dayKey == targetDayKey }) {
            return exact.weightKg
        }

        // 2. Closest within 7 days
        let sortedByProximity = weighIns.sorted {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }

        if let closest = sortedByProximity.first {
            let maxDeltaSeconds: TimeInterval = 7 * 86400
            if abs(closest.date.timeIntervalSince(date)) <= maxDeltaSeconds {
                return closest.weightKg
            }
        }

        return nil
    }
}

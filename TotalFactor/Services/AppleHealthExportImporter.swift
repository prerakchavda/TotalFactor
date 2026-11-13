import Compression
import Foundation
import SwiftData

public struct HealthFileImportSummary: Equatable, Sendable {
    public var formatDescription: String
    public var telemetrySummary: String
    public var workoutsImported: Int
    public var weighInImported: Bool
}

public enum AppleHealthExportError: LocalizedError {
    case unreadableFile
    case unsupportedFormat
    case missingExportXMLInZip
    case invalidArchiveData
    case noRecentHealthDataFound

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Could not read the selected health export file."
        case .unsupportedFormat:
            return "Unsupported file format. Choose Apple Health export.zip / export.xml, a Health JSON export, or a CSV export."
        case .missingExportXMLInZip:
            return "No export.xml file was found inside this ZIP archive."
        case .invalidArchiveData:
            return "Could not unpack export.xml from the ZIP archive. Try unzipping it in the Files app first and selecting export.xml."
        case .noRecentHealthDataFound:
            return "No recent Apple Health metrics (today's steps/calories/HR, recent weigh-ins, or recent workouts) were found in this file."
        }
    }
}

public struct ParsedHealthExportBatch: Sendable {
    public var formatDescription: String
    public var todayPayload: BridgedHealthPayload?
    public var recentWorkouts: [BridgedHealthPayload]
}

public enum AppleHealthExportImporter {
    private static let lbsToKgFactor = 0.45359237

    @MainActor
    public static func importFile(
        at url: URL,
        context: ModelContext?,
        healthService: HealthKitService = .shared,
        referenceDate: Date = .now,
        defaultUnitSystem: UnitSystem = .imperial
    ) async throws -> HealthFileImportSummary {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let batch = try await Task.detached(priority: .userInitiated) {
            try parseFile(at: url, referenceDate: referenceDate, defaultUnitSystem: defaultUnitSystem)
        }.value

        var importedWorkouts = 0
        var telemetrySummary = ""

        if let todayPayload = batch.todayPayload {
            telemetrySummary = ShortcutsHealthBridge.apply(
                todayPayload,
                context: context,
                healthService: healthService
            )
            if todayPayload.workoutDurationSeconds != nil {
                importedWorkouts += 1
            }
        }

        for workoutPayload in batch.recentWorkouts {
            let previousCount = (try? context?.fetchCount(FetchDescriptor<CardioSession>())) ?? 0
            let summary = ShortcutsHealthBridge.apply(
                workoutPayload,
                context: context,
                healthService: healthService
            )
            let updatedCount = (try? context?.fetchCount(FetchDescriptor<CardioSession>())) ?? previousCount
            if updatedCount > previousCount {
                importedWorkouts += 1
            }
            if telemetrySummary.isEmpty && !summary.isEmpty && summary != "No new health metrics in payload." {
                telemetrySummary = summary
            }
        }

        if telemetrySummary.isEmpty {
            telemetrySummary = importedWorkouts > 0
                ? "Imported \(importedWorkouts) cardio workout\(importedWorkouts == 1 ? "" : "s")."
                : "Up to date (0 new entries)."
        }

        return HealthFileImportSummary(
            formatDescription: batch.formatDescription,
            telemetrySummary: telemetrySummary,
            workoutsImported: importedWorkouts,
            weighInImported: batch.todayPayload?.weightKg != nil
        )
    }

    public static func parseFile(
        at url: URL,
        referenceDate: Date = .now,
        defaultUnitSystem: UnitSystem = .imperial
    ) throws -> ParsedHealthExportBatch {
        let ext = url.pathExtension.lowercased()

        if ext == "zip" {
            let tempXMLURL = try extractExportXMLFromZip(at: url)
            defer { try? FileManager.default.removeItem(at: tempXMLURL) }
            return try parseAppleHealthXML(at: tempXMLURL, referenceDate: referenceDate)
        }

        if ext == "xml" {
            return try parseAppleHealthXML(at: url, referenceDate: referenceDate)
        }

        guard let data = try? Data(contentsOf: url) else {
            throw AppleHealthExportError.unreadableFile
        }

        // Detect PKZIP magic bytes even if extension was stripped
        if data.count >= 4, data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]) {
            let tempXMLURL = try extractExportXMLFromZipData(data)
            defer { try? FileManager.default.removeItem(at: tempXMLURL) }
            return try parseAppleHealthXML(at: tempXMLURL, referenceDate: referenceDate)
        }

        if ext == "json" || data.first(where: { !$0.isWhitespaceASCII }) == UInt8(ascii: "{") {
            return try parseJSONExport(data: data, referenceDate: referenceDate, defaultUnitSystem: defaultUnitSystem)
        }

        if ext == "csv" || ext == "txt" {
            return try parseCSVExport(data: data, referenceDate: referenceDate, defaultUnitSystem: defaultUnitSystem)
        }

        if let xmlBatch = try? parseAppleHealthXML(at: url, referenceDate: referenceDate) {
            return xmlBatch
        }

        throw AppleHealthExportError.unsupportedFormat
    }

    // MARK: - Apple Health XML Parser (`export.xml`)

    public static func parseAppleHealthXML(
        at url: URL,
        referenceDate: Date = .now
    ) throws -> ParsedHealthExportBatch {
        guard let parser = XMLParser(contentsOf: url) else {
            throw AppleHealthExportError.unreadableFile
        }

        let delegate = AppleHealthXMLStreamDelegate(referenceDate: referenceDate)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? AppleHealthExportError.unreadableFile
        }

        let batch = delegate.buildBatch()
        if batch.todayPayload == nil && batch.recentWorkouts.isEmpty {
            throw AppleHealthExportError.noRecentHealthDataFound
        }
        return batch
    }

    // MARK: - Streaming Zip Extractor (`export.zip` -> `export.xml`)

    private static func extractExportXMLFromZip(at url: URL) throws -> URL {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw AppleHealthExportError.unreadableFile
        }
        return try extractExportXMLFromZipData(data)
    }

    private static func extractExportXMLFromZipData(_ data: Data) throws -> URL {
        // Locate End of Central Directory (PK\x05\x06) scanning from end (max comment 64KB + 22 bytes).
        let eocdSig: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        let minStart = max(0, data.count - 65558)
        var eocdOffset: Int?
        var idx = data.count - 22
        while idx >= minStart {
            if data[idx] == eocdSig[0], data[idx + 1] == eocdSig[1], data[idx + 2] == eocdSig[2], data[idx + 3] == eocdSig[3] {
                eocdOffset = idx
                break
            }
            idx -= 1
        }
        guard let eocd = eocdOffset, eocd + 22 <= data.count else {
            throw AppleHealthExportError.invalidArchiveData
        }

        let cdSize = Int(readUInt32LE(data, at: eocd + 12))
        let cdOffset = Int(readUInt32LE(data, at: eocd + 16))
        guard cdOffset >= 0, cdSize > 0, cdOffset + cdSize <= data.count else {
            throw AppleHealthExportError.invalidArchiveData
        }

        var cursor = cdOffset
        let cdEnd = cdOffset + cdSize

        struct ZipEntry {
            let name: String
            let method: UInt16
            let compressedSize: Int
            let uncompressedSize: Int
            let localHeaderOffset: Int
        }

        var candidates: [ZipEntry] = []
        while cursor + 46 <= cdEnd {
            guard data[cursor] == 0x50, data[cursor + 1] == 0x4B, data[cursor + 2] == 0x01, data[cursor + 3] == 0x02 else {
                break
            }
            let method = readUInt16LE(data, at: cursor + 10)
            let compSize = Int(readUInt32LE(data, at: cursor + 20))
            let uncompSize = Int(readUInt32LE(data, at: cursor + 24))
            let nameLen = Int(readUInt16LE(data, at: cursor + 28))
            let extraLen = Int(readUInt16LE(data, at: cursor + 30))
            let commentLen = Int(readUInt16LE(data, at: cursor + 32))
            let localOffset = Int(readUInt32LE(data, at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLen <= cdEnd else { break }
            let name = String(data: data.subdata(in: nameStart..<(nameStart + nameLen)), encoding: .utf8) ?? ""
            candidates.append(ZipEntry(
                name: name,
                method: method,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderOffset: localOffset
            ))
            cursor = nameStart + nameLen + extraLen + commentLen
        }

        guard let target = candidates.first(where: {
            let lower = $0.name.lowercased()
            return lower == "export.xml" || lower.hasSuffix("/export.xml")
        }) ?? candidates.first(where: {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".xml") && !lower.contains("cda")
        }) else {
            throw AppleHealthExportError.missingExportXMLInZip
        }

        let lh = target.localHeaderOffset
        guard lh + 30 <= data.count,
              data[lh] == 0x50, data[lh + 1] == 0x4B, data[lh + 2] == 0x03, data[lh + 3] == 0x04 else {
            throw AppleHealthExportError.invalidArchiveData
        }
        let localNameLen = Int(readUInt16LE(data, at: lh + 26))
        let localExtraLen = Int(readUInt16LE(data, at: lh + 28))
        let payloadStart = lh + 30 + localNameLen + localExtraLen
        let payloadEnd = payloadStart + target.compressedSize
        guard payloadStart >= 0, payloadEnd <= data.count else {
            throw AppleHealthExportError.invalidArchiveData
        }

        let compressedSlice = data.subdata(in: payloadStart..<payloadEnd)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tf_health_export_\(UUID().uuidString).xml")

        if target.method == 0 {
            try compressedSlice.write(to: tempURL)
            return tempURL
        }

        guard target.method == 8 else {
            throw AppleHealthExportError.invalidArchiveData
        }

        try inflateRawDeflateToFile(compressedSlice, to: tempURL)
        return tempURL
    }

    private static func inflateRawDeflateToFile(_ compressed: Data, to outputURL: URL) throws {
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }

        let dummyPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { dummyPtr.deallocate() }

        var stream = compression_stream(
            dst_ptr: dummyPtr,
            dst_size: 0,
            src_ptr: UnsafePointer(dummyPtr),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw AppleHealthExportError.invalidArchiveData
        }
        defer { compression_stream_destroy(&stream) }

        let outBufSize = 256 * 1024
        var outBuf = [UInt8](repeating: 0, count: outBufSize)

        try compressed.withUnsafeBytes { rawBuf in
            guard let basePtr = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.src_ptr = basePtr
            stream.src_size = compressed.count

            while true {
                let status: compression_status = outBuf.withUnsafeMutableBufferPointer { dst in
                    stream.dst_ptr = dst.baseAddress!
                    stream.dst_size = outBufSize
                    return compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                }
                let produced = outBufSize - stream.dst_size
                if produced > 0 {
                    try handle.write(contentsOf: Data(outBuf.prefix(produced)))
                }
                if status == COMPRESSION_STATUS_END {
                    break
                }
                if status == COMPRESSION_STATUS_ERROR {
                    throw AppleHealthExportError.invalidArchiveData
                }
            }
        }
    }

    // MARK: - JSON Importer (`Health Auto Export` + `BridgedHealthPayload`)

    public static func parseJSONExport(
        data: Data,
        referenceDate: Date = .now,
        defaultUnitSystem: UnitSystem = .imperial
    ) throws -> ParsedHealthExportBatch {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let directPayload = try? decoder.decode(BridgedHealthPayload.self, from: data),
           hasAnyHealthValue(directPayload) {
            return ParsedHealthExportBatch(
                formatDescription: "Total Factor Health JSON",
                todayPayload: directPayload,
                recentWorkouts: []
            )
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppleHealthExportError.unsupportedFormat
        }

        let container = (root["data"] as? [String: Any]) ?? root
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: referenceDate)

        var payload = BridgedHealthPayload()
        var stepsSum = 0.0
        var activeSum = 0.0
        var basalSum = 0.0
        var latestWeightDate: Date?
        var latestRHRDate: Date?
        var latestHRVDate: Date?
        var latestHRDate: Date?
        var todayHRMin: Double?
        var todayHRMax: Double?

        if let metrics = container["metrics"] as? [[String: Any]] {
            for metric in metrics {
                let name = ((metric["name"] as? String) ?? "").lowercased()
                let units = ((metric["units"] as? String) ?? "").lowercased()
                let points = (metric["data"] as? [[String: Any]]) ?? []
                for point in points {
                    guard let val = parseNumericAny(point["qty"] ?? point["avg"] ?? point["value"]) else { continue }
                    let pointDate = parseAnyDate(point["date"] as? String) ?? referenceDate
                    let isToday = pointDate >= todayStart && pointDate <= referenceDate.addingTimeInterval(3600)

                    if name.contains("step") {
                        if isToday { stepsSum += val }
                    } else if name.contains("active_energy") || name.contains("active energy") || name.contains("active_calories") {
                        if isToday {
                            activeSum += units.contains("kj") ? (val / 4.184) : val
                        }
                    } else if name.contains("basal_energy") || name.contains("resting_energy") || name.contains("resting energy") {
                        if isToday {
                            basalSum += units.contains("kj") ? (val / 4.184) : val
                        }
                    } else if name.contains("resting_heart_rate") || name == "rhr" {
                        if pointDate >= referenceDate.addingTimeInterval(-3 * 86400),
                           latestRHRDate == nil || pointDate >= latestRHRDate! {
                            latestRHRDate = pointDate
                            payload.restingHeartRateBPM = val.rounded()
                        }
                    } else if name.contains("heart_rate_variability") || name == "hrv" {
                        if pointDate >= referenceDate.addingTimeInterval(-3 * 86400),
                           latestHRVDate == nil || pointDate >= latestHRVDate! {
                            latestHRVDate = pointDate
                            payload.hrvSDNNMilliseconds = val.rounded()
                        }
                    } else if name == "heart_rate" || name.contains("heart rate") {
                        if isToday {
                            if latestHRDate == nil || pointDate >= latestHRDate! {
                                latestHRDate = pointDate
                                payload.currentHeartRateBPM = val.rounded()
                            }
                            let low = parseNumericAny(point["min"] ?? point["Min"]) ?? val
                            let high = parseNumericAny(point["max"] ?? point["Max"]) ?? val
                            todayHRMin = todayHRMin.map { min($0, low) } ?? low
                            todayHRMax = todayHRMax.map { max($0, high) } ?? high
                        }
                    } else if name.contains("weight") || name.contains("body_mass") {
                        if pointDate >= referenceDate.addingTimeInterval(-30 * 86400),
                           latestWeightDate == nil || pointDate >= latestWeightDate! {
                            latestWeightDate = pointDate
                            payload.weightKg = normalizeWeightKg(val, unitHint: units, defaultUnitSystem: defaultUnitSystem)
                        }
                    } else if name.contains("sleep") {
                        if isToday {
                            let hours = units.contains("min") ? (val / 60.0) : (units.contains("sec") ? (val / 3600.0) : val)
                            payload.sleepHours = ((payload.sleepHours ?? 0) + hours)
                        }
                    }
                }
            }
        }

        if stepsSum > 0 { payload.steps = Int(stepsSum.rounded()) }
        if activeSum > 0 { payload.activeCalories = activeSum.rounded() }
        if basalSum > 0 { payload.basalCalories = basalSum.rounded() }
        if let lo = todayHRMin { payload.minHeartRateBPM = lo.rounded() }
        if let hi = todayHRMax { payload.maxHeartRateBPM = hi.rounded() }
        if let sleep = payload.sleepHours { payload.sleepHours = (sleep * 10).rounded() / 10.0 }

        var workouts: [BridgedHealthPayload] = []
        if let rawWorkouts = container["workouts"] as? [[String: Any]] {
            let cutoff = referenceDate.addingTimeInterval(-14 * 86400)
            for item in rawWorkouts {
                let start = parseAnyDate(item["start"] as? String ?? item["startDate"] as? String) ?? referenceDate
                guard start >= cutoff else { continue }
                let durationSec: Int = {
                    if let s = parseNumericAny(item["duration"]) {
                        // Health Auto Export durations are seconds if >= 60 or unit=="s"; check unit
                        let u = ((item["durationUnit"] as? String) ?? "s").lowercased()
                        return Int((u.hasPrefix("min") ? s * 60.0 : s).rounded())
                    }
                    if let end = parseAnyDate(item["end"] as? String ?? item["endDate"] as? String) {
                        return max(0, Int(end.timeIntervalSince(start).rounded()))
                    }
                    return 0
                }()
                guard durationSec >= 30 else { continue }

                var w = BridgedHealthPayload()
                w.workoutTitle = (item["name"] as? String) ?? "Workout"
                w.workoutKindRaw = w.workoutTitle
                w.workoutStartDate = start
                w.workoutDurationSeconds = durationSec
                w.workoutSourceName = (item["source"] as? String) ?? "Health Export (JSON)"

                if let activeDict = item["activeEnergyBurned"] as? [String: Any],
                   let qty = parseNumericAny(activeDict["qty"]) {
                    let u = ((activeDict["units"] as? String) ?? "kcal").lowercased()
                    w.workoutCalories = (u.contains("kj") ? qty / 4.184 : qty).rounded()
                } else if let kcal = parseNumericAny(item["activeEnergy"] ?? item["calories"]) {
                    w.workoutCalories = kcal.rounded()
                }

                if let distDict = item["distance"] as? [String: Any],
                   let qty = parseNumericAny(distDict["qty"]) {
                    let u = ((distDict["units"] as? String) ?? "km").lowercased()
                    w.workoutDistanceMeters = normalizeDistanceMeters(qty, unit: u)
                }

                if let hrDict = item["avgHeartRate"] as? [String: Any],
                   let qty = parseNumericAny(hrDict["qty"]) {
                    w.workoutAvgHeartRate = qty.rounded()
                }
                workouts.append(w)
            }
        }

        if !hasAnyHealthValue(payload) && workouts.isEmpty {
            throw AppleHealthExportError.noRecentHealthDataFound
        }

        return ParsedHealthExportBatch(
            formatDescription: "Apple Health JSON Export",
            todayPayload: hasAnyHealthValue(payload) ? payload : nil,
            recentWorkouts: workouts
        )
    }

    // MARK: - CSV Importer (`Simple Health Export CSV` / `QS Access`)

    public static func parseCSVExport(
        data: Data,
        referenceDate: Date = .now,
        defaultUnitSystem: UnitSystem = .imperial
    ) throws -> ParsedHealthExportBatch {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw AppleHealthExportError.unreadableFile
        }
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0) }

        guard lines.count >= 2 else {
            throw AppleHealthExportError.noRecentHealthDataFound
        }

        let headers = parseCSVRow(lines[0]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let lowerHeaders = headers.map { $0.lowercased() }

        let dateCol = lowerHeaders.firstIndex(where: { $0.contains("date") || $0.contains("start") || $0.contains("time") })
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: referenceDate)

        var payload = BridgedHealthPayload()
        var stepsSum = 0.0
        var activeSum = 0.0
        var basalSum = 0.0
        var matchedTodayRows = 0

        for line in lines.dropFirst() {
            let cols = parseCSVRow(line)
            guard cols.count == headers.count else { continue }

            let rowDate: Date? = dateCol.flatMap { parseAnyDate(cols[$0]) }
            let isTodayOrUndated: Bool = {
                guard let rowDate else { return true }
                return cal.isDate(rowDate, inSameDayAs: todayStart)
            }()
            let isRecent = rowDate.map { $0 >= referenceDate.addingTimeInterval(-30 * 86400) } ?? true
            guard isRecent else { continue }

            if isTodayOrUndated {
                matchedTodayRows += 1
            }

            for (idx, h) in lowerHeaders.enumerated() {
                guard idx != dateCol, let val = parseNumericString(cols[idx]) else { continue }
                if h.contains("step") && isTodayOrUndated {
                    stepsSum += val
                } else if (h.contains("active energy") || h.contains("active calories")) && isTodayOrUndated {
                    activeSum += val
                } else if (h.contains("resting energy") || h.contains("basal")) && isTodayOrUndated {
                    basalSum += val
                } else if h.contains("resting heart") {
                    payload.restingHeartRateBPM = val.rounded()
                } else if h.contains("hrv") || h.contains("variability") {
                    payload.hrvSDNNMilliseconds = val.rounded()
                } else if h.contains("heart rate") && isTodayOrUndated {
                    payload.currentHeartRateBPM = val.rounded()
                } else if h.contains("weight") || h.contains("body mass") {
                    payload.weightKg = normalizeWeightKg(val, unitHint: h, defaultUnitSystem: defaultUnitSystem)
                } else if h.contains("sleep") && isTodayOrUndated {
                    let hours = h.contains("min") ? (val / 60.0) : val
                    payload.sleepHours = ((payload.sleepHours ?? 0) + hours)
                }
            }
        }

        if stepsSum > 0 { payload.steps = Int(stepsSum.rounded()) }
        if activeSum > 0 { payload.activeCalories = activeSum.rounded() }
        if basalSum > 0 { payload.basalCalories = basalSum.rounded() }
        if let sleep = payload.sleepHours { payload.sleepHours = (sleep * 10).rounded() / 10.0 }

        guard matchedTodayRows > 0 || hasAnyHealthValue(payload) else {
            throw AppleHealthExportError.noRecentHealthDataFound
        }

        return ParsedHealthExportBatch(
            formatDescription: "Health CSV Export",
            todayPayload: hasAnyHealthValue(payload) ? payload : nil,
            recentWorkouts: []
        )
    }

    // MARK: - Helpers

    private static func hasAnyHealthValue(_ p: BridgedHealthPayload) -> Bool {
        p.steps != nil || p.activeCalories != nil || p.basalCalories != nil || p.restingHeartRateBPM != nil || p.hrvSDNNMilliseconds != nil || p.currentHeartRateBPM != nil || p.weightKg != nil || p.sleepHours != nil || p.workoutDurationSeconds != nil
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    fileprivate static func normalizeWeightKg(_ value: Double, unitHint: String, defaultUnitSystem: UnitSystem) -> Double {
        let lower = unitHint.lowercased()
        if lower.contains("kg") { return value }
        if lower.contains("lb") || lower.contains("pound") { return value * lbsToKgFactor }
        if lower.contains("st") { return value * 6.35029318 }
        return defaultUnitSystem == .imperial ? (value * lbsToKgFactor) : value
    }

    fileprivate static func normalizeDistanceMeters(_ value: Double, unit: String) -> Double {
        let lower = unit.lowercased()
        if lower.contains("km") { return value * 1000.0 }
        if lower.contains("mi") { return value * CardioDistanceUnit.metersPerMile }
        if lower.contains("yd") { return value * 0.9144 }
        return value
    }

    private static func parseNumericAny(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return parseNumericString(s) }
        return nil
    }

    private static func parseNumericString(_ s: String) -> Double? {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private static func parseCSVRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    fileprivate static func parseAnyDate(_ str: String?) -> Date? {
        guard let raw = str?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        for fmt in AppleHealthXMLDateFormatters.all {
            if let d = fmt.date(from: raw) { return d }
        }
        if let iso = ISO8601DateFormatter().date(from: raw) {
            return iso
        }
        return nil
    }
}

private enum AppleHealthXMLDateFormatters {
    static let appleHealth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let usDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d/yyyy"
        return f
    }()

    static let all: [DateFormatter] = [appleHealth, dateTime, dateOnly, usDate]
}

private final class AppleHealthXMLStreamDelegate: NSObject, XMLParserDelegate {
    private let referenceDate: Date
    private let todayStart: Date
    private let weightCutoff: Date
    private let vitalsCutoff: Date
    private let workoutCutoff: Date

    private var stepsToday: Double = 0
    private var activeToday: Double = 0
    private var basalToday: Double = 0
    private var sleepHoursToday: Double = 0

    private var latestRHR: (Date, Double)?
    private var latestHRV: (Date, Double)?
    private var latestHR: (Date, Double)?
    private var minHRToday: Double?
    private var maxHRToday: Double?
    private var latestWeightKg: (Date, Double)?

    private struct ActiveWorkoutContext {
        var activityType: String
        var startDate: Date
        var endDate: Date
        var durationSeconds: Int
        var sourceName: String
        var activeCalories: Double?
        var distanceMeters: Double?
        var avgHR: Double?
    }

    private var activeWorkout: ActiveWorkoutContext?
    private var workouts: [BridgedHealthPayload] = []

    init(referenceDate: Date) {
        self.referenceDate = referenceDate
        let cal = Calendar.current
        self.todayStart = cal.startOfDay(for: referenceDate)
        self.vitalsCutoff = referenceDate.addingTimeInterval(-3 * 86400)
        self.workoutCutoff = referenceDate.addingTimeInterval(-14 * 86400)
        self.weightCutoff = referenceDate.addingTimeInterval(-30 * 86400)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        if elementName == "Record" {
            handleRecord(attributes)
        } else if elementName == "Workout" {
            handleWorkoutStart(attributes)
        } else if elementName == "WorkoutStatistics", activeWorkout != nil {
            handleWorkoutStatistics(attributes)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "Workout", let ctx = activeWorkout {
            activeWorkout = nil
            var payload = BridgedHealthPayload()
            let readable = Self.humanReadableWorkoutTitle(ctx.activityType)
            payload.workoutTitle = readable
            payload.workoutKindRaw = readable
            payload.workoutStartDate = ctx.startDate
            payload.workoutDurationSeconds = ctx.durationSeconds
            payload.workoutCalories = ctx.activeCalories?.rounded()
            payload.workoutDistanceMeters = ctx.distanceMeters
            payload.workoutAvgHeartRate = ctx.avgHR?.rounded()
            payload.workoutSourceName = ctx.sourceName
            payload.workoutExternalID = "ahxml|\(Int(ctx.startDate.timeIntervalSince1970))|\(ctx.durationSeconds)"
            workouts.append(payload)
        }
    }

    private func handleRecord(_ attrs: [String: String]) {
        guard let type = attrs["type"] else { return }
        guard let startStr = attrs["startDate"],
              let startDate = AppleHealthXMLDateFormatters.appleHealth.date(from: startStr) else {
            return
        }
        guard startDate >= weightCutoff else { return }
        let endDate = attrs["endDate"].flatMap { AppleHealthXMLDateFormatters.appleHealth.date(from: $0) } ?? startDate

        if type == "HKCategoryTypeIdentifierSleepAnalysis" {
            guard endDate >= todayStart && endDate <= referenceDate.addingTimeInterval(3600) else { return }
            let val = attrs["value"] ?? ""
            if val.contains("Asleep") {
                sleepHoursToday += max(0, endDate.timeIntervalSince(startDate)) / 3600.0
            }
            return
        }

        guard let valueStr = attrs["value"], let numericValue = Double(valueStr) else { return }
        let unit = (attrs["unit"] ?? "").lowercased()
        let isToday = endDate >= todayStart && startDate <= referenceDate.addingTimeInterval(3600)

        switch type {
        case "HKQuantityTypeIdentifierStepCount":
            if isToday { stepsToday += numericValue }
        case "HKQuantityTypeIdentifierActiveEnergyBurned":
            if isToday {
                activeToday += unit.contains("kj") ? (numericValue / 4.184) : numericValue
            }
        case "HKQuantityTypeIdentifierBasalEnergyBurned":
            if isToday {
                basalToday += unit.contains("kj") ? (numericValue / 4.184) : numericValue
            }
        case "HKQuantityTypeIdentifierRestingHeartRate":
            if startDate >= vitalsCutoff, latestRHR == nil || startDate >= latestRHR!.0 {
                latestRHR = (startDate, numericValue)
            }
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            if startDate >= vitalsCutoff, latestHRV == nil || startDate >= latestHRV!.0 {
                latestHRV = (startDate, numericValue)
            }
        case "HKQuantityTypeIdentifierHeartRate":
            if isToday {
                if latestHR == nil || startDate >= latestHR!.0 {
                    latestHR = (startDate, numericValue)
                }
                minHRToday = minHRToday.map { min($0, numericValue) } ?? numericValue
                maxHRToday = maxHRToday.map { max($0, numericValue) } ?? numericValue
            }
        case "HKQuantityTypeIdentifierBodyMass":
            if startDate >= weightCutoff, latestWeightKg == nil || startDate >= latestWeightKg!.0 {
                let kg = AppleHealthExportImporter.normalizeWeightKg(numericValue, unitHint: unit, defaultUnitSystem: .metric)
                latestWeightKg = (startDate, kg)
            }
        default:
            break
        }
    }

    private func handleWorkoutStart(_ attrs: [String: String]) {
        guard let startStr = attrs["startDate"],
              let startDate = AppleHealthXMLDateFormatters.appleHealth.date(from: startStr),
              startDate >= workoutCutoff else {
            return
        }
        let endDate = attrs["endDate"].flatMap { AppleHealthXMLDateFormatters.appleHealth.date(from: $0) } ?? startDate

        let durationSec: Int = {
            if let durStr = attrs["duration"], let durVal = Double(durStr), durVal > 0 {
                let u = (attrs["durationUnit"] ?? "min").lowercased()
                let mult: Double = u.hasPrefix("s") ? 1.0 : (u.hasPrefix("hr") || u.hasPrefix("h") ? 3600.0 : 60.0)
                return Int((durVal * mult).rounded())
            }
            return max(0, Int(endDate.timeIntervalSince(startDate).rounded()))
        }()
        guard durationSec >= 30 else { return }

        let activeKcal: Double? = attrs["totalEnergyBurned"].flatMap(Double.init).map { val in
            let u = (attrs["totalEnergyBurnedUnit"] ?? "kcal").lowercased()
            return u.contains("kj") ? val / 4.184 : val
        }
        let distMeters: Double? = attrs["totalDistance"].flatMap(Double.init).map { val in
            AppleHealthExportImporter.normalizeDistanceMeters(val, unit: attrs["totalDistanceUnit"] ?? "km")
        }

        activeWorkout = ActiveWorkoutContext(
            activityType: attrs["workoutActivityType"] ?? "HKWorkoutActivityTypeOther",
            startDate: startDate,
            endDate: endDate,
            durationSeconds: durationSec,
            sourceName: (attrs["sourceName"]?.isEmpty == false ? attrs["sourceName"]! : "Apple Health Export"),
            activeCalories: activeKcal,
            distanceMeters: distMeters,
            avgHR: nil
        )
    }

    private func handleWorkoutStatistics(_ attrs: [String: String]) {
        guard var ctx = activeWorkout, let type = attrs["type"] else { return }
        let unit = (attrs["unit"] ?? "").lowercased()
        if type == "HKQuantityTypeIdentifierActiveEnergyBurned",
           let sumStr = attrs["sum"], let sumVal = Double(sumStr) {
            ctx.activeCalories = unit.contains("kj") ? (sumVal / 4.184) : sumVal
        } else if type.contains("Distance"),
                  let sumStr = attrs["sum"], let sumVal = Double(sumStr) {
            ctx.distanceMeters = AppleHealthExportImporter.normalizeDistanceMeters(sumVal, unit: unit.isEmpty ? "m" : unit)
        } else if type == "HKQuantityTypeIdentifierHeartRate",
                  let avgStr = attrs["average"], let avgVal = Double(avgStr) {
            ctx.avgHR = avgVal
        }
        activeWorkout = ctx
    }

    func buildBatch() -> ParsedHealthExportBatch {
        var today = BridgedHealthPayload()
        if stepsToday > 0 { today.steps = Int(stepsToday.rounded()) }
        if activeToday > 0 { today.activeCalories = activeToday.rounded() }
        if basalToday > 0 { today.basalCalories = basalToday.rounded() }
        if let rhr = latestRHR?.1 { today.restingHeartRateBPM = rhr.rounded() }
        if let hrv = latestHRV?.1 { today.hrvSDNNMilliseconds = hrv.rounded() }
        if let hr = latestHR?.1 { today.currentHeartRateBPM = hr.rounded() }
        if let lo = minHRToday { today.minHeartRateBPM = lo.rounded() }
        if let hi = maxHRToday { today.maxHeartRateBPM = hi.rounded() }
        if let wKg = latestWeightKg?.1 { today.weightKg = wKg }
        if sleepHoursToday > 0 { today.sleepHours = (sleepHoursToday * 10).rounded() / 10.0 }

        let hasToday = today.steps != nil || today.activeCalories != nil || today.basalCalories != nil || today.restingHeartRateBPM != nil || today.hrvSDNNMilliseconds != nil || today.currentHeartRateBPM != nil || today.weightKg != nil || today.sleepHours != nil

        return ParsedHealthExportBatch(
            formatDescription: "Apple Health Export XML",
            todayPayload: hasToday ? today : nil,
            recentWorkouts: workouts
        )
    }

    private static func humanReadableWorkoutTitle(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(of: "HKWorkoutActivityType", with: "")
        switch stripped.lowercased() {
        case "running": return "Run"
        case "walking": return "Walk"
        case "cycling": return "Cycling"
        case "rowing": return "Rowing"
        case "swimming": return "Swimming"
        case "soccer": return "Soccer"
        case "basketball": return "Basketball"
        case "highintensityintervaltraining": return "HIIT"
        default: return stripped.isEmpty ? "Cardio" : stripped
        }
    }
}

private extension UInt8 {
    var isWhitespaceASCII: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}

import Compression
import XCTest
import SwiftData
#if canImport(TotalFactor)
@testable import TotalFactor
#endif

#if canImport(TotalFactor)
@MainActor
final class AppleHealthExportImporterTests: XCTestCase {
    func testParseAppleHealthExportXMLAndModernWorkoutStatistics() throws {
        let now = Date()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        let morning = Calendar.current.startOfDay(for: now).addingTimeInterval(3600 * 9)
        let noon = morning.addingTimeInterval(3600 * 3)
        let workoutStart = morning.addingTimeInterval(3600 * 2)
        let workoutEnd = workoutStart.addingTimeInterval(1800)

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="en_US">
          <Record type="HKQuantityTypeIdentifierStepCount" unit="count" value="3200" startDate="\(fmt.string(from: morning))" endDate="\(fmt.string(from: morning.addingTimeInterval(600)))"/>
          <Record type="HKQuantityTypeIdentifierStepCount" unit="count" value="4100" startDate="\(fmt.string(from: noon))" endDate="\(fmt.string(from: noon.addingTimeInterval(600)))"/>
          <Record type="HKQuantityTypeIdentifierActiveEnergyBurned" unit="kcal" value="250.5" startDate="\(fmt.string(from: morning))" endDate="\(fmt.string(from: morning.addingTimeInterval(600)))"/>
          <Record type="HKQuantityTypeIdentifierActiveEnergyBurned" unit="kcal" value="180.0" startDate="\(fmt.string(from: noon))" endDate="\(fmt.string(from: noon.addingTimeInterval(600)))"/>
          <Record type="HKQuantityTypeIdentifierBasalEnergyBurned" unit="kcal" value="1620" startDate="\(fmt.string(from: morning))" endDate="\(fmt.string(from: noon))"/>
          <Record type="HKQuantityTypeIdentifierRestingHeartRate" unit="count/min" value="57" startDate="\(fmt.string(from: morning))" endDate="\(fmt.string(from: morning))"/>
          <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" unit="ms" value="62" startDate="\(fmt.string(from: morning))" endDate="\(fmt.string(from: morning))"/>
          <Record type="HKQuantityTypeIdentifierBodyMass" unit="lb" value="170" startDate="\(fmt.string(from: morning))" endDate="\(fmt.string(from: morning))"/>
          <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="30" durationUnit="min" startDate="\(fmt.string(from: workoutStart))" endDate="\(fmt.string(from: workoutEnd))" sourceName="Apple Watch">
            <WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" sum="315" unit="kcal"/>
            <WorkoutStatistics type="HKQuantityTypeIdentifierDistanceWalkingRunning" sum="3.1" unit="mi"/>
            <WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" average="154" unit="count/min"/>
          </Workout>
        </HealthData>
        """

        let xmlURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_health_export_\(UUID().uuidString).xml")
        defer { try? FileManager.default.removeItem(at: xmlURL) }
        try xml.write(to: xmlURL, atomically: true, encoding: .utf8)

        let batch = try AppleHealthExportImporter.parseAppleHealthXML(at: xmlURL, referenceDate: now)
        let today = try XCTUnwrap(batch.todayPayload)
        XCTAssertEqual(today.steps, 7300)
        XCTAssertEqual(today.activeCalories, 431)
        XCTAssertEqual(today.basalCalories, 1620)
        XCTAssertEqual(today.restingHeartRateBPM, 57)
        XCTAssertEqual(today.hrvSDNNMilliseconds, 62)
        XCTAssertEqual(try XCTUnwrap(today.weightKg), 170.0 * 0.45359237, accuracy: 0.05)

        XCTAssertEqual(batch.recentWorkouts.count, 1)
        let w = try XCTUnwrap(batch.recentWorkouts.first)
        XCTAssertEqual(w.workoutTitle, "Run")
        XCTAssertEqual(w.workoutDurationSeconds, 1800)
        XCTAssertEqual(w.workoutCalories, 315)
        XCTAssertEqual(try XCTUnwrap(w.workoutDistanceMeters), 3.1 * CardioDistanceUnit.metersPerMile, accuracy: 1.0)
        XCTAssertEqual(w.workoutAvgHeartRate, 154)
    }

    func testParseDeflatedExportZipContainer() throws {
        let now = Date()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let morning = Calendar.current.startOfDay(for: now).addingTimeInterval(3600 * 8)

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData>
          <Record type="HKQuantityTypeIdentifierStepCount" unit="count" value="5432" startDate="\(fmt.string(from: morning))" endDate="\(fmt.string(from: morning.addingTimeInterval(600)))"/>
        </HealthData>
        """
        let rawData = Data(xml.utf8)
        let compressed = try rawDeflate(rawData)

        let zipData = makeSingleEntryZip(
            fileName: "apple_health_export/export.xml",
            compressedPayload: compressed,
            uncompressedSize: UInt32(rawData.count),
            method: 8
        )

        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_export_\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zipURL) }
        try zipData.write(to: zipURL)

        let batch = try AppleHealthExportImporter.parseFile(at: zipURL, referenceDate: now)
        XCTAssertEqual(batch.todayPayload?.steps, 5432)
    }

    func testParseHealthAutoExportJSONAndCSV() throws {
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now)

        let jsonStr = """
        {
          "data": {
            "metrics": [
              { "name": "step_count", "units": "count", "data": [{ "date": "\(iso)", "qty": 9120 }] },
              { "name": "active_energy", "units": "kcal", "data": [{ "date": "\(iso)", "qty": 510 }] },
              { "name": "weight_body_mass", "units": "lb", "data": [{ "date": "\(iso)", "qty": 175.0 }] }
            ],
            "workouts": [
              {
                "name": "Cycling",
                "start": "\(iso)",
                "duration": 2400,
                "activeEnergyBurned": { "qty": 380, "units": "kcal" },
                "distance": { "qty": 12.0, "units": "km" }
              }
            ]
          }
        }
        """

        let jsonBatch = try AppleHealthExportImporter.parseJSONExport(
            data: Data(jsonStr.utf8),
            referenceDate: now,
            defaultUnitSystem: .imperial
        )
        XCTAssertEqual(jsonBatch.todayPayload?.steps, 9120)
        XCTAssertEqual(jsonBatch.todayPayload?.activeCalories, 510)
        XCTAssertEqual(try XCTUnwrap(jsonBatch.todayPayload?.weightKg), 175.0 * 0.45359237, accuracy: 0.05)
        XCTAssertEqual(jsonBatch.recentWorkouts.count, 1)
        XCTAssertEqual(jsonBatch.recentWorkouts.first?.workoutTitle, "Cycling")

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.dateFormat = "yyyy-MM-dd"
        let csv = """
        Date,Steps,Active Energy (kcal),Resting Heart Rate (bpm)
        \(dayFmt.string(from: now)),8450,420,56
        """
        let csvBatch = try AppleHealthExportImporter.parseCSVExport(data: Data(csv.utf8), referenceDate: now)
        XCTAssertEqual(csvBatch.todayPayload?.steps, 8450)
        XCTAssertEqual(csvBatch.todayPayload?.activeCalories, 420)
        XCTAssertEqual(csvBatch.todayPayload?.restingHeartRateBPM, 56)
    }

    // MARK: - Minimal Deflate + ZIP Builder for Tests

    private func rawDeflate(_ input: Data) throws -> Data {
        let cap = max(input.count + 64, 1024)
        var out = Data(count: cap)
        let written = out.withUnsafeMutableBytes { dstBuf -> Int in
            input.withUnsafeBytes { srcBuf -> Int in
                guard let dst = dstBuf.bindMemory(to: UInt8.self).baseAddress,
                      let src = srcBuf.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(dst, cap, src, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        XCTAssertGreaterThan(written, 0)
        return out.prefix(written)
    }

    private func makeSingleEntryZip(
        fileName: String,
        compressedPayload: Data,
        uncompressedSize: UInt32,
        method: UInt16
    ) -> Data {
        let nameData = Data(fileName.utf8)
        let compSize = UInt32(compressedPayload.count)
        let nameLen = UInt16(nameData.count)

        var zip = Data()
        // Local file header (simulate data descriptor zeroes like iOS archives)
        zip.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
        zip.appendLE(UInt16(20))
        zip.appendLE(UInt16(0x0008))
        zip.appendLE(method)
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt32(0))
        zip.appendLE(UInt32(0))
        zip.appendLE(UInt32(0))
        zip.appendLE(nameLen)
        zip.appendLE(UInt16(0))
        zip.append(nameData)
        zip.append(compressedPayload)

        let cdOffset = UInt32(zip.count)
        zip.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        zip.appendLE(UInt16(20))
        zip.appendLE(UInt16(20))
        zip.appendLE(UInt16(0x0008))
        zip.appendLE(method)
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt32(0))
        zip.appendLE(compSize)
        zip.appendLE(uncompressedSize)
        zip.appendLE(nameLen)
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt32(0))
        zip.appendLE(UInt32(0))
        zip.append(nameData)

        let cdSize = UInt32(zip.count) - cdOffset
        zip.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(1))
        zip.appendLE(UInt16(1))
        zip.appendLE(cdSize)
        zip.appendLE(cdOffset)
        zip.appendLE(UInt16(0))
        return zip
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
#endif

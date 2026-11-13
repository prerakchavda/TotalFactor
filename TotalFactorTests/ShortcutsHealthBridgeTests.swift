import XCTest
import SwiftData
#if canImport(TotalFactor)
@testable import TotalFactor
#endif

#if canImport(TotalFactor)
@MainActor
final class ShortcutsHealthBridgeTests: XCTestCase {
    func testParseHealthSyncURLWithGroupedNumbersAndWeightUnit() throws {
        let url = try XCTUnwrap(
            URL(string: "totalfactor://health-sync?steps=10,432&active_kcal=485.4&basal_kcal=1720&rhr=58&hrv=64&hr=72&weight=172.0&weight_unit=lb")
        )
        let payload = try XCTUnwrap(ShortcutsHealthBridge.parseURL(url, defaultUnitSystem: .metric))

        XCTAssertEqual(payload.steps, 10_432)
        XCTAssertEqual(payload.activeCalories, 485)
        XCTAssertEqual(payload.basalCalories, 1720)
        XCTAssertEqual(payload.restingHeartRateBPM, 58)
        XCTAssertEqual(payload.hrvSDNNMilliseconds, 64)
        XCTAssertEqual(payload.currentHeartRateBPM, 72)
        XCTAssertEqual(try XCTUnwrap(payload.weightKg), 172.0 * 0.45359237, accuracy: 0.01)
    }

    func testParseAndApplyWorkoutSyncDeduplicatesRepeatCalls() throws {
        let schema = Schema([CardioSession.self, WeighIn.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let fixedStart = Date(timeIntervalSince1970: 1_794_500_000)
        let iso = ISO8601DateFormatter().string(from: fixedStart)
        let url = try XCTUnwrap(
            URL(string: "totalfactor://workout-sync?workout_title=Incline%20Walk&workout_min=35&workout_kcal=290&workout_mi=2.0&source=Apple%20Fitness&workout_start=\(iso)")
        )

        let payload = try XCTUnwrap(ShortcutsHealthBridge.parseURL(url))
        XCTAssertEqual(payload.workoutDurationSeconds, 2100)
        XCTAssertEqual(try XCTUnwrap(payload.workoutDistanceMeters), 3218.688, accuracy: 0.5)

        let service = HealthKitService()
        _ = ShortcutsHealthBridge.apply(payload, context: context, healthService: service)
        _ = ShortcutsHealthBridge.apply(payload, context: context, healthService: service)

        let stored = try context.fetch(FetchDescriptor<CardioSession>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.kind, .inclineWalk)
        XCTAssertEqual(stored.first?.durationSeconds, 2100)
        XCTAssertEqual(stored.first?.activeCalories, 290)
        XCTAssertEqual(stored.first?.importedFromHealth, true)
    }
}
#endif

import XCTest
import SwiftData
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

final class ChargingSessionTests: XCTestCase {

    private let tariff = BulgarianTariffProfile()

    private func sample(
        at date: Date,
        charging: Bool?,
        powerKW: Double?,
        soc: Double? = 50
    ) -> TelemetrySample {
        var sample = TelemetrySample(timestamp: date)
        sample.isCharging = charging
        sample.batteryPowerKW = powerKW
        sample.socPercent = soc
        return sample
    }

    private func date(hour: Int, minute: Int, day: Int = 15) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - Energy and cost

    func testEnergyIsIntegratedFromPowerSamples() {
        var tracker = ChargingSessionTracker(tariff: tariff)
        let start = date(hour: 10, minute: 0)

        _ = tracker.ingest(sample(at: start, charging: true, powerKW: -7.2))
        var latest: ChargingSessionTracker.Event?
        for second in 1...60 {
            latest = tracker.ingest(
                sample(at: start.addingTimeInterval(Double(second)), charging: true, powerKW: -7.2)
            )
        }

        guard case let .updated(_, energy, peak, cost, _)? = latest else {
            return XCTFail("expected an update, got \(String(describing: latest))")
        }
        XCTAssertEqual(energy, 0.12, accuracy: 1e-6)          // 7.2 kW × 60 s
        XCTAssertEqual(peak, 7.2, accuracy: 1e-6)
        XCTAssertEqual(cost, energy * tariff.day.allInEURPerKWh, accuracy: 1e-9)
    }

    func testCostSplitsAtTheNightTariffBoundary() {
        var tracker = ChargingSessionTracker(tariff: tariff)
        let start = date(hour: 21, minute: 58)

        _ = tracker.ingest(sample(at: start, charging: true, powerKW: -6))
        var last: ChargingSessionTracker.Event?
        for minute in 1...4 {
            last = tracker.ingest(
                sample(at: start.addingTimeInterval(Double(minute) * 60), charging: true, powerKW: -6)
            )
        }

        guard case let .updated(_, energy, _, cost, _)? = last else {
            return XCTFail("expected an update")
        }
        // 6 kW for 4 minutes = 0.4 kWh, two minutes on each tariff.
        XCTAssertEqual(energy, 0.4, accuracy: 1e-6)
        let expected = BulgarianTariffEngine.costForInterval(
            energyKWh: 0.4,
            start: start,
            end: start.addingTimeInterval(240),
            profile: tariff
        )
        XCTAssertEqual(cost, expected, accuracy: 1e-9)
        XCTAssertLessThan(cost, 0.4 * tariff.day.allInEURPerKWh)
        XCTAssertGreaterThan(cost, 0.4 * tariff.night.allInEURPerKWh)
    }

    // MARK: - Lifecycle

    func testSessionNeedsThreeIdleSamplesToEnd() {
        var tracker = ChargingSessionTracker(tariff: tariff)
        let start = date(hour: 9, minute: 0)
        _ = tracker.ingest(sample(at: start, charging: true, powerKW: -11))

        XCTAssertNil(tracker.ingest(sample(at: start.addingTimeInterval(1), charging: false, powerKW: 0.4)))
        XCTAssertNil(tracker.ingest(sample(at: start.addingTimeInterval(2), charging: false, powerKW: 0.4)))
        guard case let .ended(summary)? = tracker.ingest(
            sample(at: start.addingTimeInterval(3), charging: false, powerKW: 0.4)
        ) else {
            return XCTFail("expected the session to end after 3 idle samples")
        }
        XCTAssertEqual(summary.start, start)
        XCTAssertEqual(summary.isDC, false)
        XCTAssertNil(tracker.active)
    }

    func testDCClassificationUsesPeakPower() {
        var tracker = ChargingSessionTracker(tariff: tariff)
        let start = date(hour: 12, minute: 0)
        _ = tracker.ingest(sample(at: start, charging: true, powerKW: -11))
        _ = tracker.ingest(sample(at: start.addingTimeInterval(30), charging: true, powerKW: -150))
        for index in 2...4 {
            _ = tracker.ingest(
                sample(at: start.addingTimeInterval(Double(index) * 30), charging: true, powerKW: -150)
            )
        }
        var endEvent: ChargingSessionTracker.Event?
        for second in 201...203 {
            endEvent = tracker.ingest(
                sample(at: start.addingTimeInterval(Double(second)), charging: false, powerKW: 0)
            )
        }
        guard case let .ended(summary)? = endEvent else { return XCTFail("expected end") }
        XCTAssertTrue(summary.isDC)
        XCTAssertEqual(summary.peakPowerKW, 150, accuracy: 1e-9)
    }

    func testUnknownChargingFlagDoesNotCloseTheSession() {
        var tracker = ChargingSessionTracker(tariff: tariff)
        let start = date(hour: 8, minute: 0)
        _ = tracker.ingest(sample(at: start, charging: true, powerKW: -7))
        for second in 1...5 {
            XCTAssertNil(tracker.ingest(sample(
                at: start.addingTimeInterval(Double(second)),
                charging: nil,
                powerKW: nil
            )))
        }
        XCTAssertNotNil(tracker.active)
    }

    func testLongGapClosesTheOldSessionAndStartsANewOne() {
        var tracker = ChargingSessionTracker(tariff: tariff)
        let start = date(hour: 14, minute: 0)
        _ = tracker.ingest(sample(at: start, charging: true, powerKW: -50))
        _ = tracker.ingest(sample(at: start.addingTimeInterval(30), charging: true, powerKW: -50))

        guard case let .ended(summary)? = tracker.ingest(
            sample(at: start.addingTimeInterval(30 + 1_200), charging: true, powerKW: -50)
        ) else { return XCTFail("expected the old session to close") }
        XCTAssertEqual(summary.end, start.addingTimeInterval(30))
        XCTAssertNotNil(tracker.active)
        XCTAssertEqual(tracker.active?.start, start.addingTimeInterval(30 + 1_200))
    }

    // MARK: - Persistence / migration

    func testSchemaV2MigratesAV1StoreAndKeepsTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("evinfo-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("store.sqlite")

        // Write a V1 store with one trip, then close it.
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(TripRecord(startDate: Date(timeIntervalSince1970: 1_700_000_000)))
            try context.save()
        }

        // Reopen with V2 and the migration plan.
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripRecord>()), 1)
        let session = ChargingSession(startDate: .now, startSOCPercent: 30)
        context.insert(session)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChargingSession>()), 1)
    }
}

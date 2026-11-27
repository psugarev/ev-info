import XCTest
import SwiftData
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

// Covers audit H2/H4: retention, cascade delete, delete-all and the versioned
// schema container.

@MainActor
final class StorageHygieneTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContext() -> ModelContext {
        ModelContext(PersistenceController.makeInMemoryContainer())
    }

    private func frame(daysAgo: Int, tripID: UUID? = nil) -> RawOBDFrame {
        let frame = RawOBDFrame(request: "010D", response: "41 0D 00", tripID: tripID)
        frame.timestamp = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return frame
    }

    // MARK: Retention

    func testCutoffIsNilWhenRetentionIsUnlimited() {
        XCTAssertNil(DataRetention.cutoff(days: 0, now: now))
    }

    func testPurgeRemovesOnlyFramesOlderThanRetention() throws {
        let context = makeContext()
        context.insert(frame(daysAgo: 100))
        context.insert(frame(daysAgo: 91))
        context.insert(frame(daysAgo: 10))
        try context.save()

        try DataRetention.purge(olderThanDays: 90, in: context, now: now)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RawOBDFrame>()), 1)
    }

    func testPurgeKeepsEverythingWhenRetentionIsForever() throws {
        let context = makeContext()
        context.insert(frame(daysAgo: 4_000))
        try context.save()

        try DataRetention.purge(olderThanDays: 0, in: context, now: now)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RawOBDFrame>()), 1)
    }

    func testPurgeKeepsTripSummaries() throws {
        let context = makeContext()
        context.insert(TripRecord(startDate: now.addingTimeInterval(-400 * 86_400)))
        try context.save()

        try DataRetention.purge(olderThanDays: 30, in: context, now: now)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripRecord>()), 1)
    }

    // MARK: Cascade delete

    func testDeletingTripRemovesItsRawFramesOnly() throws {
        let context = makeContext()
        let doomed = TripRecord(startDate: now)
        let kept = TripRecord(startDate: now)
        context.insert(doomed)
        context.insert(kept)
        context.insert(frame(daysAgo: 0, tripID: doomed.id))
        context.insert(frame(daysAgo: 0, tripID: doomed.id))
        context.insert(frame(daysAgo: 0, tripID: kept.id))
        context.insert(frame(daysAgo: 0, tripID: nil))
        try context.save()

        try DataRetention.delete(doomed, in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RawOBDFrame>()), 2)
    }

    // MARK: Delete all

    func testDeleteAllEmptiesEveryTable() throws {
        let context = makeContext()
        context.insert(TripRecord(startDate: now))
        context.insert(frame(daysAgo: 0))
        context.insert(TelemetryLogRecord(sample: TelemetrySample(timestamp: now)))
        context.insert(BatterySnapshot(sample: TelemetrySample(timestamp: now)))
        context.insert(DiagnosticReport(kind: "battery", status: "pass", title: "t", summary: "s", detailsJSON: "{}"))
        context.insert(ChargingSession(startDate: now))
        try context.save()

        try DataRetention.deleteAll(in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RawOBDFrame>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TelemetryLogRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BatterySnapshot>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DiagnosticReport>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChargingSession>()), 0)
    }

    // MARK: Schema

    func testVersionedSchemaListsEveryPersistentModel() {
        XCTAssertEqual(SchemaV1.models.count, 5)
        XCTAssertEqual(SchemaV2.models.count, 6)
        XCTAssertEqual(AppMigrationPlan.schemas.count, 2)
        XCTAssertEqual(AppMigrationPlan.stages.count, 1)
    }

    func testInMemoryContainerRoundTripsAModel() throws {
        let context = makeContext()
        context.insert(TripRecord(startDate: now))
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripRecord>()), 1)
    }
}

import XCTest
import SwiftData
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

/// The demo seeders run on a background context; these tests prove they insert
/// the data the Costs / Trip detail / History screens need for screenshots.
@MainActor
final class DemoDataTests: XCTestCase {

    private func container() throws -> ModelContainer {
        let schema = Schema([
            TripRecord.self,
            RawOBDFrame.self,
            TelemetryLogRecord.self,
            BatterySnapshot.self,
            DiagnosticReport.self,
            ChargingSession.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func waitForCount(_ descriptor: FetchDescriptor<TripRecord>, in container: ModelContainer, expected: Int) async throws {
        for _ in 0..<50 {
            if try container.mainContext.fetchCount(descriptor) >= expected { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func testSeedTripsInsertsFiveTripsWithSummaries() async throws {
        let container = try container()
        DemoData.seedTrips(container: container)
        try await waitForCount(FetchDescriptor<TripRecord>(), in: container, expected: 5)

        let trips = try container.mainContext.fetch(
            FetchDescriptor<TripRecord>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        )
        XCTAssertEqual(trips.count, 5)
        XCTAssertFalse(trips[0].startPlace?.isEmpty ?? true)
        XCTAssertFalse(trips[0].summary?.isEmpty ?? true)
        XCTAssertGreaterThan(trips[0].costEUR ?? 0, 0)
        XCTAssertGreaterThan(trips[0].energyKWh ?? 0, 0)
    }

    func testSeedChargingSessionsInsertsThreeSessions() async throws {
        let container = try container()
        DemoData.seedChargingSessions(container: container)
        for _ in 0..<50 {
            if try container.mainContext.fetchCount(FetchDescriptor<ChargingSession>()) >= 3 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let sessions = try container.mainContext.fetch(
            FetchDescriptor<ChargingSession>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        )
        XCTAssertEqual(sessions.count, 3)
        XCTAssertTrue(sessions.contains { $0.isDC })
        XCTAssertTrue(sessions.allSatisfy { $0.costEUR > 0 && $0.energyKWh > 0 && $0.endDate != nil })
    }

    func testSeedTripsDoesNotDuplicateExistingTrips() async throws {
        let container = try container()
        DemoData.seedTrips(container: container)
        try await waitForCount(FetchDescriptor<TripRecord>(), in: container, expected: 5)

        DemoData.seedTrips(container: container)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TripRecord>()), 5)
    }
}

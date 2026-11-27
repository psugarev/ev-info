import XCTest
import SwiftData
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

@MainActor
final class TripRecorderTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TripRecord.self, RawOBDFrame.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func testEnergyIntegrationUsesFreshTimestamps() throws {
        let container = try makeContainer()
        let recorder = TripRecorder(modelContext: container.mainContext)
        recorder.startTrip()

        let start = Date()
        for index in 0..<10 {
            var sample = TelemetrySample(timestamp: start.addingTimeInterval(Double(index)))
            sample.batteryPowerKW = 10.0  // 10 kW discharge
            recorder.ingestSample(sample)
        }

        // 9 one-second intervals × 10 kW = 90 kW·s = 0.025 kWh
        XCTAssertEqual(recorder.tripEnergyKWh, 0.025, accuracy: 0.001)
        XCTAssertGreaterThan(recorder.tripCostEUR, 0)
        recorder.stopTrip()
    }

    func testRegenReducesNetEnergyWithoutNegativeCost() throws {
        let container = try makeContainer()
        let recorder = TripRecorder(modelContext: container.mainContext)
        recorder.startTrip()

        let start = Date()
        var sample = TelemetrySample(timestamp: start)
        sample.batteryPowerKW = 20.0
        recorder.ingestSample(sample)

        var regen = TelemetrySample(timestamp: start.addingTimeInterval(1))
        regen.batteryPowerKW = -20.0
        recorder.ingestSample(regen)

        // Close the regen interval so its -20 kW is integrated too.
        var idle = TelemetrySample(timestamp: start.addingTimeInterval(2))
        idle.batteryPowerKW = 0.0
        recorder.ingestSample(idle)

        let costAfterRegen = recorder.tripCostEUR
        XCTAssertEqual(recorder.tripEnergyKWh, 0.0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(costAfterRegen, 0)
        recorder.stopTrip()
    }

    func testNoEnergyWithoutPowerSignal() throws {
        let container = try makeContainer()
        let recorder = TripRecorder(modelContext: container.mainContext)
        recorder.startTrip()

        for index in 0..<5 {
            var sample = TelemetrySample(timestamp: Date().addingTimeInterval(Double(index)))
            sample.speedKmh = 50
            recorder.ingestSample(sample)
        }

        XCTAssertEqual(recorder.tripEnergyKWh, 0.0, accuracy: 0.0001)
        recorder.stopTrip()
    }
}

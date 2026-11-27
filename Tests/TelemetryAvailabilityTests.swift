import XCTest
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

// Covers audit B1 / P0 #3: no fake zeros, demo mode isolation, stale badge.

@MainActor
final class TelemetryAvailabilityTests: XCTestCase {

    func testFreshEngineShowsDashesInsteadOfZeros() {
        let engine = TelemetryEngine()

        XCTAssertFalse(engine.hasBMSData)
        XCTAssertEqual(engine.bmsText(engine.batteryVoltageV, "%.0f"), "—")
        XCTAssertEqual(engine.positiveText(engine.auxiliaryVoltageV, "%.1f"), "—")
    }

    func testFreshEngineIsNotFresh() {
        XCTAssertFalse(TelemetryEngine().isFresh())
    }

    func testDemoSamplePopulatesValuesAndIsAlwaysFresh() {
        let engine = TelemetryEngine()

        engine.enableDemo(with: DemoData.liveSample())

        XCTAssertTrue(engine.isDemo)
        XCTAssertTrue(engine.hasBMSData)
        XCTAssertEqual(engine.bmsText(engine.batteryVoltageV, "%.0f"), "708")
        XCTAssertTrue(engine.isFresh(at: Date().addingTimeInterval(3_600)))
    }

    func testDisablingDemoClearsEverythingBackToNoData() {
        let engine = TelemetryEngine()
        engine.enableDemo(with: DemoData.liveSample())

        engine.disableDemo()

        XCTAssertFalse(engine.isDemo)
        XCTAssertFalse(engine.hasBMSData)
        XCTAssertFalse(engine.obdReady)
        XCTAssertEqual(engine.socPercent, 0)
        XCTAssertTrue(engine.cellVoltages.isEmpty)
        XCTAssertEqual(engine.bmsText(engine.batteryVoltageV, "%.0f"), "—")
    }

    func testDemoHistorySamplesStayWithinPhysicalRanges() {
        let sample = DemoData.historySample(at: .now, hours: 3)

        XCTAssertTrue((0...100).contains(sample.socPercent ?? -1))
        XCTAssertTrue((600...800).contains(sample.batteryVoltageV ?? 0))
    }
}

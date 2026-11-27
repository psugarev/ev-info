import XCTest
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

final class DiagnosticsTests: XCTestCase {

    func testBatteryTestPassesWithHealthySample() {
        var sample = TelemetrySample()
        sample.socPercent = 65.5
        sample.batteryVoltageV = 690
        sample.batteryCurrentA = 3.1
        sample.batteryPowerKW = 2.1
        sample.cellVoltageMaxV = 3.84
        sample.cellVoltageMinV = 3.82
        sample.sohPercent = 95.5
        sample.isolationResistanceKOhm = 3000
        sample.auxiliaryVoltageV = 14.3
        sample.batteryTemperatureC = 13

        let outcome = VehicleDiagnostics.battery(sample)
        XCTAssertEqual(outcome.status, .pass)
        XCTAssertTrue(outcome.checks.contains { $0.name == "Cell balance" })
    }

    func testBatteryTestWithoutDataIsUnavailable() {
        XCTAssertEqual(VehicleDiagnostics.battery(nil).status, .unavailable)
    }

    func testChargingTestWarnsWhenNotCharging() {
        var sample = TelemetrySample()
        sample.socPercent = 50
        sample.batteryVoltageV = 690
        sample.isCharging = false
        sample.batteryTemperatureC = 20
        sample.sohPercent = 95
        sample.normalChargeCount = 1
        sample.quickChargeCount = 1

        let outcome = VehicleDiagnostics.charging(sample)
        XCTAssertEqual(outcome.status, .warn)
    }

    func testChargingTestPassesWhileCharging() {
        var sample = TelemetrySample()
        sample.socPercent = 50
        sample.batteryVoltageV = 690
        sample.isCharging = true
        sample.batteryPowerKW = -40
        sample.batteryTemperatureC = 20
        sample.sohPercent = 95
        sample.normalChargeCount = 456
        sample.quickChargeCount = 209

        XCTAssertEqual(VehicleDiagnostics.charging(sample).status, .pass)
    }

    func testTripSummaryContainsKeyFacts() {
        let trip = TripRecord(startDate: Date(timeIntervalSince1970: 1_700_000_000))
        trip.endDate = trip.startDate.addingTimeInterval(600)
        trip.distanceKm = 10
        trip.durationSeconds = 600
        trip.averageSpeedKmh = 60
        trip.maxSpeedKmh = 90
        trip.energyKWh = 2
        trip.consumptionKWhPer100Km = 20
        trip.costEUR = 0.3
        trip.stopCount = 1
        trip.startLatitude = 42.1
        trip.startLongitude = 24.7
        trip.endLatitude = 42.2
        trip.endLongitude = 24.8

        let text = TripSummaryGenerator.summary(for: trip)
        XCTAssertTrue(text.contains("10.0 km"))
        XCTAssertTrue(text.contains("€0.30"))
        XCTAssertTrue(text.contains("1 stop"))
    }

    func testCSVAndJSONExport() throws {
        var sample = TelemetrySample()
        sample.socPercent = 65.5
        sample.batteryVoltageV = 690
        sample.batteryPowerKW = 2.1
        let record = TelemetryLogRecord(sample: sample)

        let csv = ExportService.telemetryCSV([record])
        XCTAssertTrue(csv.hasPrefix("timestamp,speed_kmh,soc_percent"))
        XCTAssertTrue(csv.contains("65.5000"))

        let data = try ExportService.jsonBundle(telemetry: [record], battery: [], diagnostics: [])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["telemetry"])
        XCTAssertEqual((object?["telemetry"] as? [[String: Any]])?.count, 1)
    }
}

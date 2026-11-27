import XCTest
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

final class EnergyCalculatorTests: XCTestCase {

    // MARK: - Existing passing tests

    func testEstimatedEnergy() {
        XCTAssertEqual(
            EnergyCalculator.estimatedEnergyKWh(distanceKm: 145, consumptionKWhPer100Km: 18.7),
            27.115, accuracy: 0.001
        )
    }

    func testCostBasic() {
        XCTAssertEqual(
            EnergyCalculator.costEUR(energyKWh: 27.115, priceEURPerKWh: 0.154584),
            4.190, accuracy: 0.01
        )
    }

    // MARK: - Edge cases

    func testEstimatedEnergyZeroDistance() {
        XCTAssertEqual(EnergyCalculator.estimatedEnergyKWh(distanceKm: 0, consumptionKWhPer100Km: 18), 0)
    }

    func testEstimatedEnergyNegativeInputs() {
        // Rule 4: derived values must not produce nonsense
        XCTAssertEqual(EnergyCalculator.estimatedEnergyKWh(distanceKm: -10, consumptionKWhPer100Km: -5), 0)
    }

    func testConsumptionKWhPer100Km() {
        let c = EnergyCalculator.consumptionKWhPer100Km(energyKWh: 20, distanceKm: 100)
        XCTAssertEqual(c ?? 0, 20.0, accuracy: 0.001)
    }

    func testConsumptionZeroDistance() {
        XCTAssertNil(EnergyCalculator.consumptionKWhPer100Km(energyKWh: 10, distanceKm: 0))
    }

    func testAverageSpeed() {
        // 100 km in 3600 s = 100 km/h
        let spd = EnergyCalculator.averageSpeedKmh(distanceKm: 100, durationSeconds: 3600)
        XCTAssertEqual(spd ?? 0, 100.0, accuracy: 0.001)
    }

    func testAverageSpeedZeroDuration() {
        XCTAssertNil(EnergyCalculator.averageSpeedKmh(distanceKm: 50, durationSeconds: 0))
    }

    // MARK: - Tariff boundary split

    func testTariffNoBoundary() {
        // Trip entirely within day hours: 10:00 → 11:00
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Sofia")!
        let profile = BulgarianTariffProfile()

        let start = dateAt(hour: 10, calendar: cal)
        let end   = dateAt(hour: 11, calendar: cal)

        let cost = BulgarianTariffEngine.costForInterval(energyKWh: 1.0, start: start, end: end, profile: profile, calendar: cal)
        let expected = profile.day.allInEURPerKWh
        XCTAssertEqual(cost, expected, accuracy: 0.0001)
    }

    func testTariffCrossesNightBoundary() {
        // Trip from 21:30 to 22:30 — 30 min day + 30 min night, 1 kWh split evenly
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Sofia")!
        let profile = BulgarianTariffProfile()

        let start = dateAt(hour: 21, minute: 30, calendar: cal)
        let end   = dateAt(hour: 22, minute: 30, calendar: cal)

        let cost = BulgarianTariffEngine.costForInterval(energyKWh: 1.0, start: start, end: end, profile: profile, calendar: cal)
        let expected = 0.5 * profile.day.allInEURPerKWh + 0.5 * profile.night.allInEURPerKWh
        XCTAssertEqual(cost, expected, accuracy: 0.0001, "Cost should split across tariff boundary")
    }

    func testTariffZeroEnergy() {
        let profile = BulgarianTariffProfile()
        let start = Date()
        let end = start.addingTimeInterval(3600)
        XCTAssertEqual(BulgarianTariffEngine.costForInterval(energyKWh: 0, start: start, end: end, profile: profile), 0)
    }

    func testTariffInvalidInterval() {
        let profile = BulgarianTariffProfile()
        let now = Date()
        XCTAssertEqual(BulgarianTariffEngine.costForInterval(energyKWh: 10, start: now, end: now.addingTimeInterval(-10), profile: profile), 0)
    }

    // MARK: - Helpers

    private func dateAt(hour: Int, minute: Int = 0, calendar: Calendar) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        c.minute = minute
        c.second = 0
        return calendar.date(from: c)!
    }
}

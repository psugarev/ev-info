import XCTest
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

final class BulgarianTariffEngineTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Sofia")!
        return c
    }()
    private let profile = BulgarianTariffProfile()

    // MARK: - Single-interval (no boundary)

    func testPureDay() {
        let start = dateAt(hour: 12)
        let end   = start.addingTimeInterval(3600)   // 1 hour
        let cost  = BulgarianTariffEngine.costForInterval(energyKWh: 1.0, start: start, end: end, profile: profile, calendar: cal)
        XCTAssertEqual(cost, profile.day.allInEURPerKWh, accuracy: 0.0001)
    }

    func testPureNight() {
        let start = dateAt(hour: 23)
        let end   = start.addingTimeInterval(3600)
        let cost  = BulgarianTariffEngine.costForInterval(energyKWh: 1.0, start: start, end: end, profile: profile, calendar: cal)
        XCTAssertEqual(cost, profile.night.allInEURPerKWh, accuracy: 0.0001)
    }

    // MARK: - Boundary crossing

    func testNightBoundaryCrossing() {
        // 21:30 → 22:30 — half at day, half at night
        let start = dateAt(hour: 21, minute: 30)
        let end   = dateAt(hour: 22, minute: 30)
        let cost  = BulgarianTariffEngine.costForInterval(energyKWh: 1.0, start: start, end: end, profile: profile, calendar: cal)
        let expected = 0.5 * profile.day.allInEURPerKWh + 0.5 * profile.night.allInEURPerKWh
        XCTAssertEqual(cost, expected, accuracy: 0.0001)
    }

    func testDayBoundaryCrossing() {
        // 05:00 → 07:00 — 1 hour night, 1 hour day
        let start = dateAt(hour: 5)
        let end   = dateAt(hour: 7)
        let cost  = BulgarianTariffEngine.costForInterval(energyKWh: 1.0, start: start, end: end, profile: profile, calendar: cal)
        let expected = 0.5 * profile.night.allInEURPerKWh + 0.5 * profile.day.allInEURPerKWh
        XCTAssertEqual(cost, expected, accuracy: 0.0001)
    }

    // MARK: - Edge cases

    func testZeroEnergy() {
        let start = dateAt(hour: 10)
        let end   = start.addingTimeInterval(3600)
        XCTAssertEqual(
            BulgarianTariffEngine.costForInterval(energyKWh: 0, start: start, end: end, profile: profile, calendar: cal),
            0
        )
    }

    func testEndBeforeStart() {
        let start = dateAt(hour: 10)
        let end   = start.addingTimeInterval(-60)
        XCTAssertEqual(
            BulgarianTariffEngine.costForInterval(energyKWh: 1, start: start, end: end, profile: profile, calendar: cal),
            0
        )
    }

    func testPowerOverload() {
        // powerKW convenience overload
        let start = dateAt(hour: 12)
        let end   = start.addingTimeInterval(3600)   // 1 hour at 10 kW = 10 kWh
        let cost  = BulgarianTariffEngine.costForInterval(powerKW: 10, start: start, end: end, profile: profile, calendar: cal)
        XCTAssertEqual(cost, 10.0 * profile.day.allInEURPerKWh, accuracy: 0.001)
    }

    func testNegativePower() {
        // Regen should not add cost
        let start = dateAt(hour: 12)
        let end   = start.addingTimeInterval(3600)
        let cost  = BulgarianTariffEngine.costForInterval(powerKW: -5, start: start, end: end, profile: profile, calendar: cal)
        XCTAssertEqual(cost, 0)
    }

    // MARK: - Helpers

    private func dateAt(hour: Int, minute: Int = 0) -> Date {
        var c = cal.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        c.minute = minute
        c.second = 0
        return cal.date(from: c)!
    }
}

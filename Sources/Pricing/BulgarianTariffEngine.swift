import Foundation

// MARK: - Tariff Component

struct TariffComponent: Codable {
    var energyEURPerKWh: Double
    var networkEURPerKWh: Double
    var vat: Double

    var allInEURPerKWh: Double {
        (energyEURPerKWh + networkEURPerKWh) * (1 + vat)
    }
}

// MARK: - Bulgarian Tariff Profile
// Editable — Bulgarian electricity prices change (AGENTS.md rule 7).
// Default values from latest invoice.

struct BulgarianTariffProfile: Codable {
    var day   = TariffComponent(energyEURPerKWh: 0.09297, networkEURPerKWh: 0.03585, vat: 0.20)
    var night = TariffComponent(energyEURPerKWh: 0.04103, networkEURPerKWh: 0.03585, vat: 0.20)
    var dayStartHour   = 6   // 06:00 day begins
    var nightStartHour = 22  // 22:00 night begins

    func priceEURPerKWh(at date: Date, calendar: Calendar = .current) -> Double {
        let h = calendar.component(.hour, from: date)
        let isDay = h >= dayStartHour && h < nightStartHour
        return isDay ? day.allInEURPerKWh : night.allInEURPerKWh
    }

    // MARK: - Persistence key
    static let userDefaultsKey = "bulgarianTariffProfile"

    static func load() -> BulgarianTariffProfile {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let profile = try? JSONDecoder().decode(BulgarianTariffProfile.self, from: data) else {
            return BulgarianTariffProfile()
        }
        return profile
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}

// MARK: - Tariff Engine

enum BulgarianTariffEngine {

    /// Cost for a single interval — splits across tariff boundaries.
    /// For example, a trip from 21:50 to 22:10 is priced correctly:
    /// 10 minutes at day rate + 10 minutes at night rate.
    static func costForInterval(
        energyKWh: Double,
        start: Date,
        end: Date,
        profile: BulgarianTariffProfile,
        calendar: Calendar = .current
    ) -> Double {
        guard end > start, energyKWh > 0 else { return 0 }

        let totalSeconds = end.timeIntervalSince(start)
        var cost = 0.0
        var cursor = start

        // Walk through hourly boundaries within the interval
        while cursor < end {
            // Find the next tariff boundary (start of next hour that changes tariff)
            let nextBoundary = nextTariffBoundary(after: cursor, end: end, profile: profile, calendar: calendar)

            let segmentSeconds = nextBoundary.timeIntervalSince(cursor)
            let fraction = segmentSeconds / totalSeconds
            let segmentEnergy = energyKWh * fraction
            let rate = profile.priceEURPerKWh(at: cursor, calendar: calendar)

            cost += segmentEnergy * rate
            cursor = nextBoundary
        }

        return cost
    }

    /// Convenience overload accepting power and duration instead of pre-computed energy.
    static func costForInterval(
        powerKW: Double,
        start: Date,
        end: Date,
        profile: BulgarianTariffProfile,
        calendar: Calendar = .current
    ) -> Double {
        guard end > start else { return 0 }
        let hours = end.timeIntervalSince(start) / 3600
        let energy = max(0, powerKW) * hours
        return costForInterval(energyKWh: energy, start: start, end: end, profile: profile, calendar: calendar)
    }

    // MARK: - Private

    private static func nextTariffBoundary(
        after date: Date,
        end: Date,
        profile: BulgarianTariffProfile,
        calendar: Calendar
    ) -> Date {
        // Boundary hours that change the tariff
        let boundaries = [profile.dayStartHour, profile.nightStartHour]
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let currentHour = components.hour ?? 0

        for boundary in boundaries.sorted() {
            if boundary > currentHour {
                var bc = components
                bc.hour = boundary
                bc.minute = 0
                bc.second = 0
                if let candidate = calendar.date(from: bc), candidate > date {
                    return min(candidate, end)
                }
            }
        }

        // No boundary today — advance to next day's first boundary
        var bc = calendar.dateComponents([.year, .month, .day], from: date)
        bc.day = (bc.day ?? 0) + 1
        bc.hour = boundaries.min() ?? 0
        bc.minute = 0
        bc.second = 0
        if let tomorrow = calendar.date(from: bc), tomorrow > date {
            return min(tomorrow, end)
        }
        return end
    }
}

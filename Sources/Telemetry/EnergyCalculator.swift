import Foundation

// MARK: - Energy Calculator
// Pure stateless math helpers.
// Rule 5: Prefer measured battery power over consumption estimates when a validated signal exists.
// Rule 4: Label derived values explicitly.

enum EnergyCalculator {

    // MARK: - Integration (measured path)

    /// Accumulate net energy from a sequence of samples using power integration.
    /// Signed power is used: positive discharges, negative regen recharges.
    /// Falls back to a timestamp-aware distance estimate when no power exists.
    /// Returns `(kWh, source)` so callers can label derived estimates.
    static func integrateEnergy(samples: [TelemetrySample]) -> (kWh: Double, source: MetricSource) {
        guard samples.count >= 2 else { return (0, .unavailable) }

        var totalKWh = 0.0
        var hasMeasuredPower = false

        for index in 1 ..< samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let deltaTime = current.timestamp.timeIntervalSince(previous.timestamp)
            guard deltaTime > 0 else { continue }

            if let power = previous.batteryPowerKW {
                totalKWh += power * deltaTime / 3_600.0
                hasMeasuredPower = true
            }
        }

        if hasMeasuredPower {
            return (max(0, totalKWh), .derived)
        }

        // Fallback: distance-based estimate using the actual sample timestamps.
        var distanceKm = 0.0
        for index in 1 ..< samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let deltaTime = current.timestamp.timeIntervalSince(previous.timestamp)
            guard deltaTime > 0, let speed = previous.effectiveSpeedKmh else { continue }
            distanceKm += speed * deltaTime / 3_600.0
        }
        let estimated = estimatedEnergyKWh(distanceKm: distanceKm, consumptionKWhPer100Km: 18.0)
        return (estimated, .derived)
    }

    // MARK: - Point-in-time estimates

    /// Estimated energy from distance and average consumption (derived value).
    static func estimatedEnergyKWh(distanceKm: Double, consumptionKWhPer100Km: Double) -> Double {
        max(0, distanceKm) * max(0, consumptionKWhPer100Km) / 100
    }

    /// Consumption in kWh/100 km from trip totals.
    static func consumptionKWhPer100Km(energyKWh: Double, distanceKm: Double) -> Double? {
        guard distanceKm > 0 else { return nil }
        return energyKWh / distanceKm * 100
    }

    /// Average speed from distance and duration.
    static func averageSpeedKmh(distanceKm: Double, durationSeconds: Double) -> Double? {
        guard durationSeconds > 0 else { return nil }
        return distanceKm / (durationSeconds / 3600)
    }

    /// Cost in EUR for given energy and tariff price.
    static func costEUR(energyKWh: Double, priceEURPerKWh: Double) -> Double {
        max(0, energyKWh) * max(0, priceEURPerKWh)
    }
}

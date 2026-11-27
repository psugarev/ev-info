import Foundation
import SwiftData

// MARK: - Demo Data
// A recorded-style sample session so every screen can be explored without an
// OBD2 adapter or a car (App Review, screenshots, first look). Enabled by the
// user in Settings → Demo mode; off by default. Demo values never go through
// the vehicle pipeline: they are shown by TelemetryEngine/BLETransport demo
// state and are clearly labelled "DEMO" in the UI.

enum DemoData {

    /// UserDefaults key recording that this app seeded the history below, so
    /// turning demo mode off removes only data it created.
    static let seededHistoryKey = "demoHistorySeeded"

    // MARK: History

    /// Seeds 24 h of battery snapshots when the store has none.
    /// Runs on a background context so ~1440 inserts do not stall the UI;
    /// `@Query` observes the store and refreshes once it is saved.
    static func seedHistory(container: ModelContainer) {
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let existing = (try? context.fetchCount(FetchDescriptor<BatterySnapshot>())) ?? 0
            guard existing == 0 else { return }

            let now = Date.now
            let minutes = 24 * 60
            for minute in stride(from: minutes, through: 0, by: -1) {
                let date = now.addingTimeInterval(-Double(minute) * 60)
                let hours = Double(minutes - minute) / 60
                context.insert(BatterySnapshot(sample: historySample(at: date, hours: hours)))
            }
            do {
                try context.save()
                UserDefaults.standard.set(true, forKey: seededHistoryKey)
            } catch {
                AppLog.storage.error("Demo history save failed: \(error.localizedDescription)")
            }
        }
    }

    /// Removes the demo history, but only if demo mode created it.
    static func removeSeededHistory(container: ModelContainer) {
        guard UserDefaults.standard.bool(forKey: seededHistoryKey) else { return }
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            do {
                try context.delete(model: BatterySnapshot.self)
                try context.save()
                UserDefaults.standard.set(false, forKey: seededHistoryKey)
            } catch {
                AppLog.storage.error("Demo history removal failed: \(error.localizedDescription)")
            }
        }
    }

    static func historySample(at date: Date, hours: Double) -> TelemetrySample {
        let soc: Double
        let current: Double
        let temperature: Double

        switch hours {
        case ..<6:
            let progress = hours / 6
            soc = 82 - 24 * progress
            current = 48 + 16 * sin(progress * .pi * 2.4)
            temperature = 25 + 6 * progress
        case ..<7:
            soc = 58
            current = 0.3
            temperature = 30
        case ..<9.5:
            let progress = (hours - 7) / 2.5
            soc = 58 + 22 * (1 - pow(1 - progress, 1.6))
            current = -(180 * (1 - 0.78 * progress))
            temperature = 32 + 6 * progress
        default:
            let progress = (hours - 9.5) / 14.5
            soc = 80 - 2 * progress
            current = 0.35
            temperature = 27 - 2 * progress
        }

        var sample = TelemetrySample(timestamp: date)
        let jitter = sin(hours * 9.1) * (hours < 6 ? 3 : 0.05)
        let voltage = 652 + soc * 0.78 + sin(hours * 5.7) * 0.8
        let packCurrent = current + jitter

        sample.socPercent = soc + sin(hours * 3.1) * 0.05
        sample.batteryVoltageV = voltage
        sample.batteryCurrentA = packCurrent
        sample.batteryPowerKW = voltage * packCurrent / 1_000
        sample.batteryTemperatureC = temperature
        sample.batteryMinTemperatureC = temperature - 2
        sample.batteryInletTemperatureC = temperature - 4
        sample.cellVoltageMaxV = 3.55 + soc * 0.0015 + 0.007
        sample.cellVoltageMinV = 3.55 + soc * 0.0015 - 0.005
        sample.sohPercent = 98.6
        sample.remainingEnergyKWh = 74 * soc / 100
        sample.auxiliaryVoltageV = 12.58 + sin(hours * 2.3) * 0.05
        sample.auxiliaryCurrentA = 0.6
        sample.auxiliarySOCPercent = 84
        sample.isCharging = hours >= 7 && hours < 9.5
        sample.normalChargeCount = 148
        sample.quickChargeCount = 67
        sample.normalChargeEnergyKWh = 8_120
        sample.quickChargeEnergyKWh = 4_430
        sample.odometerKm = 34_218 + max(0, 24 * (hours < 9.5 ? 0 : 1))
        sample.tirePressuresBar = [2.41, 2.52, 2.38, 2.48]
        sample.tireTemperaturesC = [23, 26, 22, 24]
        return sample
    }

    // MARK: Live values

    static func liveSample() -> TelemetrySample {
        // No speed: OBD speed is not validated on the car, so demo mode must
        // not present one as if it were (the Drive speed row shows "—").
        var sample = TelemetrySample(timestamp: .now)
        sample.socPercent = 78.4
        sample.batteryVoltageV = 707.5
        sample.batteryCurrentA = -54.2
        sample.batteryPowerKW = 707.5 * -54.2 / 1_000
        sample.batteryTemperatureC = 31
        sample.batteryMinTemperatureC = 29
        sample.batteryInletTemperatureC = 27
        sample.sohPercent = 98.6
        sample.remainingEnergyKWh = 58.0
        sample.auxiliaryVoltageV = 12.62
        sample.auxiliaryCurrentA = 0.8
        sample.auxiliarySOCPercent = 84
        sample.normalChargeCount = 148
        sample.quickChargeCount = 67
        sample.normalChargeEnergyKWh = 8_120
        sample.quickChargeEnergyKWh = 4_430
        sample.isCharging = true
        sample.odometerKm = 34_218
        sample.ambientTemperatureC = 18

        var voltages = [Double?](repeating: nil, count: 192)
        for index in 0..<192 {
            let wave = sin(Double(index) * 0.55) * 0.004 + cos(Double(index) * 0.21) * 0.003
            voltages[index] = 3.664 + wave
        }
        // Three deliberate outliers so the grid and spread chart have a story.
        voltages[41] = 3.628
        voltages[97] = 3.641
        voltages[150] = 3.648
        sample.cellVoltages = voltages
        sample.cellVoltageMaxV = voltages.compactMap { $0 }.max()
        sample.cellVoltageMinV = voltages.compactMap { $0 }.min()

        sample.tirePressuresBar = [2.41, 2.52, 2.38, 2.48]
        sample.tireTemperaturesC = [23, 26, 22, 24]
        return sample
    }
}

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

    /// Same idea for the demo trips used by Costs and Trip detail screenshots.
    static let seededTripsKey = "demoTripsSeeded"

    /// And for the demo charging sessions on the Charging/Costs screens.
    static let seededChargingKey = "demoChargingSessionsSeeded"

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

    // MARK: Trips

    /// Seeds a handful of trips when the store has none, so Costs and Trip
    /// detail are not empty in demo mode (and can be screenshotted).
    static func seedTrips(container: ModelContainer) {
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let existing = (try? context.fetchCount(FetchDescriptor<TripRecord>())) ?? 0
            guard existing == 0 else { return }

            let now = Date.now
            let hour = 3_600.0
            let trips = [
                demoTrip(
                    start: now.addingTimeInterval(-3 * hour),
                    minutes: 32, km: 18.4, average: 34, maximum: 78,
                    energyKWh: 3.10, costEUR: 0.42,
                    from: "Sofia", to: "Vitosha",
                    stops: 2, stopSummary: "10:12, 10:15"
                ),
                demoTrip(
                    start: now.addingTimeInterval(-1 * 24 * hour),
                    minutes: 38, km: 21.7, average: 35, maximum: 71,
                    energyKWh: 3.90, costEUR: 0.53,
                    from: "Vitosha", to: "Sofia",
                    stops: 1, stopSummary: "18:20"
                ),
                demoTrip(
                    start: now.addingTimeInterval(-2 * 24 * hour),
                    minutes: 14, km: 6.2, average: 27, maximum: 52,
                    energyKWh: 1.10, costEUR: 0.15,
                    from: "Sofia", to: "Sofia Airport",
                    stops: 0, stopSummary: nil
                ),
                demoTrip(
                    start: now.addingTimeInterval(-4 * 24 * hour),
                    minutes: 84, km: 118.6, average: 85, maximum: 122,
                    energyKWh: 20.40, costEUR: 2.74,
                    from: "Sofia", to: "Plovdiv",
                    stops: 1, stopSummary: "09:40"
                ),
                demoTrip(
                    start: now.addingTimeInterval(-6 * 24 * hour),
                    minutes: 46, km: 42.3, average: 55, maximum: 96,
                    energyKWh: 7.60, costEUR: 1.02,
                    from: "Plovdiv", to: "Sofia",
                    stops: 1, stopSummary: "17:05"
                )
            ]
            for trip in trips {
                context.insert(trip)
            }
            do {
                try context.save()
                UserDefaults.standard.set(true, forKey: seededTripsKey)
            } catch {
                AppLog.storage.error("Demo trips save failed: \(error.localizedDescription)")
            }
        }
    }

    /// Removes the demo trips, but only if demo mode created them.
    static func removeSeededTrips(container: ModelContainer) {
        guard UserDefaults.standard.bool(forKey: seededTripsKey) else { return }
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            do {
                let frames = try context.fetch(FetchDescriptor<RawOBDFrame>())
                for frame in frames {
                    context.delete(frame)
                }
                try context.delete(model: TripRecord.self)
                try context.save()
                UserDefaults.standard.set(false, forKey: seededTripsKey)
            } catch {
                AppLog.storage.error("Demo trips removal failed: \(error.localizedDescription)")
            }
        }
    }

    private static func demoTrip(
        start: Date,
        minutes: Double,
        km: Double,
        average: Double,
        maximum: Double,
        energyKWh: Double,
        costEUR: Double,
        from: String,
        to: String,
        stops: Int,
        stopSummary: String?
    ) -> TripRecord {
        let trip = TripRecord(startDate: start)
        trip.endDate = start.addingTimeInterval(minutes * 60)
        trip.distanceKm = km
        trip.durationSeconds = minutes * 60
        trip.averageSpeedKmh = average
        trip.maxSpeedKmh = maximum
        trip.energyKWh = energyKWh
        trip.consumptionKWhPer100Km = km > 0 ? energyKWh / km * 100 : nil
        trip.costEUR = costEUR
        trip.stopCount = stops
        trip.stopSummary = stopSummary
        trip.startPlace = from
        trip.endPlace = to
        trip.summary = TripSummaryGenerator.summary(for: trip)
        return trip
    }

    // MARK: Charging sessions

    /// Seeds a few charging sessions so Charging and Costs show real history in
    /// demo mode (and can be screenshotted).
    static func seedChargingSessions(container: ModelContainer) {
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let existing = (try? context.fetchCount(FetchDescriptor<ChargingSession>())) ?? 0
            guard existing == 0 else { return }

            let now = Date.now
            let hour = 3_600.0
            let yesterdayEvening = Calendar.current.date(bySettingHour: 22, minute: 10, second: 0, of: now.addingTimeInterval(-1 * 24 * hour)) ?? now
            let morning = Calendar.current.date(bySettingHour: 6, minute: 40, second: 0, of: now) ?? now

            let sessions = [
                demoSession(
                    start: yesterdayEvening,
                    end: morning,
                    energyKWh: 42.6,
                    peakKW: 7.4,
                    startSOC: 24,
                    endSOC: 80,
                    costEUR: 4.41,
                    isDC: false
                ),
                demoSession(
                    start: now.addingTimeInterval(-3 * 24 * hour),
                    end: now.addingTimeInterval(-3 * 24 * hour + 2_100),
                    energyKWh: 51.2,
                    peakKW: 118,
                    startSOC: 12,
                    endSOC: 80,
                    costEUR: 7.92,
                    isDC: true
                ),
                demoSession(
                    start: now.addingTimeInterval(-5 * 24 * hour),
                    end: now.addingTimeInterval(-5 * 24 * hour + 6_600),
                    energyKWh: 12.4,
                    peakKW: 10.8,
                    startSOC: 62,
                    endSOC: 80,
                    costEUR: 1.92,
                    isDC: false
                )
            ]
            for session in sessions {
                context.insert(session)
            }
            do {
                try context.save()
                UserDefaults.standard.set(true, forKey: seededChargingKey)
            } catch {
                AppLog.storage.error("Demo charging sessions save failed: \(error.localizedDescription)")
            }
        }
    }

    /// Removes the demo charging sessions, but only if demo mode created them.
    static func removeSeededChargingSessions(container: ModelContainer) {
        guard UserDefaults.standard.bool(forKey: seededChargingKey) else { return }
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            do {
                try context.delete(model: ChargingSession.self)
                try context.save()
                UserDefaults.standard.set(false, forKey: seededChargingKey)
            } catch {
                AppLog.storage.error("Demo charging sessions removal failed: \(error.localizedDescription)")
            }
        }
    }

    private static func demoSession(
        start: Date,
        end: Date,
        energyKWh: Double,
        peakKW: Double,
        startSOC: Double,
        endSOC: Double,
        costEUR: Double,
        isDC: Bool
    ) -> ChargingSession {
        let session = ChargingSession(startDate: start, startSOCPercent: startSOC, isDC: isDC)
        session.endDate = end
        session.energyKWh = energyKWh
        session.peakPowerKW = peakKW
        session.endSOCPercent = endSOC
        session.costEUR = costEUR
        session.priceEURPerKWh = energyKWh > 0 ? costEUR / energyKWh : nil
        return session
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

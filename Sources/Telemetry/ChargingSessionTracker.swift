import Foundation

// MARK: - Charging session tracker
// Turns the live BMS stream into charging sessions without a dedicated PID:
// negative pack power + the BMS charging flag start a session, energy is
// integrated from power samples, cost is priced per interval with the same
// tariff engine the trips use, and the session ends after a few idle samples.
//
// Pure value type so the accounting can be unit-tested without SwiftData or BLE.

struct ChargingSessionTracker {

    struct Summary: Equatable {
        let start: Date
        let end: Date
        let energyKWh: Double
        let peakPowerKW: Double
        let startSOCPercent: Double?
        let endSOCPercent: Double?
        let costEUR: Double
        let isDC: Bool
    }

    enum Event: Equatable {
        case started(start: Date, startSOCPercent: Double?)
        case updated(
            start: Date,
            energyKWh: Double,
            peakPowerKW: Double,
            costEUR: Double,
            endSOCPercent: Double?
        )
        case ended(Summary)
    }

    struct Active: Equatable {
        var start: Date
        var lastSampleAt: Date
        var energyKWh: Double
        var peakPowerKW: Double
        var startSOCPercent: Double?
        var endSOCPercent: Double?
        var costEUR: Double
    }

    /// Above this peak the session is treated as a DC fast charge. The Ioniq 5
    /// tops out at 11 kW on AC, so 22 kW leaves room for tariff/decoder noise.
    static let dcThresholdKW = 22.0

    private(set) var active: Active?
    private var idleSamples = 0

    private let tariff: BulgarianTariffProfile
    private let idleSamplesToEnd: Int
    private let maxGapSeconds: TimeInterval

    init(
        tariff: BulgarianTariffProfile,
        idleSamplesToEnd: Int = 3,
        maxGapSeconds: TimeInterval = 600
    ) {
        self.tariff = tariff
        self.idleSamplesToEnd = max(1, idleSamplesToEnd)
        self.maxGapSeconds = maxGapSeconds
    }

    /// Feed one decoded sample. Returns an event when the session state changes
    /// enough for the store to persist something.
    mutating func ingest(_ sample: TelemetrySample) -> Event? {
        guard let charging = sample.isCharging else {
            // Unknown state (BMS has not answered yet) never opens or closes a
            // session — a missing flag must not split a charge in two.
            return nil
        }

        if charging {
            return ingestCharging(sample)
        }

        guard var session = active else { return nil }
        idleSamples += 1
        guard idleSamples >= idleSamplesToEnd else { return nil }
        let summary = finish(&session)
        active = nil
        idleSamples = 0
        return .ended(summary)
    }

    private mutating func ingestCharging(_ sample: TelemetrySample) -> Event? {
        let power = abs(sample.batteryPowerKW ?? 0)

        guard var session = active else {
            active = Active(
                start: sample.timestamp,
                lastSampleAt: sample.timestamp,
                energyKWh: 0,
                peakPowerKW: power,
                startSOCPercent: sample.socPercent,
                endSOCPercent: sample.socPercent,
                costEUR: 0
            )
            idleSamples = 0
            return .started(start: sample.timestamp, startSOCPercent: sample.socPercent)
        }

        let elapsed = sample.timestamp.timeIntervalSince(session.lastSampleAt)
        if elapsed > maxGapSeconds {
            // The app was not running (or the link dropped) for too long to
            // integrate across: close the old session at its last sample and
            // open a new one here. The next charging sample reports the new
            // session through `.updated(start:)`, so no event is lost.
            let summary = finish(&session)
            active = nil
            _ = ingestChargingAfterGap(sample)
            return .ended(summary)
        }

        idleSamples = 0
        if elapsed > 0 {
            let segmentEnergy = power * elapsed / 3_600
            session.energyKWh += segmentEnergy
            session.costEUR += BulgarianTariffEngine.costForInterval(
                energyKWh: segmentEnergy,
                start: session.lastSampleAt,
                end: sample.timestamp,
                profile: tariff
            )
            session.peakPowerKW = max(session.peakPowerKW, power)
            session.lastSampleAt = sample.timestamp
        }
        session.endSOCPercent = sample.socPercent ?? session.endSOCPercent
        active = session

        return .updated(
            start: session.start,
            energyKWh: session.energyKWh,
            peakPowerKW: session.peakPowerKW,
            costEUR: session.costEUR,
            endSOCPercent: session.endSOCPercent
        )
    }

    /// After a long gap the old session is already reported as finished; start
    /// a fresh one at this sample so the remainder still gets logged.
    private mutating func ingestChargingAfterGap(_ sample: TelemetrySample) -> Event? {
        let power = abs(sample.batteryPowerKW ?? 0)
        active = Active(
            start: sample.timestamp,
            lastSampleAt: sample.timestamp,
            energyKWh: 0,
            peakPowerKW: power,
            startSOCPercent: sample.socPercent,
            endSOCPercent: sample.socPercent,
            costEUR: 0
        )
        idleSamples = 0
        return .started(start: sample.timestamp, startSOCPercent: sample.socPercent)
    }

    private func finish(_ session: inout Active) -> Summary {
        Summary(
            start: session.start,
            end: session.lastSampleAt,
            energyKWh: session.energyKWh,
            peakPowerKW: session.peakPowerKW,
            startSOCPercent: session.startSOCPercent,
            endSOCPercent: session.endSOCPercent,
            costEUR: session.costEUR,
            isDC: session.peakPowerKW > Self.dcThresholdKW
        )
    }
}

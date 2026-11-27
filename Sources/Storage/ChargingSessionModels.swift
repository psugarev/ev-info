import Foundation
import SwiftData

// MARK: - Charging session
// One detected charging session: start/end, integrated energy, peak power,
// SOC window and the cost priced with the tariff that was active while the car
// charged. Sessions are derived from live BMS samples (no extra PID), labelled
// as derived data in the UI, and persisted so they survive an app restart.

@Model
final class ChargingSession {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    /// `nil` while the car is still charging; set when the session closes.
    var endDate: Date?
    /// Pack-side energy integrated from the BMS power samples.
    var energyKWh: Double
    var peakPowerKW: Double
    var startSOCPercent: Double?
    var endSOCPercent: Double?
    /// Total cost, priced per interval so a session crossing 22:00 is split.
    var costEUR: Double
    /// Effective price actually used (cost / energy), for display.
    var priceEURPerKWh: Double?
    /// DC fast charge, classified by peak power (> 22 kW).
    var isDC: Bool

    init(
        startDate: Date,
        startSOCPercent: Double? = nil,
        isDC: Bool = false
    ) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = nil
        self.energyKWh = 0
        self.peakPowerKW = 0
        self.startSOCPercent = startSOCPercent
        self.endSOCPercent = nil
        self.costEUR = 0
        self.priceEURPerKWh = nil
        self.isDC = isDC
    }

    var isActive: Bool { endDate == nil }

    var durationSeconds: Double? {
        guard let endDate else { return nil }
        return max(0, endDate.timeIntervalSince(startDate))
    }

    /// True when the session was closed after the power samples stopped for
    /// long enough that the end time is only the last sample, not a clean end.
    var wasInterrupted: Bool {
        guard let endDate else { return false }
        return endDate.timeIntervalSince(startDate) <= 1
    }

    func apply(_ summary: ChargingSessionTracker.Summary) {
        endDate = summary.end
        energyKWh = summary.energyKWh
        peakPowerKW = summary.peakPowerKW
        startSOCPercent = summary.startSOCPercent
        endSOCPercent = summary.endSOCPercent
        costEUR = summary.costEUR
        priceEURPerKWh = summary.energyKWh > 0 ? summary.costEUR / summary.energyKWh : nil
        isDC = summary.isDC
    }
}

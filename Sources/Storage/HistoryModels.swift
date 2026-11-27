import Foundation
import SwiftData

// MARK: - Telemetry log
// Compact, always-on log of decoded samples. Raw frames stay in RawOBDFrame;
// this table is what the JSON/CSV export and charts use.

@Model
final class TelemetryLogRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var speedKmh: Double?
    var socPercent: Double?
    var packVoltageV: Double?
    var packCurrentA: Double?
    var powerKW: Double?
    var maxCellV: Double?
    var minCellV: Double?
    var maxTemperatureC: Double?
    var minTemperatureC: Double?
    var auxiliaryVoltageV: Double?
    var sohPercent: Double?
    var odometerKm: Double?
    var latitude: Double?
    var longitude: Double?

    init(sample: TelemetrySample) {
        self.id = UUID()
        self.timestamp = sample.timestamp
        self.speedKmh = sample.speedKmh
        self.socPercent = sample.socPercent
        self.packVoltageV = sample.batteryVoltageV
        self.packCurrentA = sample.batteryCurrentA
        self.powerKW = sample.batteryPowerKW
        self.maxCellV = sample.cellVoltageMaxV
        self.minCellV = sample.cellVoltageMinV
        self.maxTemperatureC = sample.batteryTemperatureC
        self.minTemperatureC = sample.batteryMinTemperatureC
        self.auxiliaryVoltageV = sample.auxiliaryVoltageV
        self.sohPercent = sample.sohPercent
        self.odometerKm = sample.odometerKm
        self.latitude = sample.latitude
        self.longitude = sample.longitude
    }
}

// MARK: - Battery history
// One row per minute while the BMS is answering. Used for the battery history
// chart and for long-term degradation tracking.

@Model
final class BatterySnapshot {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var socPercent: Double?
    var sohPercent: Double?
    var packVoltageV: Double?
    var packCurrentA: Double?
    var powerKW: Double?
    var maxCellV: Double?
    var minCellV: Double?
    var maxTemperatureC: Double?
    var minTemperatureC: Double?
    var auxiliaryVoltageV: Double?
    var remainingEnergyKWh: Double?
    var normalChargeCount: Int?
    var quickChargeCount: Int?
    var normalChargeEnergyKWh: Double?
    var quickChargeEnergyKWh: Double?

    init(sample: TelemetrySample) {
        self.id = UUID()
        self.timestamp = sample.timestamp
        self.socPercent = sample.socPercent
        self.sohPercent = sample.sohPercent
        self.packVoltageV = sample.batteryVoltageV
        self.packCurrentA = sample.batteryCurrentA
        self.powerKW = sample.batteryPowerKW
        self.maxCellV = sample.cellVoltageMaxV
        self.minCellV = sample.cellVoltageMinV
        self.maxTemperatureC = sample.batteryTemperatureC
        self.minTemperatureC = sample.batteryMinTemperatureC
        self.auxiliaryVoltageV = sample.auxiliaryVoltageV
        self.remainingEnergyKWh = sample.remainingEnergyKWh
        self.normalChargeCount = sample.normalChargeCount
        self.quickChargeCount = sample.quickChargeCount
        self.normalChargeEnergyKWh = sample.normalChargeEnergyKWh
        self.quickChargeEnergyKWh = sample.quickChargeEnergyKWh
    }
}

// MARK: - Diagnostic report
// A saved battery/charging test result with human-readable checks and a JSON
// payload that the export includes.

@Model
final class DiagnosticReport {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kind: String          // "battery" / "charging"
    var status: String        // "pass" / "warn" / "fail"
    var title: String
    var summary: String
    var detailsJSON: String

    init(kind: String, status: String, title: String, summary: String, detailsJSON: String) {
        self.id = UUID()
        self.date = .now
        self.kind = kind
        self.status = status
        self.title = title
        self.summary = summary
        self.detailsJSON = detailsJSON
    }
}

import Foundation
import SwiftData

// MARK: - Export Service
// Builds portable JSON and CSV files for sharing. The JSON bundle contains
// telemetry, battery history and diagnostic reports; CSV exports are flat
// tables for spreadsheets.

enum ExportService {

    // MARK: - Background generation

    /// Telemetry is logged at 1 row/s; cap one export so a long history cannot
    /// exhaust memory or time. The newest rows are kept.
    static let maxTelemetryRows = 100_000

    struct Files {
        let json: URL
        let telemetryCSV: URL
        let batteryCSV: URL
    }

    /// Fetches and writes every export file using its own ModelContext.
    /// Call from a background task — never from the main thread.
    static func makeFiles(container: ModelContainer, since: Date?) throws -> Files {
        let context = ModelContext(container)

        var logDescriptor = FetchDescriptor<TelemetryLogRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        var batteryDescriptor = FetchDescriptor<BatterySnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        var reportDescriptor = FetchDescriptor<DiagnosticReport>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let since {
            logDescriptor.predicate = #Predicate { $0.timestamp >= since }
            batteryDescriptor.predicate = #Predicate { $0.timestamp >= since }
            reportDescriptor.predicate = #Predicate { $0.date >= since }
        }
        logDescriptor.fetchLimit = maxTelemetryRows

        let logs = try context.fetch(logDescriptor)
        let battery = try context.fetch(batteryDescriptor)
        let reports = try context.fetch(reportDescriptor)

        let jsonURL = try write(
            jsonBundle(telemetry: logs, battery: battery, diagnostics: reports),
            filename: timestampedName("ev-info-log", ext: "json")
        )
        let telemetryURL = try write(
            telemetryCSV(logs),
            filename: timestampedName("ev-info-telemetry", ext: "csv")
        )
        let batteryURL = try write(
            batteryCSV(battery),
            filename: timestampedName("ev-info-battery", ext: "csv")
        )
        return Files(json: jsonURL, telemetryCSV: telemetryURL, batteryCSV: batteryURL)
    }

    // MARK: - DTOs

    struct TelemetryDTO: Codable {
        let timestamp: String
        let speedKmh: Double?
        let socPercent: Double?
        let packVoltageV: Double?
        let packCurrentA: Double?
        let powerKW: Double?
        let maxCellV: Double?
        let minCellV: Double?
        let maxTemperatureC: Double?
        let minTemperatureC: Double?
        let auxiliaryVoltageV: Double?
        let sohPercent: Double?
        let odometerKm: Double?
        let latitude: Double?
        let longitude: Double?

        init(_ record: TelemetryLogRecord) {
            timestamp = ExportService.iso(record.timestamp)
            speedKmh = record.speedKmh
            socPercent = record.socPercent
            packVoltageV = record.packVoltageV
            packCurrentA = record.packCurrentA
            powerKW = record.powerKW
            maxCellV = record.maxCellV
            minCellV = record.minCellV
            maxTemperatureC = record.maxTemperatureC
            minTemperatureC = record.minTemperatureC
            auxiliaryVoltageV = record.auxiliaryVoltageV
            sohPercent = record.sohPercent
            odometerKm = record.odometerKm
            latitude = record.latitude
            longitude = record.longitude
        }
    }

    struct BatteryDTO: Codable {
        let timestamp: String
        let socPercent: Double?
        let sohPercent: Double?
        let packVoltageV: Double?
        let packCurrentA: Double?
        let powerKW: Double?
        let maxCellV: Double?
        let minCellV: Double?
        let maxTemperatureC: Double?
        let minTemperatureC: Double?
        let auxiliaryVoltageV: Double?
        let remainingEnergyKWh: Double?

        init(_ snapshot: BatterySnapshot) {
            timestamp = ExportService.iso(snapshot.timestamp)
            socPercent = snapshot.socPercent
            sohPercent = snapshot.sohPercent
            packVoltageV = snapshot.packVoltageV
            packCurrentA = snapshot.packCurrentA
            powerKW = snapshot.powerKW
            maxCellV = snapshot.maxCellV
            minCellV = snapshot.minCellV
            maxTemperatureC = snapshot.maxTemperatureC
            minTemperatureC = snapshot.minTemperatureC
            auxiliaryVoltageV = snapshot.auxiliaryVoltageV
            remainingEnergyKWh = snapshot.remainingEnergyKWh
        }
    }

    struct DiagnosticDTO: Codable {
        let date: String
        let kind: String
        let status: String
        let title: String
        let summary: String
        let detailsJSON: String

        init(_ report: DiagnosticReport) {
            date = ExportService.iso(report.date)
            kind = report.kind
            status = report.status
            title = report.title
            summary = report.summary
            detailsJSON = report.detailsJSON
        }
    }

    struct Bundle: Codable {
        let exportedAt: String
        let app: String
        let telemetry: [TelemetryDTO]
        let batteryHistory: [BatteryDTO]
        let diagnostics: [DiagnosticDTO]
    }

    // MARK: - JSON

    static func jsonBundle(
        telemetry: [TelemetryLogRecord],
        battery: [BatterySnapshot],
        diagnostics: [DiagnosticReport]
    ) throws -> Data {
        let bundle = Bundle(
            exportedAt: iso(.now),
            app: "EV Info",
            telemetry: telemetry.map(TelemetryDTO.init),
            batteryHistory: battery.map(BatteryDTO.init),
            diagnostics: diagnostics.map(DiagnosticDTO.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    // MARK: - CSV

    static func telemetryCSV(_ records: [TelemetryLogRecord]) -> String {
        let header = "timestamp,speed_kmh,soc_percent,pack_voltage_v,pack_current_a,power_kw,max_cell_v,min_cell_v,max_temp_c,min_temp_c,aux_v,soh_percent,odometer_km,latitude,longitude"
        let rows = records.map { record in
            [
                iso(record.timestamp),
                number(record.speedKmh),
                number(record.socPercent),
                number(record.packVoltageV),
                number(record.packCurrentA),
                number(record.powerKW),
                number(record.maxCellV),
                number(record.minCellV),
                number(record.maxTemperatureC),
                number(record.minTemperatureC),
                number(record.auxiliaryVoltageV),
                number(record.sohPercent),
                number(record.odometerKm),
                number(record.latitude),
                number(record.longitude)
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func batteryCSV(_ snapshots: [BatterySnapshot]) -> String {
        let header = "timestamp,soc_percent,soh_percent,pack_voltage_v,pack_current_a,power_kw,max_cell_v,min_cell_v,max_temp_c,min_temp_c,aux_v,remaining_kwh"
        let rows = snapshots.map { snapshot in
            [
                iso(snapshot.timestamp),
                number(snapshot.socPercent),
                number(snapshot.sohPercent),
                number(snapshot.packVoltageV),
                number(snapshot.packCurrentA),
                number(snapshot.powerKW),
                number(snapshot.maxCellV),
                number(snapshot.minCellV),
                number(snapshot.maxTemperatureC),
                number(snapshot.minTemperatureC),
                number(snapshot.auxiliaryVoltageV),
                number(snapshot.remainingEnergyKWh)
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - Files

    static func write(_ data: Data, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func write(_ string: String, filename: String) throws -> URL {
        try write(Data(string.utf8), filename: filename)
    }

    static func timestampedName(_ base: String, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(base)-\(formatter.string(from: .now)).\(ext)"
    }

    /// One shared formatter: allocating an ISO8601DateFormatter per row is slow
    /// for six-figure exports. ISO8601DateFormatter is thread-safe.
    private static let isoFormatter = ISO8601DateFormatter()

    private static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.4f", value)
    }
}

import Foundation

// MARK: - Diagnostic value types

enum CheckStatus: String, Codable {
    case pass
    case warn
    case fail
    case unavailable
}

struct DiagnosticCheck: Codable, Identifiable {
    var id: UUID = UUID()
    let name: String
    let status: CheckStatus
    let detail: String
}

struct DiagnosticOutcome {
    let kind: String
    let status: CheckStatus
    let title: String
    let checks: [DiagnosticCheck]

    var summary: String {
        switch status {
        case .pass: return "All checks passed."
        case .warn: return "Passed with warnings."
        case .fail: return "One or more checks failed."
        case .unavailable: return "Not enough data — connect the adapter."
        }
    }

    var detailsJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(checks),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    static func overall(_ checks: [DiagnosticCheck]) -> CheckStatus {
        if checks.contains(where: { $0.status == .fail }) { return .fail }
        if checks.contains(where: { $0.status == .warn }) { return .warn }
        if checks.contains(where: { $0.status == .pass }) { return .pass }
        return .unavailable
    }
}

// MARK: - Battery / charging tests
// These are read-only checks against the latest decoded BMS sample. They do
// not command the vehicle or force a load; a proper capacity test would need
// a controlled discharge, which this app deliberately does not do.

enum VehicleDiagnostics {

    static func battery(_ sample: TelemetrySample?) -> DiagnosticOutcome {
        guard let sample,
              sample.socPercent != nil,
              sample.batteryVoltageV != nil else {
            return DiagnosticOutcome(
                kind: "battery",
                status: .unavailable,
                title: "Battery test",
                checks: [DiagnosticCheck(name: "BMS data", status: .unavailable, detail: "No BMS response yet")]
            )
        }

        var checks: [DiagnosticCheck] = []

        checks.append(DiagnosticCheck(
            name: "BMS data",
            status: .pass,
            detail: String(format: "SOC %.1f %%, pack %.1f V", sample.socPercent ?? 0, sample.batteryVoltageV ?? 0)
        ))

        if let soh = sample.sohPercent {
            let status: CheckStatus = soh >= 90 ? .pass : (soh >= 80 ? .warn : .fail)
            checks.append(DiagnosticCheck(name: "State of Health", status: status, detail: String(format: "%.1f %%", soh)))
        } else {
            checks.append(DiagnosticCheck(name: "State of Health", status: .warn, detail: "Not read yet"))
        }

        if let maxCell = sample.cellVoltageMaxV, let minCell = sample.cellVoltageMinV {
            let delta = max(0, maxCell - minCell)
            let status: CheckStatus = delta <= 0.03 ? .pass : (delta <= 0.06 ? .warn : .fail)
            checks.append(DiagnosticCheck(
                name: "Cell balance",
                status: status,
                detail: String(format: "%.0f mV (max %.2f V, min %.2f V)", delta * 1_000, maxCell, minCell)
            ))
        } else {
            checks.append(DiagnosticCheck(name: "Cell balance", status: .unavailable, detail: "No cell data"))
        }

        if let isolation = sample.isolationResistanceKOhm {
            let status: CheckStatus = isolation >= 500 ? .pass : (isolation >= 100 ? .warn : .fail)
            checks.append(DiagnosticCheck(name: "Isolation", status: status, detail: String(format: "%.0f kΩ", isolation)))
        }

        if let auxiliary = sample.auxiliaryVoltageV {
            let status: CheckStatus = auxiliary >= 12.2 ? .pass : (auxiliary >= 11.6 ? .warn : .fail)
            checks.append(DiagnosticCheck(name: "12 V battery", status: status, detail: String(format: "%.1f V", auxiliary)))
        }

        if let maxTemperature = sample.batteryTemperatureC {
            let status: CheckStatus = maxTemperature < 40 ? .pass : (maxTemperature < 50 ? .warn : .fail)
            checks.append(DiagnosticCheck(name: "Pack temperature", status: status, detail: String(format: "%.0f °C", maxTemperature)))
        }

        return DiagnosticOutcome(
            kind: "battery",
            status: DiagnosticOutcome.overall(checks),
            title: "Battery test",
            checks: checks
        )
    }

    static func charging(_ sample: TelemetrySample?) -> DiagnosticOutcome {
        guard let sample,
              sample.socPercent != nil,
              sample.batteryVoltageV != nil else {
            return DiagnosticOutcome(
                kind: "charging",
                status: .unavailable,
                title: "Charging test",
                checks: [DiagnosticCheck(name: "BMS data", status: .unavailable, detail: "No BMS response yet")]
            )
        }

        var checks: [DiagnosticCheck] = []

        checks.append(DiagnosticCheck(
            name: "BMS data",
            status: .pass,
            detail: String(format: "SOC %.1f %%, %.1f V", sample.socPercent ?? 0, sample.batteryVoltageV ?? 0)
        ))

        if let charging = sample.isCharging {
            checks.append(DiagnosticCheck(
                name: "Charging state",
                status: charging ? .pass : .warn,
                detail: charging ? "Charging" : "Not charging — plug in and run again"
            ))

            if charging, let power = sample.batteryPowerKW {
                let status: CheckStatus = power < 0 ? .pass : .warn
                checks.append(DiagnosticCheck(
                    name: "Power direction",
                    status: status,
                    detail: String(format: "%.2f kW (negative = charging in this app)", power)
                ))
            }
        } else {
            checks.append(DiagnosticCheck(name: "Charging state", status: .unavailable, detail: "Not reported"))
        }

        if let maxTemperature = sample.batteryTemperatureC {
            let status: CheckStatus = maxTemperature < 40 ? .pass : (maxTemperature < 50 ? .warn : .fail)
            checks.append(DiagnosticCheck(name: "Pack temperature", status: status, detail: String(format: "%.0f °C", maxTemperature)))
        }

        if let soh = sample.sohPercent {
            let status: CheckStatus = soh >= 80 ? .pass : .warn
            checks.append(DiagnosticCheck(name: "State of Health", status: status, detail: String(format: "%.1f %%", soh)))
        }

        if let count = sample.normalChargeCount, let quick = sample.quickChargeCount {
            checks.append(DiagnosticCheck(
                name: "Charging history",
                status: .pass,
                detail: "\(count) AC / \(quick) DC sessions"
            ))
        }

        return DiagnosticOutcome(
            kind: "charging",
            status: DiagnosticOutcome.overall(checks),
            title: "Charging test",
            checks: checks
        )
    }
}

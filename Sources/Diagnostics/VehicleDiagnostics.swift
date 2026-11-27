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

    /// Localised when the report is created, so the stored text matches the
    /// language the user was reading at the time.
    var summary: String {
        switch status {
        case .pass: return AppLocalization.string("All checks passed.")
        case .warn: return AppLocalization.string("Passed with warnings.")
        case .fail: return AppLocalization.string("One or more checks failed.")
        case .unavailable: return AppLocalization.string("Not enough data — connect the adapter.")
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
                title: AppLocalization.string("Battery test"),
                checks: [DiagnosticCheck(
                    name: AppLocalization.string("BMS data"),
                    status: .unavailable,
                    detail: AppLocalization.string("No BMS response yet")
                )]
            )
        }

        var checks: [DiagnosticCheck] = []

        checks.append(DiagnosticCheck(
            name: AppLocalization.string("BMS data"),
            status: .pass,
            detail: String(
                format: AppLocalization.string("SOC %@ %%, pack %@ V"),
                AppLocalization.number(sample.socPercent ?? 0, decimals: 1),
                AppLocalization.number(sample.batteryVoltageV ?? 0, decimals: 1)
            )
        ))

        if let soh = sample.sohPercent {
            let status: CheckStatus = soh >= 90 ? .pass : (soh >= 80 ? .warn : .fail)
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("State of Health"),
                status: status,
                detail: String(format: AppLocalization.string("%@ %%"), AppLocalization.number(soh, decimals: 1))
            ))
        } else {
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("State of Health"),
                status: .warn,
                detail: AppLocalization.string("Not read yet")
            ))
        }

        if let maxCell = sample.cellVoltageMaxV, let minCell = sample.cellVoltageMinV {
            let delta = max(0, maxCell - minCell)
            let status: CheckStatus = delta <= 0.03 ? .pass : (delta <= 0.06 ? .warn : .fail)
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("Cell balance"),
                status: status,
                detail: String(
                    format: AppLocalization.string("%@ mV (max %@ V, min %@ V)"),
                    AppLocalization.number(delta * 1_000, decimals: 0),
                    AppLocalization.number(maxCell, decimals: 2),
                    AppLocalization.number(minCell, decimals: 2)
                )
            ))
        } else {
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("Cell balance"),
                status: .unavailable,
                detail: AppLocalization.string("No cell data")
            ))
        }

        if let isolation = sample.isolationResistanceKOhm {
            let status: CheckStatus = isolation >= 500 ? .pass : (isolation >= 100 ? .warn : .fail)
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("Isolation"),
                status: status,
                detail: String(format: AppLocalization.string("%@ kΩ"), AppLocalization.number(isolation, decimals: 0))
            ))
        }

        if let auxiliary = sample.auxiliaryVoltageV {
            let status: CheckStatus = auxiliary >= 12.2 ? .pass : (auxiliary >= 11.6 ? .warn : .fail)
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("12 V battery"),
                status: status,
                detail: String(format: AppLocalization.string("%@ V"), AppLocalization.number(auxiliary, decimals: 1))
            ))
        }

        if let maxTemperature = sample.batteryTemperatureC {
            let status: CheckStatus = maxTemperature < 40 ? .pass : (maxTemperature < 50 ? .warn : .fail)
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("Pack temperature"),
                status: status,
                detail: String(format: AppLocalization.string("%@ °C"), AppLocalization.number(maxTemperature, decimals: 0))
            ))
        }

        return DiagnosticOutcome(
            kind: "battery",
            status: DiagnosticOutcome.overall(checks),
            title: AppLocalization.string("Battery test"),
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
                title: AppLocalization.string("Charging test"),
                checks: [DiagnosticCheck(
                    name: AppLocalization.string("BMS data"),
                    status: .unavailable,
                    detail: AppLocalization.string("No BMS response yet")
                )]
            )
        }

        var checks: [DiagnosticCheck] = []

        checks.append(DiagnosticCheck(
            name: AppLocalization.string("BMS data"),
            status: .pass,
            detail: String(
                format: AppLocalization.string("SOC %@ %%, %@ V"),
                AppLocalization.number(sample.socPercent ?? 0, decimals: 1),
                AppLocalization.number(sample.batteryVoltageV ?? 0, decimals: 1)
            )
        ))

        if let charging = sample.isCharging {
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("Charging state"),
                status: charging ? .pass : .warn,
                detail: charging
                    ? AppLocalization.string("Charging")
                    : AppLocalization.string("Not charging — plug in and run again")
            ))

            if charging, let power = sample.batteryPowerKW {
                let status: CheckStatus = power < 0 ? .pass : .warn
                checks.append(DiagnosticCheck(
                    name: AppLocalization.string("Power direction"),
                    status: status,
                    detail: String(
                        format: AppLocalization.string("%@ kW (negative = charging in this app)"),
                        AppLocalization.number(power, decimals: 2)
                    )
                ))
            }
        } else {
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("Charging state"),
                status: .unavailable,
                detail: AppLocalization.string("Not reported")
            ))
        }

        if let maxTemperature = sample.batteryTemperatureC {
            let status: CheckStatus = maxTemperature < 40 ? .pass : (maxTemperature < 50 ? .warn : .fail)
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("Pack temperature"),
                status: status,
                detail: String(format: AppLocalization.string("%@ °C"), AppLocalization.number(maxTemperature, decimals: 0))
            ))
        }

        if let soh = sample.sohPercent {
            let status: CheckStatus = soh >= 80 ? .pass : .warn
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("State of Health"),
                status: status,
                detail: String(format: AppLocalization.string("%@ %%"), AppLocalization.number(soh, decimals: 1))
            ))
        }

        if let count = sample.normalChargeCount, let quick = sample.quickChargeCount {
            checks.append(DiagnosticCheck(
                name: AppLocalization.string("Charging history"),
                status: .pass,
                detail: String(
                    format: AppLocalization.string("%@ AC / %@ DC sessions"),
                    "\(count)",
                    "\(quick)"
                )
            ))
        }

        return DiagnosticOutcome(
            kind: "charging",
            status: DiagnosticOutcome.overall(checks),
            title: AppLocalization.string("Charging test"),
            checks: checks
        )
    }
}

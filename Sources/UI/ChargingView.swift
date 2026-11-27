import SwiftUI
import SwiftData

// MARK: - Charging
// Live charging state, lifetime counters and the charging self-test. Kept apart
// from driving and from the tariff/cost screen.

struct ChargingView: View {
    @EnvironmentObject var telemetry: TelemetryEngine
    @EnvironmentObject var store: TelemetryStore

    @Query(sort: \BatterySnapshot.timestamp, order: .reverse)
    private var snapshots: [BatterySnapshot]

    @Query(sort: \ChargingSession.startDate, order: .reverse)
    private var sessions: [ChargingSession]

    private var counterSource: BatterySnapshot? {
        snapshots.first { $0.normalChargeCount != nil || $0.quickChargeCount != nil }
    }

    private var acCount: Int? {
        counterSource?.normalChargeCount ?? (telemetry.normalChargeCount > 0 ? telemetry.normalChargeCount : nil)
    }

    private var dcCount: Int? {
        counterSource?.quickChargeCount ?? (telemetry.quickChargeCount > 0 ? telemetry.quickChargeCount : nil)
    }

    private var acEnergy: Double? {
        counterSource?.normalChargeEnergyKWh ?? (telemetry.normalChargeEnergyKWh > 0 ? telemetry.normalChargeEnergyKWh : nil)
    }

    private var dcEnergy: Double? {
        counterSource?.quickChargeEnergyKWh ?? (telemetry.quickChargeEnergyKWh > 0 ? telemetry.quickChargeEnergyKWh : nil)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                liveCard
                sessionsCard
                countersCard
                diagnosticsCard
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Charging")
        .settingsToolbar()
    }

    private var liveCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel(text: "CHARGING")
                    Spacer()
                    Text(telemetry.isCharging ? "CHARGING" : "NOT CHARGING")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(telemetry.isCharging ? Theme.green : Theme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((telemetry.isCharging ? Theme.green : Theme.textTertiary).opacity(0.12), in: Capsule())
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(telemetry.bmsText(telemetry.batteryPowerKW, "%+.1f"))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(!telemetry.hasBMSData ? Theme.textTertiary : (telemetry.batteryPowerKW < 0 ? Theme.green : Theme.cyan))
                    Text("kW")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(telemetry.hasBMSData ? String(format: "%.0f %%", telemetry.socPercent) : "—")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(telemetry.hasBMSData ? Theme.textPrimary : Theme.textTertiary)
                }

                HStack {
                    Label(telemetry.hasBMSData ? String(format: "%.0f V", telemetry.batteryVoltageV) : "—", systemImage: "bolt.fill")
                    Spacer()
                    Label(telemetry.hasBMSData ? String(format: "%.0f °C", telemetry.batteryTemperatureC) : "—", systemImage: "thermometer.medium")
                    Spacer()
                    Label(telemetry.auxiliaryVoltageV > 0 ? String(format: "%.1f V", telemetry.auxiliaryVoltageV) : "—", systemImage: "car.battery")
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

                if !telemetry.isCharging {
                    Text("Plug in an AC or DC charger and run the charging test to validate the charging path.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    // MARK: - Sessions

    private var sessionsCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardLabel(text: "SESSIONS")
                    Spacer()
                    if !sessions.isEmpty {
                        Text("\(sessions.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                if let active = store.activeChargingSession {
                    sessionRow(active, isActive: true)
                    Divider().overlay(Theme.border)
                }

                let finished = sessions.filter { !$0.isActive }
                if finished.isEmpty && store.activeChargingSession == nil {
                    Text("No charging sessions yet — plug in and the app starts logging automatically.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(Array(finished.prefix(8))) { session in
                        sessionRow(session, isActive: false)
                        if session.id != finished.prefix(8).last?.id {
                            Divider().overlay(Theme.border)
                        }
                    }
                }

                Text("Sessions are detected from the BMS while the app is connected. Energy is integrated from pack power and priced with the tariff in Costs.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func sessionRow(_ session: ChargingSession, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.startDate, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(session.isDC ? "DC" : "AC")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(session.isDC ? Theme.violet : Theme.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((session.isDC ? Theme.violet : Theme.cyan).opacity(0.12), in: Capsule())
                    if isActive {
                        Text("CHARGING NOW")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(Theme.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.green.opacity(0.12), in: Capsule())
                    }
                }
                Text(sessionDetail(session, isActive: isActive))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.1f kWh", session.energyKWh))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text(String(format: "€%.2f", session.costEUR))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.amber)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func sessionDetail(_ session: ChargingSession, isActive: Bool) -> String {
        let peak = AppLocalization.format("Peak %@ kW", AppLocalization.number(session.peakPowerKW, decimals: 1))
        guard !isActive, let duration = session.durationSeconds else {
            return AppLocalization.format("So far · %@", peak)
        }
        let minutes = Int((duration / 60).rounded())
        return AppLocalization.format("%@ · %@ min · %@", peak, "\(minutes)", socText(session))
    }

    private func socText(_ session: ChargingSession) -> String {
        guard let start = session.startSOCPercent, let end = session.endSOCPercent else { return "—" }
        return AppLocalization.format("%@ → %@ %%", AppLocalization.number(start, decimals: 0), AppLocalization.number(end, decimals: 0))
    }

    private var countersCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(text: "LIFETIME")

                HStack(spacing: 0) {
                    stat("AC sessions", acCount.map(String.init) ?? "—")
                    Divider().frame(height: 30).overlay(Theme.border)
                    stat("DC sessions", dcCount.map(String.init) ?? "—")
                    Divider().frame(height: 30).overlay(Theme.border)
                    stat("AC energy", acEnergy.map { String(format: "%.0f kWh", $0) } ?? "—")
                    Divider().frame(height: 30).overlay(Theme.border)
                    stat("DC energy", dcEnergy.map { String(format: "%.0f kWh", $0) } ?? "—")
                }

                if let timestamp = counterSource?.timestamp {
                    Text(lastKnownText(timestamp))
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Text("Counters come from the BMS. If you have connected before, historical values appear here after the first snapshot; otherwise connect and wait for the BMS read.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private var diagnosticsCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(text: "TEST")

                Button {
                    store.runChargingTest()
                } label: {
                    Label("Run charging test", systemImage: "bolt.badge.clock")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyan)

                if let report = store.lastReport, report.kind == "charging" {
                    HStack {
                        Text(report.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(report.status.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(report.status == "pass" ? Theme.green : (report.status == "fail" ? Theme.red : Theme.amber))
                    }
                    Text(report.summary)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                DisclaimerFootnote()
            }
        }
    }

    /// Date is formatted with the app language, not the system locale, because
    /// this string is built outside SwiftUI's environment.
    private func lastKnownText(_ timestamp: Date) -> String {
        let stamp = timestamp.formatted(
            Date.FormatStyle().day().month(.abbreviated).year().hour().minute().locale(AppLocalization.locale)
        )
        return AppLocalization.format(
            "Last known values from %@. These are stored every minute while the BMS is connected.",
            stamp
        )
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 3) {
            CardLabel(text: title)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}

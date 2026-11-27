import SwiftUI

// MARK: - Battery Detail
// Collapsible, card-based battery sections. Values come from manufacturer-
// specific PIDs and stay labelled candidate until cluster-correlated.

struct BatteryDetailView: View {
    @EnvironmentObject var telemetry: TelemetryEngine
    @EnvironmentObject var store: TelemetryStore

    @State private var expanded: Set<String> = ["health"]
    @State private var showInfo = false

    private var cellDelta: Double {
        max(0, telemetry.cellVoltageMaxV - telemetry.cellVoltageMinV)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryCard

                BatteryGroup(
                    title: "Health",
                    icon: "heart.text.square",
                    subtitle: telemetry.sohPercent > 0 ? String(format: "SoH %.1f %%", telemetry.sohPercent) : nil,
                    isExpanded: binding("health")
                ) {
                    Text("SoH is the BMS estimate of remaining capacity compared with a new pack. A small cell-voltage spread is normal; a growing spread can point to a weak cell.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.bottom, 6)

                    infoRow("State of Health", percent(telemetry.sohPercent))
                    infoRow("Remaining energy", kwh(telemetry.remainingEnergyKWh))
                    infoRow("Display SOC", percent(telemetry.socPercent))
                    infoRow("12 V battery charge", telemetry.auxiliarySOCPercent > 0 ? "\(telemetry.auxiliarySOCPercent) %" : "—")
                }

                BatteryGroup(
                    title: "High-voltage battery",
                    icon: "bolt.batteryblock",
                    subtitle: volts(telemetry.batteryVoltageV),
                    isExpanded: binding("pack")
                ) {
                    Text("Live aggregate measurements from the high-voltage traction battery. Individual cell readings are in Cells.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.bottom, 6)

                    infoRow("DC voltage", volts(telemetry.batteryVoltageV))
                    infoRow("Current", amps(telemetry.batteryCurrentA))
                    infoRow("Power", String(format: "%.2f kW", telemetry.batteryPowerKW))
                    infoRow("Max temperature", celsius(telemetry.batteryTemperatureC))
                    infoRow("Min temperature", celsius(telemetry.batteryMinTemperatureC))
                    infoRow("Inlet temperature", celsius(telemetry.batteryInletTemperatureC))
                }

                BatteryGroup(
                    title: "12 V battery & DC-DC",
                    icon: "car.battery",
                    subtitle: volts(telemetry.auxiliaryVoltageV),
                    isExpanded: binding("ldc")
                ) {
                    Text("This is the conventional 12 V auxiliary battery (lead-acid/AGM), not the traction battery. The LDC — low-voltage DC-DC converter — charges it from the high-voltage pack.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.bottom, 6)

                    infoRow("12 V battery voltage", volts(telemetry.auxiliaryVoltageV))
                    infoRow("12 V battery current", amps(telemetry.auxiliaryCurrentA))
                    infoRow("LDC output voltage", volts(telemetry.ldcOutputVoltageV))
                    infoRow("LDC output current", amps(telemetry.ldcOutputCurrentA))
                    infoRow("LDC temperature", celsius(telemetry.ldcTemperatureC))
                }

                BatteryGroup(
                    title: "Diagnostics",
                    icon: "checkmark.shield",
                    subtitle: store.lastReport?.status.uppercased(),
                    isExpanded: binding("diagnostics")
                ) {
                    Button {
                        store.runBatteryTest()
                        expanded.insert("diagnostics")
                    } label: {
                        Label("Run battery test", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        store.runChargingTest()
                        expanded.insert("diagnostics")
                    } label: {
                        Label("Run charging test", systemImage: "bolt.badge.clock")
                    }
                    .buttonStyle(.borderless)

                    if let report = store.lastReport {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(report.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(report.status.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(statusColor(report.status))
                            }
                            Text(report.summary)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 6)
                    }
                }

                BatteryGroup(
                    title: "More",
                    icon: "ellipsis.circle",
                    subtitle: nil,
                    isExpanded: binding("more")
                ) {
                    NavigationLink {
                        BatteryHistoryView()
                    } label: {
                        linkRow("Battery history", icon: "chart.xyaxis.line")
                    }

                    NavigationLink {
                        LogsView()
                    } label: {
                        linkRow("Logs & export", icon: "square.and.arrow.up")
                    }
                }

                DisclaimerFootnote()
                    .padding(.top, 4)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Battery")
        .settingsToolbar()
        .tint(Theme.cyan)
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                BatteryInfoSheet()
            }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel(text: "BATTERY")
                    Spacer()
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.cyan)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Battery information")
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(percent(telemetry.socPercent))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SoH")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Theme.textTertiary)
                        Text(percent(telemetry.sohPercent))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.green)
                    }
                }

                HStack {
                    Label(kwh(telemetry.remainingEnergyKWh), systemImage: "bolt.fill")
                    Spacer()
                    Label(volts(telemetry.batteryVoltageV), systemImage: "waveform.path.ecg")
                    Spacer()
                    Label(celsius(telemetry.batteryTemperatureC), systemImage: "thermometer.medium")
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Group / rows

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(key) },
            set: { value in
                if value { expanded.insert(key) } else { expanded.remove(key) }
            }
        )
    }

    private func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 3)
    }

    private func linkRow(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 3)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pass": return Theme.green
        case "fail": return Theme.red
        default: return Theme.amber
        }
    }

    // MARK: - Formatting

    private func percent(_ value: Double) -> String {
        value > 0 ? String(format: "%.1f %%", value) : "—"
    }

    private func volts(_ value: Double) -> String {
        value > 0 ? String(format: "%.2f V", value) : "—"
    }

    private func amps(_ value: Double) -> String {
        value != 0 ? String(format: "%+.1f A", value) : "—"
    }

    private func celsius(_ value: Double) -> String {
        value != 0 ? String(format: "%.0f °C", value) : "—"
    }

    private func kwh(_ value: Double) -> String {
        value > 0 ? String(format: "%.2f kWh", value) : "—"
    }

    private func cellVolts(_ value: Double) -> String {
        value > 0 ? String(format: "%.2f V", value) : "—"
    }

    private func count(_ value: Int) -> String {
        value > 0 ? "\(value)" : "—"
    }
}

// MARK: - Collapsible card

private struct BatteryGroup<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let subtitle: String?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.cyan)
                        .frame(width: 24)

                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(Theme.border)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 2) {
                    content
                }
                .padding(16)
            }
        }
        .background(Theme.surface, in: Theme.cardShape)
        .overlay(Theme.cardShape.stroke(Theme.border, lineWidth: 1))
    }
}


// MARK: - Battery explained

struct BatteryInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Battery explained")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)

                info("HV pack", "The 800 V traction battery is the whole high-voltage pack. It stores the energy that moves the car.")
                info("Modules", "The pack is divided into modules. Each module contains a group of cells and its own sensing.")
                info("Cells", "Each cell is about 3.7 V nominal. The BMS reports up to 192 cells in six blocks of 32, and balances them so they age evenly.")
                info("12 V battery", "This is a separate lead-acid/AGM auxiliary battery that powers the car's electronics. The LDC (low-voltage DC-DC converter) charges it from the HV pack.")
                info("BMS", "The Battery Management System measures voltage, current and temperature, estimates SoC/SoH, and protects the pack. Everything in this app is read-only.")
                info("Candidate values", "Battery values come from manufacturer-specific data. They have not been compared with the car's dashboard, so treat them as informational estimates.")
            }
            .padding(20)
        }
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func info(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.cyan)
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
    }
}

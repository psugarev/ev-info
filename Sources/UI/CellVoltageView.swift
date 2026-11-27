import SwiftUI
import Charts

// MARK: - Cell Voltages
// 192-cell grid, filled as the six BMS cell DIDs are polled, plus a sorted
// spread chart that makes a single weak cell obvious without counting tiles.

struct CellVoltageView: View {
    @EnvironmentObject var telemetry: TelemetryEngine
    @State private var showInfo = false

    private var cells: [(index: Int, value: Double?)] {
        telemetry.cellVoltages.enumerated().map { (index: $0.offset + 1, value: $0.element) }
    }

    private var readings: [CellReading] {
        cells.compactMap { cell in
            guard let value = cell.value else { return nil }
            return CellReading(index: cell.index, value: value)
        }
    }

    private var sortedReadings: [CellReading] {
        readings
            .sorted { $0.value < $1.value }
            .enumerated()
            .map { rank, reading in
                CellReading(index: reading.index, value: reading.value, rank: rank)
            }
    }

    private var hasData: Bool { !readings.isEmpty }
    private var readCount: Int { readings.count }

    private var maxVoltage: Double? { readings.map(\.value).max() }
    private var minVoltage: Double? { readings.map(\.value).min() }

    private var spread: Double {
        max(0, (maxVoltage ?? 0) - (minVoltage ?? 0))
    }

    var body: some View {
        Group {
            if hasData {
                ScrollView {
                    VStack(spacing: 12) {
                        infoButton
                        InfoCard(
                            icon: "brain.head.profile",
                            title: "About the BMS",
                            text: "Every EV traction battery is a stack of cells. This car's BMS — Battery Management System — exposes up to 192 cells in six blocks of 32. Each cell is about 3.7 V nominal; the BMS measures voltage and temperature, and balances the cells. The app colours each cell by how far it sits below the strongest cell. A 10–30 mV spread is normal; a growing gap can indicate a weak cell."
                        )

                        summary
                        spreadCard

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6),
                            spacing: 4
                        ) {
                            ForEach(cells, id: \.index) { cell in
                                cellTile(cell)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No cell data",
                    systemImage: "battery.0percent",
                    description: Text("Connect to the BMS and wait for the cell-voltage DIDs to be polled.")
                )
            }
        }
        .navigationTitle("Cell Voltages")
        .settingsToolbar()
        .background(Theme.background)
        .tint(Theme.cyan)
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                BatteryInfoSheet()
            }
        }
    }

    private var infoButton: some View {
        Button {
            showInfo = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What am I looking at?")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Pack → modules → cells, and what the BMS measures.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.amber.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summary: some View {
        TelemetryCard {
            HStack(spacing: 0) {
                summaryItem("READ", "\(readCount)", "cells")
                Divider().frame(height: 30).overlay(Theme.border)
                summaryItem("MAX", maxVoltage.map { String(format: "%.2f", $0) } ?? "—", "V")
                Divider().frame(height: 30).overlay(Theme.border)
                summaryItem("MIN", minVoltage.map { String(format: "%.2f", $0) } ?? "—", "V")
                Divider().frame(height: 30).overlay(Theme.border)
                summaryItem(
                    "Δ",
                    String(format: "%.0f", spread * 1_000),
                    "mV",
                    color: spread > 0.030 ? Theme.red : (spread > 0.010 ? Theme.amber : Theme.green)
                )
            }
        }
    }

    private func summaryItem(
        _ title: LocalizedStringKey,
        _ value: String,
        _ unit: String,
        color: Color = Theme.textPrimary
    ) -> some View {
        VStack(spacing: 3) {
            CardLabel(text: title)
            MetricValue(value: value, unit: unit, color: color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Spread chart

    private var spreadCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardLabel(text: "CELL SPREAD")
                    Spacer()
                    Text("SORTED LOW → HIGH")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(Theme.textTertiary)
                }

                Chart(sortedReadings) { reading in
                    BarMark(
                        x: .value("Rank", reading.rank),
                        y: .value("Voltage", reading.value)
                    )
                    .foregroundStyle(color(for: reading.value))
                    .cornerRadius(1)
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: voltageDomain)
                .chartYAxis {
                    AxisMarks(
                        position: .leading,
                        values: [minVoltage, maxVoltage].compactMap { $0 }.sorted()
                    ) { value in
                        AxisGridLine()
                            .foregroundStyle(Theme.border.opacity(0.4))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.2f", number))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                .chartPlotStyle { plot in
                    plot
                        .background(Theme.surfaceElevated.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(height: 104)
                .accessibilityLabel(Text("Cell voltage spread, \(String(format: "%.0f", spread * 1_000)) millivolts"))

                legend
                weakestRow
            }
        }
    }

    private var voltageDomain: ClosedRange<Double> {
        guard let low = minVoltage, let high = maxVoltage else { return 3...4.5 }
        let padding = max(0.006, (high - low) * 0.3)
        return (low - padding)...(high + padding)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(Theme.green, "≤ 10 mV")
            legendItem(Theme.amber, "10–30 mV")
            legendItem(Theme.red, "> 30 mV")
            Spacer()
        }
    }

    private func legendItem(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var weakestRow: some View {
        HStack(spacing: 6) {
            Text("WEAKEST")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)

            ForEach(sortedReadings.prefix(3)) { reading in
                let delta = Int(((maxVoltage ?? reading.value) - reading.value) * 1_000)
                Text("\(reading.index) · −\(delta) mV")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color(for: reading.value))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(color(for: reading.value).opacity(0.1), in: Capsule())
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Cell grid

    private func cellTile(_ cell: (index: Int, value: Double?)) -> some View {
        let tileColor = color(for: cell.value)
        return VStack(spacing: 2) {
            Text("\(cell.index)")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            Text(cell.value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(tileColor.opacity(cell.value == nil ? 0.06 : 0.16), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            cell.value.map { "Cell \(cell.index), \(String(format: "%.2f", $0)) volts" } ?? "Cell \(cell.index), not read"
        )
    }

    private func color(for value: Double?) -> Color {
        guard let value, let maxVoltage else { return Theme.textTertiary }
        let delta = maxVoltage - value
        if delta <= 0.010 { return Theme.green }
        if delta <= 0.030 { return Theme.amber }
        return Theme.red
    }
}

private struct CellReading: Identifiable {
    let index: Int
    let value: Double
    let rank: Int

    var id: Int { index }

    init(index: Int, value: Double, rank: Int = 0) {
        self.index = index
        self.value = value
        self.rank = rank
    }
}

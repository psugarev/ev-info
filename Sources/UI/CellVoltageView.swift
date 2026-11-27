import SwiftUI
import Charts

// MARK: - Cell Voltages
// Six labelled BMS blocks (32 cells each) instead of one flat 192-tile wall.
// Each block shows its own read count, min/max, spread and a balance chip; the
// strongest and weakest cell in a block are ringed, and tapping any cell opens
// a detail sheet. The sorted spread chart stays as the quick "is one cell
// drifting?" view. Grouping and thresholds live in `CellAnalysis` (testable).

struct CellVoltageView: View {
    @EnvironmentObject var telemetry: TelemetryEngine

    @State private var showInfo = false
    @State private var selectedCell: CellReading?

    private var analysis: CellAnalysis {
        CellAnalysis(voltages: telemetry.cellVoltages)
    }

    private var hasData: Bool { !analysis.readings.isEmpty }

    var body: some View {
        Group {
            if hasData {
                ScrollViewReader { proxy in
                    ScrollView {
                        content
                    }
                    .onAppear { scrollForDebugScreenshot(proxy) }
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
        .sheet(item: $selectedCell) { cell in
            CellDetailSheet(cell: cell, analysis: analysis)
        }
        .onAppear { presentDetailForDebugScreenshot() }
    }

    private var content: some View {
        VStack(spacing: 12) {
            infoButton
            summary
            weakestCellsCard

            ForEach(analysis.modules) { module in
                moduleCard(module)
            }

            spreadCard
            footnotes
        }
        .padding()
        .padding(.bottom, 12)
    }

    // MARK: - Explainer

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
                readSummaryItem
                Divider().frame(height: 30).overlay(Theme.border)
                summaryItem("MAX", analysis.maxVoltage.map { String(format: "%.3f", $0) } ?? "—", "V")
                Divider().frame(height: 30).overlay(Theme.border)
                summaryItem("MIN", analysis.minVoltage.map { String(format: "%.3f", $0) } ?? "—", "V")
                Divider().frame(height: 30).overlay(Theme.border)
                summaryItem(
                    "Δ",
                    String(format: "%.0f", analysis.spread * 1_000),
                    "mV",
                    color: color(for: CellBalance(deltaToMax: analysis.spread))
                )
            }
        }
    }

    /// The READ tile needs a localized unit ("cells" / "клетки"); MetricValue
    /// takes a plain String, so this one tile is drawn inline.
    private var readSummaryItem: some View {
        VStack(spacing: 3) {
            CardLabel(text: "READ")
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(analysis.readCount)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("cells")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
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

    // MARK: - Weakest cells

    private var weakestCellsCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardLabel(text: "WEAKEST CELLS")
                    Spacer()
                    Text("TAP FOR DETAILS")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(Theme.textTertiary)
                }

                ForEach(Array(analysis.weakestRanking.prefix(3))) { cell in
                    Button {
                        selectedCell = cell
                    } label: {
                        weakestRow(cell)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }

                if let strongest = analysis.strongest {
                    Text("Δ is measured from the strongest cell (\(strongest.index) · \(String(format: "%.2f", strongest.value)) V).")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func weakestRow(_ cell: CellReading) -> some View {
        let delta = Int((analysis.deltaToMax(cell) * 1_000).rounded())
        let balance = analysis.balance(for: cell)
        return HStack(spacing: 10) {
            Text("\(cell.index)")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 34, alignment: .leading)

            Text("Module \(analysis.moduleNumber(forCell: cell.index))")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 8)

            Text(String(format: "%.3f V", cell.value))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)

            Text(delta == 0 ? "MAX" : "−\(delta) mV")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color(for: balance))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color(for: balance).opacity(0.12), in: Capsule())

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Module block

    private func moduleCard(_ module: CellModule) -> some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Module \(module.index)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)

                    Text("\(module.readCount)/\(module.expectedCells)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)

                    Spacer()

                    if let balance = module.balance {
                        balanceChip(balance)
                    }
                }

                HStack(spacing: 0) {
                    moduleStat("MIN", module.minVoltage.map { String(format: "%.3f", $0) } ?? "—", "V")
                    Divider().frame(height: 22).overlay(Theme.border)
                    moduleStat("MAX", module.maxVoltage.map { String(format: "%.3f", $0) } ?? "—", "V")
                    Divider().frame(height: 22).overlay(Theme.border)
                    moduleStat(
                        "Δ",
                        module.spread.map { String(format: "%.0f", $0 * 1_000) } ?? "—",
                        "mV",
                        color: module.balance.map(color(for:)) ?? Theme.textPrimary
                    )
                }

                if module.readCount == 0 {
                    Text("Not read yet")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8),
                        spacing: 4
                    ) {
                        ForEach(module.firstCellIndex...module.lastCellIndex, id: \.self) { index in
                            cellTile(
                                index: index,
                                reading: module.reading(at: index),
                                module: module
                            )
                        }
                    }
                }
            }
        }
        .id("module-\(module.index)")
    }

    private func balanceChip(_ balance: CellBalance) -> some View {
        Text(balance.label)
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(color(for: balance))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color(for: balance).opacity(0.12), in: Capsule())
    }

    private func moduleStat(
        _ title: LocalizedStringKey,
        _ value: String,
        _ unit: String,
        color: Color = Theme.textPrimary
    ) -> some View {
        VStack(spacing: 1) {
            CardLabel(text: title)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(unit)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cell tile

    private func cellTile(index: Int, reading: CellReading?, module: CellModule) -> some View {
        let balance = reading.map(analysis.balance(for:))
        let tileColor = balance.map(color(for:)) ?? Theme.textTertiary
        let isStrongest = module.strongest?.index == index
        let isWeakest = module.weakest?.index == index
        let ring: Color? = isWeakest ? Theme.red : (isStrongest ? Theme.cyan : nil)

        return Button {
            guard let reading else { return }
            selectedCell = reading
        } label: {
            VStack(spacing: 1) {
                Text("\(index)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Text(reading.map { String(format: "%.3f", $0.value) } ?? "—")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(reading == nil ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                tileColor.opacity(reading == nil ? 0.05 : tintOpacity(for: balance)),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(ring ?? Theme.border, lineWidth: ring == nil ? 0.5 : 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(reading == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            reading.map {
                "Cell \($0.index), \(String(format: "%.2f", $0.value)) volts, module \(module.index)"
            } ?? "Cell \(index), not read"
        )
        .accessibilityHint(Text("Shows cell detail"))
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

                Chart(chartPoints) { point in
                    BarMark(
                        x: .value("Rank", point.rank),
                        y: .value("Voltage", point.reading.value),
                        width: .fixed(1.2)
                    )
                    .foregroundStyle(color(for: analysis.balance(for: point.reading)))
                    .cornerRadius(0.5)
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: voltageDomain)
                .chartYAxis {
                    AxisMarks(
                        position: .leading,
                        values: [analysis.minVoltage, analysis.maxVoltage].compactMap { $0 }.sorted()
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
                .accessibilityLabel(Text("Cell voltage spread, \(String(format: "%.0f", analysis.spread * 1_000)) millivolts"))

                legend
            }
        }
    }

    /// Cells ordered weakest-first with a 1-based rank, so the chart's left
    /// edge is the lowest cell in the pack.
    private var chartPoints: [CellChartPoint] {
        analysis.weakestRanking.enumerated().map { offset, reading in
            CellChartPoint(rank: offset + 1, reading: reading)
        }
    }

    private var voltageDomain: ClosedRange<Double> {
        guard let low = analysis.minVoltage, let high = analysis.maxVoltage else { return 3...4.5 }
        let padding = max(0.006, (high - low) * 0.3)
        return (low - padding)...(high + padding)
    }

    private var legend: some View {
        let buckets = analysis.bucketCounts
        return HStack(spacing: 12) {
            legendItem(Theme.green, "≤ 10 mV", count: buckets.good)
            legendItem(Theme.amber, "10–30 mV", count: buckets.watch)
            legendItem(Theme.red, "> 30 mV", count: buckets.poor)
            Spacer()
        }
    }

    private func legendItem(_ color: Color, _ label: LocalizedStringKey, count: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Footnotes

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ring marks the strongest and weakest cell in the module.")
            Text("Module grouping follows the six BMS cell blocks; each block holds up to 32 cells.")
        }
        .font(.caption2)
        .foregroundStyle(Theme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    // MARK: - Debug screenshot harness

    /// `-demoScrollModule 2` scrolls to that block; `-demoCell 42` opens the
    /// detail sheet. Debug builds only, used to capture App Store screenshots.
    private func scrollForDebugScreenshot(_ proxy: ScrollViewProxy) {
#if DEBUG
        guard let target = DebugScreenshotArgument.int(for: "-demoScrollModule") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo("module-\(target)", anchor: .top)
            }
        }
#endif
    }

    private func presentDetailForDebugScreenshot() {
#if DEBUG
        guard let index = DebugScreenshotArgument.int(for: "-demoCell"),
              let reading = analysis.readings.first(where: { $0.index == index }) else { return }
        selectedCell = reading
#endif
    }

    // MARK: - Colour

    private func tintOpacity(for balance: CellBalance?) -> Double {
        switch balance {
        case .good: 0.14
        case .watch: 0.18
        case .poor: 0.24
        case nil: 0.05
        }
    }

    private func color(for balance: CellBalance) -> Color {
        switch balance {
        case .good: Theme.green
        case .watch: Theme.amber
        case .poor: Theme.red
        }
    }
}

#if DEBUG
/// Reads `-flag <int>` launch arguments; design harness only.
private enum DebugScreenshotArgument {
    static func int(for flag: String) -> Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return Int(arguments[index + 1])
    }
}
#endif

// MARK: - Chart point

private struct CellChartPoint: Identifiable {
    let rank: Int
    let reading: CellReading

    var id: Int { rank }
}

// MARK: - Balance labels

private extension CellBalance {
    var label: LocalizedStringKey {
        switch self {
        case .good: "GOOD"
        case .watch: "WATCH"
        case .poor: "DRIFT"
        }
    }
}

// MARK: - Cell detail

/// `navigationBarTitleDisplayMode` is iOS-only; the core package also builds on macOS.
private struct InlineTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.navigationBarTitleDisplayMode(.inline)
#else
        content
#endif
    }
}

struct CellDetailSheet: View {
    let cell: CellReading
    let analysis: CellAnalysis

    @Environment(\.dismiss) private var dismiss

    private var module: CellModule? { analysis.module(forCell: cell.index) }
    private var delta: Int { Int((analysis.deltaToMax(cell) * 1_000).rounded()) }
    private var balance: CellBalance { analysis.balance(for: cell) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    detailCard
                    thresholdCard
                    Text("Informational only — values stay candidate until compared with the car's dashboard.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(Text("Cell \(cell.index)"))
            .modifier(InlineTitleModifier())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Module \(analysis.moduleNumber(forCell: cell.index))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
                Text(balance.label)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(color(for: balance))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(color(for: balance).opacity(0.12), in: Capsule())
            }

            Text(String(format: "%.3f V", cell.value))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

            Text(delta == 0 ? "This is the strongest cell in the pack." : "Below strongest by \(delta) mV")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var detailCard: some View {
        TelemetryCard {
            VStack(spacing: 10) {
                row("Cells read", "\(module?.readCount ?? 0)/\(module?.expectedCells ?? 0)")
                Divider().overlay(Theme.border)
                row("Module min", module?.minVoltage.map { String(format: "%.2f V", $0) } ?? "—")
                Divider().overlay(Theme.border)
                row("Module max", module?.maxVoltage.map { String(format: "%.2f V", $0) } ?? "—")
                Divider().overlay(Theme.border)
                row("Module spread", module?.spread.map { String(format: "%.0f mV", $0 * 1_000) } ?? "—")
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var thresholdCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "CELL SPREAD")
            thresholdRow(Theme.green, "≤ 10 mV")
            thresholdRow(Theme.amber, "10–30 mV")
            thresholdRow(Theme.red, "> 30 mV")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
    }

    private func thresholdRow(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func tintOpacity(for balance: CellBalance?) -> Double {
        switch balance {
        case .good: 0.14
        case .watch: 0.18
        case .poor: 0.24
        case nil: 0.05
        }
    }

    private func color(for balance: CellBalance) -> Color {
        switch balance {
        case .good: Theme.green
        case .watch: Theme.amber
        case .poor: Theme.red
        }
    }
}

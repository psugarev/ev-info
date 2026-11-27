import SwiftUI
import SwiftData
import Charts

// MARK: - Battery History
// Snapshot every minute while the BMS is answering. The chart offers four
// metrics over five time ranges; drag (or tap) the plot to inspect a point.
// The snapshot list below is the accessible, textual fallback for the chart.

struct BatteryHistoryView: View {
    @Query(sort: \BatterySnapshot.timestamp, order: .reverse)
    private var snapshots: [BatterySnapshot]

    @State private var metric: BatteryMetric = .soc
    @State private var range: HistoryRange = .day
    @State private var selectedDate: Date?
    @State private var showAllSnapshots = false

    private var latest: BatterySnapshot? { snapshots.first }
    private var referenceDate: Date { snapshots.first?.timestamp ?? .now }

    /// Ascending, newest-last. Cap the query so a very old store cannot stall
    /// the chart; 20k one-minute rows is roughly two weeks of driving.
    private var chronological: [BatterySnapshot] {
        Array(snapshots.prefix(20_000).reversed())
    }

    var body: some View {
        Group {
            if snapshots.count < 2 {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Battery History")
        .background(Theme.background)
        .tint(Theme.cyan)
    }

    // MARK: - Layout

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    rangeChips
                    chartCard
                    latestCard
                    snapshotsCard
                        .id(snapshotAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
#if DEBUG
            .onAppear {
#if DEBUG
                guard ProcessInfo.processInfo.arguments.contains("-demoScrollBottom") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.6)) {
                        proxy.scrollTo(snapshotAnchor, anchor: .bottom)
                    }
                }
#endif
            }
#endif
        }
    }

    private let snapshotAnchor = "snapshots"

    private var emptyState: some View {
        ContentUnavailableView(
            "Not enough history",
            systemImage: "chart.xyaxis.line",
            description: Text("A snapshot is stored every minute while the BMS is connected.")
        )
    }

    // MARK: - Range

    private var rangeChips: some View {
        HStack(spacing: 6) {
            ForEach(HistoryRange.allCases) { item in
                let selected = item == range
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        range = item
                        selectedDate = nil
                    }
                } label: {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.6)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundStyle(selected ? Theme.cyan : Theme.textSecondary)
                        .background(selected ? Theme.cyan.opacity(0.12) : Theme.surface, in: Capsule())
                        .overlay(
                            Capsule().stroke(
                                selected ? Theme.cyan.opacity(0.45) : Theme.border,
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.accessibilityTitle)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 12) {
                chartHeader

                Picker("Metric", selection: $metric) {
                    ForEach(BatteryMetric.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: metric) { _, _ in selectedDate = nil }

                chart
                chartFooter
            }
        }
    }

    private var chartHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                CardLabel(text: LocalizedStringKey(metric.title))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayValueText)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text(metric.unit)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }

                Text(chartSubtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                if let delta = pointDelta {
                    HStack(spacing: 3) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(metric.signedText(delta))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Theme.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.cyan.opacity(0.1), in: Capsule())
                }

                if selectedPoint == nil {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            if metric.showsZeroLine {
                RuleMark(y: .value("Zero", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Theme.border)
            }

            ForEach(displayPoints) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value(metric.title, point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(areaGradient)

                LineMark(
                    x: .value("Time", point.date),
                    y: .value(metric.title, point.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(metric.color)
            }

            if let average {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Theme.textTertiary.opacity(0.55))
            }

            if let point = selectedPoint {
                RuleMark(x: .value("Selected", point.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))

                PointMark(
                    x: .value("Time", point.date),
                    y: .value(metric.title, point.value)
                )
                .symbolSize(64)
                .foregroundStyle(metric.color)
                .annotation(position: .top, spacing: 6) {
                    Text("\(metric.valueText(point.value)) \(metric.unit)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.textPrimary, in: Capsule())
                }
            } else if let last = displayPoints.last {
                PointMark(
                    x: .value("Time", last.date),
                    y: .value(metric.title, last.value)
                )
                .symbolSize(46)
                .foregroundStyle(metric.color)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.border.opacity(0.45))
                AxisValueLabel(format: axisDateFormat)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.border.opacity(0.45))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(metric.axisText(number))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(Theme.surfaceElevated.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(height: 224)
        .accessibilityLabel(Text("\(metric.title) history, \(range.accessibilityTitle)"))
    }

    private var chartFooter: some View {
        HStack(spacing: 0) {
            footerStat("MIN", minimum.map(metric.valueText) ?? "—")
            footerDivider
            footerStat("AVG", average.map(metric.valueText) ?? "—")
            footerDivider
            footerStat("MAX", maximum.map(metric.valueText) ?? "—")
        }
    }

    private func footerStat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 2) {
            CardLabel(text: title)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var footerDivider: some View {
        Divider()
            .frame(height: 24)
            .overlay(Theme.border)
    }

    // MARK: - Latest

    private var latestCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardLabel(text: "LATEST")
                    Spacer()
                    if let timestamp = latest?.timestamp {
                        Text(timestamp, format: .dateTime.hour().minute())
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    stat("SOC", value: latest?.socPercent, unit: "%", digits: 1)
                    stat("SoH", value: latest?.sohPercent, unit: "%", digits: 1)
                    stat("PACK", value: latest?.packVoltageV, unit: "V", digits: 1)
                    stat("CURRENT", value: latest?.packCurrentA, unit: "A", digits: 1, signed: true)
                }
            }
        }
    }

    private func stat(
        _ title: LocalizedStringKey,
        value: Double?,
        unit: String,
        digits: Int,
        signed: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(text: title)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { String(format: signed ? "%+.\(digits)f" : "%.\(digits)f", $0) } ?? "—")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Snapshots

    private var visibleSnapshots: [BatterySnapshot] {
        showAllSnapshots ? Array(snapshots) : Array(snapshots.prefix(30))
    }

    private var snapshotsCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CardLabel(text: "SNAPSHOTS")
                    Spacer()
                    Text("\(snapshots.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.bottom, 8)

                ForEach(Array(visibleSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                    snapshotRow(snapshot)
                    if index < visibleSnapshots.count - 1 {
                        Divider()
                            .overlay(Theme.border.opacity(0.55))
                    }
                }

                if snapshots.count > 30 {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showAllSnapshots.toggle()
                        }
                    } label: {
                        HStack {
                            Text(showAllSnapshots ? "Show fewer" : "Show all")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Spacer()
                            Image(systemName: showAllSnapshots ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Theme.cyan)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func snapshotRow(_ snapshot: BatterySnapshot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.timestamp, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    if let voltage = snapshot.packVoltageV {
                        Text(String(format: "%.1f V", voltage))
                    }
                    if let current = snapshot.packCurrentA {
                        Text(String(format: "%+.0f A", current))
                    }
                    if let soh = snapshot.sohPercent {
                        Text(String(format: "SoH %.1f%%", soh))
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            if let soc = snapshot.socPercent {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", soc))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
                .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.vertical, 9)
    }

    // MARK: - Derived chart data

    private var displayPoints: [HistoryPoint] {
        let cutoff = range.cutoff(from: referenceDate)
        let filtered = cutoff.map { boundary in
            chronological.filter { $0.timestamp >= boundary }
        } ?? chronological

        let raw = filtered.compactMap { snapshot -> HistoryPoint? in
            guard let value = metric.value(from: snapshot) else { return nil }
            return HistoryPoint(date: snapshot.timestamp, value: value)
        }

        guard raw.count > 320 else { return raw }

        // Stride-sample to at most ~320 points, always keeping the newest one.
        let step = max(1, raw.count / 320)
        var sampled = raw.enumerated()
            .filter { $0.offset % step == 0 }
            .map(\.element)
        if let last = raw.last, sampled.last?.date != last.date {
            sampled.append(last)
        }
        return sampled
    }

    private var selectedPoint: HistoryPoint? {
        guard let selectedDate else { return nil }
        return displayPoints.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var minimum: Double? { displayPoints.map(\.value).min() }
    private var maximum: Double? { displayPoints.map(\.value).max() }

    private var average: Double? {
        let values = displayPoints.map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var pointDelta: Double? {
        guard let first = displayPoints.first?.value, let last = displayPoints.last?.value else {
            return nil
        }
        return last - first
    }

    private var displayValueText: String {
        if let point = selectedPoint {
            return metric.valueText(point.value)
        }
        return displayPoints.last.map { metric.valueText($0.value) } ?? "—"
    }

    private var chartSubtitle: String {
        if let point = selectedPoint {
            return point.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        }
        return "Updated \(referenceDate.formatted(.dateTime.day().month(.abbreviated).hour().minute()))"
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [metric.color.opacity(0.28), metric.color.opacity(0.015)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var axisDateFormat: Date.FormatStyle {
        switch range {
        case .hour, .sixHours:
            return .dateTime.hour().minute()
        case .day:
            return .dateTime.hour().minute()
        case .week:
            return .dateTime.weekday(.abbreviated).hour()
        case .all:
            return .dateTime.day().month(.abbreviated)
        }
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = displayPoints.first?.date, let last = displayPoints.last?.date else {
            return referenceDate.addingTimeInterval(-3_600)...referenceDate
        }
        if last.timeIntervalSince(first) < 60 {
            return first.addingTimeInterval(-1_800)...last.addingTimeInterval(1_800)
        }
        let span = last.timeIntervalSince(first)
        let padding = max(span * 0.04, 120)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }

    private var yDomain: ClosedRange<Double> {
        let values = displayPoints.map(\.value)
        guard let lower = values.min(), let upper = values.max() else { return 0...1 }

        var low = lower
        var high = upper
        if metric.showsZeroLine {
            low = min(low, 0)
            high = max(high, 0)
        }

        let span = max(high - low, metric.minimumSpan)
        let padding = span * 0.12
        low -= padding
        high += padding

        if metric == .soc {
            low = max(0, low)
            high = min(100, high)
        }
        if high - low < 0.001 {
            high = low + 1
        }
        return low...high
    }
}

// MARK: - Supporting types

private struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

private enum HistoryRange: String, CaseIterable, Identifiable {
    case hour
    case sixHours
    case day
    case week
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: return "1H"
        case .sixHours: return "6H"
        case .day: return "24H"
        case .week: return "7D"
        case .all: return "ALL"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .hour: return "Last hour"
        case .sixHours: return "Last 6 hours"
        case .day: return "Last 24 hours"
        case .week: return "Last 7 days"
        case .all: return "All history"
        }
    }

    func cutoff(from reference: Date) -> Date? {
        switch self {
        case .hour: return reference.addingTimeInterval(-3_600)
        case .sixHours: return reference.addingTimeInterval(-6 * 3_600)
        case .day: return reference.addingTimeInterval(-24 * 3_600)
        case .week: return reference.addingTimeInterval(-7 * 24 * 3_600)
        case .all: return nil
        }
    }
}

private enum BatteryMetric: String, CaseIterable, Identifiable {
    case soc
    case voltage
    case current
    case power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soc: return "SOC"
        case .voltage: return "Voltage"
        case .current: return "Current"
        case .power: return "Power"
        }
    }

    var unit: String {
        switch self {
        case .soc: return "%"
        case .voltage: return "V"
        case .current: return "A"
        case .power: return "kW"
        }
    }

    var color: Color {
        switch self {
        case .soc: return Theme.green
        case .voltage: return Theme.cyan
        case .current: return Theme.amber
        case .power: return Theme.violet
        }
    }

    var showsZeroLine: Bool {
        switch self {
        case .soc, .voltage: return false
        case .current, .power: return true
        }
    }

    /// Keeps a nearly flat series from being magnified into fake noise.
    var minimumSpan: Double {
        switch self {
        case .soc: return 6
        case .voltage: return 4
        case .current: return 10
        case .power: return 10
        }
    }

    var digits: Int { 1 }

    func value(from snapshot: BatterySnapshot) -> Double? {
        switch self {
        case .soc: return snapshot.socPercent
        case .voltage: return snapshot.packVoltageV
        case .current: return snapshot.packCurrentA
        case .power: return snapshot.powerKW
        }
    }

    func valueText(_ value: Double) -> String {
        switch self {
        case .current, .power:
            return String(format: "%+.1f", value)
        default:
            return String(format: "%.1f", value)
        }
    }

    func signedText(_ value: Double) -> String {
        String(format: "%+.1f %@", value, unit)
    }

    func axisText(_ value: Double) -> String {
        switch self {
        case .current, .power:
            return String(format: "%+.0f", value)
        default:
            return String(format: "%.0f", value)
        }
    }
}

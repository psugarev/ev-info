import SwiftUI
import SwiftData

// MARK: - Logs & Export
// Always-on telemetry log, battery snapshots and diagnostic reports.
// Exports a JSON bundle and flat CSV tables. Files are generated only when the
// user taps Prepare, on a background task, for a chosen time range — never on
// appear and never on the main thread.

struct LogsView: View {

    private enum ExportRange: String, CaseIterable, Identifiable {
        case week, month, all

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .week: "7 days"
            case .month: "30 days"
            case .all: "All"
            }
        }

        var startDate: Date? {
            switch self {
            case .week: Calendar.current.date(byAdding: .day, value: -7, to: .now)
            case .month: Calendar.current.date(byAdding: .day, value: -30, to: .now)
            case .all: nil
            }
        }
    }

    private static let recentRowLimit = 50

    @Environment(\.modelContext) private var modelContext

    @Query private var recentLogs: [TelemetryLogRecord]
    @Query private var reports: [DiagnosticReport]

    @State private var telemetryCount = 0
    @State private var batteryCount = 0
    @State private var reportCount = 0

    @State private var range: ExportRange = .week
    @State private var files: ExportService.Files?
    @State private var isPreparing = false
    @State private var exportError: String?

    init() {
        var logs = FetchDescriptor<TelemetryLogRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        logs.fetchLimit = Self.recentRowLimit
        _recentLogs = Query(logs)

        var reportDescriptor = FetchDescriptor<DiagnosticReport>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        reportDescriptor.fetchLimit = Self.recentRowLimit
        _reports = Query(reportDescriptor)
    }

    var body: some View {
        List {
            Section("Data") {
                LabeledContent("Telemetry rows", value: "\(telemetryCount)")
                LabeledContent("Battery snapshots", value: "\(batteryCount)")
                LabeledContent("Test reports", value: "\(reportCount)")
            }

            exportSection
            recentTelemetrySection
            reportsSection
        }
        .navigationTitle("Logs & Export")
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .listRowBackground(Theme.surface)
        .tint(Theme.cyan)
        .task { loadCounts() }
    }

    // MARK: - Sections

    private var exportSection: some View {
        Section {
            Picker("Range", selection: $range) {
                ForEach(ExportRange.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: range) { _, _ in files = nil }

            Button(action: prepareExports) {
                if isPreparing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Preparing…")
                    }
                } else {
                    Text("Prepare JSON + CSV")
                }
            }
            .disabled(isPreparing)

            if let files {
                ShareLink(item: files.json) {
                    Label("Share JSON bundle", systemImage: "doc.text")
                }
                ShareLink(item: files.telemetryCSV) {
                    Label("Share telemetry CSV", systemImage: "tablecells")
                }
                ShareLink(item: files.batteryCSV) {
                    Label("Share battery CSV", systemImage: "tablecells")
                }
                ShareLink(item: files.chargingCSV) {
                    Label("Share charging sessions CSV", systemImage: "bolt.car")
                }
            }

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(Theme.red)
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Telemetry exports include at most the latest 100,000 rows. Charging sessions follow the selected range.")
        }
    }

    private var recentTelemetrySection: some View {
        Section("Recent telemetry") {
            if recentLogs.isEmpty {
                Text("No telemetry logged yet.").foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(recentLogs) { record in
                    HStack {
                        Text(record.timestamp, format: .dateTime.hour().minute().second())
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if let soc = record.socPercent {
                            Text(String(format: "%.1f %%", soc))
                        }
                        if let power = record.powerKW {
                            Text(String(format: "%.1f kW", power))
                                .foregroundStyle(power >= 0 ? Theme.cyan : Theme.green)
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var reportsSection: some View {
        Section("Diagnostic reports") {
            if reports.isEmpty {
                Text("Run a battery or charging test from the Battery screen.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(report.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(report.status.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(statusColor(report.status))
                        }
                        Text(report.summary).font(.caption).foregroundStyle(Theme.textSecondary)
                        Text(report.date, format: .dateTime.day().month().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pass": Theme.green
        case "fail": Theme.red
        default: Theme.amber
        }
    }

    private func loadCounts() {
        telemetryCount = (try? modelContext.fetchCount(FetchDescriptor<TelemetryLogRecord>())) ?? 0
        batteryCount = (try? modelContext.fetchCount(FetchDescriptor<BatterySnapshot>())) ?? 0
        reportCount = (try? modelContext.fetchCount(FetchDescriptor<DiagnosticReport>())) ?? 0
    }

    private func prepareExports() {
        guard !isPreparing else { return }
        isPreparing = true
        exportError = nil
        files = nil

        let container = modelContext.container
        let since = range.startDate
        Task {
            do {
                files = try await Task.detached(priority: .userInitiated) {
                    try ExportService.makeFiles(container: container, since: since)
                }.value
            } catch {
                AppLog.storage.error("Export failed: \(error.localizedDescription)")
                exportError = String(localized: "Export failed. Please try again.")
            }
            isPreparing = false
        }
    }
}

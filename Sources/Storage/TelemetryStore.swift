import Foundation
import SwiftData
import Combine

// MARK: - Telemetry Store
// Always-on decoded telemetry log, battery history and diagnostic reports.
// Raw adapter frames remain in RawOBDFrame; this store holds the compact,
// export-friendly data used by the logs/history UI.

@MainActor
final class TelemetryStore: ObservableObject {

    @Published private(set) var latestSample: TelemetrySample?
    @Published private(set) var lastReport: DiagnosticReport?

    private let modelContext: ModelContext
    private var cancellables = Set<AnyCancellable>()
    private var lastLogTime = Date.distantPast
    private var lastSnapshotTime = Date.distantPast
    private var unsavedRecords = 0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func bind(session: OBDSession) {
        session.sampleUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in
                self?.record(sample)
            }
            .store(in: &cancellables)
    }

    private func record(_ sample: TelemetrySample) {
        latestSample = sample
        let now = Date()

        if now.timeIntervalSince(lastLogTime) >= 1 {
            modelContext.insert(TelemetryLogRecord(sample: sample))
            lastLogTime = now
            unsavedRecords += 1
        }

        if now.timeIntervalSince(lastSnapshotTime) >= 60,
           sample.sohPercent != nil || sample.socPercent != nil {
            modelContext.insert(BatterySnapshot(sample: sample))
            lastSnapshotTime = now
            unsavedRecords += 1
        }

        if unsavedRecords >= 20 {
            save()
        }
    }

    func runBatteryTest() {
        let outcome = VehicleDiagnostics.battery(latestSample)
        persist(outcome)
    }

    func runChargingTest() {
        let outcome = VehicleDiagnostics.charging(latestSample)
        persist(outcome)
    }

    private func persist(_ outcome: DiagnosticOutcome) {
        let report = DiagnosticReport(
            kind: outcome.kind,
            status: outcome.status.rawValue,
            title: outcome.title,
            summary: outcome.summary,
            detailsJSON: outcome.detailsJSON
        )
        modelContext.insert(report)
        lastReport = report
        save()
    }

    func save() {
        guard unsavedRecords > 0 || lastReport != nil else { return }
        try? modelContext.save()
        unsavedRecords = 0
    }
}

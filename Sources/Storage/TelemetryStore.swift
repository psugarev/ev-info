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
    /// Session currently being charged, if the car is charging right now.
    @Published private(set) var activeChargingSession: ChargingSession?

    private let modelContext: ModelContext
    private var cancellables = Set<AnyCancellable>()
    private var lastLogTime = Date.distantPast
    private var lastSnapshotTime = Date.distantPast
    private var unsavedRecords = 0

    private var chargingTracker: ChargingSessionTracker
    private var lastChargingPersist = Date.distantPast

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.chargingTracker = ChargingSessionTracker(tariff: .load())
        closeInterruptedChargingSessions()
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
        recordChargingSession(sample)
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

    // MARK: - Charging sessions

    /// Turns tracker events into the persisted `ChargingSession`. The tracker is
    /// a pure value type; this is the only place that touches SwiftData.
    private func recordChargingSession(_ sample: TelemetrySample) {
        guard let event = chargingTracker.ingest(sample) else { return }

        switch event {
        case let .started(start, startSOC):
            let session = ChargingSession(startDate: start, startSOCPercent: startSOC)
            modelContext.insert(session)
            activeChargingSession = session
            lastChargingPersist = .now
            save()

        case let .updated(start, energy, peak, cost, endSOC):
            let session = activeChargingSession ?? {
                let created = ChargingSession(startDate: start)
                modelContext.insert(created)
                activeChargingSession = created
                return created
            }()
            // The session is written at most every 5 s: a 1 s poll would
            // otherwise turn a 40-minute charge into 2 400 saves.
            guard Date().timeIntervalSince(lastChargingPersist) >= 5 else { return }
            session.energyKWh = energy
            session.peakPowerKW = peak
            session.costEUR = cost
            session.endSOCPercent = endSOC
            lastChargingPersist = .now
            save()

        case let .ended(summary):
            guard let session = activeChargingSession else { return }
            session.apply(summary)
            activeChargingSession = nil
            lastChargingPersist = .now
            save()
        }
    }

    /// A session with no end date is one the app was killed during. Close it at
    /// its start rather than showing a charge that never ends.
    private func closeInterruptedChargingSessions() {
        let descriptor = FetchDescriptor<ChargingSession>(
            predicate: #Predicate { $0.endDate == nil }
        )
        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else { return }
        for session in sessions {
            session.endDate = session.startDate
        }
        save()
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
        guard unsavedRecords > 0 || lastReport != nil || lastChargingPersist != .distantPast else { return }
        try? modelContext.save()
        unsavedRecords = 0
    }
}

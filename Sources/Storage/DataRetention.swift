import Foundation
import SwiftData

// MARK: - Data Retention
// The app logs 1 telemetry row per second and every raw OBD frame, so storage
// must be bounded and user-controllable: an age-based retention setting,
// cascade deletion of a trip's raw frames, and a "delete all data" action.

enum DataRetention {

    /// UserDefaults / @AppStorage key for the retention setting (days, 0 = keep forever).
    static let settingKey = "retentionDays"
    static let defaultDays = 90
    static let options = [30, 90, 365, 0]

    /// Days currently configured, falling back to the default.
    static var configuredDays: Int {
        UserDefaults.standard.object(forKey: settingKey) as? Int ?? defaultDays
    }

    /// Oldest date to keep, or nil when retention is unlimited.
    static func cutoff(days: Int, now: Date = .now) -> Date? {
        guard days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: now)
    }

    /// Removes high-volume records older than `days`: raw frames, telemetry
    /// rows, battery snapshots and diagnostic reports. Trip summaries are tiny
    /// and are kept until the user deletes them.
    static func purge(olderThanDays days: Int, in context: ModelContext, now: Date = .now) throws {
        guard let cutoff = cutoff(days: days, now: now) else { return }
        try context.delete(model: RawOBDFrame.self, where: #Predicate { $0.timestamp < cutoff })
        try context.delete(model: TelemetryLogRecord.self, where: #Predicate { $0.timestamp < cutoff })
        try context.delete(model: BatterySnapshot.self, where: #Predicate { $0.timestamp < cutoff })
        try context.delete(model: DiagnosticReport.self, where: #Predicate { $0.date < cutoff })
        try context.save()
    }

    /// Deletes a trip together with the raw OBD frames captured during it, so
    /// no orphaned frames remain after the trip disappears from the list.
    static func delete(_ trip: TripRecord, in context: ModelContext) throws {
        let tripID: UUID? = trip.id
        try context.delete(model: RawOBDFrame.self, where: #Predicate { $0.tripID == tripID })
        context.delete(trip)
        try context.save()
    }

    /// Erases everything the app has stored.
    static func deleteAll(in context: ModelContext) throws {
        try context.delete(model: RawOBDFrame.self)
        try context.delete(model: TelemetryLogRecord.self)
        try context.delete(model: BatterySnapshot.self)
        try context.delete(model: DiagnosticReport.self)
        try context.delete(model: TripRecord.self)
        try context.save()
    }

    /// Runs the retention purge off the main thread.
    static func purgeInBackground(container: ModelContainer) {
        let days = configuredDays
        guard days > 0 else { return }
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            do {
                try purge(olderThanDays: days, in: context)
            } catch {
                AppLog.storage.error("Retention purge failed: \(error.localizedDescription)")
            }
        }
    }
}

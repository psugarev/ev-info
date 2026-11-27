import Foundation
import SwiftData

// MARK: - Schema & migration plan
// Every future model change must add a new VersionedSchema (SchemaV2, …) and a
// migration stage here, so an app update never loses a user's trip history.

enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TripRecord.self,
            RawOBDFrame.self,
            TelemetryLogRecord.self,
            BatterySnapshot.self,
            DiagnosticReport.self
        ]
    }
}

/// Adds charging sessions (issue #7). The store keeps V1 data: the migration
/// stage is lightweight because only a new model is added, no existing model or
/// attribute changes.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        SchemaV1.models + [ChargingSession.self]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

// MARK: - Persistence controller

/// Builds the app's ModelContainer. If the on-disk store cannot be opened the
/// app still launches on a temporary in-memory store, but `failureReason` is
/// set so the UI can tell the user that nothing will be saved — instead of
/// silently dropping persistence.
struct PersistenceController {
    let container: ModelContainer
    /// Non-nil when the persistent store failed to open and data is temporary.
    let failureReason: String?

    var isPersistent: Bool { failureReason == nil }

    static func make() -> PersistenceController {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration("IoniqDrive", schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [configuration]
            )
            return PersistenceController(container: container, failureReason: nil)
        } catch {
            AppLog.storage.error("Persistent store failed to open: \(error.localizedDescription)")
            return PersistenceController(
                container: makeInMemoryContainer(),
                failureReason: error.localizedDescription
            )
        }
    }

    /// In-memory container with the current schema (fallback and tests).
    static func makeInMemoryContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            // Without any container the app cannot present data at all.
            fatalError("Unable to create an in-memory SwiftData container: \(error)")
        }
    }
}

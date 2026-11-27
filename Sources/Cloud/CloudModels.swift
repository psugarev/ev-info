import Foundation
import SwiftData

// MARK: - Cloud vehicle data
// Read-only snapshot pulled from the official Pleos personal Vehicle Data API.
// Everything here is displayed with a `Cloud` provenance badge and never
// replaces a live OBD reading — it is a fallback and a cross-check.

/// Where the values came from, for the provenance badge.
enum CloudSource: String, Codable {
    case pleos = "Pleos"
}

struct CloudVehicleData: Equatable {
    var vin: String
    var fetchedAt: Date
    var source: CloudSource = .pleos

    // Battery / charging (batteries endpoint)
    var socPercent: Double?
    var isCharging: Bool?
    var isPluggedIn: Bool?
    var chargeRemainingMinutes: Int?
    var chargeStatusText: String?
    var batteryCapacityKWh: Double?
    var targetSOCStandard: Double?
    var targetSOCQuick: Double?

    // Powertrain (powertrains endpoint)
    var powertrainSOCPercent: Double?
    var rangeKm: Double?

    // Driving (driving endpoint)
    var odometerKm: Double?
    var isInPark: Bool?

    // Location (locations endpoint)
    var latitude: Double?
    var longitude: Double?

    // Status (status endpoint)
    var outsideTemperatureC: Double?
    var climateOn: Bool?
    var isLocked: Bool?
    var warnings: [String] = []

    var hasAnyReading: Bool {
        socPercent != nil || powertrainSOCPercent != nil || rangeKm != nil
            || isCharging != nil || odometerKm != nil || latitude != nil
    }

    /// SOC to show in the UI, preferring the dedicated battery endpoint.
    var displaySOCPercent: Double? { socPercent ?? powertrainSOCPercent }
}

/// Persisted cache of the last successful cloud fetch (one row per VIN).
@Model
final class CloudVehicleSnapshot {
    @Attribute(.unique) var vin: String
    var fetchedAt: Date
    var socPercent: Double?
    var rangeKm: Double?
    var isCharging: Bool?
    var isPluggedIn: Bool?
    var chargeRemainingMinutes: Int?
    var chargeStatusText: String?
    var odometerKm: Double?
    var latitude: Double?
    var longitude: Double?
    var outsideTemperatureC: Double?
    var climateOn: Bool?
    var isLocked: Bool?
    var warningsJSON: String

    init(_ data: CloudVehicleData) {
        self.vin = data.vin
        self.fetchedAt = data.fetchedAt
        self.socPercent = data.displaySOCPercent
        self.rangeKm = data.rangeKm
        self.isCharging = data.isCharging
        self.isPluggedIn = data.isPluggedIn
        self.chargeRemainingMinutes = data.chargeRemainingMinutes
        self.chargeStatusText = data.chargeStatusText
        self.odometerKm = data.odometerKm
        self.latitude = data.latitude
        self.longitude = data.longitude
        self.outsideTemperatureC = data.outsideTemperatureC
        self.climateOn = data.climateOn
        self.isLocked = data.isLocked
        self.warningsJSON = Self.encodeWarnings(data.warnings)
    }

    func update(_ data: CloudVehicleData) {
        fetchedAt = data.fetchedAt
        socPercent = data.displaySOCPercent
        rangeKm = data.rangeKm
        isCharging = data.isCharging
        isPluggedIn = data.isPluggedIn
        chargeRemainingMinutes = data.chargeRemainingMinutes
        chargeStatusText = data.chargeStatusText
        odometerKm = data.odometerKm
        latitude = data.latitude
        longitude = data.longitude
        outsideTemperatureC = data.outsideTemperatureC
        climateOn = data.climateOn
        isLocked = data.isLocked
        warningsJSON = Self.encodeWarnings(data.warnings)
    }

    var warnings: [String] {
        guard let data = warningsJSON.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    var isStale: Bool {
        Date.now.timeIntervalSince(fetchedAt) > CloudService.staleAfterSeconds
    }

    private static func encodeWarnings(_ warnings: [String]) -> String {
        guard let data = try? JSONEncoder().encode(warnings),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
}

// MARK: - Errors

enum CloudError: LocalizedError, Equatable {
    case notConfigured
    case authFailed
    case rateLimited(retryAfter: TimeInterval)
    case http(Int, String)
    case invalidResponse
    case noVehicles

    var errorDescription: String? {
        switch self {
        case .notConfigured: return AppLocalization.string("Cloud account is not connected.")
        case .authFailed: return AppLocalization.string("Pleos rejected the credentials. Check the Client ID and Secret.")
        case .rateLimited: return AppLocalization.string("Pleos rate limit reached. Try again later.")
        case let .http(status, code): return AppLocalization.format("Pleos error %@ (%@).", "\(status)", code)
        case .invalidResponse: return AppLocalization.string("Unexpected response from Pleos.")
        case .noVehicles: return AppLocalization.string("No vehicle is authorised for this key.")
        }
    }
}

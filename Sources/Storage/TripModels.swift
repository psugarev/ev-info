import Foundation
import SwiftData

// MARK: - Trip Summary (SwiftData persistent model)

@Model
final class TripRecord {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var distanceKm: Double
    var durationSeconds: Double
    var averageSpeedKmh: Double
    var maxSpeedKmh: Double
    var energyKWh: Double?
    var consumptionKWhPer100Km: Double?
    var costEUR: Double?
    var encodedPolyline: String?    // Google-encoded polyline for route replay
    var stopCount: Int?
    var stopSummary: String?        // "18:32, 18:40"
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var startPlace: String?
    var endPlace: String?
    var summary: String?            // locally generated trip summary

    init(startDate: Date = .now) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = nil
        self.distanceKm = 0
        self.durationSeconds = 0
        self.averageSpeedKmh = 0
        self.maxSpeedKmh = 0
        self.stopCount = 0
    }
}

// MARK: - Raw OBD Frame (SwiftData persistent model)
// Preserves every ELM327 response so future decoders can reprocess old trips.

@Model
final class RawOBDFrame {
    var id: UUID
    var tripID: UUID?       // Links back to TripRecord.id
    var timestamp: Date
    var request: String
    var response: String

    init(request: String, response: String, tripID: UUID? = nil) {
        self.id = UUID()
        self.tripID = tripID
        self.timestamp = .now
        self.request = request
        self.response = response
    }
}

// MARK: - TripSummary (value-type DTO for display)
// Lightweight snapshot used in list views and energy calculations.

struct TripSummary: Codable, Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    let distanceKm: Double
    let durationSeconds: Double
    let averageSpeedKmh: Double
    let maxSpeedKmh: Double
    let energyKWh: Double?
    let consumptionKWhPer100Km: Double?
    let costEUR: Double?

    init(from record: TripRecord) {
        self.id = record.id
        self.startDate = record.startDate
        self.endDate = record.endDate
        self.distanceKm = record.distanceKm
        self.durationSeconds = record.durationSeconds
        self.averageSpeedKmh = record.averageSpeedKmh
        self.maxSpeedKmh = record.maxSpeedKmh
        self.energyKWh = record.energyKWh
        self.consumptionKWhPer100Km = record.consumptionKWhPer100Km
        self.costEUR = record.costEUR
    }
}

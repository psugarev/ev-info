import Foundation

// MARK: - Trip Summary
// Local, private, deterministic summary of a finished trip. It uses the data
// the app already has (time, coordinates, distance, energy, cost, stops).
// This is the place to swap in an on-device/LLM generator later without
// changing the trip model.

enum TripSummaryGenerator {

    static func summary(for trip: TripRecord) -> String {
        let start = trip.startDate
        let end = trip.endDate ?? start
        let dateText = start.formatted(date: .abbreviated, time: .shortened)
        let timeText = "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"

        var parts: [String] = []
        parts.append("Trip on \(dateText) (\(timeText)).")

        let origin = trip.startPlace ?? coordinate(trip.startLatitude, trip.startLongitude)
        let destination = trip.endPlace ?? coordinate(trip.endLatitude, trip.endLongitude)
        if let origin, let destination {
            parts.append("Started at \(origin) and ended at \(destination).")
        } else if let origin {
            parts.append("Started at \(origin); the end position was not recorded.")
        }

        let duration = durationText(trip.durationSeconds)
        parts.append(String(
            format: "%.1f km in %@, average %.0f km/h, maximum %.0f km/h.",
            trip.distanceKm,
            duration,
            trip.averageSpeedKmh,
            trip.maxSpeedKmh
        ))

        if let energy = trip.energyKWh, energy > 0 {
            var energyText = String(format: "Used %.2f kWh", energy)
            if let consumption = trip.consumptionKWhPer100Km {
                energyText += String(format: " (%.1f kWh/100 km)", consumption)
            }
            if let cost = trip.costEUR {
                energyText += String(format: ", cost €%.2f", cost)
            }
            parts.append(energyText + ".")
        } else if let cost = trip.costEUR, cost > 0 {
            parts.append(String(format: "Cost €%.2f.", cost))
        }

        let stops = trip.stopCount ?? 0
        if let stopSummary = trip.stopSummary, !stopSummary.isEmpty {
            parts.append("Stops of a minute or more at \(stopSummary).")
        } else if stops > 0 {
            parts.append("\(stops) stop\(stops == 1 ? "" : "s") of at least one minute.")
        } else {
            parts.append("No stops of a minute or more.")
        }

        return parts.joined(separator: " ")
    }

    private static func coordinate(_ latitude: Double?, _ longitude: Double?) -> String? {
        guard let latitude, let longitude else { return nil }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }

    private static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm", minutes)
    }
}

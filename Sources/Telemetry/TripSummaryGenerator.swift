import Foundation

// MARK: - Trip Summary
// Local, private, deterministic summary of a finished trip. It uses the data
// the app already has (time, coordinates, distance, energy, cost, stops).
// This is the place to swap in an on-device/LLM generator later without
// changing the trip model.
//
// The text is written in the language selected at the time the trip ends and is
// stored with the trip, so a later language switch does not rewrite history.

enum TripSummaryGenerator {

    static func summary(for trip: TripRecord) -> String {
        let start = trip.startDate
        let end = trip.endDate ?? start
        let locale = AppLocalization.locale
        let dateText = start.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        let clock = Date.FormatStyle().hour().minute().locale(locale)
        let timeText = "\(start.formatted(clock))–\(end.formatted(clock))"

        var parts: [String] = []
        parts.append(AppLocalization.format("Trip on %@ (%@).", dateText, timeText))

        let origin = trip.startPlace ?? coordinate(trip.startLatitude, trip.startLongitude)
        let destination = trip.endPlace ?? coordinate(trip.endLatitude, trip.endLongitude)
        if let origin, let destination {
            parts.append(AppLocalization.format("Started at %@ and ended at %@.", origin, destination))
        } else if let origin {
            parts.append(AppLocalization.format("Started at %@; the end position was not recorded.", origin))
        }

        let duration = durationText(trip.durationSeconds)
        let km = AppLocalization.number(trip.distanceKm, decimals: 1)
        let average = AppLocalization.number(trip.averageSpeedKmh, decimals: 0)
        let maximum = AppLocalization.number(trip.maxSpeedKmh, decimals: 0)
        parts.append(AppLocalization.format("%@ km in %@, average %@ km/h, maximum %@ km/h.", km, duration, average, maximum))

        if let energy = trip.energyKWh, energy > 0 {
            var energyText = AppLocalization.format("Used %@ kWh", AppLocalization.number(energy, decimals: 2))
            if let consumption = trip.consumptionKWhPer100Km {
                energyText += AppLocalization.format(" (%@ kWh/100 km)", AppLocalization.number(consumption, decimals: 1))
            }
            if let cost = trip.costEUR {
                energyText += AppLocalization.format(", cost €%@", AppLocalization.number(cost, decimals: 2))
            }
            parts.append(energyText + ".")
        } else if let cost = trip.costEUR, cost > 0 {
            parts.append(AppLocalization.format("Cost €%@.", AppLocalization.number(cost, decimals: 2)))
        }

        let stops = trip.stopCount ?? 0
        if let stopSummary = trip.stopSummary, !stopSummary.isEmpty {
            parts.append(AppLocalization.format("Stops of a minute or more at %@.", stopSummary))
        } else if stops == 1 {
            parts.append(AppLocalization.format("%@ stop of at least one minute.", "\(stops)"))
        } else if stops > 1 {
            parts.append(AppLocalization.format("%@ stops of at least one minute.", "\(stops)"))
        } else {
            parts.append(AppLocalization.string("No stops of a minute or more."))
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
            return AppLocalization.format("%@ h %@ min", "\(hours)", String(format: "%02d", minutes))
        }
        return AppLocalization.format("%@ min", "\(minutes)")
    }
}

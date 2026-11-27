import SwiftUI
import SwiftData

// MARK: - Trip History View

struct TripHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TripRecord.startDate, order: .reverse) private var trips: [TripRecord]

    var body: some View {
        Group {
            if trips.isEmpty {
                ContentUnavailableView(
                    "No Trips Yet",
                    systemImage: "car",
                    description: Text("Start a trip from the dashboard to see it here.")
                )
            } else {
                List {
                    ForEach(trips, id: \.id) { trip in
                        NavigationLink {
                            TripDetailView(trip: trip)
                        } label: {
                            TripRow(trip: trip)
                        }
                    }
                    .onDelete(perform: deleteTrips)
                }
            }
        }
        .navigationTitle("Trip History")
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .listRowBackground(Theme.surface)
        .tint(Theme.cyan)
    }

    private func deleteTrips(at offsets: IndexSet) {
        // Snapshot first: deleting while iterating live @Query results shifts indices.
        let doomed = offsets.map { trips[$0] }
        for trip in doomed {
            do {
                try DataRetention.delete(trip, in: modelContext)
            } catch {
                AppLog.storage.error("Trip delete failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Trip Row

private struct TripRow: View {
    let trip: TripRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Date + distance header
            HStack {
                Text(trip.startDate, format: .dateTime.day().month().year().hour().minute())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f km", trip.distanceKm))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.blue)
            }

            // Stats row
            HStack(spacing: 16) {
                Label(durationText, systemImage: "clock")
                Label(String(format: "Ø %.0f km/h", trip.averageSpeedKmh), systemImage: "speedometer")
                Label(String(format: "↑ %.0f km/h", trip.maxSpeedKmh), systemImage: "arrow.up")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Energy + cost
            HStack(spacing: 16) {
                if let energy = trip.energyKWh {
                    Label(String(format: "%.2f kWh", energy), systemImage: "bolt.fill")
                        .foregroundStyle(.green)
                }
                if let cost = trip.costEUR {
                    Label(String(format: "€%.2f", cost), systemImage: "eurosign.circle")
                        .foregroundStyle(.orange)
                }
                if let cons = trip.consumptionKWhPer100Km {
                    Text(String(format: "%.1f kWh/100 km", cons))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let summary = trip.summary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let stops = trip.stopCount, stops > 0 {
                Label("\(stops) stop\(stops == 1 ? "" : "s")", systemImage: "pause.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var durationText: String {
        let total = Int(trip.durationSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm", m)
    }
}


// MARK: - Trip Detail

struct TripDetailView: View {
    let trip: TripRecord

    var body: some View {
        List {
            if let summary = trip.summary {
                Section("Summary") {
                    Text(summary)
                        .font(.callout)
                }
            }

            Section("Trip") {
                LabeledContent("Start") {
                    Text(trip.startDate, format: .dateTime.day().month().year().hour().minute())
                }
                if let end = trip.endDate {
                    LabeledContent("End") {
                        Text(end, format: .dateTime.day().month().year().hour().minute())
                    }
                }
                LabeledContent("Distance", value: String(format: "%.1f km", trip.distanceKm))
                LabeledContent("Duration", value: durationText(trip.durationSeconds))
                LabeledContent("Average", value: String(format: "%.0f km/h", trip.averageSpeedKmh))
                LabeledContent("Maximum", value: String(format: "%.0f km/h", trip.maxSpeedKmh))
                LabeledContent("Stops", value: "\(trip.stopCount ?? 0)")
            }

            Section("Energy") {
                if let energy = trip.energyKWh {
                    LabeledContent("Energy", value: String(format: "%.2f kWh", energy))
                }
                if let consumption = trip.consumptionKWhPer100Km {
                    LabeledContent("Consumption", value: String(format: "%.1f kWh/100 km", consumption))
                }
                if let cost = trip.costEUR {
                    LabeledContent("Cost", value: String(format: "€%.2f", cost))
                }
            }
        }
        .navigationTitle("Trip")
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .listRowBackground(Theme.surface)
        .tint(Theme.cyan)
    }

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        return hours > 0 ? String(format: "%dh %02dm", hours, minutes) : String(format: "%dm", minutes)
    }
}

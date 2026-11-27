import SwiftUI
import SwiftData

// MARK: - Costs
// Electricity tariff (one collapsible card) and the cost history of trips.
// Deliberately separate from the driving screen.

struct CostsView: View {
    @EnvironmentObject var recorder: TripRecorder

    @Query(sort: \TripRecord.startDate, order: .reverse)
    private var trips: [TripRecord]

    @State private var profile = BulgarianTariffProfile.load()
    @State private var tariffExpanded = false
    @State private var saved = false

    private var totalCost: Double {
        trips.compactMap(\.costEUR).reduce(0, +)
    }

    private var totalEnergy: Double {
        trips.compactMap(\.energyKWh).reduce(0, +)
    }

    private var averagePrice: Double? {
        totalEnergy > 0 ? totalCost / totalEnergy : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryCard
                tariffCard
                tripsCard
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Costs")
        .settingsToolbar()
    }

    // MARK: - Summary

    private var summaryCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(text: "COST")

                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "€%.2f", totalCost))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.amber)

                    Spacer()

                    if let averagePrice {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("AVERAGE")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(Theme.textTertiary)
                            Text(String(format: "€%.4f/kWh", averagePrice))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                HStack {
                    Label(String(format: "%.1f kWh", totalEnergy), systemImage: "bolt.fill")
                    Spacer()
                    Label("\(trips.count) trips", systemImage: "road.lanes")
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Tariff

    private var tariffCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    tariffExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "eurosign.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Electricity tariff")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text(String(format: "Day €%.4f · Night €%.4f / kWh", profile.day.allInEURPerKWh, profile.night.allInEURPerKWh))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(tariffExpanded ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if tariffExpanded {
                Divider().overlay(Theme.border).padding(.horizontal, 16)

                VStack(spacing: 10) {
                    TariffEditorRow(title: "Day Energy", value: $profile.day.energyEURPerKWh, unit: "€/kWh")
                    TariffEditorRow(title: "Day Network Fee", value: $profile.day.networkEURPerKWh, unit: "€/kWh")
                    TariffEditorRow(title: "Night Energy", value: $profile.night.energyEURPerKWh, unit: "€/kWh")
                    TariffEditorRow(title: "Night Network Fee", value: $profile.night.networkEURPerKWh, unit: "€/kWh")
                    TariffEditorRow(title: "Day VAT", value: $profile.day.vat, unit: "rate", isPercentage: true)
                    TariffEditorRow(title: "Night VAT", value: $profile.night.vat, unit: "rate", isPercentage: true)

                    HStack {
                        Stepper("Day starts \(profile.dayStartHour):00", value: $profile.dayStartHour, in: 0...23)
                        Spacer()
                    }
                    .font(.caption)

                    Button {
                        recorder.updateTariff(profile)
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                    } label: {
                        Label(saved ? "Saved" : "Save Tariff", systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.amber)
                }
                .padding(16)
            }
        }
        .background(Theme.surface, in: Theme.cardShape)
        .overlay(Theme.cardShape.stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Trips

    private var tripsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "TRIPS")
                Spacer()
                NavigationLink("All trips") {
                    TripHistoryView()
                }
                .font(.caption)
                .foregroundStyle(Theme.cyan)
            }

            if trips.isEmpty {
                Text("No trips yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(trips.prefix(8)) { trip in
                    NavigationLink {
                        TripDetailView(trip: trip)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.startDate, format: .dateTime.day().month().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(String(format: "%.1f km · %.1f kWh/100 km", trip.distanceKm, trip.consumptionKWhPer100Km ?? 0))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            if let cost = trip.costEUR {
                                Text(String(format: "€%.2f", cost))
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(Theme.amber)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: Theme.cardShape)
        .overlay(Theme.cardShape.stroke(Theme.border, lineWidth: 1))
    }
}

private struct TariffEditorRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let unit: String
    var isPercentage = false

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...5)))
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
                .multilineTextAlignment(.trailing)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 100)
            Text(isPercentage ? "%" : unit)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

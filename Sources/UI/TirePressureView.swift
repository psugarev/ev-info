import SwiftUI

// MARK: - Tires
// TPMS values, tire-size selection and a cold-pressure recommendation check.

struct TirePressureView: View {
    @EnvironmentObject var telemetry: TelemetryEngine
    @AppStorage("tirePressureUnit") private var unit = "bar"
    @AppStorage("tireSize") private var tireSize = "235/55 R19"

    private let labels = ["FL", "FR", "RL", "RR"]
    private let names: [LocalizedStringKey] = ["Front left", "Front right", "Rear left", "Rear right"]

    private var recommendation: Double {
        tireSize == "255/45 R20" ? 2.5 : 2.5
    }

    private var suitableCount: Int {
        (0..<4).filter { index in
            guard let bar = telemetry.tirePressuresBar.indices.contains(index) ? telemetry.tirePressuresBar[index] : nil else { return false }
            return abs(bar - recommendation) <= 0.2
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                sizeCard
                recommendationCard

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        card(index: 0)
                        card(index: 1)
                    }
                    HStack(spacing: 12) {
                        card(index: 2)
                        card(index: 3)
                    }
                }
                .padding(.horizontal)

                Text("TPMS values are measured hot. Check cold pressures against the recommendation; a ±0.2 bar difference is treated as acceptable here.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Theme.background)
        .navigationTitle("Tires")
    }

    private var sizeCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(text: "TIRE SIZE")

                Picker("Tire size", selection: $tireSize) {
                    Text("235/55 R19").tag("235/55 R19")
                    Text("255/45 R20").tag("255/45 R20")
                }
                .pickerStyle(.segmented)

                Text("Choose the size on the car's tire placard. Recommended cold pressure is 2.5 bar (36 psi) for both Ioniq 5 sizes.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal)
    }

    private var recommendationCard: some View {
        InfoCard(
            icon: "checkmark.seal",
            title: "Pressure check",
            text: "\(suitableCount) of 4 tires are within ±0.2 bar of the recommended 2.5 bar (36 psi)."
        )
        .padding(.horizontal)
    }

    private func card(index: Int) -> some View {
        let pressure = telemetry.tirePressuresBar.indices.contains(index) ? telemetry.tirePressuresBar[index] : nil
        let temperature = telemetry.tireTemperaturesC.indices.contains(index) ? telemetry.tireTemperaturesC[index] : nil
        let status = status(for: pressure)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(labels[index])
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Text(names[index])
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(pressureText(pressure))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(status.color)

            HStack {
                Text(temperature.map { String(format: "%.0f °C", $0) } ?? "— °C")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(status.label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(status.color.opacity(0.12), in: Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
    }

    private func status(for bar: Double?) -> (label: LocalizedStringKey, color: Color) {
        guard let bar else { return ("NO DATA", Theme.textTertiary) }
        if bar < recommendation - 0.2 { return ("LOW", Theme.amber) }
        if bar > recommendation + 0.2 { return ("HIGH", Theme.amber) }
        return ("OK", Theme.green)
    }

    private func pressureText(_ bar: Double?) -> String {
        guard let bar else { return "—" }
        if unit == "psi" {
            return String(format: "%.1f psi", bar / 0.0689476)
        }
        return String(format: "%.2f bar", bar)
    }
}

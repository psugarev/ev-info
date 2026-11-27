import SwiftUI
import SwiftData

// MARK: - Drive Dashboard
// Energy and trip focused dashboard. Speed stays visible as a compact,
// source-labelled contextual reading.

struct DashboardView: View {
    @EnvironmentObject var telemetry: TelemetryEngine
    @EnvironmentObject var recorder: TripRecorder
    @EnvironmentObject var ble: BLETransport
    @EnvironmentObject var location: LocationManager

    @AppStorage("demoModeEnabled") private var demoModeEnabled = false
    @State private var showAdapterSettings = false

    @Query(sort: \TripRecord.startDate, order: .reverse)
    private var trips: [TripRecord]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                // Re-evaluated every second so values flip to "stale" within
                // seconds of the adapter going silent, instead of freezing.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let fresh = telemetry.isFresh(at: context.date)
                    ScrollView {
                        VStack(spacing: 14) {
                            header(fresh: fresh)
                            if !ble.connected {
                                connectCard
                            }
                            batteryCard(fresh: fresh)
                            tripCard
                            metricsGrid(fresh: fresh)
                            tireCard
                            recentTripsCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationDestination(isPresented: $showAdapterSettings) {
                SettingsView()
            }
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: TripHistoryView()) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
#else
                ToolbarItem {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
#endif
            }
            .navigationTitle("")
        }
    }

    // MARK: - Header

    private enum LinkState {
        case demo, live, stale, waiting

        var label: LocalizedStringKey {
            switch self {
            case .demo: "DEMO"
            case .live: "LIVE"
            case .stale: "STALE"
            case .waiting: "OBD"
            }
        }

        var color: Color {
            switch self {
            case .demo, .stale: Theme.amber
            case .live: Theme.green
            case .waiting: Theme.textTertiary
            }
        }
    }

    private func linkState(fresh: Bool) -> LinkState {
        if telemetry.isDemo { return .demo }
        guard telemetry.obdReady else { return .waiting }
        return fresh ? .live : .stale
    }

    private func header(fresh: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(ble.connected ? Theme.green.opacity(0.18) : Theme.amber.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: ble.connected ? "bolt.horizontal.circle.fill" : "bolt.slash.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ble.connected ? Theme.green : Theme.amber)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(ble.statusMessage)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("Vehicle telemetry")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(linkState(fresh: fresh).label)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(linkState(fresh: fresh).color)
                    Text(telemetry.obdProtocol.isEmpty ? "—" : telemetry.obdProtocol)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            if !telemetry.vin.isEmpty || telemetry.odometerKm > 0 {
                HStack(spacing: 12) {
                    if !telemetry.vin.isEmpty {
                        Text("VIN \(telemetry.vin)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if telemetry.odometerKm > 0 {
                        Text(String(format: "%.0f km", telemetry.odometerKm))
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.top, 4)
        .contentShape(Rectangle())
        .onTapGesture { openAdapterSettings() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Opens adapter settings"))
    }

    private func openAdapterSettings() {
        if !ble.connected { ble.scan() }
        showAdapterSettings = true
    }

    // MARK: - Connect empty state

    private var connectCard: some View {
        TelemetryCard {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(text: "NO ADAPTER CONNECTED")
                Text("Connect your OBD2 adapter — or explore the app with demo data.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 10) {
                    Button {
                        openAdapterSettings()
                    } label: {
                        Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(Theme.background)
                            .background(Theme.cyan, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        demoModeEnabled = true
                    } label: {
                        Text("Use demo data")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(Theme.cyan)
                            .overlay(Capsule().stroke(Theme.cyan, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Battery

    private func batteryCard(fresh: Bool) -> some View {
        TelemetryCard {
            VStack(spacing: 14) {
                HStack {
                    CardLabel(text: "BATTERY")
                    Spacer()
                    Text(batteryBadge)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Theme.textTertiary)
                }

                HStack(spacing: 16) {
                    SOCGauge(
                        percent: telemetry.socPercent,
                        color: batteryColor,
                        isLive: telemetry.socSource != .unavailable
                    )
                    .frame(width: 104, height: 104)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 18) {
                            miniMetric("PACK", telemetry.bmsText(telemetry.batteryVoltageV, "%.0f"), "V")
                            miniMetric("CURRENT", telemetry.bmsText(telemetry.batteryCurrentA, "%+.1f"), "A")
                        }
                        HStack(spacing: 18) {
                            miniMetric("POWER", telemetry.bmsText(telemetry.batteryPowerKW, "%.1f"), "kW")
                            miniMetric("TEMP", telemetry.bmsText(telemetry.batteryTemperatureC, "%.0f"), "°C")
                        }
                    }
                    Spacer(minLength: 0)
                }

                powerBar
            }
        }
        .opacity(fresh ? 1 : 0.45)
        .accessibilityElement(children: .combine)
    }

    /// Provenance of the battery values (AGENTS.md rule 4): BMS signals come
    /// from manufacturer-specific PIDs that are not yet validated on the car.
    private var batteryBadge: LocalizedStringKey {
        if telemetry.isDemo { return "DEMO" }
        return telemetry.obdReady ? "BMS · CANDIDATE" : "—"
    }

    private var speedSourceLabel: LocalizedStringKey? {
        switch telemetry.speedSource {
        case .gps: "GPS"
        case .obdStandard: "OBD"
        default: nil
        }
    }

    private var batteryColor: Color {
        guard telemetry.socSource != .unavailable else { return Theme.textTertiary }
        if telemetry.socPercent < 15 { return Theme.red }
        if telemetry.socPercent < 30 { return Theme.amber }
        return Theme.green
    }

    private func miniMetric(_ title: LocalizedStringKey, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CardLabel(text: title)
            MetricValue(value: value, unit: unit)
        }
    }

    private var powerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let maxKW = 160.0
                let fraction = min(abs(telemetry.batteryPowerKW) / maxKW, 1)
                let half = geometry.size.width / 2

                ZStack(alignment: .center) {
                    Capsule()
                        .fill(Theme.border.opacity(0.8))
                        .frame(height: 6)

                    ForEach([0.25, 0.5, 0.75], id: \.self) { mark in
                        Rectangle()
                            .fill(Theme.textTertiary.opacity(0.35))
                            .frame(width: 1, height: 10)
                            .offset(x: half * mark)
                        Rectangle()
                            .fill(Theme.textTertiary.opacity(0.35))
                            .frame(width: 1, height: 10)
                            .offset(x: -half * mark)
                    }

                    Rectangle()
                        .fill(Theme.textTertiary.opacity(0.7))
                        .frame(width: 1, height: 13)

                    Capsule()
                        .fill(telemetry.batteryPowerKW >= 0 ? Theme.cyan : Theme.green)
                        .frame(width: max(2, half * fraction), height: 6)
                        .offset(x: telemetry.batteryPowerKW >= 0 ? half * fraction / 2 : -half * fraction / 2)
                        .animation(.easeOut(duration: 0.2), value: telemetry.batteryPowerKW)
                }
            }
            .frame(height: 13)

            HStack(spacing: 5) {
                Image(systemName: "arrow.left")
                Text("REGEN")
                Spacer()
                Text("0")
                Spacer()
                Text("POWER")
                Image(systemName: "arrow.right")
            }
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(1)
            .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Trip

    private var tripCard: some View {
        TelemetryCard {
            VStack(spacing: 14) {
                HStack {
                    CardLabel(text: "TRIP")
                    Spacer()
                    if recorder.isRecording {
                        Text(durationText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                speedRow

                if location.isDenied {
                    locationDeniedBanner
                }

                HStack(spacing: 0) {
                    tripStat("DISTANCE", String(format: "%.1f", recorder.tripDistanceKm), "km")
                    Divider().frame(height: 32).overlay(Theme.border)
                    tripStat("ENERGY", String(format: "%.2f", recorder.tripEnergyKWh), "kWh")
                    Divider().frame(height: 32).overlay(Theme.border)
                    tripStat("COST", String(format: "€%.2f", recorder.tripCostEUR), "")
                    Divider().frame(height: 32).overlay(Theme.border)
                    tripStat("AVG", recorder.currentConsumptionKWhPer100Km.map { String(format: "%.1f", $0) } ?? "—", "kWh/100")
                }

                tripActionButton
            }
        }
    }

    /// Compact speed readout. Speed is never a hero element; the chip says
    /// where it came from (GPS until OBD speed is validated on the car).
    private var speedRow: some View {
        HStack(spacing: 8) {
            CardLabel(text: "SPEED")
            Spacer()
            Text(speedSourceLabel == nil ? "—" : String(format: "%.0f km/h", telemetry.speedKmh))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(speedSourceLabel == nil ? Theme.textTertiary : Theme.textPrimary)
            if let label = speedSourceLabel {
                Text(label)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(Theme.textSecondary)
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var locationDeniedBanner: some View {
        Button {
            SystemSettings.open()
        } label: {
            Label("Location is off, so trips record no distance. Open Settings to allow it.",
                  systemImage: "location.slash")
                .font(.caption)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Theme.amber)
        }
        .buttonStyle(.plain)
    }

    private var tripActionButton: some View {
        Button {
            if recorder.isRecording {
                recorder.stopTrip()
                location.stopTracking()
            } else {
                recorder.startTrip()
                location.startTracking()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: recorder.isRecording ? "stop.fill" : "play.fill")
                Text(recorder.isRecording ? "STOP TRIP" : "START TRIP")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(Theme.background)
            .background(recorder.isRecording ? Theme.red : Theme.cyan, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recorder.isRecording ? "Stop trip" : "Start trip")
    }

    private func tripStat(_ title: LocalizedStringKey, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 3) {
            CardLabel(text: title)
            MetricValue(value: value, unit: unit)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationText: String {
        let total = Int(recorder.tripDurationSeconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Metric grid

    private var tireCard: some View {
        NavigationLink {
            TirePressureView()
        } label: {
            TelemetryCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CardLabel(text: "TIRES")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            VStack(spacing: 2) {
                                Text(["FL", "FR", "RL", "RR"][index])
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textTertiary)
                                Text(tireText(index))
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func tireText(_ index: Int) -> String {
        guard telemetry.tirePressuresBar.indices.contains(index),
              let bar = telemetry.tirePressuresBar[index] else { return "—" }
        return String(format: "%.1f", bar)
    }

    private var recentTripsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "RECENT TRIPS")
                Spacer()
                NavigationLink("All trips") {
                    TripHistoryView()
                }
                .font(.caption)
                .foregroundStyle(Theme.cyan)
            }

            if trips.isEmpty {
                Text("Start a trip to see it here.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(trips.prefix(3)) { trip in
                    NavigationLink {
                        TripDetailView(trip: trip)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.startDate, format: .dateTime.day().month().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(String(format: "%.1f km · %.1f kWh", trip.distanceKm, trip.energyKWh ?? 0))
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

    private func metricsGrid(fresh: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            gridCard("POWER · DERIVED", telemetry.bmsText(telemetry.batteryPowerKW, "%.1f"), "kW", Theme.cyan, fresh: fresh)
            gridCard("TEMPERATURE", telemetry.bmsText(telemetry.batteryTemperatureC, "%.0f"), "°C", Theme.amber, fresh: fresh)
            gridCard("12V", telemetry.positiveText(telemetry.auxiliaryVoltageV, "%.1f"), "V", Theme.green, fresh: fresh)
            gridCard("BATTERY", telemetry.bmsText(telemetry.batteryVoltageV, "%.0f"), "V", Theme.violet, fresh: fresh)
        }
    }

    private func gridCard(
        _ title: LocalizedStringKey,
        _ value: String,
        _ unit: String,
        _ color: Color,
        fresh: Bool
    ) -> some View {
        let available = value != "—"
        return TelemetryCard {
            VStack(alignment: .leading, spacing: 6) {
                CardLabel(text: title)
                MetricValue(value: value, unit: available ? unit : "", color: available ? color : Theme.textTertiary)
            }
        }
        .opacity(fresh ? 1 : 0.45)
        .accessibilityElement(children: .combine)
    }
}

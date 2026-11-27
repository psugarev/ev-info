import Foundation
import CoreLocation
import Combine

// MARK: - Telemetry Engine
// Coordinates OBDSession and LocationManager into a unified, observable
// live-data object suitable for driving the dashboard UI.
// Enforces data provenance (AGENTS.md rule 4) — every published value
// knows where it came from.

@MainActor
final class TelemetryEngine: ObservableObject {

    // MARK: - Live display state

    @Published private(set) var speedKmh: Double = 0
    @Published private(set) var speedSource: MetricSource = .unavailable

    @Published private(set) var socPercent: Double = 0
    @Published private(set) var socSource: MetricSource = .unavailable

    @Published private(set) var batteryPowerKW: Double = 0
    @Published private(set) var powerSource: MetricSource = .unavailable

    @Published private(set) var batteryVoltageV: Double = 0
    @Published private(set) var batteryCurrentA: Double = 0
    @Published private(set) var batteryTemperatureC: Double = 0
    @Published private(set) var batteryMinTemperatureC: Double = 0
    @Published private(set) var batteryInletTemperatureC: Double = 0
    @Published private(set) var cellVoltageMaxV: Double = 0
    @Published private(set) var cellVoltageMinV: Double = 0
    @Published private(set) var auxiliaryVoltageV: Double = 0
    @Published private(set) var auxiliaryCurrentA: Double = 0
    @Published private(set) var auxiliarySOCPercent: Int = 0
    @Published private(set) var sohPercent: Double = 0
    @Published private(set) var remainingEnergyKWh: Double = 0
    @Published private(set) var normalChargeCount: Int = 0
    @Published private(set) var quickChargeCount: Int = 0
    @Published private(set) var normalChargeEnergyKWh: Double = 0
    @Published private(set) var quickChargeEnergyKWh: Double = 0
    @Published private(set) var ldcTemperatureC: Double = 0
    @Published private(set) var ldcOutputVoltageV: Double = 0
    @Published private(set) var ldcOutputCurrentA: Double = 0
    @Published private(set) var cellVoltages: [Double?] = []
    @Published private(set) var isCharging = false
    @Published private(set) var tirePressuresBar: [Double?] = []
    @Published private(set) var tireTemperaturesC: [Double?] = []

    @Published private(set) var instantaneousConsumption: Double?

    // MARK: - Data availability

    /// True once a real (or demo) BMS sample has been received. Until then the
    /// numeric properties above hold placeholder zeros that the UI must render
    /// as "—" rather than as measurements.
    @Published private(set) var hasBMSData = false

    /// Arrival time of the most recent sample; drives the stale indicator.
    @Published private(set) var lastSampleDate: Date?

    /// True while user-enabled demo data is being shown instead of vehicle data.
    @Published private(set) var isDemo = false

    // MARK: - OBD session status

    @Published private(set) var obdReady = false
    @Published private(set) var obdProtocol = ""
    @Published private(set) var obdError: String?
    @Published private(set) var vin = ""
    @Published private(set) var odometerKm: Double = 0

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var lastSample: TelemetrySample?
    private var lastSampleTime: Date?

    /// Seconds without a new sample after which values are shown as stale.
    static let staleAfterSeconds: TimeInterval = 3

    // MARK: - Init

    init() {}

    // MARK: - Bind

    func bind(session: OBDSession, location: LocationManager) {
        session.sampleUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in
                self?.apply(sample)
            }
            .store(in: &cancellables)

        session.$isReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                if self?.isDemo == true {
                    self?.obdReady = true
                    return
                }
                self?.obdReady = ready
            }
            .store(in: &cancellables)

        session.$protocolName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                if self?.isDemo == true { return }
                self?.obdProtocol = name
            }
            .store(in: &cancellables)

        session.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.obdError = error
            }
            .store(in: &cancellables)

        session.$vin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.vin = value
            }
            .store(in: &cancellables)

        location.$location
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] loc in
                self?.applyGPS(loc)
            }
            .store(in: &cancellables)
    }

    // MARK: - Apply OBD sample

    private func apply(_ sample: TelemetrySample) {
        lastSample = sample
        lastSampleTime = sample.timestamp
        lastSampleDate = .now
        if sample.socPercent != nil || sample.batteryVoltageV != nil {
            hasBMSData = true
        }

        if let speed = sample.speedKmh {
            speedKmh = speed
            speedSource = .obdStandard
        }

        if let odometer = sample.odometerKm {
            odometerKm = odometer
        }

        socPercent = sample.socPercent ?? 0
        socSource = sample.socPercent == nil ? .unavailable : .hyundaiExtended

        batteryPowerKW = sample.batteryPowerKW ?? 0
        powerSource = sample.batteryPowerKW == nil ? .unavailable : .derived

        batteryVoltageV = sample.batteryVoltageV ?? 0
        batteryCurrentA = sample.batteryCurrentA ?? 0
        batteryTemperatureC = sample.batteryTemperatureC ?? 0
        batteryMinTemperatureC = sample.batteryMinTemperatureC ?? 0
        batteryInletTemperatureC = sample.batteryInletTemperatureC ?? 0
        cellVoltageMaxV = sample.cellVoltageMaxV ?? 0
        cellVoltageMinV = sample.cellVoltageMinV ?? 0
        auxiliaryVoltageV = sample.auxiliaryVoltageV ?? 0
        auxiliaryCurrentA = sample.auxiliaryCurrentA ?? 0
        auxiliarySOCPercent = sample.auxiliarySOCPercent ?? 0
        sohPercent = sample.sohPercent ?? 0
        remainingEnergyKWh = sample.remainingEnergyKWh ?? 0
        normalChargeCount = sample.normalChargeCount ?? 0
        quickChargeCount = sample.quickChargeCount ?? 0
        normalChargeEnergyKWh = sample.normalChargeEnergyKWh ?? 0
        quickChargeEnergyKWh = sample.quickChargeEnergyKWh ?? 0
        ldcTemperatureC = sample.ldcTemperatureC ?? 0
        ldcOutputVoltageV = sample.ldcOutputVoltageV ?? 0
        ldcOutputCurrentA = sample.ldcOutputCurrentA ?? 0
        if sample.cellVoltages.contains(where: { $0 != nil }) {
            cellVoltages = sample.cellVoltages
        }
        if let charging = sample.isCharging {
            isCharging = charging
        }
        if sample.tirePressuresBar.contains(where: { $0 != nil }) {
            tirePressuresBar = sample.tirePressuresBar
            tireTemperaturesC = sample.tireTemperaturesC
        }

        // Instantaneous consumption: kWh/100 km at current speed and power
        if let power = sample.batteryPowerKW, let speed = sample.speedKmh, speed > 3 {
            instantaneousConsumption = (power / speed) * 100
        } else {
            instantaneousConsumption = nil
        }
    }

    // MARK: - Apply GPS

    private func applyGPS(_ location: CLLocation) {
        // Rule 6: GPS is fallback only — never overwrite fresh OBD speed.
        guard !hasFreshOBDSpeed else { return }
        guard location.speed >= 0 else { return }
        speedKmh = location.speed * 3.6
        speedSource = .gps
    }

    private var hasFreshOBDSpeed: Bool {
        guard lastSample?.speedKmh != nil, let lastSampleTime else { return false }
        return Date.now.timeIntervalSince(lastSampleTime) < 5
    }
}

// MARK: - Freshness & demo

extension TelemetryEngine {

    /// Whether displayed values are current. Demo data is always considered
    /// fresh; otherwise the last sample must be newer than `staleAfterSeconds`.
    func isFresh(at date: Date = .now) -> Bool {
        if isDemo { return true }
        guard let lastSampleDate else { return false }
        return date.timeIntervalSince(lastSampleDate) <= Self.staleAfterSeconds
    }

    /// Formats a BMS-derived value, or "—" while no BMS data has arrived.
    func bmsText(_ value: Double, _ format: String) -> String {
        hasBMSData ? String(format: format, value) : "—"
    }

    /// Formats a value that is only meaningful when strictly positive
    /// (e.g. 12 V battery voltage), or "—" when it was never read.
    func positiveText(_ value: Double, _ format: String) -> String {
        value > 0 ? String(format: format, value) : "—"
    }

    /// Shows a recorded sample as live data. Used only for the user-enabled
    /// demo mode, which the UI labels clearly.
    func enableDemo(with sample: TelemetrySample) {
        isDemo = true
        apply(sample)
        obdReady = true
        obdProtocol = "CAN 11/500 · 6F1"
    }

    /// Leaves demo mode and clears every demo value back to "no data".
    func disableDemo() {
        guard isDemo else { return }
        isDemo = false
        reset()
    }

    private func reset() {
        lastSample = nil
        lastSampleTime = nil
        lastSampleDate = nil
        hasBMSData = false
        speedKmh = 0
        speedSource = .unavailable
        socPercent = 0
        socSource = .unavailable
        batteryPowerKW = 0
        powerSource = .unavailable
        batteryVoltageV = 0
        batteryCurrentA = 0
        batteryTemperatureC = 0
        batteryMinTemperatureC = 0
        batteryInletTemperatureC = 0
        cellVoltageMaxV = 0
        cellVoltageMinV = 0
        auxiliaryVoltageV = 0
        auxiliaryCurrentA = 0
        auxiliarySOCPercent = 0
        sohPercent = 0
        remainingEnergyKWh = 0
        normalChargeCount = 0
        quickChargeCount = 0
        normalChargeEnergyKWh = 0
        quickChargeEnergyKWh = 0
        ldcTemperatureC = 0
        ldcOutputVoltageV = 0
        ldcOutputCurrentA = 0
        cellVoltages = []
        isCharging = false
        tirePressuresBar = []
        tireTemperaturesC = []
        instantaneousConsumption = nil
        odometerKm = 0
        obdReady = false
        obdProtocol = ""
    }
}

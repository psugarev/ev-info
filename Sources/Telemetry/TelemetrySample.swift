import Foundation

// MARK: - Telemetry Sample
// A point-in-time snapshot of all vehicle signals.
// All fields are optional — only include what was actually received.
// Source enum ensures the UI can flag derived or unvalidated values.

struct TelemetrySample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date

    // --- Speed ---
    var speedKmh: Double?           // Source: obdStandard 010D (km/h)
    var gpsSpeedKmh: Double?        // Source: gps (fallback when OBD unavailable)

    // --- State of Charge ---
    var socPercent: Double?         // Source: hyundaiExtended 220101 dashboard SOC (candidate)

    // --- HV Battery ---
    var batteryVoltageV: Double?        // Source: hyundaiExtended 220101 pack voltage (candidate)
    var batteryCurrentA: Double?        // Source: hyundaiExtended 220101 current (candidate)
    var batteryPowerKW: Double?         // Source: derived (V × I / 1000); positive = discharge
    var batteryTemperatureC: Double?    // Source: hyundaiExtended 220101 max module temp (candidate)
    var batteryMinTemperatureC: Double? // Source: hyundaiExtended 220101 min module temp (candidate)
    var batteryInletTemperatureC: Double? // Source: hyundaiExtended 220101 inlet temp (candidate)
    var cellVoltageMaxV: Double?        // Source: hyundaiExtended 220101 (candidate)
    var cellVoltageMinV: Double?        // Source: hyundaiExtended 220101 (candidate)
    var auxiliaryVoltageV: Double?      // Source: hyundaiExtended 220101 12 V battery (candidate)
    var auxiliaryCurrentA: Double?      // Source: 22E011 LDC/aux (candidate)
    var auxiliarySOCPercent: Int?       // Source: 22E011 (candidate)
    var isolationResistanceKOhm: Double?// Source: hyundaiExtended 220101 (candidate)
    var sohPercent: Double?             // Source: 220105 state of health (candidate)
    var remainingEnergyKWh: Double?     // Source: 220105 remaining energy (candidate)
    var normalChargeCount: Int?         // Source: 220111 AC charge count
    var quickChargeCount: Int?          // Source: 220111 DC charge count
    var normalChargeEnergyKWh: Double?  // Source: 220111 AC energy total
    var quickChargeEnergyKWh: Double?   // Source: 220111 DC energy total
    var ldcTemperatureC: Double?        // Source: 22E011 LDC temperature
    var ldcOutputVoltageV: Double?      // Source: 22E011 LDC output voltage
    var ldcOutputCurrentA: Double?      // Source: 22E011 LDC output current
    var isCharging: Bool?               // Source: 220101 charging flag
    var cellVoltages: [Double?]         // 1-based pack cell voltages (nil = not read yet)
    var tirePressuresBar: [Double?]     // FL, FR, RL, RR (22C00B)
    var tireTemperaturesC: [Double?]    // FL, FR, RL, RR (22C00B)
    var bmsRawPayload: String?          // Hex of the decoded BMS payload, for diagnostics

    // --- Drivetrain ---
    var motorRPM: Double?           // Source: obdStandard 010C (may be meaningless on BEV)
    var acceleratorPercent: Double? // Source: obdStandard 0111
    var brakePercent: Double?       // Source: not yet validated
    var ambientTemperatureC: Double?// Source: obdStandard 0146

    // --- Trip ---
    var odometerKm: Double?         // Source: 22B002 on 7C6 (km)

    // --- Location ---
    var latitude: Double?           // Source: gps
    var longitude: Double?          // Source: gps

    // --- Raw ---
    var rawPayload: String?         // Echo of ELM327 response for debugging

    init(timestamp: Date = .now) {
        id = UUID()
        self.timestamp = timestamp
        cellVoltages = Array(repeating: nil, count: 192)
        tirePressuresBar = Array(repeating: nil, count: 4)
        tireTemperaturesC = Array(repeating: nil, count: 4)
    }

    /// Copy every signal into a new sample with a fresh timestamp.
    /// The session uses this on each update so energy integration always sees
    /// a real delta between samples (and stale values are not republished as new).
    func snapshot(at date: Date = .now) -> TelemetrySample {
        var copy = TelemetrySample(timestamp: date)
        copy.speedKmh = speedKmh
        copy.gpsSpeedKmh = gpsSpeedKmh
        copy.socPercent = socPercent
        copy.batteryVoltageV = batteryVoltageV
        copy.batteryCurrentA = batteryCurrentA
        copy.batteryPowerKW = batteryPowerKW
        copy.batteryTemperatureC = batteryTemperatureC
        copy.batteryMinTemperatureC = batteryMinTemperatureC
        copy.batteryInletTemperatureC = batteryInletTemperatureC
        copy.cellVoltageMaxV = cellVoltageMaxV
        copy.cellVoltageMinV = cellVoltageMinV
        copy.auxiliaryVoltageV = auxiliaryVoltageV
        copy.auxiliaryCurrentA = auxiliaryCurrentA
        copy.auxiliarySOCPercent = auxiliarySOCPercent
        copy.isolationResistanceKOhm = isolationResistanceKOhm
        copy.sohPercent = sohPercent
        copy.remainingEnergyKWh = remainingEnergyKWh
        copy.normalChargeCount = normalChargeCount
        copy.quickChargeCount = quickChargeCount
        copy.normalChargeEnergyKWh = normalChargeEnergyKWh
        copy.quickChargeEnergyKWh = quickChargeEnergyKWh
        copy.ldcTemperatureC = ldcTemperatureC
        copy.ldcOutputVoltageV = ldcOutputVoltageV
        copy.ldcOutputCurrentA = ldcOutputCurrentA
        copy.isCharging = isCharging
        copy.cellVoltages = cellVoltages
        copy.tirePressuresBar = tirePressuresBar
        copy.tireTemperaturesC = tireTemperaturesC
        copy.bmsRawPayload = bmsRawPayload
        copy.motorRPM = motorRPM
        copy.acceleratorPercent = acceleratorPercent
        copy.brakePercent = brakePercent
        copy.ambientTemperatureC = ambientTemperatureC
        copy.odometerKm = odometerKm
        copy.latitude = latitude
        copy.longitude = longitude
        copy.rawPayload = rawPayload
        return copy
    }

    // Convenience: effective speed (OBD preferred, GPS fallback)
    var effectiveSpeedKmh: Double? { speedKmh ?? gpsSpeedKmh }
}

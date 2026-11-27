import Foundation

// MARK: - Metric Source
// Every live value carries a provenance tag so the UI can flag unvalidated data.

enum MetricSource: String, Codable {
    case obdStandard      // Standard OBD-II Mode 01
    case hyundaiExtended  // Manufacturer-specific — requires validation
    case gps              // CoreLocation derived
    case derived          // Calculated from other validated signals
    case unavailable      // Signal not confirmed on this vehicle
}

// MARK: - PID Definition

struct PIDDefinition: Identifiable {
    let id: String              // e.g. "010D"
    let command: String         // ELM327 command string, e.g. "010D"
    let name: String
    let unit: String
    let source: MetricSource
    let interval: TimeInterval  // Seconds between polls
    let timeout: TimeInterval   // Response timeout
    let header: String          // CAN header required for this request

    init(
        id: String,
        command: String,
        name: String,
        unit: String,
        source: MetricSource,
        interval: TimeInterval,
        timeout: TimeInterval = 1.0,
        header: String = "7DF"
    ) {
        self.id = id
        self.command = command
        self.name = name
        self.unit = unit
        self.source = source
        self.interval = interval
        self.timeout = timeout
        self.header = header
    }
}

// MARK: - PID Registry

enum PIDRegistry {

    /// Functional broadcast header used for standard Mode 01 requests.
    static let functionalHeader = "7DF"

    /// Hyundai BMS physical request header. Responses come from 7EC (7E4 + 8).
    static let bmsHeader = "7E4"

    /// Standard OBD-II PID definitions. Availability is discovered for each
    /// connection and is not claimed until the target vehicle reports support.
    static let standard: [PIDDefinition] = [
        // Support discovery — polled once at session start
        .init(id: "0100", command: "0100", name: "Supported PIDs 01-20", unit: "", source: .obdStandard, interval: 999),
        .init(id: "0120", command: "0120", name: "Supported PIDs 21-40", unit: "", source: .obdStandard, interval: 999),
        .init(id: "0140", command: "0140", name: "Supported PIDs 41-60", unit: "", source: .obdStandard, interval: 999),

        // Fast group
        .init(id: "010D", command: "010D", name: "Vehicle Speed", unit: "km/h", source: .obdStandard, interval: 0.2, timeout: 0.6),

        // Slow group — may not be meaningful on a BEV
        .init(id: "010C", command: "010C", name: "Engine RPM", unit: "rpm", source: .obdStandard, interval: 1.0),
        .init(id: "0111", command: "0111", name: "Throttle Position", unit: "%", source: .obdStandard, interval: 0.5),
        .init(id: "0146", command: "0146", name: "Ambient Temperature", unit: "°C", source: .obdStandard, interval: 10, timeout: 1.5)
    ]

    /// Hyundai-specific candidate request. Read-only UDS service 0x22 with
    /// DID 0x0101, addressed physically to the BMS at 7E4.
    ///
    /// The response layout is still a candidate (see OBDResponseParser). It is
    /// polled so the app can preserve raw frames and validate the decoding
    /// against the instrument cluster.
    static let hyundaiBMS = PIDDefinition(
        id: "220101",
        command: "220101",
        name: "HV Battery Status",
        unit: "",
        source: .hyundaiExtended,
        interval: 1.0,
        timeout: 2.0,
        header: bmsHeader
    )

    /// Battery health / SOH and remaining energy (7E4, DID 0105).
    static let batteryHealth = PIDDefinition(
        id: "220105",
        command: "220105",
        name: "Battery Health",
        unit: "",
        source: .hyundaiExtended,
        interval: 10,
        timeout: 2.0,
        header: bmsHeader
    )

    /// Lifetime AC/DC charging counters and energy (7E4, DID 0111).
    static let chargingCounters = PIDDefinition(
        id: "220111",
        command: "220111",
        name: "Charging Counters",
        unit: "",
        source: .hyundaiExtended,
        interval: 60,
        timeout: 2.0,
        header: bmsHeader
    )

    /// Low-voltage DC-DC converter and auxiliary battery (7E5, DID E011).
    static let ldcStatus = PIDDefinition(
        id: "22E011",
        command: "22E011",
        name: "12V / LDC",
        unit: "",
        source: .hyundaiExtended,
        interval: 10,
        timeout: 2.0,
        header: "7E5"
    )

    /// Six DIDs x 32 cell voltages. 220102 covers cells 1–32, 220103 33–64,
    /// 220104 65–96, 22010A 97–128, 22010B 129–160 and 22010C 161–192.
    static let cellVoltagePIDs: [PIDDefinition] = [
        .init(id: "220102", command: "220102", name: "Cells 1-32", unit: "V", source: .hyundaiExtended, interval: 30, timeout: 2.0, header: bmsHeader),
        .init(id: "220103", command: "220103", name: "Cells 33-64", unit: "V", source: .hyundaiExtended, interval: 30, timeout: 2.0, header: bmsHeader),
        .init(id: "220104", command: "220104", name: "Cells 65-96", unit: "V", source: .hyundaiExtended, interval: 30, timeout: 2.0, header: bmsHeader),
        .init(id: "22010A", command: "22010A", name: "Cells 97-128", unit: "V", source: .hyundaiExtended, interval: 30, timeout: 2.0, header: bmsHeader),
        .init(id: "22010B", command: "22010B", name: "Cells 129-160", unit: "V", source: .hyundaiExtended, interval: 30, timeout: 2.0, header: bmsHeader),
        .init(id: "22010C", command: "22010C", name: "Cells 161-192", unit: "V", source: .hyundaiExtended, interval: 30, timeout: 2.0, header: bmsHeader)
    ]

    /// Tire pressures and temperatures (7A0, DID C00B).
    static let tirePressures = PIDDefinition(
        id: "22C00B",
        command: "22C00B",
        name: "Tire Pressures",
        unit: "bar",
        source: .obdStandard,
        interval: 30,
        timeout: 2.0,
        header: "7A0"
    )

    /// Vehicle identity (VIN) from the VCU, and odometer from the cluster.
    static let vin = PIDDefinition(
        id: "22F190",
        command: "22F190",
        name: "VIN",
        unit: "",
        source: .obdStandard,
        interval: 3_600,   // once per connection in practice
        timeout: 2.0,
        header: "7E2"
    )

    static let odometer = PIDDefinition(
        id: "22B002",
        command: "22B002",
        name: "Odometer",
        unit: "km",
        source: .obdStandard,
        interval: 10,
        timeout: 2.0,
        header: "7C6"
    )

    /// Kept as a list for callers that enumerate manufacturer PIDs.
    static let hyundaiExtended: [PIDDefinition] = [hyundaiBMS]

    /// Read-only standard PIDs eligible for polling after support discovery.
    static func activeStandardPIDs(supportedBy masks: [UInt32]) -> [PIDDefinition] {
        standard.filter { pid in
            guard !["0100", "0120", "0140"].contains(pid.id),
                  let value = Int(pid.id.dropFirst(2), radix: 16) else { return false }
            return isSupported(pid: value, by: masks)
        }
    }

    static func isSupported(pid: Int, by masks: [UInt32]) -> Bool {
        guard pid > 0 else { return false }
        let group = (pid - 1) / 32
        let position = (pid - 1) % 32
        guard masks.indices.contains(group) else { return false }
        return (masks[group] & (UInt32(1) << UInt32(31 - position))) != 0
    }
}

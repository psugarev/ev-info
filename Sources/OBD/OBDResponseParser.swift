import Foundation

// MARK: - OBD Response Parser
// Parses ELM327 ASCII responses into typed values.
//
// Two framing styles are supported:
//   1. ISO-TP frames with headers on:  "7E8 03 41 0D 64"
//      multi-frame:                   "7EC 10 3E 62 01 01 ..." / "7EC 21 ..."
//   2. Headers-off / already-formatted output: "41 0D 64" or "0: 62 01 01 ..."
//
// The Hyundai BMS layout below is validated against a real 2022 Ioniq 5
// 220101 capture (62-byte payload, 59 data bytes) and cross-checked with the
// OBDb IONIQ 5 DID 0101 signal map. Values still carry the `candidate` label
// in the UI until they are correlated with the instrument cluster in the app.

enum OBDResponseParser {

    // MARK: - Types

    struct Payload: Equatable {
        let header: String?
        let bytes: [UInt8]
    }

    struct BMSStatus: Equatable {
        var socPercent: Double?
        var packVoltageV: Double?
        var packCurrentA: Double?
        var maxTemperatureC: Double?
        var minTemperatureC: Double?
        var moduleTemperaturesC: [Double] = []
        var inletTemperatureC: Double?
        var maxCellVoltageV: Double?
        var minCellVoltageV: Double?
        var maxCellNumber: Int?
        var minCellNumber: Int?
        var auxiliaryVoltageV: Double?
        var inverterCapacitorVoltageV: Double?
        var isolationResistanceKOhm: Double?
        var isCharging: Bool?
        var rawPayloadHex: String
    }

    // MARK: - Standard OBD-II (Mode 01)

    /// Speed in km/h — Mode 01, PID 0D. Single byte, direct km/h.
    static func parseSpeed(_ response: String) -> Double? {
        guard let data = data(after: [0x41, 0x0D], in: response), let a = data.first else { return nil }
        return Double(a)
    }

    /// Engine/motor RPM — Mode 01, PID 0C. Two bytes: ((A*256)+B)/4.
    static func parseRPM(_ response: String) -> Double? {
        guard let data = data(after: [0x41, 0x0C], in: response), data.count >= 2 else { return nil }
        return Double((Int(data[0]) * 256) + Int(data[1])) / 4.0
    }

    /// Throttle position % — Mode 01, PID 11. Single byte: A/2.55.
    static func parseThrottlePosition(_ response: String) -> Double? {
        guard let data = data(after: [0x41, 0x11], in: response), let a = data.first else { return nil }
        return Double(a) / 2.55
    }

    /// Ambient air temperature °C — Mode 01, PID 46. Single byte: A - 40.
    static func parseAmbientTemp(_ response: String) -> Double? {
        guard let data = data(after: [0x41, 0x46], in: response), let a = data.first else { return nil }
        return Double(a) - 40.0
    }

    /// Supported PIDs bitmap (Mode 01, PID 00). When multiple ECUs reply,
    /// returns the union of their advertised capabilities.
    static func parseSupportedPIDs00(_ response: String) -> UInt32? {
        supportedBitmap(prefix: [0x41, 0x00], response: response)
    }

    static func parseSupportedPIDs20(_ response: String) -> UInt32? {
        supportedBitmap(prefix: [0x41, 0x20], response: response)
    }

    static func parseSupportedPIDs40(_ response: String) -> UInt32? {
        supportedBitmap(prefix: [0x41, 0x40], response: response)
    }

    // MARK: - Hyundai / Kia extended (UDS 0x22, DID 0x0101)
    //
    // Request: 22 01 01 (physical addressing to 7E4)
    // Positive response: 62 01 01 <59 data bytes> from 7EC
    //
    // Offsets below are relative to the first data byte after the three-byte
    // `62 01 01` echo. This matches the OBDb IONIQ 5 signal map (bit index / 8).
    // Validated against a real capture:
    //
    //   62 01 01 | EF FB E7 EF 84 00 00 00 00 00 00 1F 1B 0B ...
    //             ^ data[0]
    //
    //   data[4]      dashboard SOC / 2               = 66.0 %
    //   data[10..11] current, signed int16 / 10      = 3.1 A
    //   data[12..13] pack voltage / 10               = 692.3 V
    //   data[14]     max temperature, signed int8    = 13 °C
    //   data[15]     min temperature, signed int8    = 12 °C
    //   data[16..20] module temperatures, int8       = 12…13 °C
    //   data[22]     inlet temperature, raw - 40     = 10 °C
    //   data[23]     max cell voltage / 50           = 3.84 V
    //   data[24]     max cell number                 = 169
    //   data[25]     min cell voltage / 50           = 3.84 V
    //   data[26]     min cell number                 = 13
    //   data[29]     auxiliary battery voltage / 10  = 13.8 V
    //   data[51..52] inverter capacitor voltage      = 693 V
    //   data[57..58] isolation resistance            = 3000 kOhm

    static func parseBMSStatus(_ response: String) -> BMSStatus? {
        guard let payload = firstPayload(matching: [0x62, 0x01, 0x01], in: response) else {
            return nil
        }
        // Offsets are relative to the first data byte after `62 01 01`, which
        // matches the OBDb signal map (bit index / 8).
        let data = Array(payload.dropFirst(3))
        guard data.count >= 5 else { return nil }

        func byte(_ index: Int) -> UInt8? {
            index < data.count ? data[index] : nil
        }
        func u16(_ index: Int) -> UInt16? {
            guard index + 1 < data.count else { return nil }
            return (UInt16(data[index]) << 8) | UInt16(data[index + 1])
        }

        var status = BMSStatus(
            rawPayloadHex: payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        )

        if let value = byte(4) {
            status.socPercent = Double(value) / 2.0
        }
        if let raw = u16(10) {
            status.packCurrentA = Double(Int16(bitPattern: raw)) / 10.0
        }
        if let raw = u16(12) {
            status.packVoltageV = Double(raw) / 10.0
        }
        if let value = byte(14) {
            status.maxTemperatureC = Double(Int8(bitPattern: value))
        }
        if let value = byte(15) {
            status.minTemperatureC = Double(Int8(bitPattern: value))
        }

        var moduleTemperatures: [Double] = []
        for index in 16...20 {
            if let value = byte(index) {
                moduleTemperatures.append(Double(Int8(bitPattern: value)))
            }
        }
        status.moduleTemperaturesC = moduleTemperatures

        if let value = byte(22) {
            status.inletTemperatureC = Double(value) - 40.0
        }
        if let value = byte(23) {
            status.maxCellVoltageV = Double(value) / 50.0
        }
        if let value = byte(24) {
            status.maxCellNumber = Int(value)
        }
        if let value = byte(25) {
            status.minCellVoltageV = Double(value) / 50.0
        }
        if let value = byte(26) {
            status.minCellNumber = Int(value)
        }
        if let value = byte(29) {
            status.auxiliaryVoltageV = Double(value) / 10.0
        }
        if let raw = u16(51), raw <= 1_000 {
            status.inverterCapacitorVoltageV = Double(raw)
        }
        if let raw = u16(57) {
            status.isolationResistanceKOhm = Double(raw)
        }
        if let value = byte(9) {
            status.isCharging = (value & 0x01) != 0
        }

        if status.socPercent == nil,
           status.packVoltageV == nil,
           status.packCurrentA == nil,
           status.maxTemperatureC == nil {
            return nil
        }
        return status
    }

    static func parseHVBatterySOC(_ response: String) -> Double? {
        parseBMSStatus(response)?.socPercent
    }

    static func parseHVBatteryVoltage(_ response: String) -> Double? {
        parseBMSStatus(response)?.packVoltageV
    }

    static func parseHVBatteryCurrent(_ response: String) -> Double? {
        parseBMSStatus(response)?.packCurrentA
    }

    static func parseHVBatteryTemperature(_ response: String) -> Double? {
        parseBMSStatus(response)?.maxTemperatureC
    }

    // MARK: - Tire pressures (22 C0 0B, 7A0 → 7A8)

    struct TirePressures: Equatable {
        var frontLeftBar: Double?
        var frontRightBar: Double?
        var rearLeftBar: Double?
        var rearRightBar: Double?
        var frontLeftC: Double?
        var frontRightC: Double?
        var rearLeftC: Double?
        var rearRightC: Double?
        var rawPayloadHex: String
    }

    static func parseTirePressures(_ response: String) -> TirePressures? {
        guard let payload = firstPayload(matching: [0x62, 0xC0, 0x0B], in: response) else {
            return nil
        }
        let data = Array(payload.dropFirst(3))
        guard data.count >= 21 else { return nil }

        func pressure(_ index: Int) -> Double? {
            let raw = Int(data[index])
            guard raw > 0, raw != 0xFF else { return nil }
            let psi = Double(raw) / 5.0
            return psi * 0.0689476
        }
        func temperature(_ index: Int) -> Double? {
            let raw = Int(data[index])
            guard raw > 0, raw != 0xFF else { return nil }
            return Double(raw) - 50.0
        }

        return TirePressures(
            frontLeftBar: pressure(4),
            frontRightBar: pressure(9),
            rearLeftBar: pressure(14),
            rearRightBar: pressure(19),
            frontLeftC: temperature(5),
            frontRightC: temperature(10),
            rearLeftC: temperature(15),
            rearRightC: temperature(20),
            rawPayloadHex: payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        )
    }

    // MARK: - Cell voltages (220102/03/04/0A/0B/0C)

    /// Decode 32 cell voltages from one of the six BMS cell DIDs.
    /// `firstIndex` is the 1-based pack cell number of the first value.
    static func parseCellVoltages(
        _ response: String,
        did: UInt8,
        firstIndex: Int
    ) -> [Int: Double]? {
        guard let payload = firstPayload(matching: [0x62, 0x01, did], in: response) else {
            return nil
        }
        let data = Array(payload.dropFirst(3))
        guard data.count >= 36 else { return nil }

        var cells: [Int: Double] = [:]
        for offset in 0..<32 {
            let raw = data[4 + offset]
            if raw == 0xFF || raw == 0 { continue }
            let value = Double(raw) / 50.0
            guard value >= 2.0, value <= 4.5 else { continue }
            cells[firstIndex + offset] = value
        }
        return cells.isEmpty ? nil : cells
    }

    // MARK: - Battery health (UDS 22 01 05)

    struct BatteryHealth: Equatable {
        var sohPercent: Double?
        var remainingEnergyKWh: Double?
        var displaySOCPercent: Double?
        var moduleTemperaturesC: [Double] = []
        var rawPayloadHex: String
    }

    static func parseBatteryHealth(_ response: String) -> BatteryHealth? {
        guard let payload = firstPayload(matching: [0x62, 0x01, 0x05], in: response) else {
            return nil
        }
        let data = Array(payload.dropFirst(3))
        guard data.count >= 32 else { return nil }

        var health = BatteryHealth(
            rawPayloadHex: payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        )
        health.sohPercent = Double((UInt16(data[25]) << 8) | UInt16(data[26])) / 10.0
        health.remainingEnergyKWh = Double((UInt16(data[28]) << 8) | UInt16(data[29])) * 2.0 / 1_000.0
        health.displaySOCPercent = Double(data[31]) / 2.0

        var temperatures: [Double] = []
        for index in 9...15 {
            temperatures.append(Double(Int8(bitPattern: data[index])))
        }
        health.moduleTemperaturesC = temperatures
        return health
    }

    // MARK: - Charging counters (UDS 22 01 11)

    struct ChargingCounters: Equatable {
        var normalChargeCount: Int?
        var quickChargeCount: Int?
        var normalChargeEnergyKWh: Double?
        var quickChargeEnergyKWh: Double?
        var rawPayloadHex: String
    }

    static func parseChargingCounters(_ response: String) -> ChargingCounters? {
        guard let payload = firstPayload(matching: [0x62, 0x01, 0x11], in: response) else {
            return nil
        }
        let data = Array(payload.dropFirst(3))
        guard data.count >= 20 else { return nil }

        func uint32(_ index: Int) -> Int {
            (Int(data[index]) << 24) | (Int(data[index + 1]) << 16)
                | (Int(data[index + 2]) << 8) | Int(data[index + 3])
        }

        return ChargingCounters(
            normalChargeCount: uint32(4),
            quickChargeCount: uint32(8),
            normalChargeEnergyKWh: Double(uint32(12)),
            quickChargeEnergyKWh: Double(uint32(16)),
            rawPayloadHex: payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        )
    }

    // MARK: - 12 V / LDC (UDS 22 E0 11, 7E5)

    struct LDCStatus: Equatable {
        var temperatureC: Double?
        var outputVoltageV: Double?
        var outputCurrentA: Double?
        var inputVoltageV: Double?
        var auxiliaryCurrentA: Double?
        var auxiliarySOCPercent: Int?
        var rawPayloadHex: String
    }

    static func parseLDCStatus(_ response: String) -> LDCStatus? {
        guard let payload = firstPayload(matching: [0x62, 0xE0, 0x11], in: response) else {
            return nil
        }
        let data = Array(payload.dropFirst(3))
        guard data.count >= 21 else { return nil }

        func u16(_ index: Int) -> Int {
            (Int(data[index]) << 8) | Int(data[index + 1])
        }

        return LDCStatus(
            temperatureC: Double(data[9]) - 100.0,
            outputVoltageV: Double(u16(10)) / 1_000.0,
            outputCurrentA: Double(u16(12)) * 10.0 / 1_000.0,
            inputVoltageV: Double(u16(14)) / 10.0,
            auxiliaryCurrentA: Double(u16(18)) / 100.0 - 327.0,
            auxiliarySOCPercent: Int(data[20]),
            rawPayloadHex: payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        )
    }

    // MARK: - Vehicle identity / odometer

    /// VIN — UDS 22 F1 90 on the VCU (7E2 → 7EA), 17 ASCII bytes.
    static func parseVIN(_ response: String) -> String? {
        guard let payload = firstPayload(matching: [0x62, 0xF1, 0x90], in: response) else {
            return nil
        }
        let vinBytes = Array(payload.dropFirst(3).prefix(17))
        guard vinBytes.count == 17,
              let vin = String(bytes: vinBytes, encoding: .ascii),
              vin.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return nil
        }
        return vin
    }

    /// Odometer in km — UDS 22 B0 02 on the cluster (7C6 → 7CE).
    /// 24-bit big-endian at data[6..8].
    static func parseOdometer(_ response: String) -> Double? {
        guard let payload = firstPayload(matching: [0x62, 0xB0, 0x02], in: response) else {
            return nil
        }
        let data = Array(payload.dropFirst(3))
        guard data.count >= 9 else { return nil }
        let raw = (UInt32(data[6]) << 16) | (UInt32(data[7]) << 8) | UInt32(data[8])
        return Double(raw)
    }

    // MARK: - Framing / ISO-TP reassembly

    /// Decode every complete message in an ELM327 response.
    ///
    /// Handles single frames, ISO-TP first/consecutive frames grouped by CAN
    /// header, the numbered `0:`/`1:` form, and bare payloads from adapters
    /// that strip the PCI byte.
    static func payloads(from response: String) -> [Payload] {
        let normalized = response
            .uppercased()
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let numbered = numberedPayload(from: lines) {
            return [Payload(header: nil, bytes: numbered)]
        }

        var frames: [(header: String?, bytes: [UInt8])] = []
        for line in lines {
            var text = line
            if let colon = text.firstIndex(of: ":"),
               colon > text.startIndex,
               text[text.startIndex..<colon].allSatisfy({ $0.isNumber }) {
                text = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }

            var tokens = text
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
            guard !tokens.isEmpty else { continue }

            var header: String?
            if let first = tokens.first,
               first.count == 3 || first.count == 8,
               first.allSatisfy({ $0.isHexDigit }) {
                header = first
                tokens.removeFirst()
            }

            let bytes = tokens.compactMap { UInt8($0, radix: 16) }
            guard !bytes.isEmpty else { continue }
            frames.append((header, bytes))
        }

        var completed: [Payload] = []
        var multi: [String: (length: Int, data: [UInt8], next: Int)] = [:]

        for frame in frames {
            guard let pci = frame.bytes.first else { continue }
            let key = frame.header ?? "_"

            switch pci >> 4 {
            case 0:
                // Single frame: low nibble is the payload length.
                let declared = Int(pci & 0x0F)
                var body = Array(frame.bytes.dropFirst())
                if declared > 0, declared <= body.count {
                    body = Array(body.prefix(declared))
                }
                if !body.isEmpty {
                    completed.append(Payload(header: frame.header, bytes: body))
                }

            case 1:
                // First frame of a multi-frame message.
                guard frame.bytes.count >= 2 else { continue }
                let length = (Int(pci & 0x0F) << 8) | Int(frame.bytes[1])
                var body = Array(frame.bytes.dropFirst(2))
                if length == 0 {
                    if !body.isEmpty {
                        completed.append(Payload(header: frame.header, bytes: body))
                    }
                    continue
                }
                if body.count > length { body = Array(body.prefix(length)) }
                multi[key] = (length, body, 1)

            case 2:
                // Consecutive frame.
                guard var buffer = multi[key] else { continue }
                let sequence = Int(pci & 0x0F)
                guard sequence == buffer.next % 16 else {
                    multi[key] = nil
                    continue
                }
                buffer.data.append(contentsOf: frame.bytes.dropFirst())
                buffer.next += 1
                if buffer.data.count >= buffer.length {
                    completed.append(Payload(header: frame.header, bytes: Array(buffer.data.prefix(buffer.length))))
                    multi[key] = nil
                } else {
                    multi[key] = buffer
                }

            default:
                // Flow-control frame (3x) is ignored. A bare payload (e.g.
                // "62 01 01 ...") starts with the service byte and is taken
                // as a complete message.
                if pci >> 4 > 3 {
                    completed.append(Payload(header: frame.header, bytes: frame.bytes))
                }
            }
        }

        return completed
    }

    /// First complete payload whose bytes begin with `prefix`.
    static func firstPayload(matching prefix: [UInt8], in response: String) -> [UInt8]? {
        payloads(from: response)
            .first(where: { $0.bytes.starts(with: prefix) })?
            .bytes
    }

    // MARK: - Helpers

    private static func data(after prefix: [UInt8], in response: String) -> [UInt8]? {
        guard let payload = firstPayload(matching: prefix, in: response) else { return nil }
        return Array(payload.dropFirst(prefix.count))
    }

    private static func supportedBitmap(prefix: [UInt8], response: String) -> UInt32? {
        var combined: UInt32?
        for payload in payloads(from: response) where payload.bytes.starts(with: prefix) {
            let data = Array(payload.bytes.dropFirst(prefix.count))
            guard data.count >= 4 else { continue }
            let bitmap = (UInt32(data[0]) << 24)
                | (UInt32(data[1]) << 16)
                | (UInt32(data[2]) << 8)
                | UInt32(data[3])
            combined = (combined ?? 0) | bitmap
        }
        return combined
    }

    private static func numberedPayload(from lines: [String]) -> [UInt8]? {
        var entries: [(Int, [UInt8])] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":"),
                  colon > line.startIndex,
                  line[line.startIndex..<colon].allSatisfy({ $0.isNumber }),
                  let index = Int(line[line.startIndex..<colon]) else {
                continue
            }
            let rest = line[line.index(after: colon)...]
            let bytes = rest
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .compactMap { UInt8($0, radix: 16) }
            if !bytes.isEmpty {
                entries.append((index, bytes))
            }
        }
        guard !entries.isEmpty else { return nil }
        entries.sort { $0.0 < $1.0 }
        return entries.flatMap { $0.1 }
    }

    /// True when an ELM327 response indicates an error or no-data condition.
    static func isError(_ response: String) -> Bool {
        let upper = response.uppercased()
        let markers = [
            "NO DATA", "ERROR", "UNABLE TO CONNECT", "BUS BUSY",
            "CAN ERROR", "BUFFER FULL", "STOPPED", "?"
        ]
        return markers.contains { upper.contains($0) }
    }
}

import XCTest
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

final class OBDResponseParserTests: XCTestCase {

    // MARK: - Speed

    func testSpeedBasic() {
        XCTAssertEqual(OBDResponseParser.parseSpeed("41 0D 64"), 100.0)
    }

    func testSpeedZero() {
        XCTAssertEqual(OBDResponseParser.parseSpeed("41 0D 00"), 0.0)
    }

    func testSpeedMaxByte() {
        XCTAssertEqual(OBDResponseParser.parseSpeed("41 0D FF"), 255.0)
    }

    func testSpeedWithEcho() {
        // ATE0 should remove this, but the parser must tolerate an echo anyway.
        XCTAssertEqual(OBDResponseParser.parseSpeed("010D\r41 0D 64\r>"), 100.0)
    }

    func testSpeedWithCANHeaderAndLengthByte() {
        // Real ELM327 output with ATH1 on: header + ISO-TP PCI + data.
        XCTAssertEqual(OBDResponseParser.parseSpeed("7E8 03 41 0D 64"), 100.0)
        XCTAssertEqual(OBDResponseParser.parseSpeed("7E8 03 41 0D 64\r\r>"), 100.0)
    }

    func testSpeedPicksFirstRespondingECU() {
        let response = "7E8 03 41 0D 64\r7E9 03 41 0D 32"
        XCTAssertEqual(OBDResponseParser.parseSpeed(response), 100.0)
    }

    func testSpeedNoData() {
        XCTAssertNil(OBDResponseParser.parseSpeed("NO DATA"))
    }

    func testSpeedWrongPID() {
        XCTAssertNil(OBDResponseParser.parseSpeed("41 0C 1A F8"))
    }

    // MARK: - RPM

    func testRPMBasic() {
        // 0x1A, 0xF8 → (26*256 + 248) / 4 = 1726 rpm
        let rpm = OBDResponseParser.parseRPM("41 0C 1A F8")
        XCTAssertNotNil(rpm)
        XCTAssertEqual(rpm!, (26 * 256 + 248) / 4.0, accuracy: 0.01)
    }

    func testRPMWithHeader() {
        let rpm = OBDResponseParser.parseRPM("7E8 04 41 0C 1A F8")
        XCTAssertEqual(rpm ?? 0, (26 * 256 + 248) / 4.0, accuracy: 0.01)
    }

    func testRPMZero() {
        XCTAssertEqual(OBDResponseParser.parseRPM("41 0C 00 00"), 0.0)
    }

    func testRPMMissingBytes() {
        XCTAssertNil(OBDResponseParser.parseRPM("41 0C 1A"))  // Only 1 byte
    }

    // MARK: - Throttle / ambient

    func testThrottleHalf() {
        // 0x80 = 128 → 128/2.55 ≈ 50.2%
        let throttle = OBDResponseParser.parseThrottlePosition("41 11 80")
        XCTAssertNotNil(throttle)
        XCTAssertEqual(throttle!, 128.0 / 2.55, accuracy: 0.01)
    }

    func testThrottleWideOpen() {
        let throttle = OBDResponseParser.parseThrottlePosition("41 11 FF")
        XCTAssertNotNil(throttle)
        XCTAssertEqual(throttle!, 255.0 / 2.55, accuracy: 0.01)
    }

    func testAmbientTemperature() {
        // 0x50 = 80 → 40 °C
        XCTAssertEqual(OBDResponseParser.parseAmbientTemp("41 46 50"), 40.0)
        XCTAssertEqual(OBDResponseParser.parseAmbientTemp("7E8 03 41 46 28"), 0.0)
    }

    // MARK: - Error detection

    func testNoData() {
        XCTAssertTrue(OBDResponseParser.isError("NO DATA"))
        XCTAssertTrue(OBDResponseParser.isError("UNABLE TO CONNECT"))
        XCTAssertTrue(OBDResponseParser.isError("BUS BUSY"))
        XCTAssertTrue(OBDResponseParser.isError("?"))
        XCTAssertTrue(OBDResponseParser.isError("BUFFER FULL"))
        XCTAssertFalse(OBDResponseParser.isError("41 0D 64"))
    }

    // MARK: - Supported PIDs bitmap

    func testSupportedPIDs00() {
        let mask = OBDResponseParser.parseSupportedPIDs00("41 00 FF FF FF FF")
        XCTAssertEqual(mask, 0xFFFFFFFF)
    }

    func testSupportedPIDs00WithHeader() {
        // 7E8, 6 payload bytes, 41 00, then the 4-byte bitmap.
        let mask = OBDResponseParser.parseSupportedPIDs00("7E8 06 41 00 BE 3E B8 13")
        XCTAssertEqual(mask, 0xBE3EB813)
    }

    func testSupportedPIDs00Missing() {
        XCTAssertNil(OBDResponseParser.parseSupportedPIDs00("NO DATA"))
    }

    func testSupportedPIDs00CombinesMultipleECUs() {
        let response = "7EE 06 41 00 80 00 00 00\r7EC 06 41 00 80 00 00 01\r7EB 06 41 00 80 00 00 01"
        XCTAssertEqual(OBDResponseParser.parseSupportedPIDs00(response), 0x80000001)
    }

    func testSupportedPIDsRealIoniqCapture() {
        // Captured from the target car (ELM327 v2.3, ISO 15765-4, ATH1).
        let response = "SEARCHING...\r7EE 06 41 00 80 00 00 00 \r7EC 06 41 00 80 00 00 01 \r7EB 06 41 00 80 00 00 01 \r7EA 06 41 00 00 00 00 00 \r\r>"
        XCTAssertEqual(OBDResponseParser.parseSupportedPIDs00(response), 0x80000001)
        XCTAssertFalse(OBDResponseParser.isError(response))
    }

    func testSupportedPIDs20() {
        let mask = OBDResponseParser.parseSupportedPIDs20("7E8 06 41 20 80 00 00 01")
        XCTAssertEqual(mask, 0x80000001)
    }

    // MARK: - Hyundai BMS / UDS 22 01 01

    func testBMSRealIoniqCapture() {
        let status = OBDResponseParser.parseBMSStatus(realBMSResponse)

        XCTAssertNotNil(status)
        XCTAssertEqual(status?.socPercent ?? 0, 66.0, accuracy: 0.01)
        XCTAssertEqual(status?.packVoltageV ?? 0, 692.3, accuracy: 0.01)
        XCTAssertEqual(status?.packCurrentA ?? 0, 3.1, accuracy: 0.01)
        XCTAssertEqual(status?.maxTemperatureC ?? 0, 13.0, accuracy: 0.01)
        XCTAssertEqual(status?.minTemperatureC ?? 0, 12.0, accuracy: 0.01)
        XCTAssertEqual(status?.moduleTemperaturesC ?? [], [12, 13, 12, 13, 12])
        XCTAssertEqual(status?.inletTemperatureC ?? 0, 10.0, accuracy: 0.01)
        XCTAssertEqual(status?.maxCellVoltageV ?? 0, 3.84, accuracy: 0.001)
        XCTAssertEqual(status?.minCellVoltageV ?? 0, 3.84, accuracy: 0.001)
        XCTAssertEqual(status?.maxCellNumber, 169)
        XCTAssertEqual(status?.minCellNumber, 13)
        XCTAssertEqual(status?.auxiliaryVoltageV ?? 0, 13.8, accuracy: 0.01)
        XCTAssertEqual(status?.inverterCapacitorVoltageV ?? 0, 693.0, accuracy: 0.01)
        XCTAssertEqual(status?.isolationResistanceKOhm ?? 0, 3000.0, accuracy: 0.01)
        XCTAssertEqual(status?.isCharging, false)
    }

    func testBMSPowerFromValidatedValues() {
        let status = OBDResponseParser.parseBMSStatus(realBMSResponse)
        let powerKW = ((status?.packVoltageV ?? 0) * (status?.packCurrentA ?? 0)) / 1_000.0
        XCTAssertEqual(powerKW, 2.14613, accuracy: 0.0001)
    }

    func testBMSSecondCaptureDecodes() {
        let response = [
            "7EC 10 3E 62 01 01 EF FB E7 ",
            "7EC 21 EF 84 00 00 00 00 00 ",
            "7EC 22 00 22 1A FE 0D 0C 0D ",
            "7EC 23 0D 0C 0D 0D 00 33 C0 ",
            "7EC 24 25 BF 60 00 00 8A 00 ",
            "7EC 25 05 F3 F4 00 05 C1 FD ",
            "7EC 26 00 04 1F E3 00 03 D6 ",
            "7EC 27 9F 02 D7 22 90 00 02 ",
            "7EC 28 B5 00 00 00 00 0B B8 "
        ].joined(separator: "\r")

        let status = OBDResponseParser.parseBMSStatus(response)
        XCTAssertEqual(status?.socPercent ?? 0, 66.0, accuracy: 0.01)
        XCTAssertEqual(status?.packVoltageV ?? 0, 691.0, accuracy: 0.01)
        XCTAssertEqual(status?.packCurrentA ?? 0, 3.4, accuracy: 0.01)
        XCTAssertEqual(status?.maxTemperatureC ?? 0, 13.0, accuracy: 0.01)
        XCTAssertEqual(status?.minTemperatureC ?? 0, 12.0, accuracy: 0.01)
        XCTAssertEqual(status?.moduleTemperaturesC ?? [], [13, 13, 12, 13, 13])
        XCTAssertEqual(status?.inletTemperatureC ?? 0, 11.0, accuracy: 0.01)
        XCTAssertEqual(status?.maxCellVoltageV ?? 0, 3.84, accuracy: 0.001)
        XCTAssertEqual(status?.maxCellNumber, 37)
        XCTAssertEqual(status?.minCellVoltageV ?? 0, 3.82, accuracy: 0.001)
        XCTAssertEqual(status?.minCellNumber, 96)
    }

    func testBatteryHealth() {
        let response = "62 01 05 FF FB 74 0F 01 2C 01 01 2C 0D 0C 0D 0C 0D 0D 0C 5C E6 62 D4 00 00 50 0C 00 03 BB 60 4C AC 00 83 00 00 00 00 00 00 00 0C 0D 0C 0D 0A"
        let health = OBDResponseParser.parseBatteryHealth(response)
        XCTAssertEqual(health?.sohPercent ?? 0, 95.5, accuracy: 0.01)
        XCTAssertEqual(health?.remainingEnergyKWh ?? 0, 39.256, accuracy: 0.001)
        XCTAssertEqual(health?.displaySOCPercent ?? 0, 65.5, accuracy: 0.01)
    }

    func testChargingCounters() {
        let response = "62 01 11 F3 9F FF FF 00 00 01 C8 00 00 00 D1 00 00 30 F1 00 00 0A 3E 4C AC 00 00 00 00 00 00 00 00"
        let counters = OBDResponseParser.parseChargingCounters(response)
        XCTAssertEqual(counters?.normalChargeCount, 456)
        XCTAssertEqual(counters?.quickChargeCount, 209)
        XCTAssertEqual(counters?.normalChargeEnergyKWh ?? 0, 12_529, accuracy: 0.1)
        XCTAssertEqual(counters?.quickChargeEnergyKWh ?? 0, 2_622, accuracy: 0.1)
    }

    func testLDCStatus() {
        let response = "62 E0 11 FF FF FF F8 01 01 00 00 00 73 3A 5F 0A A9 1B 19 39 26 84 5E 59 21 FC 00 68 08 01"
        let ldc = OBDResponseParser.parseLDCStatus(response)
        XCTAssertEqual(ldc?.temperatureC ?? 0, 15.0, accuracy: 0.01)
        XCTAssertEqual(ldc?.outputVoltageV ?? 0, 14.943, accuracy: 0.001)
        XCTAssertEqual(ldc?.outputCurrentA ?? 0, 27.29, accuracy: 0.01)
        XCTAssertEqual(ldc?.inputVoltageV ?? 0, 693.7, accuracy: 0.01)
        XCTAssertEqual(ldc?.auxiliaryCurrentA ?? 0, 11.86, accuracy: 0.01)
        XCTAssertEqual(ldc?.auxiliarySOCPercent, 89)
    }

    func testTirePressures() {
        let response = "62 C0 0B FF FF FF 80 BC 3D 01 00 00 BC 3C 01 00 00 BD 3D 01 00 00 BD 3D 01 00 00 FF 98 B0 98 B0 98 B0 98 B0"
        let tires = OBDResponseParser.parseTirePressures(response)
        XCTAssertEqual(tires?.frontLeftBar ?? 0, 2.5924, accuracy: 0.0001)
        XCTAssertEqual(tires?.frontRightBar ?? 0, 2.5924, accuracy: 0.0001)
        XCTAssertEqual(tires?.rearLeftBar ?? 0, 2.6062, accuracy: 0.0001)
        XCTAssertEqual(tires?.frontLeftC ?? 0, 11.0)
        XCTAssertEqual(tires?.frontRightC ?? 0, 10.0)
    }

    func testCellVoltages() {
        var bytes: [UInt8] = [0x62, 0x01, 0x02, 0xFF, 0xFF, 0xFF, 0xFF]
        bytes.append(contentsOf: Array(repeating: 0xBF, count: 32))
        bytes[7] = 0xC0  // first cell 3.84 V (data[4])
        let response = hex(bytes)

        let cells = OBDResponseParser.parseCellVoltages(response, did: 0x02, firstIndex: 1)
        XCTAssertEqual(cells?.count, 32)
        XCTAssertEqual(cells?[1] ?? 0, 3.84, accuracy: 0.001)
        XCTAssertEqual(cells?[2] ?? 0, 3.82, accuracy: 0.001)
        XCTAssertEqual(cells?[32] ?? 0, 3.82, accuracy: 0.001)
    }

    func testVIN() {
        let response = "62 F1 90 4B 4D 48 4B 4E 38 31 41 46 4E 55 30 33 30 36 37 31"
        XCTAssertEqual(OBDResponseParser.parseVIN(response), "KMHKN81AFNU030671")
    }

    func testOdometer() {
        let response = "62 B0 02 E0 00 00 00 FF B8 01 D5 25 00 00 00"
        XCTAssertEqual(OBDResponseParser.parseOdometer(response), 120101)
    }

    func testBMSNegativeCurrentUsesSignedInt16() {
        var payload = realBMSPayload
        payload[13] = 0xFF
        payload[14] = 0x9C  // data[10..11] = -100 → -10.0 A
        let status = OBDResponseParser.parseBMSStatus(isoTPFrames(payload))
        XCTAssertEqual(status?.packCurrentA ?? 0, -10.0, accuracy: 0.01)
    }

    func testBMSInverterVoltageOutOfRangeIsRejected() {
        var payload = realBMSPayload
        payload[54] = 0x19
        payload[55] = 0x99  // data[51..52] = 6553 V — outside 0…1000 V
        let status = OBDResponseParser.parseBMSStatus(isoTPFrames(payload))
        XCTAssertNil(status?.inverterCapacitorVoltageV)
        // The rest of the frame still decodes.
        XCTAssertEqual(status?.socPercent ?? 0, 66.0, accuracy: 0.01)
    }

    func testBMSNumberedMultiFrame() {
        let chunks = stride(from: 0, to: realBMSPayload.count, by: 7).enumerated().map { index, offset -> String in
            let end = min(offset + 7, realBMSPayload.count)
            return "\(index): " + hex(Array(realBMSPayload[offset..<end]))
        }
        let response = chunks.joined(separator: "\r")
        let status = OBDResponseParser.parseBMSStatus(response)
        XCTAssertEqual(status?.socPercent ?? 0, 66.0, accuracy: 0.01)
        XCTAssertEqual(status?.packVoltageV ?? 0, 692.3, accuracy: 0.01)
    }

    func testBMSWrongModeIsRejected() {
        XCTAssertNil(OBDResponseParser.parseHVBatterySOC("61 01 00 00 00 00 00 96"))
        XCTAssertNil(OBDResponseParser.parseHVBatteryVoltage("61 01 00 00 00 00 00 00 17 80"))
    }

    func testBMSShortFrameIsRejected() {
        XCTAssertNil(OBDResponseParser.parseBMSStatus("62 01 01 00 00"))
    }

    func testBMSHeaderEcho() {
        let response = "220101\r" + realBMSResponse
        XCTAssertEqual(OBDResponseParser.parseBMSStatus(response)?.socPercent ?? 0, 66.0, accuracy: 0.01)
    }

    // MARK: - Helpers

    private var realBMSPayload: [UInt8] {
        [
            0x62, 0x01, 0x01, 0xEF, 0xFB, 0xE7, 0xEF, 0x84,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x1B,
            0x0B, 0x0D, 0x0C, 0x0C, 0x0D, 0x0C, 0x0D, 0x0C,
            0x00, 0x32, 0xC0, 0xA9, 0xC0, 0x0D, 0x00, 0x00,
            0x8A, 0x00, 0x05, 0xF3, 0xF4, 0x00, 0x05, 0xC1,
            0xFD, 0x00, 0x04, 0x1F, 0xE3, 0x00, 0x03, 0xD6,
            0x9F, 0x02, 0xD7, 0x0E, 0x63, 0x00, 0x02, 0xB5,
            0x00, 0x00, 0x00, 0x00, 0x0B, 0xB8
        ]
    }

    private var realBMSResponse: String {
        [
            "7EC 10 3E 62 01 01 EF FB E7 ",
            "7EC 21 EF 84 00 00 00 00 00 ",
            "7EC 22 00 1F 1B 0B 0D 0C 0C ",
            "7EC 23 0D 0C 0D 0C 00 32 C0 ",
            "7EC 24 A9 C0 0D 00 00 8A 00 ",
            "7EC 25 05 F3 F4 00 05 C1 FD ",
            "7EC 26 00 04 1F E3 00 03 D6 ",
            "7EC 27 9F 02 D7 0E 63 00 02 ",
            "7EC 28 B5 00 00 00 00 0B B8 "
        ].joined(separator: "\r")
    }

    private func isoTPFrames(_ payload: [UInt8], header: String = "7EC") -> String {
        precondition(payload.count <= 0xFFF)
        var lines: [String] = []

        let firstChunk = Array(payload.prefix(6))
        let pci1 = UInt8(0x10 | ((payload.count >> 8) & 0x0F))
        let pci2 = UInt8(payload.count & 0xFF)
        lines.append("\(header) \(hex([pci1, pci2] + firstChunk))")

        var index = 6
        var sequence = 1
        while index < payload.count {
            let end = min(index + 7, payload.count)
            let chunk = Array(payload[index..<end])
            let pci = UInt8(0x20 | (sequence % 16))
            lines.append("\(header) \(hex([pci] + chunk))")
            index = end
            sequence += 1
        }
        return lines.joined(separator: "\r")
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

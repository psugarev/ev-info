import XCTest
import Combine
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

private final class FakeOBDTransport: OBDTransport {
    let connection = CurrentValueSubject<Bool, Never>(false)
    let data = PassthroughSubject<Data, Never>()
    private(set) var sent: [String] = []

    var isConnected: Bool { connection.value }
    var connectedPublisher: AnyPublisher<Bool, Never> { connection.eraseToAnyPublisher() }
    var dataPublisher: AnyPublisher<Data, Never> { data.eraseToAnyPublisher() }

    func send(_ command: String) {
        sent.append(command)
    }
}

@MainActor
final class OBDSessionTests: XCTestCase {

    private let real0100 = "SEARCHING...\r7EE 06 41 00 80 00 00 00 \r7EC 06 41 00 80 00 00 01 \r7EB 06 41 00 80 00 00 01 \r7EA 06 41 00 00 00 00 00 \r\r>"

    func testInitDiscoveryAndBMSPoll() {
        let transport = FakeOBDTransport()
        let session = OBDSession(transport: transport)
        var samples: [TelemetrySample] = []
        var stages: [OBDSession.InitializationStatus] = []
        session.initializationStatusDidChange = { status in
            if let status { stages.append(status) }
        }
        let cancellable = session.sampleUpdates.sink { samples.append($0) }
        defer { cancellable.cancel(); session.stopPolling() }

        session.begin()
        XCTAssertEqual(transport.sent, ["ATZ\r"])
        XCTAssertEqual(stages.last, .initializingAdapter)

        session.receive("ATZ\r\r\rELM327 v2.3\r\r>")
        XCTAssertEqual(transport.sent.last, "ATE0\r")
        XCTAssertEqual(stages.last, .configuringAdapter)

        for _ in 0..<6 {
            session.receive("OK\r\r>")
        }
        XCTAssertEqual(transport.sent.last, "ATDPN\r")

        session.receive("A6\r\r>")
        XCTAssertEqual(transport.sent.last, "0100\r")
        XCTAssertEqual(stages.last, .discoveringCapabilities)

        session.receive(real0100)
        XCTAssertEqual(transport.sent.last, "0120\r")

        session.receive("7E8 06 41 20 80 00 00 01\r\r>")
        XCTAssertEqual(transport.sent.last, "0140\r")

        session.receive("7E8 06 41 40 00 00 00 00\r\r>")
        XCTAssertTrue(session.isReady)
        XCTAssertEqual(stages.last, .preparingBMSRead)
        XCTAssertEqual(session.protocolCode, "A6")
        XCTAssertTrue(session.protocolName.contains("15765-4"))

        // The car advertises only PID 01 and 20, so no fast PIDs are polled;
        // the BMS request is still issued with a header switch.
        XCTAssertEqual(transport.sent.last, "ATSH7E4\r")
        session.receive("OK\r\r>")
        XCTAssertEqual(transport.sent.last, "220101\r")

        let before = Date()
        let payload: [UInt8] = [
            0x62, 0x01, 0x01, 0xEF, 0xFB, 0xE7, 0xEF, 0x84,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x1B,
            0x0B, 0x0D, 0x0C, 0x0C, 0x0D, 0x0C, 0x0D, 0x0C,
            0x00, 0x32, 0xC0, 0xA9, 0xC0, 0x0D, 0x00, 0x00,
            0x8A, 0x00, 0x05, 0xF3, 0xF4, 0x00, 0x05, 0xC1,
            0xFD, 0x00, 0x04, 0x1F, 0xE3, 0x00, 0x03, 0xD6,
            0x9F, 0x02, 0xD7, 0x0E, 0x63, 0x00, 0x02, 0xB5,
            0x00, 0x00, 0x00, 0x00, 0x0B, 0xB8
        ]
        session.receive(isoTPFrames(payload) + "\r\r>")

        XCTAssertEqual(samples.count, 1)
        let sample = samples[0]
        XCTAssertGreaterThan(sample.timestamp, before)
        XCTAssertEqual(sample.socPercent ?? 0, 66.0, accuracy: 0.01)
        XCTAssertEqual(sample.batteryVoltageV ?? 0, 692.3, accuracy: 0.01)
        XCTAssertEqual(sample.batteryCurrentA ?? 0, 3.1, accuracy: 0.01)
        XCTAssertEqual(sample.batteryPowerKW ?? 0, 2.14613, accuracy: 0.001)
        XCTAssertEqual(sample.batteryTemperatureC ?? 0, 13.0, accuracy: 0.01)
        XCTAssertEqual(sample.auxiliaryVoltageV ?? 0, 13.8, accuracy: 0.01)
        XCTAssertNil(session.lastError)
        XCTAssertEqual(stages.last, .ready(protocolName: session.protocolName))
    }

    func testDiscoveryFailureSetsErrorButFinishes() {
        let transport = FakeOBDTransport()
        let session = OBDSession(transport: transport)
        defer { session.stopPolling() }

        session.begin()
        session.receive("ATZ\r\r\rELM327 v2.3\r\r>")
        for _ in 0..<6 { session.receive("OK\r\r>") }
        session.receive("A6\r\r>")

        XCTAssertEqual(transport.sent.last, "0100\r")
        session.receive("NO DATA\r\r>")
        XCTAssertEqual(transport.sent.last, "0100\r")  // one retry
        session.receive("NO DATA\r\r>")

        XCTAssertTrue(session.isReady)
        XCTAssertEqual(session.lastError, "Vehicle did not report supported PIDs")
        XCTAssertTrue(session.supportedPIDs.isEmpty)
    }

    func testBMSDecodeFailureKeepsRawFrameAndSetsError() {
        let transport = FakeOBDTransport()
        let session = OBDSession(transport: transport)
        defer { session.stopPolling() }

        session.begin()
        session.receive("ATZ\r\r\rELM327 v2.3\r\r>")
        for _ in 0..<6 { session.receive("OK\r\r>") }
        session.receive("A6\r\r>")
        session.receive(real0100)
        session.receive("NO DATA\r\r>")   // 0120 → finish with no further range
        // 0120 failure calls finishInit and starts the BMS poll.

        XCTAssertEqual(transport.sent.last, "ATSH7E4\r")
        session.receive("OK\r\r>")
        XCTAssertEqual(transport.sent.last, "220101\r")
        session.receive("7EC 03 62 01 01\r\r>")
        XCTAssertEqual(session.lastError, "BMS reply not decoded (raw frame preserved)")
    }

    func testTimeoutSendsResyncAndRecordsError() {
        let transport = FakeOBDTransport()
        let session = OBDSession(transport: transport, timeScale: 0.01)
        defer { session.stopPolling() }

        session.begin()
        XCTAssertEqual(transport.sent.last, "ATZ\r")

        // ATZ timeout is 5 s; with timeScale 0.01 that is 50 ms.
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))

        XCTAssertTrue(session.lastError?.hasPrefix("No response to ") ?? false)
        XCTAssertTrue(transport.sent.contains("\r"), "expected a resync flush")
    }

    // MARK: - Helper

    private func isoTPFrames(_ payload: [UInt8]) -> String {
        var lines: [String] = []
        let firstChunk = Array(payload.prefix(6))
        let pci1 = UInt8(0x10 | ((payload.count >> 8) & 0x0F))
        let pci2 = UInt8(payload.count & 0xFF)
        lines.append("7EC " + hex([pci1, pci2] + firstChunk))

        var index = 6
        var sequence = 1
        while index < payload.count {
            let end = min(index + 7, payload.count)
            let chunk = Array(payload[index..<end])
            let pci = UInt8(0x20 | (sequence % 16))
            lines.append("7EC " + hex([pci] + chunk))
            index = end
            sequence += 1
        }
        return lines.joined(separator: "\r")
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

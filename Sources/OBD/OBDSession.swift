import Foundation
import Combine

// MARK: - Transport abstraction
// Lets the session be driven by BLETransport in the app and by a fake
// transport in tests, without touching CoreBluetooth.

protocol OBDTransport: AnyObject {
    var isConnected: Bool { get }
    var connectedPublisher: AnyPublisher<Bool, Never> { get }
    var dataPublisher: AnyPublisher<Data, Never> { get }
    func send(_ command: String)
}

// MARK: - OBD Session
// Manages the ELM327 command/response lifecycle.
// Responsibilities:
//   1. Run the ELM327 initialisation sequence after BLE connect.
//   2. Serialise OBD requests (one at a time — ELM327 is half-duplex).
//   3. Recover from timeouts without letting a late reply poison the next command.
//   4. Switch CAN headers between functional (7DF) and BMS (7E4) requests.
//   5. Poll standard PIDs and the Hyundai BMS, publishing fresh samples.

final class OBDSession: ObservableObject {

    // MARK: - Public state

    @Published private(set) var isReady = false         // init + discovery complete
    @Published private(set) var protocolCode = ""       // ATDPN result, e.g. "A6"
    @Published private(set) var protocolName = ""       // human-readable protocol
    @Published private(set) var lastError: String?
    @Published private(set) var supportedPIDs: [String] = []
    @Published private(set) var vin = ""

    /// Raw ELM327 response lines for logging / debugging.
    let rawResponses = PassthroughSubject<RawOBDFrame, Never>()

    /// Decoded telemetry updates. Every sample carries the time it was built.
    let sampleUpdates = PassthroughSubject<TelemetrySample, Never>()

    // MARK: - Private

    private let transport: OBDTransport
    private let timeScale: TimeInterval
    private var cancellables = Set<AnyCancellable>()

    private struct PendingCommand {
        let id: UUID
        let command: String
        let timeout: TimeInterval
        let completion: ((String) -> Void)?

        init(command: String, timeout: TimeInterval, completion: ((String) -> Void)? = nil) {
            self.id = UUID()
            self.command = command
            self.timeout = timeout
            self.completion = completion
        }
    }

    private var commandQueue: [PendingCommand] = []
    private var pendingCommand: PendingCommand?
    private var responseBuffer = ""
    private var isResyncing = false
    private var pollTimers: [String: Timer] = [:]
    private var currentSample = TelemetrySample()
    private var discoveredPIDMasks: [Int: UInt32] = [:]
    private var currentHeader = PIDRegistry.functionalHeader
    private var scheduledHeader: String? = PIDRegistry.functionalHeader
    private var discoveryAttempts = 0

    private static let prompt: Character = ">"
    private static let maxQueueDepth = 64
    private static let maxBufferCharacters = 16_384

    // MARK: - Init

    init(transport: OBDTransport, timeScale: TimeInterval = 1.0) {
        self.transport = transport
        self.timeScale = max(0.001, timeScale)
        bindTransport()
    }

    private func bindTransport() {
        transport.connectedPublisher
            .sink { [weak self] connected in
                if connected {
                    self?.begin()
                } else {
                    self?.handleDisconnect()
                }
            }
            .store(in: &cancellables)

        transport.dataPublisher
            .sink { [weak self] data in
                self?.handleIncomingData(data)
            }
            .store(in: &cancellables)
    }

    // MARK: - Test / manual hooks

    /// Start the init sequence immediately. The app calls this through the
    /// connection publisher; tests call it directly.
    func begin() {
        startInitSequence()
    }

    /// Feed raw adapter text into the response buffer.
    func receive(_ text: String) {
        handleIncomingData(Data(text.utf8))
    }

    // MARK: - ELM327 Init Sequence

    private func startInitSequence() {
        isReady = false
        lastError = nil
        protocolCode = ""
        protocolName = ""
        supportedPIDs = []
        vin = ""
        responseBuffer = ""
        isResyncing = false
        commandQueue.removeAll()
        pendingCommand = nil
        currentSample = TelemetrySample()
        discoveredPIDMasks.removeAll()
        discoveryAttempts = 0
        currentHeader = PIDRegistry.functionalHeader
        scheduledHeader = PIDRegistry.functionalHeader

        let initCommands: [(String, TimeInterval)] = [
            ("ATZ", 5.0),     // Reset
            ("ATE0", 0.5),    // Echo off
            ("ATL0", 0.5),    // Linefeeds off
            ("ATS1", 0.5),    // Keep spaces — the parser consumes byte-separated frames
            ("ATH1", 0.5),    // Headers on (needed for multi-ECU / ISO-TP)
            ("ATAT1", 0.5),   // Adaptive timing 1
            ("ATSP0", 2.0),   // Auto-select protocol
            ("ATDPN", 1.0)    // Read the protocol number
        ]

        for (command, timeout) in initCommands {
            _ = enqueueRaw(command, timeout: timeout)
        }

        // First discovery range. No header switch is needed: 7DF is the
        // adapter's default after ATZ.
        _ = enqueueRaw("0100", timeout: 10.0)
        drainQueue()
    }

    private func handleDisconnect() {
        isReady = false
        lastError = nil
        stopPolling()
        commandQueue.removeAll()
        pendingCommand = nil
        responseBuffer = ""
        isResyncing = false
        discoveredPIDMasks.removeAll()
        supportedPIDs = []
        vin = ""
        currentHeader = PIDRegistry.functionalHeader
        scheduledHeader = PIDRegistry.functionalHeader
    }

    // MARK: - Command Queue

    @discardableResult
    private func enqueueRaw(
        _ command: String,
        timeout: TimeInterval,
        completion: ((String) -> Void)? = nil,
        allowDuplicate: Bool = false
    ) -> Bool {
        let normalized = command.uppercased()

        if !allowDuplicate {
            if pendingCommand?.command.uppercased() == normalized { return false }
            if commandQueue.contains(where: { $0.command.uppercased() == normalized }) { return false }
        }
        guard commandQueue.count < Self.maxQueueDepth else { return false }

        commandQueue.append(PendingCommand(command: command, timeout: timeout, completion: completion))
        return true
    }

    /// Enqueue a request, inserting an ATSH header change first when needed.
    private func enqueue(
        _ command: String,
        timeout: TimeInterval,
        header: String? = nil,
        completion: ((String) -> Void)? = nil,
        allowDuplicate: Bool = false
    ) {
        if let header, header != scheduledHeader {
            if enqueueRaw("ATSH\(header)", timeout: 1.0) {
                scheduledHeader = header
            }
        }
        _ = enqueueRaw(command, timeout: timeout, completion: completion, allowDuplicate: allowDuplicate)
    }

    private func drainQueue() {
        guard pendingCommand == nil, !commandQueue.isEmpty else { return }
        let next = commandQueue.removeFirst()
        pendingCommand = next
        responseBuffer = ""

        transport.send(next.command + "\r")

        let id = next.id
        DispatchQueue.main.asyncAfter(deadline: .now() + next.timeout * timeScale) { [weak self] in
            guard let self, self.pendingCommand?.id == id else { return }
            self.handleTimeout(for: next)
        }
    }

    private func handleTimeout(for command: PendingCommand) {
        pendingCommand = nil
        let upper = command.command.uppercased()
        lastError = "No response to \(command.command)"

        if upper.hasPrefix("ATSH") {
            currentHeader = ""
            scheduledHeader = nil
        }

        // A timed-out discovery request must not leave the session permanently
        // un-ready. Retry 0100 once, then finish with an explicit error so the
        // BMS poll and the UI still come up.
        if ["0100", "0120", "0140"].contains(upper) {
            if upper == "0100", discoveryAttempts < 1 {
                discoveryAttempts += 1
                _ = enqueueRaw("0100", timeout: 10.0, allowDuplicate: true)
            } else {
                finishInit()
            }
        }

        // Flush the adapter and discard anything it still owes us. Without
        // this, a late ">" would complete the next command with stale bytes.
        responseBuffer = ""
        isResyncing = true
        transport.send("\r")

        // If the adapter does not emit its prompt, do not stall forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 * timeScale) { [weak self] in
            guard let self, self.isResyncing else { return }
            self.isResyncing = false
            self.responseBuffer = ""
            self.drainQueue()
        }
    }

    // MARK: - Response Handling

    private func handleIncomingData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { return }

        responseBuffer += text
        if responseBuffer.count > Self.maxBufferCharacters {
            responseBuffer = String(responseBuffer.suffix(4_096))
        }

        while let promptIndex = responseBuffer.firstIndex(of: Self.prompt) {
            let chunk = String(responseBuffer[responseBuffer.startIndex...promptIndex])
            responseBuffer.removeSubrange(responseBuffer.startIndex...promptIndex)

            if isResyncing {
                // Discard the late reply plus the flush prompt.
                isResyncing = false
                responseBuffer = ""
                drainQueue()
                continue
            }

            guard let command = pendingCommand else { continue }
            complete(chunk, command: command)
        }
    }

    private func complete(_ raw: String, command: PendingCommand) {
        pendingCommand = nil

        let cleaned = clean(raw, command: command.command)
        command.completion?(cleaned)
        rawResponses.send(RawOBDFrame(request: command.command, response: raw))

        processResponse(cleaned, forCommand: command.command)
        drainQueue()
    }

    /// Strip the prompt and an optional first-line echo without touching data.
    private func clean(_ raw: String, command: String) -> String {
        let text = raw.replacingOccurrences(of: ">", with: "")
        var lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let first = lines.first, first.caseInsensitiveCompare(command) == .orderedSame {
            lines.removeFirst()
        }
        return lines.joined(separator: "\r")
    }

    // MARK: - Response Dispatch

    private func processResponse(_ response: String, forCommand command: String) {
        let upper = command.uppercased()

        switch upper {
        case "ATZ":
            break

        case "ATE0", "ATL0", "ATS1", "ATH1", "ATAT1", "ATSP0":
            if !response.uppercased().contains("OK") {
                lastError = "Adapter rejected \(upper)"
            }

        case "ATDPN":
            protocolCode = response.trimmingCharacters(in: .whitespacesAndNewlines)
            protocolName = Self.protocolName(for: protocolCode)

        case "0100":
            handleDiscovery(response, range: 0x00)
        case "0120":
            handleDiscovery(response, range: 0x20)
        case "0140":
            handleDiscovery(response, range: 0x40)

        case "220101":
            decodeBMS(response)

        case "22F190":
            if let value = OBDResponseParser.parseVIN(response) {
                vin = value
            }

        case "22B002":
            if let value = OBDResponseParser.parseOdometer(response) {
                decodeOdometer(value)
            }

        case "220102": decodeCellVoltages(response, did: 0x02, firstIndex: 1)
        case "220103": decodeCellVoltages(response, did: 0x03, firstIndex: 33)
        case "220104": decodeCellVoltages(response, did: 0x04, firstIndex: 65)
        case "22010A": decodeCellVoltages(response, did: 0x0A, firstIndex: 97)
        case "22010B": decodeCellVoltages(response, did: 0x0B, firstIndex: 129)
        case "22010C": decodeCellVoltages(response, did: 0x0C, firstIndex: 161)

        case "220105":
            decodeBatteryHealth(response)

        case "220111":
            decodeChargingCounters(response)

        case "22E011":
            decodeLDC(response)

        case "22C00B":
            decodeTirePressures(response)

        default:
            if upper.hasPrefix("ATSH") {
                currentHeader = String(upper.dropFirst(4))
                scheduledHeader = currentHeader
                if !response.uppercased().contains("OK") {
                    lastError = "Header change rejected: \(upper)"
                }
            } else {
                decodeStandard(response, command: upper)
            }
        }
    }

    // MARK: - Discovery

    private func handleDiscovery(_ response: String, range: Int) {
        let mask: UInt32?
        switch range {
        case 0x00: mask = OBDResponseParser.parseSupportedPIDs00(response)
        case 0x20: mask = OBDResponseParser.parseSupportedPIDs20(response)
        default:   mask = OBDResponseParser.parseSupportedPIDs40(response)
        }

        guard let mask else {
            if range == 0x00, discoveryAttempts < 1 {
                // One retry — the first request can race the protocol search.
                discoveryAttempts += 1
                _ = enqueueRaw("0100", timeout: 10.0, allowDuplicate: true)
                return
            }
            lastError = "Vehicle did not report supported PIDs"
            finishInit()
            return
        }

        discoveredPIDMasks[range] = mask
        updateSupportedPIDList()
        lastError = nil

        if (mask & 1) != 0, range < 0x40 {
            let next = range + 0x20
            let command = String(format: "%04X", 0x0100 + next)
            _ = enqueueRaw(command, timeout: 3.0)
        } else {
            finishInit()
        }
    }

    private func updateSupportedPIDList() {
        var list: [String] = []
        for pid in 1...0x60 where isSupported(pid) {
            list.append(String(format: "%02X", pid))
        }
        supportedPIDs = list
    }

    private func isSupported(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        let group = (pid - 1) / 32
        let position = (pid - 1) % 32
        guard let mask = discoveredPIDMasks[group * 0x20] else { return false }
        return (mask & (UInt32(1) << UInt32(31 - position))) != 0
    }

    private func finishInit() {
        guard !isReady else { return }
        isReady = true
        startPolling()
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        currentSample = TelemetrySample()

        let masks = [0x00, 0x20, 0x40].map { discoveredPIDMasks[$0] ?? 0 }
        for pid in PIDRegistry.activeStandardPIDs(supportedBy: masks) {
            schedule(pid)
        }
        // Always poll the BMS once discovery is done; the parser preserves the
        // raw frame even while the byte offsets remain candidates.
        schedule(PIDRegistry.hyundaiBMS)

        schedule(PIDRegistry.batteryHealth)
        schedule(PIDRegistry.ldcStatus)
        schedule(PIDRegistry.chargingCounters)
        for pid in PIDRegistry.cellVoltagePIDs {
            schedule(pid)
        }
        schedule(PIDRegistry.tirePressures)

        // Identity and odometer are read-only and low-rate.
        schedule(PIDRegistry.odometer)
        schedule(PIDRegistry.vin)
    }

    func stopPolling() {
        pollTimers.values.forEach { $0.invalidate() }
        pollTimers.removeAll()
    }

    private func schedule(_ pid: PIDDefinition) {
        let timer = Timer.scheduledTimer(withTimeInterval: pid.interval, repeats: true) { [weak self] _ in
            self?.request(pid)
        }
        pollTimers[pid.id] = timer
        request(pid)
    }

    private func request(_ pid: PIDDefinition) {
        guard isReady else { return }
        enqueue(pid.command, timeout: pid.timeout, header: pid.header)
    }

    // MARK: - Telemetry Decoding

    private func decodeStandard(_ response: String, command: String) {
        guard !OBDResponseParser.isError(response) else { return }

        var sample = currentSample.snapshot(at: .now)
        var updated = false

        switch command {
        case "010D":
            if let value = OBDResponseParser.parseSpeed(response) {
                sample.speedKmh = value
                updated = true
            }
        case "010C":
            if let value = OBDResponseParser.parseRPM(response) {
                sample.motorRPM = value
                updated = true
            }
        case "0111":
            if let value = OBDResponseParser.parseThrottlePosition(response) {
                sample.acceleratorPercent = value
                updated = true
            }
        case "0146":
            if let value = OBDResponseParser.parseAmbientTemp(response) {
                sample.ambientTemperatureC = value
                updated = true
            }
        default:
            break
        }

        guard updated else { return }
        currentSample = sample
        sampleUpdates.send(sample)
    }

    private func decodeTirePressures(_ response: String) {
        guard let tires = OBDResponseParser.parseTirePressures(response) else { return }
        var sample = currentSample.snapshot(at: .now)
        sample.tirePressuresBar = [
            tires.frontLeftBar, tires.frontRightBar, tires.rearLeftBar, tires.rearRightBar
        ]
        sample.tireTemperaturesC = [
            tires.frontLeftC, tires.frontRightC, tires.rearLeftC, tires.rearRightC
        ]
        currentSample = sample
        sampleUpdates.send(sample)
    }

    private func decodeCellVoltages(_ response: String, did: UInt8, firstIndex: Int) {
        guard let cells = OBDResponseParser.parseCellVoltages(response, did: did, firstIndex: firstIndex) else {
            return
        }
        var sample = currentSample.snapshot(at: .now)
        if sample.cellVoltages.count != 192 {
            sample.cellVoltages = Array(repeating: nil, count: 192)
        }
        for (index, value) in cells where index >= 1 && index <= 192 {
            sample.cellVoltages[index - 1] = value
        }
        currentSample = sample
        sampleUpdates.send(sample)
    }

    private func decodeBatteryHealth(_ response: String) {
        guard let health = OBDResponseParser.parseBatteryHealth(response) else { return }
        var sample = currentSample.snapshot(at: .now)
        if let soh = health.sohPercent { sample.sohPercent = soh }
        if let remaining = health.remainingEnergyKWh { sample.remainingEnergyKWh = remaining }
        currentSample = sample
        sampleUpdates.send(sample)
    }

    private func decodeChargingCounters(_ response: String) {
        guard let counters = OBDResponseParser.parseChargingCounters(response) else { return }
        var sample = currentSample.snapshot(at: .now)
        sample.normalChargeCount = counters.normalChargeCount
        sample.quickChargeCount = counters.quickChargeCount
        sample.normalChargeEnergyKWh = counters.normalChargeEnergyKWh
        sample.quickChargeEnergyKWh = counters.quickChargeEnergyKWh
        currentSample = sample
        sampleUpdates.send(sample)
    }

    private func decodeLDC(_ response: String) {
        guard let ldc = OBDResponseParser.parseLDCStatus(response) else { return }
        var sample = currentSample.snapshot(at: .now)
        if let value = ldc.temperatureC { sample.ldcTemperatureC = value }
        if let value = ldc.outputVoltageV { sample.ldcOutputVoltageV = value }
        if let value = ldc.outputCurrentA { sample.ldcOutputCurrentA = value }
        if let value = ldc.auxiliaryCurrentA { sample.auxiliaryCurrentA = value }
        if let value = ldc.auxiliarySOCPercent { sample.auxiliarySOCPercent = value }
        currentSample = sample
        sampleUpdates.send(sample)
    }

    private func decodeOdometer(_ value: Double) {
        var sample = currentSample.snapshot(at: .now)
        sample.odometerKm = value
        currentSample = sample
        sampleUpdates.send(sample)
    }

    private func decodeBMS(_ response: String) {
        guard !OBDResponseParser.isError(response) else {
            lastError = "BMS request returned an error"
            return
        }
        guard let status = OBDResponseParser.parseBMSStatus(response) else {
            lastError = "BMS reply not decoded (raw frame preserved)"
            return
        }

        var sample = currentSample.snapshot(at: .now)
        if let soc = status.socPercent { sample.socPercent = soc }
        if let voltage = status.packVoltageV { sample.batteryVoltageV = voltage }
        if let current = status.packCurrentA { sample.batteryCurrentA = current }
        if let maxTemperature = status.maxTemperatureC { sample.batteryTemperatureC = maxTemperature }
        if let minTemperature = status.minTemperatureC { sample.batteryMinTemperatureC = minTemperature }
        if let inletTemperature = status.inletTemperatureC { sample.batteryInletTemperatureC = inletTemperature }
        if let maxCellVoltage = status.maxCellVoltageV { sample.cellVoltageMaxV = maxCellVoltage }
        if let minCellVoltage = status.minCellVoltageV { sample.cellVoltageMinV = minCellVoltage }
        if let auxiliaryVoltage = status.auxiliaryVoltageV { sample.auxiliaryVoltageV = auxiliaryVoltage }
        if let isolation = status.isolationResistanceKOhm { sample.isolationResistanceKOhm = isolation }
        if let charging = status.isCharging { sample.isCharging = charging }
        sample.bmsRawPayload = status.rawPayloadHex

        if let voltage = status.packVoltageV, let current = status.packCurrentA {
            sample.batteryPowerKW = (voltage * current) / 1_000.0
        } else {
            sample.batteryPowerKW = nil
        }

        currentSample = sample
        lastError = nil
        sampleUpdates.send(sample)
    }

    // MARK: - Protocol names

    private static func protocolName(for code: String) -> String {
        switch code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "1": return "SAE J1850 PWM"
        case "2": return "SAE J1850 VPW"
        case "3": return "ISO 9141-2"
        case "4": return "ISO 14230-4 KWP (5 baud init)"
        case "5": return "ISO 14230-4 KWP (fast init)"
        case "6", "A6": return "ISO 15765-4 CAN (11-bit, 500 kbit/s)"
        case "7", "A7": return "ISO 15765-4 CAN (29-bit, 500 kbit/s)"
        case "8", "A8": return "ISO 15765-4 CAN (11-bit, 250 kbit/s)"
        case "9", "A9": return "ISO 15765-4 CAN (29-bit, 250 kbit/s)"
        default:
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "" : "Protocol \(trimmed)"
        }
    }
}

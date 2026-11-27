import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE Transport
// Manages CoreBluetooth connection to the vLinker iCar Pro BLE 4.0 adapter.
// vLinker and iCar firmware has several known ELM327 serial-over-BLE layouts.
// A complete known profile is verified before any OBD request is sent.

final class BLETransport: NSObject, ObservableObject {

    struct DiscoveredAdapter: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    // MARK: - Published state

    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var connected = false
    @Published private(set) var statusMessage = "Not connected"
    @Published private(set) var discoveredAdapters: [DiscoveredAdapter] = []

    /// True while user-enabled demo mode shows a fake connection; stops the
    /// CoreBluetooth state callback from overwriting the demo header.
    @Published private(set) var isDemo = false

    /// True when the system denied Bluetooth access. The UI offers a Settings
    /// shortcut because the permission prompt cannot be shown a second time.
    var isPermissionDenied: Bool { state == .unauthorized }

    // Incoming data stream — raw bytes from the adapter
    let incomingData = PassthroughSubject<Data, Never>()

    // MARK: - Known UART profiles
    // Unknown characteristics are never written.
    private struct UARTProfile {
        let name: String
        let service: CBUUID
        let notify: CBUUID
        let write: CBUUID
    }

    private let uartProfiles = [
        UARTProfile(name: "vLinker / iCar Pro", service: CBUUID(string: "18F0"), notify: CBUUID(string: "2AF0"), write: CBUUID(string: "2AF1")),
        UARTProfile(name: "iCar Pro custom", service: CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2"), notify: CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F"), write: CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")),
        UARTProfile(name: "BLE serial FFF0", service: CBUUID(string: "FFF0"), notify: CBUUID(string: "FFF1"), write: CBUUID(string: "FFF2")),
        UARTProfile(name: "BLE serial FFE0", service: CBUUID(string: "FFE0"), notify: CBUUID(string: "FFE1"), write: CBUUID(string: "FFE1")),
        UARTProfile(name: "Nordic UART", service: CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"), notify: CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"), write: CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"))
    ]

    // MARK: - Private

    // Created lazily so the Bluetooth permission prompt appears when the user
    // first asks to connect (or on launch only if they connected before and the
    // permission is already decided) — never as an unexplained first-launch alert.
    private var centralCreated = false
    private lazy var central: CBCentralManager = {
        centralCreated = true
        return CBCentralManager(delegate: self, queue: .main)
    }()
    private var scanWhenReady = false
    private static let lastAdapterKey = "lastAdapterID"
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var pendingProfile: UARTProfile?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    // Discovery is intentionally short and local: only adapters advertising a
    // known UART service or a recognisable name, only reasonably close, at most
    // six entries, and stale entries are dropped after five minutes.
    private var scanTimer: Timer?
    private var purgeTimer: Timer?
    private var lastSeen: [UUID: Date] = [:]
    private let scanWindow: TimeInterval = 12
    private let staleAfter: TimeInterval = 300
    private let maximumVisibleAdapters = 6

    // MARK: - Init

    override init() {
        super.init()
        // A remembered adapter means Bluetooth permission was already decided,
        // so reconnecting at launch cannot surface a surprise prompt.
        if lastAdapterID != nil {
            _ = central
        }
    }

    private var lastAdapterID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.lastAdapterKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.lastAdapterKey) }
    }

    /// Forgets the remembered adapter so the app stops auto-reconnecting to it.
    func forgetAdapter() {
        lastAdapterID = nil
    }

    // MARK: - Public API

    func scan() {
        guard !isDemo else { return }
        guard centralCreated else {
            // First use: creating the manager triggers the system permission
            // prompt; the scan starts once Bluetooth reports poweredOn.
            scanWhenReady = true
            statusMessage = "Starting Bluetooth…"
            _ = central
            return
        }
        guard central.state == .poweredOn else {
            statusMessage = state == .unauthorized ? "Bluetooth permission denied" : "Bluetooth not ready"
            return
        }
        central.stopScan()
        discoveredAdapters.removeAll()
        discoveredPeripherals.removeAll()
        lastSeen.removeAll()
        statusMessage = "Scanning for OBD2 adapters…"

        // No service filter: some adapter firmware does not advertise its UART
        // service. Relevance is checked in didDiscover and the characteristic is
        // verified before any command is sent.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])

        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanWindow, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.central.stopScan()
            if self.discoveredAdapters.isEmpty {
                self.statusMessage = "No OBD2 adapter nearby — move closer and rescan"
            } else {
                self.statusMessage = "Scan complete — select your OBD2 adapter"
            }
        }

        purgeTimer?.invalidate()
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.purgeStaleAdapters()
        }
    }

    func connect(to adapterID: UUID) {
        guard let peripheral = discoveredPeripherals[adapterID] else {
            statusMessage = "Adapter is no longer available — scan again"
            return
        }
        self.peripheral = peripheral
        central.stopScan()
        scanTimer?.invalidate()
        statusMessage = "Connecting to \(peripheral.name ?? "adapter")…"
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        reconnectAttempts = maxReconnectAttempts  // Suppress auto-reconnect
        guard centralCreated, let p = peripheral else { return }
        central.cancelPeripheralConnection(p)
    }

    /// Write a string to the ELM327 TX characteristic.
    func send(string: String) {
        guard let p = peripheral, let ch = txCharacteristic else { return }
        guard let data = string.data(using: .utf8) else { return }
        // ELM327 adapters accept write-without-response for speed
        let type: CBCharacteristicWriteType = ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        p.writeValue(data, for: ch, type: type)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLETransport: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !isDemo else { return }
        state = central.state
        switch central.state {
        case .poweredOn:
            statusMessage = "Ready to scan"
            if reconnectToLastAdapter() { break }
            if scanWhenReady {
                scanWhenReady = false
                scan()
            }
        case .poweredOff:
            statusMessage = "Bluetooth off"
            connected = false
        case .unauthorized:
            statusMessage = "Bluetooth permission denied"
        case .unsupported:
            statusMessage = "BLE unsupported"
        default:
            statusMessage = "Bluetooth unavailable"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssi = RSSI.intValue
        guard rssi < 0, rssi >= -85 else { return }
        guard isRelevantAdapter(peripheral, advertisementData: advertisementData) else { return }

        discoveredPeripherals[peripheral.identifier] = peripheral
        lastSeen[peripheral.identifier] = .now

        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "Nearby adapter"
        let adapter = DiscoveredAdapter(id: peripheral.identifier, name: name, rssi: rssi)

        if let index = discoveredAdapters.firstIndex(where: { $0.id == adapter.id }) {
            discoveredAdapters[index] = adapter
        } else {
            discoveredAdapters.append(adapter)
        }

        discoveredAdapters.sort { $0.rssi > $1.rssi }
        if discoveredAdapters.count > maximumVisibleAdapters {
            discoveredAdapters = Array(discoveredAdapters.prefix(maximumVisibleAdapters))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected = false
        reconnectAttempts = 0
        statusMessage = "Connected — discovering services…"
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        statusMessage = "Connection failed: \(error?.localizedDescription ?? "unknown")"
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connected = false
        txCharacteristic = nil
        rxCharacteristic = nil
        pendingProfile = nil
        statusMessage = "Disconnected"
        if error != nil {
            scheduleReconnect()
        }
    }

    /// Reconnects to the adapter used last time without scanning. A pending
    /// CoreBluetooth connection completes as soon as the adapter powers up
    /// (e.g. when the car is switched on), so a returning user needs no taps.
    private func reconnectToLastAdapter() -> Bool {
        guard !connected, peripheral == nil,
              let id = lastAdapterID,
              let known = central.retrievePeripherals(withIdentifiers: [id]).first else { return false }
        discoveredPeripherals[id] = known
        peripheral = known
        reconnectAttempts = 0
        statusMessage = "Connecting to \(known.name ?? "adapter")…"
        central.connect(known, options: nil)
        return true
    }

    private func isRelevantAdapter(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        if advertisedServices.contains(where: { uuid in uartProfiles.contains { $0.service == uuid } }) {
            return true
        }

        let name = ((advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "").lowercased()
        let keywords = ["vlinker", "icar", "obd", "obd2", "elm", "vgate", "konnwei", "obdlink"]
        return keywords.contains { name.contains($0) }
    }

    private func purgeStaleAdapters() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        let stale = lastSeen.filter { $0.value < cutoff }.map(\.key)
        guard !stale.isEmpty else { return }

        for id in stale {
            lastSeen.removeValue(forKey: id)
            discoveredPeripherals.removeValue(forKey: id)
            discoveredAdapters.removeAll { $0.id == id }
        }
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            statusMessage = "Could not connect — tap to retry"
            return
        }
        reconnectAttempts += 1
        let delay = Double(reconnectAttempts) * 2.0
        statusMessage = "Reconnecting in \(Int(delay))s… (attempt \(reconnectAttempts))"
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            if let p = self?.peripheral {
                self?.central.connect(p)
            } else {
                self?.scan()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLETransport: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            statusMessage = "Service discovery failed"
            return
        }
        let uartServices = services.filter { service in
            uartProfiles.contains { $0.service == service.uuid }
        }
        guard !uartServices.isEmpty else {
            statusMessage = "vLinker UART service not found — no OBD commands sent"
            return
        }
        for service in uartServices {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            statusMessage = "Characteristic discovery failed"
            return
        }
        guard let profile = uartProfiles.first(where: { $0.service == service.uuid }),
              let notify = characteristics.first(where: { $0.uuid == profile.notify }),
              let write = characteristics.first(where: { $0.uuid == profile.write }) else {
            statusMessage = "vLinker UART characteristic not found — no OBD commands sent"
            return
        }
        guard write.properties.contains(.write) || write.properties.contains(.writeWithoutResponse) else {
            statusMessage = "Adapter UART cannot accept writes"
            return
        }
        guard notify.properties.contains(.notify) || notify.properties.contains(.indicate) else {
            statusMessage = "Adapter UART cannot send responses — no OBD commands sent"
            return
        }
        txCharacteristic = write
        rxCharacteristic = notify
        pendingProfile = profile
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        incomingData.send(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            statusMessage = "Notification error: \(error.localizedDescription)"
        } else if characteristic == rxCharacteristic {
            // OBDSession starts only after response notifications are enabled.
            connected = true
            lastAdapterID = peripheral.identifier
            statusMessage = "Ready — \(pendingProfile?.name ?? "BLE UART")"
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            AppLog.bluetooth.error("Write error: \(error.localizedDescription)")
        }
    }
}

// MARK: - OBDTransport

extension BLETransport: OBDTransport {
    var isConnected: Bool { connected }

    var connectedPublisher: AnyPublisher<Bool, Never> {
        $connected.eraseToAnyPublisher()
    }

    var dataPublisher: AnyPublisher<Data, Never> {
        incomingData.eraseToAnyPublisher()
    }

    func send(_ command: String) {
        send(string: command)
    }
}

// MARK: - Demo connection

extension BLETransport {
    /// Shows a labelled fake connection so the app can be explored without an
    /// adapter. Never sends anything: no UART characteristic is ever set.
    func setDemoConnection(_ enabled: Bool) {
        guard enabled != isDemo else { return }
        isDemo = enabled
        if enabled {
            connected = true
            statusMessage = "Demo data"
        } else {
            connected = false
            statusMessage = "Not connected"
        }
    }
}

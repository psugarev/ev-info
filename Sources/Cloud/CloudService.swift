import Foundation
import SwiftData

// MARK: - Cloud service
// Owns the Pleos account for this personal build: credentials in the Keychain,
// a SwiftData cache of the last snapshot, manual/periodic refresh, and the
// cross-check between cloud-reported SOC and the decoded BMS value.

@MainActor
final class CloudService: ObservableObject {

    enum State: Equatable {
        case notConfigured
        case connecting
        case connected
        case error(String)
    }

    struct Comparison: Equatable {
        let cloudSOC: Double
        let bmsSOC: Double
        let deltaPercent: Double

        /// Within 3 % the BMS decode is treated as confirmed by the car's server.
        var agrees: Bool { abs(deltaPercent) <= 3 }
    }

    /// A cloud snapshot older than this is shown as "last known" and triggers a
    /// refresh when the app becomes active.
    static let staleAfterSeconds: TimeInterval = 600
    static let brandKey = "cloudPLEOSBrand"
    static let vinKey = "cloudPLEOSVIN"

    @Published private(set) var state: State = .notConfigured
    @Published private(set) var snapshot: CloudVehicleSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var vehicles: [String] = []
    @Published var brand: PleosBrand {
        didSet { UserDefaults.standard.set(brand.rawValue, forKey: Self.brandKey) }
    }

    private let modelContext: ModelContext
    private let clientFactory: (CloudCredentials, PleosBrand) -> PleosClient
    private var vin: String?

    init(
        modelContext: ModelContext,
        clientFactory: @escaping (CloudCredentials, PleosBrand) -> PleosClient = { credentials, brand in
            PleosClient(credentials: credentials, brand: brand)
        }
    ) {
        self.modelContext = modelContext
        self.clientFactory = clientFactory
        let storedBrand = UserDefaults.standard.string(forKey: Self.brandKey) ?? ""
        self.brand = PleosBrand(rawValue: storedBrand) ?? .hyundai
        self.vin = UserDefaults.standard.string(forKey: Self.vinKey)
        loadCachedSnapshot()
        if currentCredentials != nil {
            state = .connected
        }
    }

    // MARK: - Public state

    var isConfigured: Bool { currentCredentials != nil }

    var currentCredentials: CloudCredentials? {
        guard let id = KeychainStore.read(account: "clientId"),
              let secret = KeychainStore.read(account: "clientSecret") else { return nil }
        let credentials = CloudCredentials(clientId: id, clientSecret: secret)
        return credentials.isComplete ? credentials : nil
    }

    var lastUpdatedText: String? {
        guard let snapshot else { return nil }
        return snapshot.fetchedAt.formatted(
            Date.FormatStyle().day().month(.abbreviated).hour().minute().locale(AppLocalization.locale)
        )
    }

    /// Cross-check the cloud SOC against the live BMS decode (AGENTS rule 3).
    func comparison(bmsSOC: Double?) -> Comparison? {
        guard let cloud = snapshot?.socPercent, let bmsSOC, bmsSOC > 0, cloud > 0 else { return nil }
        return Comparison(cloudSOC: cloud, bmsSOC: bmsSOC, deltaPercent: cloud - bmsSOC)
    }

    // MARK: - Account

    /// Saves the credentials, verifies them against Pleos and stores the VIN.
    func connect(clientId: String, clientSecret: String, brand: PleosBrand) async throws {
        let credentials = CloudCredentials(
            clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard credentials.isComplete else { throw CloudError.authFailed }
        self.brand = brand
        state = .connecting
        let client = clientFactory(credentials, brand)
        do {
            let vins = try await client.vehicles()
            guard KeychainStore.save(credentials.clientId, account: "clientId"),
                  KeychainStore.save(credentials.clientSecret, account: "clientSecret") else {
                throw CloudError.invalidResponse
            }
            vehicles = vins
            vin = vins.first
            UserDefaults.standard.set(vin, forKey: Self.vinKey)
            state = .connected
            lastError = nil
            try await refresh(client: client)
        } catch {
            state = .error(error.localizedDescription)
            lastError = error.localizedDescription
            throw error
        }
    }

    func disconnect() {
        KeychainStore.delete(account: "clientId")
        KeychainStore.delete(account: "clientSecret")
        UserDefaults.standard.removeObject(forKey: Self.vinKey)
        vin = nil
        snapshot = nil
        vehicles = []
        state = .notConfigured
        lastError = nil
        clearCachedSnapshots()
    }

    // MARK: - Refresh

    func refreshIfStale() async {
        guard isConfigured else { return }
        if let snapshot, !snapshot.isStale { return }
        await refresh()
    }

    func refresh() async {
        guard let credentials = currentCredentials, let vin, !vin.isEmpty else {
            state = .notConfigured
            return
        }
        state = .connecting
        do {
            let client = clientFactory(credentials, brand)
            try await refresh(client: client)
        } catch {
            state = .error(error.localizedDescription)
            lastError = error.localizedDescription
            AppLog.cloud.error("Cloud refresh failed: \(error.localizedDescription)")
        }
    }

    private func refresh(client: PleosClient) async throws {
        guard let vin else { throw CloudError.noVehicles }
        let data = try await client.snapshot(vin: vin)
        AppLog.cloud.info("Cloud snapshot refreshed: soc=\(data.displaySOCPercent != nil), charging=\(data.isCharging != nil), range=\(data.rangeKm != nil)")
        persist(data)
        snapshot = cachedSnapshot(for: data.vin)
        state = .connected
        lastError = nil
    }

    // MARK: - Cache

    private func loadCachedSnapshot() {
        guard let vin else { return }
        snapshot = cachedSnapshot(for: vin)
    }

    private func cachedSnapshot(for vin: String) -> CloudVehicleSnapshot? {
        let descriptor = FetchDescriptor<CloudVehicleSnapshot>(
            predicate: #Predicate { $0.vin == vin }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func persist(_ data: CloudVehicleData) {
        if let existing = cachedSnapshot(for: data.vin) {
            existing.update(data)
        } else {
            modelContext.insert(CloudVehicleSnapshot(data))
        }
        try? modelContext.save()
    }

    private func clearCachedSnapshots() {
        try? modelContext.delete(model: CloudVehicleSnapshot.self)
        try? modelContext.save()
    }
}

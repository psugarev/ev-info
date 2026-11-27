import Foundation

// MARK: - Pleos personal Vehicle Data API client
// Official read-only API (https://api.pleos.ai). Personal Client ID/Secret are
// exchanged for a one-hour access token; the token is refreshed once when the
// API answers 401/403. Only GET requests are ever sent to vehicle endpoints.
//
// Endpoints used: batteries, powertrains, driving, status, locations.
// No command endpoint exists in this client by design (AGENTS.md rule 1).

enum PleosBrand: String, CaseIterable, Codable, Identifiable {
    case hyundai
    case kia
    case genesis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hyundai: return "Hyundai"
        case .kia: return "Kia"
        case .genesis: return "Genesis"
        }
    }
}

protocol PleosTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionPleosTransport: PleosTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
        return (data, http)
    }
}

final class PleosClient: @unchecked Sendable {
    static let baseURL = URL(string: "https://api.pleos.ai")!
    static let snapshotEndpoints = ["batteries", "powertrains", "driving", "status", "locations"]

    private let credentials: CloudCredentials
    private let brand: PleosBrand
    private let transport: PleosTransport
    private let now: () -> Date

    private var token: String?
    private var tokenExpiry: Date?
    private var rateLimitedUntil: Date?

    init(
        credentials: CloudCredentials,
        brand: PleosBrand,
        transport: PleosTransport = URLSessionPleosTransport(),
        now: @escaping () -> Date = Date.init
    ) {
        self.credentials = credentials
        self.brand = brand
        self.transport = transport
        self.now = now
    }

    // MARK: - Public API

    /// VINs authorised for this personal key.
    func vehicles() async throws -> [String] {
        let data = try await request(path: "/v1/vehicles/consent")
        guard let dict = data as? [String: Any],
              let list = dict["vehicles"] as? [[String: Any]] else {
            throw CloudError.invalidResponse
        }
        let vins = list.compactMap { $0["vin"] as? String }.filter { !$0.isEmpty }
        guard !vins.isEmpty else { throw CloudError.noVehicles }
        return vins
    }

    /// One read-only snapshot of the selected vehicle.
    func snapshot(vin: String, fetchedAt: Date = .now) async throws -> CloudVehicleData {
        guard !vin.isEmpty, !vin.contains("/") else { throw CloudError.invalidResponse }
        var payloads: [String: Any] = [:]
        for endpoint in Self.snapshotEndpoints {
            payloads[endpoint] = try await request(path: "/v1/vehicles/\(vin)/\(endpoint)")
        }
        return PleosSnapshotParser.parse(vin: vin, fetchedAt: fetchedAt, payloads: payloads)
    }

    // MARK: - Transport

    private func request(path: String) async throws -> Any {
        if let until = rateLimitedUntil, now() < until {
            throw CloudError.rateLimited(retryAfter: until.timeIntervalSince(now()))
        }
        for attempt in 0...1 {
            let token = try await accessToken()
            var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
            request.httpMethod = "GET"
            request.setValue(brand.rawValue, forHTTPHeaderField: "Brand")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30
            let (data, response) = try await transport.send(request)

            if response.statusCode == 429 {
                let seconds = Self.retryAfter(from: response) ?? 300
                rateLimitedUntil = now().addingTimeInterval(max(300, seconds))
                throw CloudError.rateLimited(retryAfter: max(300, seconds))
            }
            let envelope = try Self.envelope(from: data, status: response.statusCode)
            if response.statusCode == 401 || response.statusCode == 403, attempt == 0 {
                invalidateToken()
                continue
            }
            if let error = envelope.error {
                throw error
            }
            return envelope.data ?? [:]
        }
        invalidateToken()
        throw CloudError.authFailed
    }

    private func accessToken() async throws -> String {
        if let token, let expiry = tokenExpiry, now() < expiry { return token }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("/v1/auth/personal-token"))
        request.httpMethod = "POST"
        request.setValue(brand.rawValue, forHTTPHeaderField: "Brand")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "clientId": credentials.clientId,
            "clientSecret": credentials.clientSecret
        ])
        let (data, response) = try await transport.send(request)
        if response.statusCode == 401 || response.statusCode == 403 {
            throw CloudError.authFailed
        }
        let envelope = try Self.envelope(from: data, status: response.statusCode)
        if let error = envelope.error { throw error }
        guard let dict = envelope.data as? [String: Any],
              let access = dict["accessToken"] as? String, !access.isEmpty else {
            throw CloudError.invalidResponse
        }
        token = access
        // Tokens live for one hour; refresh a little early.
        tokenExpiry = now().addingTimeInterval(55 * 60)
        return access
    }

    private func invalidateToken() {
        token = nil
        tokenExpiry = nil
    }

    // MARK: - Response handling

    private struct Envelope {
        let data: Any?
        let error: CloudError?
    }

    private static func envelope(from data: Data, status: Int) throws -> Envelope {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudError.invalidResponse
        }
        let meta = payload["meta"] as? [String: Any] ?? [:]
        let success = meta["success"] as? Bool ?? (status < 300 && payload["error"] == nil)
        if success {
            return Envelope(data: payload["data"], error: nil)
        }
        let errorCode: String
        if let error = payload["error"] as? [String: Any], let code = error["code"] {
            errorCode = "\(code)"
        } else if let code = meta["code"] {
            errorCode = "\(code)"
        } else {
            errorCode = "unknown"
        }
        if status == 401 || status == 403 || ["401", "4011", "40003", "40004"].contains(errorCode) {
            return Envelope(data: nil, error: .authFailed)
        }
        if status == 429 || errorCode == "429" {
            return Envelope(data: nil, error: .rateLimited(retryAfter: 300))
        }
        return Envelope(data: nil, error: .http(status, errorCode))
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value) { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return date.timeIntervalSinceNow
    }
}

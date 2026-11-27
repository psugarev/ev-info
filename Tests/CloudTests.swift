import XCTest
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

final class CloudTests: XCTestCase {

    // MARK: - Parser

    private func wrapper(_ value: Any, _ unit: String? = nil) -> [String: Any] {
        var dict: [String: Any] = ["value": value]
        if let unit { dict["unit"] = unit }
        return dict
    }

    private func fixturePayloads() -> [String: Any] {
        [
            "batteries": [
                "charge": [
                    "stateOfCharge": wrapper(78, "%"),
                    "charging": wrapper("ON"),
                    "plugIn": wrapper(true),
                    "remainTime": wrapper(95, "min"),
                    "status": wrapper("charging"),
                    "batteryCapacity": wrapper(259_000, "kJ"),
                    "targetStateOfCharge": [
                        "standard": wrapper(80, "%"),
                        "quick": wrapper(90, "%")
                    ]
                ]
            ],
            "powertrains": [
                "batteries": ["main": ["remainRatio": wrapper(77, "%")]],
                "distanceToEmpties": [
                    ["type": "ice", "value": wrapper(0, "km")],
                    ["type": "ev", "value": wrapper(310, "miles")]
                ]
            ],
            "driving": [
                "odometer": wrapper(120_101, "km"),
                "transmission": ["parkingPosition": wrapper("P")]
            ],
            "status": [
                "outsideTemperature": wrapper(68, "F"),
                "climateControl": ["status": wrapper("OFF")],
                "doors": [
                    ["type": "row1Left", "value": "locked"],
                    ["type": "row1Right", "value": "locked"]
                ],
                "warnings": ["tirePressureFrontLeft"]
            ],
            "locations": [
                "location": [
                    "latitude": wrapper(42.6977, "°"),
                    "longitude": wrapper(23.3219, "°")
                ]
            ]
        ]
    }

    func testParserReadsTheDocumentedFields() throws {
        let snapshot = PleosSnapshotParser.parse(
            vin: "VINTEST",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            payloads: fixturePayloads()
        )
        XCTAssertEqual(snapshot.socPercent, 78)
        XCTAssertEqual(snapshot.isCharging, true)
        XCTAssertEqual(snapshot.isPluggedIn, true)
        XCTAssertEqual(snapshot.chargeRemainingMinutes, 95)
        XCTAssertEqual(snapshot.chargeStatusText, "charging")
        XCTAssertEqual(snapshot.batteryCapacityKWh ?? 0, 259_000 / 3_600, accuracy: 0.001)
        XCTAssertEqual(snapshot.targetSOCStandard, 80)
        XCTAssertEqual(snapshot.targetSOCQuick, 90)

        XCTAssertEqual(snapshot.powertrainSOCPercent, 77)
        // 310 miles → km
        XCTAssertEqual(snapshot.rangeKm ?? 0, 310 * 1.609_344, accuracy: 0.01)

        XCTAssertEqual(snapshot.odometerKm, 120_101)
        XCTAssertEqual(snapshot.isInPark, true)
        XCTAssertEqual(snapshot.latitude ?? 0, 42.6977, accuracy: 0.0001)
        XCTAssertEqual(snapshot.longitude ?? 0, 23.3219, accuracy: 0.0001)
        // 68 °F → 20 °C
        XCTAssertEqual(snapshot.outsideTemperatureC ?? 0, 20, accuracy: 0.01)
        XCTAssertEqual(snapshot.climateOn, false)
        XCTAssertEqual(snapshot.isLocked, true)
        XCTAssertEqual(snapshot.warnings, ["tirePressureFrontLeft"])
        XCTAssertEqual(snapshot.displaySOCPercent, 78)
    }

    func testParserDropsOutOfRangeAndUnknownUnits() {
        let payloads: [String: Any] = [
            "batteries": ["charge": [
                "stateOfCharge": wrapper(250, "%"),
                "batteryCapacity": wrapper(10, "furlongs")
            ]],
            "powertrains": ["distanceToEmpties": [
                ["type": "ev", "value": wrapper(50, "parsecs")]
            ]],
            "status": ["doors": [["type": "row1Left", "value": "open"]]]
        ]
        let snapshot = PleosSnapshotParser.parse(vin: "V", fetchedAt: .now, payloads: payloads)
        XCTAssertNil(snapshot.socPercent)
        XCTAssertNil(snapshot.batteryCapacityKWh)
        XCTAssertNil(snapshot.rangeKm)
        XCTAssertEqual(snapshot.isLocked, false)
        XCTAssertTrue(snapshot.warnings.isEmpty)
    }

    // MARK: - Client

    private final class FakeTransport: PleosTransport, @unchecked Sendable {
        var requests: [URLRequest] = []
        var responses: [(Int, Data)] = []
        var error: Error?

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            if let error { throw error }
            guard !responses.isEmpty else { throw CloudError.invalidResponse }
            let (status, data) = responses.removeFirst()
            let http = HTTPURLResponse(
                url: request.url ?? PleosClient.baseURL,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, http)
        }
    }

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func envelope(_ data: Any) -> Data {
        json(["meta": ["success": true, "code": "200"], "data": data])
    }

    private let credentials = CloudCredentials(clientId: "cid", clientSecret: "secret")

    func testClientAuthenticatesListsVehiclesAndFetchesSnapshot() async throws {
        let transport = FakeTransport()
        transport.responses = [
            (200, envelope(["accessToken": "token-1"])),
            (200, envelope(["vehicles": [["vin": "VIN1"]]]))
        ]
        for endpoint in PleosClient.snapshotEndpoints {
            var payload: [String: Any] = [:]
            if endpoint == "batteries" {
                payload["charge"] = ["stateOfCharge": wrapper(50, "%")]
            }
            transport.responses.append((200, envelope(payload)))
        }

        let client = PleosClient(credentials: credentials, brand: .hyundai, transport: transport)
        let vins = try await client.vehicles()
        XCTAssertEqual(vins, ["VIN1"])

        let snapshot = try await client.snapshot(vin: "VIN1")
        XCTAssertEqual(snapshot.socPercent, 50)

        // 1 token + 1 vehicle list + 5 endpoints.
        XCTAssertEqual(transport.requests.count, 7)
        let tokenRequest = transport.requests[0]
        XCTAssertEqual(tokenRequest.url?.path, "/v1/auth/personal-token")
        XCTAssertEqual(tokenRequest.value(forHTTPHeaderField: "Brand"), "hyundai")
        let body = try XCTUnwrap(tokenRequest.httpBody)
        let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(bodyObject["clientId"] as? String, "cid")

        let vehicleRequest = transport.requests[2]
        XCTAssertEqual(vehicleRequest.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
        XCTAssertEqual(vehicleRequest.httpMethod, "GET")
    }

    func testClientRefreshesAnExpiredTokenOnce() async throws {
        let transport = FakeTransport()
        transport.responses = [
            (200, envelope(["accessToken": "old"])),
            (401, json(["meta": ["success": false, "code": "401"], "error": ["code": "401"]])),
            (200, envelope(["accessToken": "new"])),
            (200, envelope(["vehicles": [["vin": "VIN1"]]]))
        ]
        let client = PleosClient(credentials: credentials, brand: .hyundai, transport: transport)
        let vins = try await client.vehicles()
        XCTAssertEqual(vins, ["VIN1"])
        XCTAssertEqual(transport.requests.count, 4)
        XCTAssertEqual(transport.requests[3].value(forHTTPHeaderField: "Authorization"), "Bearer new")
    }

    func testClientMapsInvalidCredentialsToAuthError() async throws {
        let transport = FakeTransport()
        transport.responses = [
            (401, json(["meta": ["success": false, "code": "40003"], "error": ["code": "40003"]]))
        ]
        let client = PleosClient(credentials: credentials, brand: .hyundai, transport: transport)
        do {
            _ = try await client.vehicles()
            XCTFail("expected auth failure")
        } catch let error as CloudError {
            XCTAssertEqual(error, .authFailed)
        }
    }

    func testClientReportsRateLimit() async throws {
        let transport = FakeTransport()
        transport.responses = [
            (200, envelope(["accessToken": "token"])),
            (429, json(["meta": ["success": false, "code": "429"]]))
        ]
        let client = PleosClient(credentials: credentials, brand: .hyundai, transport: transport)
        do {
            _ = try await client.vehicles()
            XCTFail("expected rate limit")
        } catch let error as CloudError {
            guard case .rateLimited = error else { return XCTFail("expected rate limited, got \(error)") }
        }
    }

    func testComparisonThreshold() {
        let same = CloudService.Comparison(cloudSOC: 66, bmsSOC: 66.5, deltaPercent: -0.5)
        XCTAssertTrue(same.agrees)
        let differs = CloudService.Comparison(cloudSOC: 70, bmsSOC: 66, deltaPercent: 4)
        XCTAssertFalse(differs.agrees)
    }
}

@testable import VoyagerFeaturesAccountAccess
import VoyagerShared
import XCTest

/// ACC-002: AccessStatusResponse backend wire-format 디코딩 및 toAccessStatus() 매핑 검증.
///
/// Backend `GET /access/status`가 반환하는 camelCase JSON을 AccessStatusResponse가 올바르게 디코딩하고,
/// `toAccessStatus()`가 raw status + productKey 조합을 canonical AccessStatus로 변환하는지 검증한다.
final class ACC002AccessStatusResponseCodingTests: XCTestCase {
    private var decoder: JSONDecoder = {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        return jsonDecoder
    }()

    // MARK: - Backend camelCase decode

    /// Backend JSON(camelCase)이 AccessStatusResponse로 올바르게 디코딩된다.
    func testBackendCamelCaseDecode() throws {
        let json = """
        {
            "hasAccess": true,
            "status": "active",
            "reason": "active_entitlement",
            "productKey": "trial",
            "currentPeriodEnd": "2026-07-05T00:00:00Z",
            "source": "polar"
        }
        """
        let data = Data(json.utf8)

        let response = try decoder.decode(AccessStatusResponse.self, from: data)

        XCTAssertTrue(response.hasAccess)
        XCTAssertEqual(response.status, "active")
        XCTAssertEqual(response.reason, "active_entitlement")
        XCTAssertEqual(response.productKey, "trial")
        XCTAssertNotNil(response.currentPeriodEnd)
        XCTAssertEqual(response.source, "polar")
    }

    /// optional 필드가 누락된 JSON이 nil로 디코딩된다.
    func testMissingOptionalFieldsDecodeAsNil() throws {
        let json = """
        {
            "hasAccess": false,
            "status": "none"
        }
        """
        let data = Data(json.utf8)

        let response = try decoder.decode(AccessStatusResponse.self, from: data)

        XCTAssertFalse(response.hasAccess)
        XCTAssertEqual(response.status, "none")
        XCTAssertNil(response.reason)
        XCTAssertNil(response.productKey)
        XCTAssertNil(response.currentPeriodEnd)
        XCTAssertNil(response.source)
    }

    /// currentPeriodEnd가 null인 JSON이 nil로 디코딩된다.
    func testNullCurrentPeriodEndDecodesAsNil() throws {
        let json = """
        {
            "hasAccess": true,
            "status": "active",
            "currentPeriodEnd": null
        }
        """
        let data = Data(json.utf8)

        let response = try decoder.decode(AccessStatusResponse.self, from: data)

        XCTAssertTrue(response.hasAccess)
        XCTAssertNil(response.currentPeriodEnd)
    }

    // MARK: - toAccessStatus() 매핑

    /// active + trial productKey → .trialActive
    func testToAccessStatusActiveTrial() {
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "trial",
            source: "polar",
        )
        XCTAssertEqual(response.toAccessStatus(), .trialActive)
    }

    /// active + core productKey → .coreLicenseActive
    func testToAccessStatusActiveCore() {
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )
        XCTAssertEqual(response.toAccessStatus(), .coreLicenseActive)
    }

    /// active + lifetime productKey → .coreLicenseActive
    func testToAccessStatusActiveLifetime() {
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            productKey: "lifetime",
        )
        XCTAssertEqual(response.toAccessStatus(), .coreLicenseActive)
    }

    /// active + null productKey → .coreLicenseActive (fallback)
    func testToAccessStatusActiveNullProductKey() {
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            productKey: nil,
        )
        XCTAssertEqual(response.toAccessStatus(), .coreLicenseActive)
    }

    /// Backend canonical status는 hasAccess fallback보다 우선한다.
    func testToAccessStatusCanonicalStatuses() {
        let cases: [(String, AccessStatus)] = [
            ("core_license_active", .coreLicenseActive),
            ("internal_test_active", .internalTestActive),
            ("trial_active", .trialActive),
            ("trial_expired", .trialExpired),
            ("revoked", .revoked),
            ("refunded", .refunded),
            ("none", .none),
        ]

        for (status, expected) in cases {
            let response = AccessStatusResponse(hasAccess: false, status: status)
            XCTAssertEqual(response.toAccessStatus(), expected)
        }
    }

    /// revoked → .revoked
    func testToAccessStatusRevoked() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "revoked",
            reason: "revoked_entitlement",
        )
        XCTAssertEqual(response.toAccessStatus(), .revoked)
    }

    /// refunded → .refunded
    func testToAccessStatusRefunded() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "refunded",
            reason: "refunded_entitlement",
        )
        XCTAssertEqual(response.toAccessStatus(), .refunded)
    }

    /// expired + trial → .trialExpired
    func testToAccessStatusExpiredTrial() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "expired",
            reason: "expired_entitlement",
            productKey: "trial",
        )
        XCTAssertEqual(response.toAccessStatus(), .trialExpired)
    }

    /// expired + non-trial → .none
    func testToAccessStatusExpiredNonTrial() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "expired",
            productKey: "core",
        )
        XCTAssertEqual(response.toAccessStatus(), .none)
    }

    /// inactive → .none
    func testToAccessStatusInactive() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "inactive",
            reason: "inactive_entitlement",
        )
        XCTAssertEqual(response.toAccessStatus(), .none)
    }

    /// past_due → .none
    func testToAccessStatusPastDue() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "past_due",
            reason: "past_due_subscription",
        )
        XCTAssertEqual(response.toAccessStatus(), .none)
    }

    /// none → .none
    func testToAccessStatusNone() {
        let response = AccessStatusResponse(
            hasAccess: false,
            status: "none",
            reason: "no_entitlement",
        )
        XCTAssertEqual(response.toAccessStatus(), .none)
    }

    // MARK: - Round-trip encode/decode

    /// 동일 struct 인스턴스를 encode → decode했을 때 값이 보존된다.
    func testRoundTripEncodeDecode() throws {
        let original = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            currentPeriodEnd: Date(timeIntervalSince1970: 1_800_000_000),
            source: "polar",
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AccessStatusResponse.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    /// 기존 snapshot blob의 expiresAt 키를 currentPeriodEnd로 복원한다.
    func testAccessStatusSnapshotDecodesLegacyExpiresAt() throws {
        struct LegacySnapshot: Encodable {
            let status: AccessStatus
            let expiresAt: Date
            let fetchedAt: Date
        }

        let expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = LegacySnapshot(
            status: .coreLicenseActive,
            expiresAt: expiresAt,
            fetchedAt: fetchedAt,
        )
        let data = try JSONEncoder().encode(legacy)

        let snapshot = try JSONDecoder().decode(AccessStatusSnapshot.self, from: data)

        XCTAssertEqual(snapshot.status, .coreLicenseActive)
        XCTAssertEqual(snapshot.currentPeriodEnd, expiresAt)
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testSnapshotStorePreservesSameBindingAndClearsReplacement() async {
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: .testValue))
        let bindingA = UUID()
        let bindingB = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")
        let snapshot = AccessStatusSnapshot(status: .coreLicenseActive)

        _ = await client.load(bindingA, gatewayEnvironment)
        await client.save(snapshot, bindingA, gatewayEnvironment, 3)

        let restored = await client.load(bindingA, gatewayEnvironment)
        XCTAssertEqual(restored?.snapshot, snapshot)
        XCTAssertEqual(restored?.sessionBindingID, bindingA)

        let replacement = await client.load(bindingB, gatewayEnvironment)
        XCTAssertNil(replacement?.snapshot)
        XCTAssertEqual(replacement?.sessionBindingID, bindingB)
        XCTAssertGreaterThan(replacement?.mutationGeneration ?? 0, 3)
    }

    func testSnapshotStoreRejectsStaleSaveAndLateSaveAfterSignOut() async {
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: .testValue))
        let binding = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")
        let snapshot = AccessStatusSnapshot(status: .coreLicenseActive)

        _ = await client.load(binding, gatewayEnvironment)
        await client.save(snapshot, binding, gatewayEnvironment, 4)
        await client.remove(binding, gatewayEnvironment, 4)
        await client.save(snapshot, binding, gatewayEnvironment, 4)
        await client.remove(nil, GatewayEnvironment(rawValue: ""), 5)
        await client.save(snapshot, binding, gatewayEnvironment, 6)

        let restored = await client.load(nil, GatewayEnvironment(rawValue: ""))
        XCTAssertNil(restored?.snapshot)
        XCTAssertNil(restored?.sessionBindingID)
        XCTAssertGreaterThan(restored?.mutationGeneration ?? 0, 5)
    }

    func testSnapshotStoreLoadsLegacyPayloadUntilCurrentSaveRewritesIt() async throws {
        let legacySnapshot = AccessStatusSnapshot(status: .trialActive)
        let legacyData = try JSONEncoder().encode(legacySnapshot)
        let storage = SnapshotStorage(initialData: legacyData)
        let client = AccessStatusSnapshotClient(store: AccessStatusSnapshotStore(userDefaults: storage.client))
        let binding = UUID()
        let gatewayEnvironment = GatewayEnvironment(rawValue: "https://gateway.example.com")

        let legacy = await client.load(binding, gatewayEnvironment)
        XCTAssertEqual(legacy?.snapshot, legacySnapshot)
        XCTAssertTrue(legacy?.isLegacy ?? false)

        await client.save(legacySnapshot, binding, gatewayEnvironment, 1)

        let rewritten = await client.load(binding, gatewayEnvironment)
        XCTAssertFalse(rewritten?.isLegacy ?? true)
        XCTAssertEqual(rewritten?.schemaVersion, AccessStatusSnapshotEnvelope.currentSchemaVersion)
    }

    private final class SnapshotStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Any?

        init(initialData: Data? = nil) {
            value = initialData
        }

        var client: UserDefaultsClient {
            UserDefaultsClient(
                bool: { _ in false },
                setBool: { _, _ in },
                string: { _ in nil },
                setString: { _, _ in },
                double: { _ in 0 },
                setDouble: { _, _ in },
                object: { [self] _ in
                    lock.lock()
                    defer { lock.unlock() }
                    return value
                },
                setObject: { [self] value, _ in
                    lock.lock()
                    defer { lock.unlock() }
                    self.value = value
                },
            )
        }
    }
}

@testable import VoyagerFeaturesAccountAccess
import XCTest

/// ACC-002: AccessStatusResponse backend wire-format 디코딩 및 toAccessStatus() 매핑 검증.
///
/// Backend `GET /access/status`가 반환하는 camelCase JSON을 AccessStatusResponse가 올바르게 디코딩하고,
/// `toAccessStatus()`가 raw status + productKey 조합을 canonical AccessStatus로 변환하는지 검증한다.
final class ACC002AccessStatusResponseCodingTests: XCTestCase {
    private var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
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
        """.data(using: .utf8)!

        let response = try decoder.decode(AccessStatusResponse.self, from: json)

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
        """.data(using: .utf8)!

        let response = try decoder.decode(AccessStatusResponse.self, from: json)

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
        """.data(using: .utf8)!

        let response = try decoder.decode(AccessStatusResponse.self, from: json)

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
}

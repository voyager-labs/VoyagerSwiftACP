@testable import VoyagerFeaturesAccountAccess
import XCTest

/// ACC-002: AccessStatusResponse snake_case CodingKeys 디코딩 검증.
///
/// Backend가 snake_case JSON을 응답할 때 AccessStatusResponse가 올바르게 디코딩되는지 검증한다.
/// CodingKeys 매핑을 통해 struct 멤버는 camelCase를 유지하면서 JSON의 snake_case 키를 매핑한다.
final class ACC002AccessStatusResponseCodingTests: XCTestCase {
    private var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Snake_case decode

    /// Backend snake_case JSON (expires_at, reason_code)에서 AccessStatusResponse가 올바르게 디코딩된다.
    func testSnakeCaseDecode() throws {
        let json = """
        {
            "status": "core_license_active",
            "expires_at": "2027-06-14T00:00:00Z",
            "entitlements": [],
            "reason_code": "expired"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(AccessStatusResponse.self, from: json)

        XCTAssertEqual(response.status, .coreLicenseActive)
        XCTAssertNotNil(response.expiresAt)
        XCTAssertEqual(response.entitlements, [])
        XCTAssertEqual(response.reasonCode, "expired")
        XCTAssertNil(response.message)
    }

    /// Backend snake_case JSON에서 message 필드가 올바르게 디코딩된다.
    func testSnakeCaseDecodeWithMessage() throws {
        let json = """
        {
            "status": "revoked",
            "entitlements": [],
            "message": "Access has been revoked"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(AccessStatusResponse.self, from: json)

        XCTAssertEqual(response.status, .revoked)
        XCTAssertEqual(response.message, "Access has been revoked")
        XCTAssertNil(response.expiresAt)
        XCTAssertNil(response.reasonCode)
    }

    // MARK: - CamelCase backward compatibility

    /// status/entitlements/message 필드는 CodingKeys 값이 property name과 동일하므로 camelCase JSON도 정상 디코딩된다.
    /// expiresAt/reasonCode는 CodingKeys가 snake_case를 지정하므로 camelCase 키는 인식되지 않고 nil로 디코딩된다.
    func testCamelCaseFieldsStillDecode() throws {
        let json = """
        {
            "status": "beta_trial_active",
            "expiresAt": "2027-06-14T00:00:00Z",
            "entitlements": [],
            "message": "camelCase message",
            "reasonCode": "trial"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(AccessStatusResponse.self, from: json)

        // CodingKeys 값이 property name과 일치하는 필드는 camelCase로 정상 디코딩
        XCTAssertEqual(response.status, .betaTrialActive)
        XCTAssertEqual(response.entitlements, [])
        XCTAssertEqual(response.message, "camelCase message")
        // CodingKeys가 snake_case를 지정하는 필드는 camelCase 키로 디코딩되지 않음
        XCTAssertNil(response.expiresAt, "expiresAt는 CodingKeys가 'expires_at'을 지정하므로 camelCase 'expiresAt'는 nil")
        XCTAssertNil(response.reasonCode, "reasonCode는 CodingKeys가 'reason_code'를 지정하므로 camelCase 'reasonCode'는 nil")
    }

    // MARK: - Missing optional fields

    /// 모든 optional 필드가 누락된 JSON이 nil로 디코딩된다.
    func testMissingOptionalFieldsDecodeAsNil() throws {
        let json = """
        {
            "status": "none",
            "entitlements": []
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(AccessStatusResponse.self, from: json)

        XCTAssertEqual(response.status, .none)
        XCTAssertEqual(response.entitlements, [])
        XCTAssertNil(response.expiresAt)
        XCTAssertNil(response.message)
        XCTAssertNil(response.reasonCode)
    }

    // MARK: - All AccessStatus raw values

    /// 모든 AccessStatus rawValue가 snake_case JSON에서 올바르게 디코딩된다.
    func testAllAccessStatusValuesDecodeFromSnakeCase() throws {
        let testCases: [(String, AccessStatus)] = [
            ("core_license_active", .coreLicenseActive),
            ("beta_trial_active", .betaTrialActive),
            ("internal_test_active", .internalTestActive),
            ("none", .none),
            ("trial_expired", .trialExpired),
            ("revoked", .revoked),
            ("refunded", .refunded),
            ("network_failure", .networkFailure),
        ]

        for (rawValue, expectedStatus) in testCases {
            let json = """
            {
                "status": "\(rawValue)",
                "entitlements": []
            }
            """.data(using: .utf8)!

            let response = try decoder.decode(AccessStatusResponse.self, from: json)
            XCTAssertEqual(response.status, expectedStatus, "status rawValue '\(rawValue)' 디코딩 실패")
        }
    }
}

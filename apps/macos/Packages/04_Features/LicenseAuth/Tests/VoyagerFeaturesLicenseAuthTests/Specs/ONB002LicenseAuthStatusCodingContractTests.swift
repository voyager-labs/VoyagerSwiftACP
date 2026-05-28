@testable import VoyagerFeaturesLicenseAuth
import XCTest

final class ONB002LicenseAuthStatusCodingContractTests: XCTestCase {
    /*
     ONB-002 access status coding contract

     포함한 interaction_id:
     - ONB-002-apply_access_unlock_result: gateway `access_status` raw value를 앱 domain status로 안정적으로 해석한다.

     Fixture reset:
     - JSONEncoder/JSONDecoder만 사용하므로 외부 fixture가 필요 없다.
     */

    // MARK: - ONB-002-apply_access_unlock_result

    // MARK: - Raw Value 디코딩 계약 테스트

    func testCoreLicenseActiveRawValue() {
        let status = LicenseAuthStatus(rawValue: "core_license_active")
        XCTAssertEqual(status, .coreLicenseActive)
    }

    func testBetaTrialActiveRawValue() {
        let status = LicenseAuthStatus(rawValue: "beta_trial_active")
        XCTAssertEqual(status, .betaTrialActive)
    }

    func testInternalTestActiveRawValue() {
        let status = LicenseAuthStatus(rawValue: "internal_test_active")
        XCTAssertEqual(status, .internalTestActive)
    }

    func testNoneRawValue() {
        let status = LicenseAuthStatus(rawValue: "none")
        XCTAssertEqual(status, LicenseAuthStatus.none)
    }

    func testTrialExpiredRawValue() {
        let status = LicenseAuthStatus(rawValue: "trial_expired")
        XCTAssertEqual(status, .trialExpired)
    }

    func testRevokedRawValue() {
        let status = LicenseAuthStatus(rawValue: "revoked")
        XCTAssertEqual(status, .revoked)
    }

    func testRefundedRawValue() {
        let status = LicenseAuthStatus(rawValue: "refunded")
        XCTAssertEqual(status, .refunded)
    }

    func testNetworkFailureRawValue() {
        let status = LicenseAuthStatus(rawValue: "network_failure")
        XCTAssertEqual(status, .networkFailure)
    }

    // MARK: - JSON 디코딩 라운드트립

    func testJSONRoundTrip() throws {
        let statuses: [LicenseAuthStatus] = [
            .coreLicenseActive, .betaTrialActive, .internalTestActive,
            .none, .trialExpired, .revoked, .refunded, .networkFailure,
        ]
        for status in statuses {
            let json = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(LicenseAuthStatus.self, from: json)
            XCTAssertEqual(decoded, status, "Round-trip failed for \(status.rawValue)")
        }
    }
}

@testable import VoyagerFeaturesAccountAccess
import XCTest

final class AccessStatusCodingContractTests: XCTestCase {
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
        let status = AccessStatus(rawValue: "core_license_active")
        XCTAssertEqual(status, .coreLicenseActive)
    }

    func testBetaTrialActiveRawValue() {
        let status = AccessStatus(rawValue: "beta_trial_active")
        XCTAssertEqual(status, .betaTrialActive)
    }

    func testInternalTestActiveRawValue() {
        let status = AccessStatus(rawValue: "internal_test_active")
        XCTAssertEqual(status, .internalTestActive)
    }

    func testNoneRawValue() {
        let status = AccessStatus(rawValue: "none")
        XCTAssertEqual(status, AccessStatus.none)
    }

    func testTrialExpiredRawValue() {
        let status = AccessStatus(rawValue: "trial_expired")
        XCTAssertEqual(status, .trialExpired)
    }

    func testRevokedRawValue() {
        let status = AccessStatus(rawValue: "revoked")
        XCTAssertEqual(status, .revoked)
    }

    func testRefundedRawValue() {
        let status = AccessStatus(rawValue: "refunded")
        XCTAssertEqual(status, .refunded)
    }

    func testNetworkFailureRawValue() {
        let status = AccessStatus(rawValue: "network_failure")
        XCTAssertEqual(status, .networkFailure)
    }

    // MARK: - JSON 디코딩 라운드트립

    func testJSONRoundTrip() throws {
        let statuses: [AccessStatus] = [
            .coreLicenseActive, .betaTrialActive, .internalTestActive,
            .none, .trialExpired, .revoked, .refunded, .networkFailure,
        ]
        for status in statuses {
            let json = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(AccessStatus.self, from: json)
            XCTAssertEqual(decoded, status, "Round-trip failed for \(status.rawValue)")
        }
    }
}

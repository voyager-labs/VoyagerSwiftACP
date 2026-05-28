@testable import VoyagerFeaturesLicenseAuth
import XCTest

final class ONB002LicenseAuthStatusActivityTests: XCTestCase {
    /*
     ONB-002 access status activity contract

     포함한 interaction_id:
     - ONB-002-show_access_unlock_status: active access states are unlockable; inactive/failure states remain blocked.

     Fixture reset:
     - Pure `LicenseAuthStatus` value tests only.
     */

    // MARK: - ONB-002-show_access_unlock_status

    // MARK: - isActive 활성 상태

    func testCoreLicenseActiveIsActive() {
        XCTAssertTrue(LicenseAuthStatus.coreLicenseActive.isActive)
    }

    func testBetaTrialActiveIsActive() {
        XCTAssertTrue(LicenseAuthStatus.betaTrialActive.isActive)
    }

    func testInternalTestActiveIsActive() {
        XCTAssertTrue(LicenseAuthStatus.internalTestActive.isActive)
    }

    // MARK: - isActive 비활성 상태

    func testNoneIsNotActive() {
        XCTAssertFalse(LicenseAuthStatus.none.isActive)
    }

    func testTrialExpiredIsNotActive() {
        XCTAssertFalse(LicenseAuthStatus.trialExpired.isActive)
    }

    func testRevokedIsNotActive() {
        XCTAssertFalse(LicenseAuthStatus.revoked.isActive)
    }

    func testRefundedIsNotActive() {
        XCTAssertFalse(LicenseAuthStatus.refunded.isActive)
    }

    func testNetworkFailureIsNotActive() {
        XCTAssertFalse(LicenseAuthStatus.networkFailure.isActive)
    }
}

@testable import VoyagerFeaturesAccountAccess
import XCTest

final class AccessStatusActivityTests: XCTestCase {
    /*
     ONB-002 access status activity contract

     포함한 interaction_id:
     - ONB-002-show_access_unlock_status: active access states are unlockable; inactive/failure states remain blocked.

     Fixture reset:
     - Pure `AccessStatus` value tests only.
     */

    // MARK: - ONB-002-show_access_unlock_status

    // MARK: - isActive 활성 상태

    func testCoreLicenseActiveIsActive() {
        XCTAssertTrue(AccessStatus.coreLicenseActive.isActive)
    }

    func testBetaTrialActiveIsActive() {
        XCTAssertTrue(AccessStatus.betaTrialActive.isActive)
    }

    func testInternalTestActiveIsActive() {
        XCTAssertTrue(AccessStatus.internalTestActive.isActive)
    }

    // MARK: - isActive 비활성 상태

    func testNoneIsNotActive() {
        XCTAssertFalse(AccessStatus.none.isActive)
    }

    func testTrialExpiredIsNotActive() {
        XCTAssertFalse(AccessStatus.trialExpired.isActive)
    }

    func testRevokedIsNotActive() {
        XCTAssertFalse(AccessStatus.revoked.isActive)
    }

    func testRefundedIsNotActive() {
        XCTAssertFalse(AccessStatus.refunded.isActive)
    }

    func testNetworkFailureIsNotActive() {
        XCTAssertFalse(AccessStatus.networkFailure.isActive)
    }
}

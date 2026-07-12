@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC002EvaluateAccessLevelTests: XCTestCase {
    // MARK: - ACC-002-evaluate_access_level

    /// ACC-002-evaluate_access_level: signedIn + coreLicenseActive → .complete
    /// signedIn 상태에서 core_license_active 권한일 때 access_level이 complete로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.coreLicenseActive → stepState==.complete
    /// - 사전 조건: hasAccountSession==true, status==.coreLicenseActive
    /// - 기대 결과: accountAccessStepState==.complete, accountAccessAuthAxis==.signedIn, status.isActive==true
    func testSignedInWithCoreLicenseActiveReturnsComplete() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .coreLicenseActive
        state.isComplete = true

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .complete)
        XCTAssertTrue(state.status?.isActive == true)
    }

    /// ACC-002-evaluate_access_level: signedIn + trialActive → .complete
    /// signedIn 상태에서 trial_active 권한일 때 access_level이 complete로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.trialActive → stepState==.complete
    /// - 사전 조건: hasAccountSession==true, status==.trialActive
    /// - 기대 결과: accountAccessStepState==.complete, accountAccessAuthAxis==.signedIn, status.isActive==true
    func testSignedInWithTrialActiveReturnsComplete() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .trialActive
        state.isComplete = true

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .complete)
        XCTAssertTrue(state.status?.isActive == true)
    }

    /// ACC-002-evaluate_access_level: signedIn + internalTestActive → .complete
    /// signedIn 상태에서 internal_test_active 권한일 때 access_level이 complete로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.internalTestActive → stepState==.complete
    /// - 사전 조건: hasAccountSession==true, status==.internalTestActive
    /// - 기대 결과: accountAccessStepState==.complete, accountAccessAuthAxis==.signedIn, status.isActive==true
    func testSignedInWithInternalTestActiveReturnsComplete() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .internalTestActive
        state.isComplete = true

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .complete)
        XCTAssertTrue(state.status?.isActive == true)
    }

    /// ACC-002-evaluate_access_level: signedIn + none → .blocked
    /// signedIn 상태에서 권한이 없을 때(none) access_level이 blocked로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.none → stepState==.blocked
    /// - 사전 조건: hasAccountSession==true, status==.none
    /// - 기대 결과: accountAccessStepState==.blocked, accountAccessAuthAxis==.signedIn, status.isActive==false
    func testSignedInWithNoneReturnsBlocked() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = AccessStatus.none

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertFalse(state.status?.isActive == true)
    }

    /// ACC-002-evaluate_access_level: signedIn + trialExpired → .blocked
    /// signedIn 상태에서 trial이 만료되었을 때 access_level이 blocked로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.trialExpired → stepState==.blocked
    /// - 사전 조건: hasAccountSession==true, status==.trialExpired
    /// - 기대 결과: accountAccessStepState==.blocked, accountAccessAuthAxis==.signedIn, status.isActive==false
    func testSignedInWithTrialExpiredReturnsBlocked() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .trialExpired

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertFalse(state.status?.isActive == true)
    }

    /// ACC-002-evaluate_access_level: signedIn + revoked → .blocked
    /// signedIn 상태에서 권한이 회수되었을 때 access_level이 blocked로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.revoked → stepState==.blocked
    /// - 사전 조건: hasAccountSession==true, status==.revoked
    /// - 기대 결과: accountAccessStepState==.blocked, accountAccessAuthAxis==.signedIn, status.isActive==false
    func testSignedInWithRevokedReturnsBlocked() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .revoked

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertFalse(state.status?.isActive == true)
    }

    /// ACC-002-evaluate_access_level: signedIn + refunded → .blocked
    /// signedIn 상태에서 환불되었을 때 access_level이 blocked로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.refunded → stepState==.blocked
    /// - 사전 조건: hasAccountSession==true, status==.refunded
    /// - 기대 결과: accountAccessStepState==.blocked, accountAccessAuthAxis==.signedIn, status.isActive==false
    func testSignedInWithRefundedReturnsBlocked() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .refunded

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertFalse(state.status?.isActive == true)
    }

    /// ACC-002-evaluate_access_level: signedIn + networkFailure → .error
    /// signedIn 상태에서 네트워크 오류 발생 시 access_level이 error로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.networkFailure → stepState==.error
    /// - 사전 조건: hasAccountSession==true, status==.networkFailure
    /// - 기대 결과: accountAccessStepState==.error, accountAccessAuthAxis==.signedIn, showsRetry==true
    func testSignedInWithNetworkFailureReturnsError() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .networkFailure

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .error)
        XCTAssertTrue(state.showsRetry)
        XCTAssertFalse(state.status?.isActive == true)
    }

    /// ACC-002-evaluate_access_level: signedIn + nil status → .pending
    /// signedIn 상태에서 status가 아직 수신되지 않았을 때 access_level이 pending으로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=nil → stepState==.pending
    /// - 사전 조건: hasAccountSession==true, status==nil
    /// - 기대 결과: accountAccessStepState==.pending, accountAccessAuthAxis==.signedIn
    func testSignedInWithNilStatusReturnsPending() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = nil

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .pending)
    }

    /// ACC-002-evaluate_access_level: signedOut + any status → .blocked
    /// 로그아웃 상태에서는 status 값과 관계없이 access_level이 blocked로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=false → stepState==.blocked (status 무관)
    /// - 사전 조건: hasAccountSession==false, status==.coreLicenseActive (active 상태여도 차단)
    /// - 기대 결과: accountAccessStepState==.blocked, accountAccessAuthAxis==.signedOut
    func testSignedOutWithAnyStatusReturnsBlocked() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = false
        state.status = .coreLicenseActive

        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
    }

    /// ACC-002-evaluate_access_level: signInFailed + any status → .blocked
    /// 로그인 실패 상태에서는 status 값과 관계없이 access_level이 blocked로 평가되는지 검증한다.
    /// - 검증 내용: didSignInFail=true, hasAccountSession=false → stepState==.blocked
    /// - 사전 조건: didSignInFail==true, hasAccountSession==false
    /// - 기대 결과: accountAccessStepState==.blocked, accountAccessAuthAxis==.signInFailed
    func testSignInFailedWithAnyStatusReturnsBlocked() {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true
        state.hasAccountSession = false
        state.status = .coreLicenseActive

        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
    }

    /// ACC-002-evaluate_access_level: signInInProgress → .pending
    /// 로그인 진행 중일 때는 access_level이 pending으로 평가되는지 검증한다.
    /// - 검증 내용: isSignInInProgress=true → stepState==.pending
    /// - 사전 조건: isSignInInProgress==true (hasAccountSession, status 무관)
    /// - 기대 결과: accountAccessStepState==.pending, accountAccessAuthAxis==.signInInProgress
    func testSignInInProgressReturnsPending() {
        var state = AccountAccessFeature.State()
        state.isSignInInProgress = true

        XCTAssertEqual(state.accountAccessAuthAxis, .signInInProgress)
        XCTAssertEqual(state.accountAccessStepState, .pending)
    }

    /// ACC-002-evaluate_access_level: AccessStatus.isActive는 active 상태에서 true를 반환한다.
    /// active 권한 상태(coreLicenseActive, trialActive, internalTestActive)에서
    /// isActive가 올바르게 true를 반환하는지 검증한다.
    /// - 검증 내용: 각 active status의 isActive 프로퍼티 값 확인
    /// - 사전 조건: status가 active 상태
    /// - 기대 결과: isActive==true
    func testAccessStatusIsActiveReturnsTrueForActiveStatuses() {
        let activeStatuses: [AccessStatus] = [.coreLicenseActive, .trialActive, .internalTestActive]

        for status in activeStatuses {
            XCTAssertTrue(status.isActive, "\(status) should be active")
        }
    }

    /// ACC-002-evaluate_access_level: AccessStatus.isActive는 비활성 상태에서 false를 반환한다.
    /// 비활성 권한 상태(none, trialExpired, revoked, refunded, networkFailure)에서
    /// isActive가 올바르게 false를 반환하는지 검증한다.
    /// - 검증 내용: 각 비활성 status의 isActive 프로퍼티 값 확인
    /// - 사전 조건: status가 비활성 상태
    /// - 기대 결과: isActive==false
    func testAccessStatusIsActiveReturnsFalseForInactiveStatuses() {
        let inactiveStatuses: [AccessStatus] = [.none, .trialExpired, .revoked, .refunded, .networkFailure]

        for status in inactiveStatuses {
            XCTAssertFalse(status.isActive, "\(status) should not be active")
        }
    }
}

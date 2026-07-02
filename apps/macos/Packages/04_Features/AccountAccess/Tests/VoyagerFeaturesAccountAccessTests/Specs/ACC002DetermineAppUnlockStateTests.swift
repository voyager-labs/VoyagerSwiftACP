@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC002DetermineAppUnlockStateTests: XCTestCase {
    // MARK: - ACC-002-determine_app_unlock_state

    /// ACC-002-determine_app_unlock_state: coreLicenseActive에서 앱 잠금 해제 상태가 완료로 결정된다.
    /// coreLicenseActive 상태가 활성화되어 있을 때 unlock state가 complete로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.coreLicenseActive에서 isActive 및 accountAccessStepState 확인
    /// - 사전 조건: hasAccountSession==true, status==.coreLicenseActive
    /// - 기대 결과: status.isActive==true, accountAccessStepState==.complete, showsRetry==false
    func testCoreLicenseActiveMapsToComplete() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .coreLicenseActive

        XCTAssertTrue(try XCTUnwrap(state.status).isActive)
        XCTAssertEqual(state.accountAccessStepState, .complete)
        XCTAssertFalse(state.showsRetry)
    }

    /// ACC-002-determine_app_unlock_state: trialActive에서 앱 잠금 해제 상태가 완료로 결정된다.
    /// trialActive 상태가 활성화되어 있을 때 unlock state가 complete로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.trialActive에서 isActive 및 accountAccessStepState 확인
    /// - 사전 조건: hasAccountSession==true, status==.trialActive
    /// - 기대 결과: status.isActive==true, accountAccessStepState==.complete, showsRetry==false
    func testTrialActiveMapsToComplete() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .trialActive

        XCTAssertTrue(try XCTUnwrap(state.status).isActive)
        XCTAssertEqual(state.accountAccessStepState, .complete)
        XCTAssertFalse(state.showsRetry)
    }

    /// ACC-002-determine_app_unlock_state: internalTestActive에서 앱 잠금 해제 상태가 완료로 결정된다.
    /// internalTestActive 상태가 활성화되어 있을 때 unlock state가 complete로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.internalTestActive에서 isActive 및 accountAccessStepState 확인
    /// - 사전 조건: hasAccountSession==true, status==.internalTestActive
    /// - 기대 결과: status.isActive==true, accountAccessStepState==.complete, showsRetry==false
    func testInternalTestActiveMapsToComplete() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .internalTestActive

        XCTAssertTrue(try XCTUnwrap(state.status).isActive)
        XCTAssertEqual(state.accountAccessStepState, .complete)
        XCTAssertFalse(state.showsRetry)
    }

    /// ACC-002-determine_app_unlock_state: none에서 앱 잠금 해제 상태가 차단됨으로 결정된다.
    /// access_status가 none일 때 unlock state가 blocked로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.none에서 accountAccessStepState 및 showsRetry 확인
    /// - 사전 조건: hasAccountSession==true, status==.none
    /// - 기대 결과: status.isActive==false, accountAccessStepState==.blocked, showsRetry==true
    func testNoneMapsToBlocked() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = AccessStatus.none

        XCTAssertFalse(try XCTUnwrap(state.status).isActive)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertTrue(state.showsRetry)
    }

    /// ACC-002-determine_app_unlock_state: trialExpired에서 앱 잠금 해제 상태가 차단됨으로 결정된다.
    /// trial이 만료되었을 때 unlock state가 blocked로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.trialExpired에서 accountAccessStepState 및 showsRetry 확인
    /// - 사전 조건: hasAccountSession==true, status==.trialExpired
    /// - 기대 결과: status.isActive==false, accountAccessStepState==.blocked, showsRetry==true
    func testTrialExpiredMapsToBlocked() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .trialExpired

        XCTAssertFalse(try XCTUnwrap(state.status).isActive)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertTrue(state.showsRetry)
    }

    /// ACC-002-determine_app_unlock_state: revoked에서 앱 잠금 해제 상태가 차단됨으로 결정된다.
    /// access_status가 revoked일 때 unlock state가 blocked로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.revoked에서 accountAccessStepState 및 showsRetry 확인
    /// - 사전 조건: hasAccountSession==true, status==.revoked
    /// - 기대 결과: status.isActive==false, accountAccessStepState==.blocked, showsRetry==true
    func testRevokedMapsToBlocked() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .revoked

        XCTAssertFalse(try XCTUnwrap(state.status).isActive)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertTrue(state.showsRetry)
    }

    /// ACC-002-determine_app_unlock_state: refunded에서 앱 잠금 해제 상태가 차단됨으로 결정된다.
    /// access_status가 refunded일 때 unlock state가 blocked로 평가되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.refunded에서 accountAccessStepState 및 showsRetry 확인
    /// - 사전 조건: hasAccountSession==true, status==.refunded
    /// - 기대 결과: status.isActive==false, accountAccessStepState==.blocked, showsRetry==true
    func testRefundedMapsToBlocked() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .refunded

        XCTAssertFalse(try XCTUnwrap(state.status).isActive)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertTrue(state.showsRetry)
    }

    /// ACC-002-determine_app_unlock_state: networkFailure에서 앱 잠금 해제 상태가 오류로 결정된다.
    /// 네트워크 오류 발생 시 unlock state가 error로 평가되고 showsRetry가 true인지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.networkFailure에서 accountAccessStepState 및 showsRetry 확인
    /// - 사전 조건: hasAccountSession==true, status==.networkFailure
    /// - 기대 결과: status.isActive==false, accountAccessStepState==.error, showsRetry==true
    func testNetworkFailureMapsToError() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .networkFailure

        XCTAssertFalse(try XCTUnwrap(state.status).isActive)
        XCTAssertEqual(state.accountAccessStepState, .error)
        XCTAssertTrue(state.showsRetry)
    }

    /// ACC-002-determine_app_unlock_state: status가 nil이면 showsRetry가 false이다.
    /// access_status를 아직 조회하지 않은 초기 상태에서 showsRetry가 false인지 검증한다.
    /// - 검증 내용: status==nil에서 showsRetry 및 accountAccessStepState 확인
    /// - 사전 조건: hasAccountSession==true, status==nil (기본값)
    /// - 기대 결과: showsRetry==false, accountAccessStepState==.pending
    func testNilStatusShowsNoRetry() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true

        XCTAssertNil(state.status)
        XCTAssertFalse(state.showsRetry)
        XCTAssertEqual(state.accountAccessStepState, .pending)
    }

    /// ACC-002-determine_app_unlock_state: AccessStatus.isActive computed property가 올바르게 동작한다.
    /// 모든 AccessStatus case에 대해 isActive가 예상대로 반환되는지 종합 검증한다.
    /// - 검증 내용: 각 status case별 isActive computed property 값 확인
    /// - 사전 조건: 모든 AccessStatus case 열거
    /// - 기대 결과: active status 3개는 true, non-active status 5개는 false
    func testAccessStatusIsActiveComputedProperty() {
        XCTAssertTrue(AccessStatus.coreLicenseActive.isActive)
        XCTAssertTrue(AccessStatus.trialActive.isActive)
        XCTAssertTrue(AccessStatus.internalTestActive.isActive)

        XCTAssertFalse(AccessStatus.none.isActive)
        XCTAssertFalse(AccessStatus.trialExpired.isActive)
        XCTAssertFalse(AccessStatus.revoked.isActive)
        XCTAssertFalse(AccessStatus.refunded.isActive)
        XCTAssertFalse(AccessStatus.networkFailure.isActive)
    }

    /// ACC-002-determine_app_unlock_state: access_status=.none일 때 blocked projection과 Refresh Access affordance가 제공된다.
    /// entitlement_access_flow.md 계약: backend none → ONB blocked. 사용자가 refresh로 복구 시도할 수 있어야 한다.
    /// - 검증 내용: status=.none + hasAccountSession=true → stepState=.blocked, canRefreshAccess=true
    /// - 사전 조건: hasAccountSession=true, status=.none
    /// - 기대 결과: accountAccessStepState=.blocked, canRefreshAccess=true, accountAccessAuthAxis=.signedIn
    func testNoneStatusDerivesBlockedProjectionWithRefreshAccess() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = AccessStatus.none

        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertTrue(state.canRefreshAccess, "blocked projection에서 Refresh Access가 가능해야 함")
        XCTAssertFalse(state.canRetry, "blocked는 retry가 아니라 refresh 복구 경로")
    }

    /// ACC-002-determine_app_unlock_state: status=nil + errorMessage!=nil (decode/notConfigured 실패) → error projection.
    /// entitlement_access_flow.md: 조회 실패는 access_status 값을 확정하지 않고 error 축에서 처리한다.
    /// - 검증 내용: status=nil, errorMessage!=nil → stepState=.error (pending이 아님)
    /// - 사전 조건: hasAccountSession=true, status=nil, errorMessage 설정
    /// - 기대 결과: accountAccessStepState=.error
    func testErrorMessageWithNilStatusDerivesErrorProjection() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = nil
        state.errorMessage = "Failed to process the response."

        XCTAssertEqual(state.accountAccessStepState, .error, "조회 실패(errorMessage 세팅)는 pending이 아니라 error여야 함")
        XCTAssertTrue(state.canRetry, "error projection은 retry affordance를 제공해야 함")
    }

    /// ACC-002-determine_app_unlock_state: status=nil + errorMessage=nil (초기/대기) → pending projection.
    /// fetch를 시작했지만 아직 응답을 받지 못한 상태가 pending으로 도출되는지 확인한다.
    /// - 검증 내용: status=nil, errorMessage=nil → stepState=.pending
    /// - 사전 조건: hasAccountSession=true, status=nil, errorMessage=nil
    /// - 기대 결과: accountAccessStepState=.pending
    func testNilStatusNoErrorMessageDerivesPendingProjection() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = nil
        state.errorMessage = nil

        XCTAssertEqual(state.accountAccessStepState, .pending)
        XCTAssertFalse(state.canRetry)
    }
}

@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC002ShowPaywallCtaTests: XCTestCase {
    // MARK: - ACC-002-show_paywall_cta

    /// ACC-002-show_paywall_cta: access_status=none에서 Account 탭 표시 시 paywall CTA 조건이 전달된다.
    /// access_status가 none일 때 paywall CTA 표시 조건이 올바르게 전달되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.none에서 accountAccessStepState 및 accountAccessAuthAxis 확인
    /// - 사전 조건: hasAccountSession==true, status==.none
    /// - 기대 결과: accountAccessStepState==.blocked, accountAccessAuthAxis==.signedIn, isComplete==false
    func testAccessStatusNoneProvidesPaywallCTAConditions() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = AccessStatus.none

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertFalse(state.isComplete)
    }

    /// ACC-002-show_paywall_cta: access_status=active에서 paywall CTA 표시 조건이 전달되지 않는다.
    /// access_status가 full(active)일 때 paywall CTA 조건이 비활성화되는지 검증한다.
    /// - 검증 내용: hasAccountSession=true, status=.coreLicenseActive에서 accountAccessStepState 확인
    /// - 사전 조건: hasAccountSession==true, status==.coreLicenseActive
    /// - 기대 결과: accountAccessStepState==.complete (paywall CTA 불필요)
    func testAccessStatusActiveSuppressesPaywallCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .coreLicenseActive

        XCTAssertEqual(state.accountAccessStepState, .complete)
        XCTAssertTrue(state.isComplete || state.status?.isActive == true)
    }

    /// ACC-002-show_paywall_cta: logged_out 전이 시 paywall CTA 대신 로그인 CTA 조건이 활성화된다.
    /// auth_state가 logged_out일 때 로그인 CTA 조건이 올바르게 활성화되는지 검증한다.
    /// - 검증 내용: hasAccountSession=false에서 accountAccessAuthAxis 및 canStartLogin 확인
    /// - 사전 조건: hasAccountSession==false (logged_out)
    /// - 기대 결과: accountAccessAuthAxis==.signedOut, requiresAccountSession==true, canStartLogin==true
    func testLoggedOutShowsLoginCTAInsteadOfPaywall() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = false
        state.status = AccessStatus.none

        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertTrue(state.requiresAccountSession)
        XCTAssertTrue(state.canStartLogin)
    }

    /// ACC-002-show_paywall_cta: status가 full로 변경되면 paywall CTA 조건이 소멸한다.
    /// paywall CTA 표시 중 access_status가 full로 변경될 때 CTA 조건이 사라지는지 검증한다.
    /// - 검증 내용: status를 .none에서 .coreLicenseActive로 변경 시 accountAccessStepState 전환 확인
    /// - 사전 조건: blocked 상태 (status==.none)에서 시작
    /// - 기대 결과: status 변경 후 accountAccessStepState==.complete로 전환
    func testStatusChangeToFullRemovesPaywallCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = AccessStatus.none

        XCTAssertEqual(state.accountAccessStepState, .blocked)

        state.status = .coreLicenseActive

        XCTAssertEqual(state.accountAccessStepState, .complete)
        XCTAssertNotEqual(state.accountAccessStepState, .blocked)
    }
}

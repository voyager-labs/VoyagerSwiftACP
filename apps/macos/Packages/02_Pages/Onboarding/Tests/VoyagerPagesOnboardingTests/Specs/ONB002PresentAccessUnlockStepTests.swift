import ComposableArchitecture
import ConcurrencyExtras
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class ONB002PresentAccessUnlockStepTests: XCTestCase {
    override func setUp() {
        super.setUp()
        prepareDependencies {
            $0.continuousClock = ImmediateClock()
        }
    }

    // MARK: - ONB-002 UI CTA affordance tests

    /// ONB-002 UI: signed-out 상태에서 Login CTA만 활성화되고 Next/Submit/Retry/Refresh는 비활성화된다.
    /// 계정 세션이 없을 때 UI에 Login 버튼이 primary CTA로 표시되어야 함을 상태 affordance로 검증합니다.
    /// - 검증 내용: hasAccountSession=false일 때 canStartLogin만 true입니다.
    /// - 사전 조건: 세션 없음, 로그인 진행 중 아님, 로그인 실패 아님.
    /// - 기대 결과: canStartLogin=true, canRefreshAccess=false, canRetry=false.
    func testSignedOutStateShowsLoginCTADisablesAllOthers() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = false

        XCTAssertTrue(state.canStartLogin, "signed-out 상태에서 canStartLogin이 true여야 함")
        XCTAssertFalse(state.canRefreshAccess, "signed-out 상태에서 canRefreshAccess가 false여야 함")
        XCTAssertFalse(state.canRetry, "signed-out 상태에서 canRetry가 false여야 함")
        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
    }

    /// ONB-002 UI: sign-in-failed 상태에서 Login CTA가 primary로 표시된다.
    /// 로그인 실패 후 재시도가 가능한지 상태 affordance로 검증합니다.
    /// - 검증 내용: didSignInFail=true일 때 canStartLogin=true입니다.
    /// - 사전 조건: hasAccountSession=false, didSignInFail=true.
    /// - 기대 결과: canStartLogin=true, canRefreshAccess=false.
    func testSignInFailedStateShowsLoginCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = false
        state.didSignInFail = true

        XCTAssertTrue(state.canStartLogin, "sign-in-failed 상태에서 canStartLogin이 true여야 함")
        XCTAssertFalse(state.canRefreshAccess, "sign-in-failed 상태에서 canRefreshAccess가 false여야 함")
        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)
    }

    /// ONB-002 UI: sign-in 진행 중에는 모든 액션 버튼이 비활성화된다.
    /// 로그인 pending 상태에서 UI가 모든 CTA를 disable하는지 검증합니다.
    /// - 검증 내용: isSignInInProgress=true일 때 모든 affordance가 false입니다.
    /// - 사전 조건: isSignInInProgress=true.
    /// - 기대 결과: canStartLogin=false, canRefreshAccess=false.
    func testSignInInProgressDisablesAllActions() {
        var state = AccountAccessFeature.State()
        state.isSignInInProgress = true

        XCTAssertFalse(state.canStartLogin, "sign-in 진행 중 canStartLogin이 false여야 함")
        XCTAssertFalse(state.canRefreshAccess, "sign-in 진행 중 canRefreshAccess가 false여야 함")
        XCTAssertFalse(state.canRetry, "sign-in 진행 중 canRetry가 false여야 함")
        XCTAssertEqual(state.accountAccessAuthAxis, .signInInProgress)
        XCTAssertEqual(state.accountAccessStepState, .pending)
    }

    /// ONB-002 UI: signed-in blocked 상태에서 Refresh Access CTA가 활성화된다.
    /// 라이선스가 revoked/trialExpired 등 blocked 상태일 때 Refresh Access가 available한지 검증합니다.
    /// - 검증 내용: hasAccountSession=true, status=revoked → canRefreshAccess=true.
    /// - 사전 조건: 세션 있음, 라이선스 revoked.
    /// - 기대 결과: canRefreshAccess=true, canStartLogin=false, accountAccessStepState=blocked.
    func testSignedInBlockedShowsRefreshAccessCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .revoked

        XCTAssertTrue(state.canRefreshAccess, "signed-in blocked 상태에서 canRefreshAccess가 true여야 함")
        XCTAssertFalse(state.canStartLogin, "signed-in 상태에서 canStartLogin이 false여야 함")
        XCTAssertFalse(state.canRetry, "blocked(비에러)에서 canRetry가 false여야 함")
        XCTAssertEqual(state.accountAccessStepState, .blocked)
    }

    /// ONB-002 UI: signed-in error 상태에서 Refresh Access와 Retry CTA가 모두 활성화된다.
    /// 네트워크 오류 등 error 상태에서 refresh와 retry가 모두 가능한지 검증합니다.
    /// - 검증 내용: hasAccountSession=true, status=networkFailure → canRefreshAccess=true, canRetry=true.
    /// - 사전 조건: 세션 있음, 네트워크 실패.
    /// - 기대 결과: canRefreshAccess=true, canRetry=true, accountAccessStepState=error.
    func testSignedInErrorShowsRefreshAndRetryCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .networkFailure

        XCTAssertTrue(state.canRefreshAccess, "signed-in error 상태에서 canRefreshAccess가 true여야 함")
        XCTAssertTrue(state.canRetry, "signed-in error 상태에서 canRetry가 true여야 함")
        XCTAssertFalse(state.canStartLogin, "signed-in 상태에서 canStartLogin이 false여야 함")
        XCTAssertEqual(state.accountAccessStepState, .error)
    }

    /// ONB-002 UI: status=nil + errorMessage error projection에서도 Retry CTA가 표시된다.
    /// URL/env 구성 실패처럼 access_status를 확정하지 못한 오류는 Refresh가 아니라 Retry 경로를 제공해야 한다.
    /// - 검증 내용: hasAccountSession=true, status=nil, errorMessage!=nil → canRetry=true.
    /// - 사전 조건: 세션 있음, access_status 미확정 오류.
    /// - 기대 결과: accountAccessStepState=error, top bar Retry 표시 대상.
    func testSignedInNilStatusErrorShowsRetryCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.errorMessage = "Access service is not configured."

        XCTAssertTrue(state.canRefreshAccess, "signed-in error 상태에서 canRefreshAccess가 true여야 함")
        XCTAssertTrue(state.canRetry, "status=nil error 상태에서 canRetry가 true여야 함")
        XCTAssertEqual(state.accountAccessStepState, .error)
    }

    /// ONB-002 UI: complete 상태에서 Next가 활성화된다.
    /// 라이선스가 active로 확인되면 onboarding 다음 단계로 진행 가능한지 검증합니다.
    /// - 검증 내용: status=coreLicenseActive, isComplete=true → onboarding canGoNext=true.
    /// - 사전 조건: 세션 있음, 라이선스 active, isComplete=true.
    /// - 기대 결과: isComplete=true, accountAccessStepState=complete.
    func testCompleteStateEnablesNext() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .coreLicenseActive
        state.isComplete = true

        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.accountAccessStepState, .complete)

        // Onboarding 수준에서 canGoNext 검증
        var onboardingState = OnboardingFeature.State()
        onboardingState.currentStep = .accessUnlock
        onboardingState.access = OnboardingAccessProjection(accountAccess: state)

        XCTAssertTrue(onboardingState.canGoNext, "complete 상태에서 canGoNext가 true여야 함")
    }

    /// ONB-002 UI: signed-in + empty input → Refresh Access는 활성.
    /// 입력 유무와 관계없이 Refresh Access가 가능해야 함을 검증합니다.
    /// - 검증 내용: hasAccountSession=true → canRefreshAccess=true.
    /// - 사전 조건: 세션 있음.
    /// - 기대 결과: canRefreshAccess=true.
    func testSignedInEnablesRefreshAccess() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true

        XCTAssertTrue(state.canRefreshAccess, "signed-in에서 canRefreshAccess가 true여야 함")
    }

    // MARK: - ONB-002 Login CTA action dispatch

    // ONB-002-mock_sign_in_handoff UI: Login CTA가 signInHandoffClient를 통해 sign-in을 시작하고 진행 상태로 전환한다.
    // onboarding scope를 통해 loginTapped가 전달될 때 signInHandoffClient를 사용하면 sign-in 진행 상태가 올바르게 반영되는지 검증한다.
    // - 검증 내용: `.accessUnlock(.loginTapped)` 전송 → isSignInInProgress=true.
    // - 사전 조건: signed-out 상태 (hasAccountSession=false), signInHandoffClient가 failure 반환.
    // - 기대 결과: isSignInInProgress=true.

    // MARK: - ONB-002 Refresh Access CTA action dispatch

    // ONB-002 UI: Refresh Access CTA가 refreshAccessTapped 액션을 디스패치하면 access status fetch가 시작된다.
    // onboarding scope를 통해 refreshAccessTapped가 전달될 때 fetch effect가 실행되는지 검증합니다.
    // - 검증 내용: `.accessUnlock(.refreshAccessTapped)` 전송 → fetchGeneration 증가, status fetch effect 실행.
    // - 사전 조건: signed-in, status=revoked (blocked), canRefreshAccess=true.
    // - 기대 결과: fetchGeneration이 1 증가하고 accessStatusResponse 수신.

    // MARK: - ONB-002 Onboarding trailing action integration

    // ONB-002 UI: onboarding accessUnlock step에서 signed-out 상태이면 Next/Activate/Retry가 모두 비활성화된다.
    // 세션이 없을 때 trailing action이 Next를 disable하는지 onboarding 상태로 검증합니다.
    // - 검증 내용: accessUnlock signed-out → canGoNext=false.
    // - 사전 조건: currentStep=accessUnlock, hasAccountSession=false.
    // - 기대 결과: canGoNext=false, showsRetry=false.

    // ONB-002 UI: onboarding accessUnlock step에서 complete 상태이면 Next가 활성화된다.
    // 라이선스가 active로 확인되면 trailing action이 Next를 enable하는지 검증합니다.
    // - 검증 내용: accessUnlock complete → canGoNext=true.
    // - 사전 조건: currentStep=accessUnlock, isComplete=true, status=active.
    // - 기대 결과: canGoNext=true.

    // ONB-002 UI: active/binding complete flag가 있어도 session이 없으면 Next는 비활성화된다.

    /// ONB-002 UI: loginTapped는 직접 entitlement 상태를 변경하지 않고 sign-in 진행 상태만 설정한다.
    /// - 검증 내용: loginTapped 후 status/snapshot/isComplete가 변경되지 않음.
    /// - 사전 조건: signed-out 상태.
    /// - 기대 결과: isSignInInProgress=true, status/snapshot/isComplete는 초기 상태 유지.
    func testLoginTappedDoesNotMutateEntitlementState() async {
        let store = TestStore(initialState: AccountAccessFeature.State()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.signInHandoffClient = SignInHandoffClient { _ in .failure }
        }

        let originalStatus = store.state.status
        let originalSnapshot = store.state.snapshot
        let originalIsComplete = store.state.isComplete

        await store.send(.loginTapped(context: .onboarding, scope: .onboarding)) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
            state.handoffTransaction = AccountAccessHandoffTransaction(context: .onboarding, scope: .onboarding)
            state.handoffGeneration = 1
        }

        XCTAssertEqual(store.state.status, originalStatus)
        XCTAssertEqual(store.state.snapshot, originalSnapshot)
        XCTAssertEqual(store.state.isComplete, originalIsComplete)

        await store.receive(\.signInHandoffCompleted) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.errorMessage = "Check your network connection and try again."
            state.handoffTransaction = nil
        }

        await store.finish()
    }

    /// ONB-002 UI: refreshAccessTapped는 signed-in 상태에서만 동작한다.
    /// signed-out 상태에서 refreshAccessTapped가 no-op인지 검증합니다.
    /// - 검증 내용: signed-out에서 refreshAccessTapped → 상태 변경 없음.
    /// - 사전 조건: hasAccountSession=false.
    /// - 기대 결과: 상태 변화 없음.
    func testRefreshAccessTappedNoopWhenSignedOut() async {
        let store = TestStore(initialState: AccountAccessFeature.State()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { StateMutation.activeAccessResponse },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            )
        }

        XCTAssertFalse(store.state.canRefreshAccess)

        // no-op: 상태 변화 없음
        await store.send(.refreshAccessTapped)

        await store.finish()
    }

    // MARK: - ONB-002 CTA projection (VOY-397)

    /// VOY-397: entitlement `none` 상태에서 Web Pricing CTA가 primary여야 한다.
    /// direct checkout(openCheckoutTapped)이 아닌 Web Pricing(openPricingTapped) 경로를 사용하는지 상태 투영으로 검증.
    /// - 검증 내용: hasAccountSession=true, status=.none → accessUnlockPrimaryCTA == .webPricing.
    /// - 사전 조건: 세션 있음, entitlement none.
    /// - 기대 결과: accessUnlockPrimaryCTA == .webPricing (NOT .checkout).
    func testNoneEntitlementProjectsWebPricingCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = AccessStatus.none

        XCTAssertEqual(
            state.accessUnlockPrimaryCTA,
            .webPricing,
            "none entitlement에서 Web Pricing CTA가 primary여야 함",
        )
        XCTAssertTrue(state.canRefreshAccess, "none 상태에서 Refresh Access도 활성화되어야 함")
    }

    /// VOY-397: retryable error 상태에서 Retry CTA만 primary여야 한다.
    /// error 상태에서 Web Pricing/pricing recovery가 표시되지 않는지 상태 투영으로 검증.
    /// - 검증 내용: hasAccountSession=true, status=.networkFailure → accessUnlockPrimaryCTA == .retry.
    /// - 사전 조건: 세션 있음, 네트워크 실패.
    /// - 기대 결과: accessUnlockPrimaryCTA == .retry (NOT .webPricing).
    func testRetryableErrorProjectsRetryOnlyCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .networkFailure

        XCTAssertEqual(
            state.accessUnlockPrimaryCTA,
            .retry,
            "retryable error에서 Retry CTA가 primary여야 함",
        )
        XCTAssertNotEqual(
            state.accessUnlockPrimaryCTA,
            .webPricing,
            "error 상태에서 Web Pricing이 표시되지 않아야 함",
        )
    }

    /// VOY-397: direct checkout CTA가 core ONB recovery 경로에서 표시되지 않는다.
    /// AccessUnlockPrimaryCTA enum에 checkout 케이스가 존재하지 않음으로 검증.
    /// - 검증 내용: 모든 blocked 상태에서 accessUnlockPrimaryCTA가 webPricing 또는 retry.
    func testDirectCheckoutHiddenFromOnbRecovery() {
        let blockedStatuses: [AccessStatus] = [AccessStatus.none, .trialExpired, .revoked, .refunded]

        for status in blockedStatuses {
            var state = AccountAccessFeature.State()
            state.hasAccountSession = true
            state.status = status

            XCTAssertEqual(
                state.accessUnlockPrimaryCTA,
                .webPricing,
                "\(status) 상태에서 Web Pricing CTA가 표시되어야 함 (direct checkout 아님)",
            )
        }
    }

    /// VOY-397: signed-out 상태에서 Login CTA가 primary여야 한다 (Web Pricing이 아님).
    /// - 검증 내용: hasAccountSession=false → accessUnlockPrimaryCTA == .login.
    func testSignedOutProjectsLoginCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = false

        XCTAssertEqual(state.accessUnlockPrimaryCTA, .login)
        XCTAssertNotEqual(state.accessUnlockPrimaryCTA, .webPricing)
    }

    /// VOY-397: complete 상태에서 Next CTA가 primary여야 한다.
    /// - 검증 내용: status=coreLicenseActive, isComplete=true → accessUnlockPrimaryCTA == .next.
    func testCompleteProjectsNextCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .coreLicenseActive
        state.isComplete = true

        XCTAssertEqual(state.accessUnlockPrimaryCTA, .next)
    }

    /// ONB-002-show_access_status: Onboarding은 canonical access status의 semantic projection을 CTA와 독립적으로 보존한다.
    /// - 검증 내용: nil, network failure, none, expired, revoked, refunded, active의 개별 semantic 상태와 기존 primary CTA
    /// - 사전 조건: current account session이 있고 각 canonical access status가 설정됨
    /// - 기대 결과: semantic 상태는 구분되고 기존 CTA family는 변경되지 않음
    func testAccessProjectionPreservesSemanticStatusesWithoutChangingPrimaryCTA() {
        struct EntitlementCase {
            let status: AccessStatus?
            let expectedEntitlementState: OnboardingAccessProjection.EntitlementState
            let expectedCTA: OnboardingAccessProjection.PrimaryCTA
        }

        let cases: [EntitlementCase] = [
            .init(status: nil, expectedEntitlementState: .unknown, expectedCTA: .pending),
            .init(status: .networkFailure, expectedEntitlementState: .unavailable, expectedCTA: .retry),
            .init(status: AccessStatus.none, expectedEntitlementState: .none, expectedCTA: .webPricing),
            .init(status: .trialExpired, expectedEntitlementState: .expired, expectedCTA: .webPricing),
            .init(status: .revoked, expectedEntitlementState: .revoked, expectedCTA: .webPricing),
            .init(status: .refunded, expectedEntitlementState: .refunded, expectedCTA: .webPricing),
            .init(status: .coreLicenseActive, expectedEntitlementState: .active, expectedCTA: .pending),
        ]

        for testCase in cases {
            var accountAccess = AccountAccessFeature.State()
            accountAccess.hasAccountSession = true
            accountAccess.status = testCase.status
            let projection = OnboardingAccessProjection(accountAccess: accountAccess)

            XCTAssertEqual(projection.entitlementState, testCase.expectedEntitlementState)
            XCTAssertEqual(projection.primaryCTA, testCase.expectedCTA)
        }
    }

    // MARK: - ONB-002-mock_sign_in_handoff

    // ONB-002-mock_sign_in_handoff: Login CTA가 mock handoff 진행 중에 isSignInInProgress와 pending 상태를 표시한다.
    // onboarding scope를 통해 loginTapped가 전달될 때 signInHandoffClient를 사용하면 sign-in 진행 상태가 올바르게 반영되는지 검증한다.
    // - 검증 내용: `.accessUnlock(.loginTapped)` 전송 → isSignInInProgress=true, accountAccessAuthAxis=signInInProgress,
    // accountAccessStepState=pending
    // - 사전 조건: signed-out 상태 (hasAccountSession=false), signInHandoffClient가 지연 후 success 반환
    // - 기대 결과: isSignInInProgress=true, accountAccessAuthAxis==.signInInProgress, accountAccessStepState==.pending

    // MARK: - ONB-002-canonical_unlock_intents

    /// ONB-002-canonical_unlock_intents: unlock UI는 supported semantic intent만 canonical action으로 변환한다.
    /// 화면은 callback, timer, generation 같은 AccountAccess 내부 action 대신 사용자 의도를 전달합니다.
    /// - 검증 내용: 모든 supported intent가 대응하는 canonical AccountAccess action으로 정확히 매핑됩니다.
    /// - 사전 조건: narrow `OnboardingAccessIntent` contract를 사용합니다.
    /// - 기대 결과: UI contract에 internal callback/result action을 노출하지 않습니다.
    func testUnlockUIContractMapsOnlySupportedCanonicalIntents() {
        let mappings: [(OnboardingAccessIntent, (AccountAccessAction) -> Bool)] = [
            (
                .login,
                { if case .loginTapped(context: .onboarding, scope: .onboarding) = $0 { true } else { false } },
            ),
            (.refresh, { if case .refreshAccessTapped = $0 { true } else { false } }),
            (.retry, { if case .retryTapped = $0 { true } else { false } }),
            (.cancelSignIn, { if case .cancelSignIn = $0 { true } else { false } }),
            (.openPricing, { if case .openPricingTapped = $0 { true } else { false } }),
            (.openAccount, { if case .openAccountTapped = $0 { true } else { false } }),
            (.openAccessHelp, { if case .openAccessHelpTapped = $0 { true } else { false } }),
        ]

        for (intent, matchesExpectedAction) in mappings {
            XCTAssertTrue(matchesExpectedAction(intent.accountAccessAction))
        }
    }
}

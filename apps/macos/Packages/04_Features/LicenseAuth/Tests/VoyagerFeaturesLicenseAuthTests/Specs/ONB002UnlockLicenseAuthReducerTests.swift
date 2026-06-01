// swiftlint:disable force_unwrapping

@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesLicenseAuth
import XCTest

/*
 ONB-002-present_access_unlock_step reducer 증거 계약

 포함한 interaction_id:
 - ONB-002-show_access_unlock_status: access status snapshot을 활성/비활성 상태로 계산한다.
 - ONB-002-start_access_unlock_recovery: license key와 beta code 입력, retry, mode 전환을 처리한다.
 - ONB-002-apply_access_unlock_result: Core License, beta trial, expired/revoked/network 결과를 unlock 여부와 delegate로 반영한다.

 Fixture reset:
 - `TestStore`와 in-memory `LicenseAuthClient`만 사용하므로 영구 credential fixture가 필요 없다.
 */

@MainActor
final class ONB002UnlockLicenseAuthReducerTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTestStore(
        licenseAuthClient: LicenseAuthClient = .mock,
        initialState: UnlockLicenseAuthFeature.State = UnlockLicenseAuthFeature.State(),
    ) -> TestStore<UnlockLicenseAuthFeature.State, UnlockLicenseAuthFeature.Action> {
        TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = licenseAuthClient
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
    }

    private func signedInInitialState() -> UnlockLicenseAuthFeature.State {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        return state
    }

    private func makeCheckoutURLClient(
        openCount: LockIsolated<Int>,
        checkoutCount: LockIsolated<Int>,
        pricingCount: LockIsolated<Int>,
        supportCount: LockIsolated<Int>,
        openedURLs: LockIsolated<[URL]>,
    ) -> CheckoutURLClient {
        CheckoutURLClient(
            openURL: { url in
                openCount.withValue { $0 += 1 }
                openedURLs.withValue { $0.append(url) }
            },
            checkoutURL: {
                checkoutCount.withValue { $0 += 1 }
                return URL(string: "http://test.test/checkout")!
            },
            pricingURL: {
                pricingCount.withValue { $0 += 1 }
                return URL(string: "http://test.test/pricing")!
            },
            supportURL: {
                supportCount.withValue { $0 += 1 }
                return URL(string: "http://test.test/support")!
            },
        )
    }

    // MARK: - ONB-002-show_access_unlock_status (Auth Axis + Access Step Interpretation)

    /// ONB-002-show_access_unlock_status
    /// 기본 상태(초기 진입): authAxis == .signedOut, accessStepState == .blocked
    /// signed-out 상태에서는 Login CTA가 보이고 Next 비활성화
    func testInitialDerivesSignedOutAndBlocked() {
        let state = UnlockLicenseAuthFeature.State()

        XCTAssertEqual(state.onb002AuthAxis, .signedOut)
        XCTAssertEqual(state.onb002AccessStepState, .blocked)
        XCTAssertTrue(state.canStartLogin)
        XCTAssertFalse(state.canRefreshAccess)
        XCTAssertFalse(state.canRetry)
        XCTAssertTrue(state.requiresAccountSession)
    }

    /// ONB-002-show_access_unlock_status
    /// signInFailed: authAxis == .signInFailed, accessStepState == .blocked
    /// 로그인 실패 시 Login CTA 다시 노출
    func testSignInFailedDerivesBlockedWithLoginCTA() {
        var state = UnlockLicenseAuthFeature.State()
        state.didSignInFail = true

        XCTAssertEqual(state.onb002AuthAxis, .signInFailed)
        XCTAssertEqual(state.onb002AccessStepState, .blocked)
        XCTAssertTrue(state.canStartLogin)
        XCTAssertFalse(state.canRefreshAccess)
        XCTAssertFalse(state.canRetry)
        XCTAssertTrue(state.requiresAccountSession)
    }

    /// ONB-002-show_access_unlock_status
    /// signedIn + status == nil: authAxis == .signedIn, accessStepState == .pending
    /// 로그인 완료 후 access status 조회 전 pending 상태
    func testSignedInNoStatusDerivesPending() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true

        XCTAssertEqual(state.onb002AuthAxis, .signedIn)
        XCTAssertEqual(state.onb002AccessStepState, .pending)
        XCTAssertFalse(state.canStartLogin)
        XCTAssertTrue(state.canRefreshAccess)
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.requiresAccountSession)
    }

    // MARK: - ONB-002-apply_access_unlock_result (Active PRODUCT Access Statuses → Complete)

    /// ONB-002-apply_access_unlock_result
    /// coreLicenseActive + signedIn → complete
    /// PRODUCT TOML: access_unlock_complete_for = ["core_license_active"]
    func testCoreLicenseActiveDerivesComplete() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .coreLicenseActive

        XCTAssertEqual(state.onb002AuthAxis, .signedIn)
        XCTAssertEqual(state.onb002AccessStepState, .complete)
        XCTAssertFalse(state.canStartLogin)
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.requiresAccountSession)
    }

    /// ONB-002-apply_access_unlock_result
    /// betaTrialActive + signedIn → complete
    /// PRODUCT TOML: access_unlock_complete_for = ["beta_trial_active"]
    func testBetaTrialActiveDerivesComplete() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .betaTrialActive

        XCTAssertEqual(state.onb002AuthAxis, .signedIn)
        XCTAssertEqual(state.onb002AccessStepState, .complete)
    }

    /// ONB-002-apply_access_unlock_result
    /// internalTestActive + signedIn → complete
    /// PRODUCT TOML: access_unlock_complete_for = ["internal_test_active"]
    func testInternalTestActiveDerivesComplete() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .internalTestActive

        XCTAssertEqual(state.onb002AuthAxis, .signedIn)
        XCTAssertEqual(state.onb002AccessStepState, .complete)
    }

    // MARK: - ONB-002-apply_access_unlock_result (Blocked PRODUCT Access Statuses → Blocked)

    /// ONB-002-apply_access_unlock_result
    /// none + signedIn → blocked
    /// PRODUCT TOML: access_unlock_blocked_for = ["none"]
    func testNoneStatusDerivesBlocked() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = LicenseAuthStatus.none

        XCTAssertEqual(state.onb002AccessStepState, .blocked)
    }

    /// ONB-002-apply_access_unlock_result
    /// trialExpired + signedIn → blocked
    /// PRODUCT TOML: access_unlock_blocked_for = ["trial_expired"]
    func testTrialExpiredDerivesBlocked() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .trialExpired

        XCTAssertEqual(state.onb002AccessStepState, .blocked)
    }

    /// ONB-002-apply_access_unlock_result
    /// revoked + signedIn → blocked
    /// PRODUCT TOML: access_unlock_blocked_for = ["revoked"]
    func testRevokedStatusDerivesBlocked() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .revoked

        XCTAssertEqual(state.onb002AccessStepState, .blocked)
    }

    /// ONB-002-apply_access_unlock_result
    /// refunded + signedIn → blocked
    /// PRODUCT TOML: access_unlock_blocked_for = ["refunded"]
    func testRefundedStatusDerivesBlocked() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .refunded

        XCTAssertEqual(state.onb002AccessStepState, .blocked)
    }

    // MARK: - ONB-002-apply_access_unlock_result (Error States)

    /// ONB-002-apply_access_unlock_result
    /// networkFailure + signedIn → error (retryable)
    func testNetworkFailureDerivesError() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .networkFailure

        XCTAssertEqual(state.onb002AccessStepState, .error)
        XCTAssertTrue(state.canRetry)
    }

    // MARK: - ONB-002-show_access_unlock_status (Settings Entitlement Guard)

    /// ONB-002-show_access_unlock_status
    /// Settings entitlement axis 값은 ONB raw access_status로 대체 불가
    /// hasAccountSession == false면 status가 active여도 blocked
    func testActiveStatusWithoutSessionDerivesBlocked() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = false
        state.status = .coreLicenseActive

        XCTAssertEqual(state.onb002AuthAxis, .signedOut)
        XCTAssertEqual(state.onb002AccessStepState, .blocked)
        XCTAssertTrue(state.requiresAccountSession)
        XCTAssertTrue(state.canStartLogin)
    }

    // MARK: - ONB-002-show_access_unlock_status (Affordance Guards)

    /// ONB-002-show_access_unlock_status
    /// canRefreshAccess: signedIn + not submitting + not signInInProgress
    func testCanRefreshAccessWhenSignedIn() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true

        XCTAssertTrue(state.canRefreshAccess)
    }

    /// ONB-002-show_access_unlock_status
    /// canRefreshAccess == false when signed out
    func testCannotRefreshAccessWhenSignedOut() {
        var state = UnlockLicenseAuthFeature.State()

        XCTAssertFalse(state.canRefreshAccess)
    }

    /// ONB-002-show_access_unlock_status
    /// canRefreshAccess == false when submitting
    func testCannotRefreshAccessWhenSubmitting() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.isSubmitting = true

        XCTAssertFalse(state.canRefreshAccess)
    }

    /// ONB-002-show_access_unlock_status
    /// canRetry: error 상태에서 retry 가능
    func testCanRetryWhenNetworkFailure() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .networkFailure

        XCTAssertTrue(state.canRetry)
    }

    /// ONB-002-show_access_unlock_status
    /// canRetry == false when status is active (complete)
    func testCannotRetryWhenComplete() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .coreLicenseActive

        XCTAssertFalse(state.canRetry)
    }

    /// ONB-002-show_access_unlock_status
    /// canRetry == false when submitting
    func testCannotRetryWhenSubmitting() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .networkFailure
        state.isSubmitting = true

        XCTAssertFalse(state.canRetry)
    }

    // MARK: - ONB-002-start_access_unlock_recovery

    /// ONB-002-start_access_unlock_recovery
    /// onAppear에서 세션이 없으면 signed-out blocked 상태로 진입하고 access-status를 조회하지 않는다.
    /// - 검증 내용: restoreSession이 nil을 반환하면 hasAccountSession == false, fetchAccessStatus 미호출
    /// - 사전 조건: restoreSession → nil
    /// - 기대 결과: authAxis == .signedOut, accessStepState == .blocked, fetchAccessStatus 호출 없음
    func testOnAppearWithNoSessionShowsLoginCTAWithoutFetchingAccessStatus() async {
        nonisolated(unsafe) var fetchCalled = false
        let store = makeTestStore(
            licenseAuthClient: LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCalled = true
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            ),
        )
        // store.exhaustivity = .off: didBecomeActive 관찰 effect는 장기 수명이라 종료를 기다리지 않는다.
        store.exhaustivity = .off

        await store.send(.onAppear)

        await store.receive(\._onAppearSessionRestored)

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertEqual(store.state.onb002AuthAxis, .signedOut)
        XCTAssertEqual(store.state.onb002AccessStepState, .blocked)
        XCTAssertFalse(fetchCalled)
    }

    /// ONB-002-start_access_unlock_recovery
    /// onAppear에서 세션이 있으면 hasAccountSession = true로 설정하고 access-status를 조회한다.
    /// - 검증 내용: restoreSession이 세션을 반환하면 signed-in 상태로 전이 후 fetchAccessStatus 호출
    /// - 사전 조건: restoreSession → LicenseAuthSession
    /// - 기대 결과: hasAccountSession == true, fetchAccessStatus 호출됨
    func testOnAppearWithSessionRestoresAndFetchesAccessStatus() async {
        nonisolated(unsafe) var fetchCalled = false
        let store = makeTestStore(
            licenseAuthClient: LicenseAuthClient(
                restoreSession: {
                    LicenseAuthSession(accessToken: "test-token", status: .coreLicenseActive)
                },
                fetchAccessStatus: {
                    fetchCalled = true
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            ),
        )
        // store.exhaustivity = .off: didBecomeActive 관찰 effect는 장기 수명이라 종료를 기다리지 않는다.
        store.exhaustivity = .off

        await store.send(.onAppear)

        await store.receive(\._onAppearSessionRestored) { state in
            state.hasAccountSession = true
            state.fetchGeneration = 1
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.status = .coreLicenseActive
            state.isComplete = true
            state.snapshot = LicenseAuthStatusSnapshot(
                status: .coreLicenseActive,
                entitlements: [.coreLicense],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertTrue(fetchCalled)
        XCTAssertTrue(store.state.hasAccountSession)
    }

    /// ONB-002-mock_sign_in_handoff: signInHandoffClient를 통한 로그인이 signInInProgress를 설정한다.
    /// - 검증 내용: loginTapped 액션이 signInHandoffClient Effect를 트리거하고 상태를 signInInProgress로 변경
    /// - 사전 조건: signed-out 상태
    /// - 기대 결과: isSignInInProgress == true, signInHandoffClient를 통해 Effect 실행
    func testLoginTappedTriggersSignInHandoffAndSetsSignInInProgress() async {
        nonisolated(unsafe) var handoffCalled = false
        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = .mock
            $0.signInHandoffClient = SignInHandoffClient {
                handoffCalled = true
                return .failure
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginTapped) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
        }

        XCTAssertTrue(handoffCalled)
        await store.receive(\.signInHandoffCompleted) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }
        await store.finish()
    }

    /// ONB-002-start_access_unlock_recovery
    /// signInInProgress 중에는 중복 loginTapped이 무시된다.
    /// - 검증 내용: isSignInInProgress == true일 때 loginTapped no-op
    /// - 사전 조건: signInInProgress 상태
    /// - 기대 결과: 상태 변화 없음, URL opener 재호출 없음
    func testDuplicateLoginTappedIgnoredDuringSignInInProgress() async {
        nonisolated(unsafe) var openCount = 0
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.isSignInInProgress = true

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = .mock
            $0.loginURLClient = LoginURLClient(
                openLoginURL: { _ in
                    openCount += 1
                },
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginTapped)

        XCTAssertEqual(openCount, 0)
        await store.finish()
    }

    // MARK: - ONB-002-open_external_url_redirect

    /// ONB-002-open_checkout_tapped: checkout CTA가 checkout URL을 한 번 열고 다른 URL은 호출하지 않는다.
    /// 구매 CTA가 checkoutURLClient의 checkoutURL → openURL 경로를 타는지 검증합니다.
    /// - 검증 내용: `.openCheckoutTapped` 전송 후 checkoutURL 1회, openURL 1회, 나머지 URL 메서드 0회.
    /// - 사전 조건: checkoutURLClient spy 설정, 초기 상태.
    /// - 기대 결과: checkout URL이 브라우저 열기 경로로 전달됩니다.
    func testOpenCheckoutTappedOpensCheckoutURL() async {
        let openCount = LockIsolated(0)
        let checkoutCount = LockIsolated(0)
        let pricingCount = LockIsolated(0)
        let supportCount = LockIsolated(0)
        let openedURLs = LockIsolated<[URL]>([])

        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.checkoutURLClient = self.makeCheckoutURLClient(
                openCount: openCount,
                checkoutCount: checkoutCount,
                pricingCount: pricingCount,
                supportCount: supportCount,
                openedURLs: openedURLs,
            )
        }

        await store.send(.openCheckoutTapped)
        await store.finish()

        XCTAssertEqual(checkoutCount.value, 1)
        XCTAssertEqual(pricingCount.value, 0)
        XCTAssertEqual(supportCount.value, 0)
        XCTAssertEqual(openCount.value, 1)
        XCTAssertEqual(openedURLs.value, [URL(string: "http://test.test/checkout")!])
    }

    /// ONB-002-open_pricing_tapped: pricing CTA가 pricing URL을 한 번 열고 다른 URL은 호출하지 않는다.
    /// 요금제 CTA가 checkoutURLClient의 pricingURL → openURL 경로를 타는지 검증합니다.
    /// - 검증 내용: `.openPricingTapped` 전송 후 pricingURL 1회, openURL 1회, 나머지 URL 메서드 0회.
    /// - 사전 조건: checkoutURLClient spy 설정, 초기 상태.
    /// - 기대 결과: pricing URL이 브라우저 열기 경로로 전달됩니다.
    func testOpenPricingTappedOpensPricingURL() async {
        let openCount = LockIsolated(0)
        let checkoutCount = LockIsolated(0)
        let pricingCount = LockIsolated(0)
        let supportCount = LockIsolated(0)
        let openedURLs = LockIsolated<[URL]>([])

        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.checkoutURLClient = self.makeCheckoutURLClient(
                openCount: openCount,
                checkoutCount: checkoutCount,
                pricingCount: pricingCount,
                supportCount: supportCount,
                openedURLs: openedURLs,
            )
        }

        await store.send(.openPricingTapped)
        await store.finish()

        XCTAssertEqual(checkoutCount.value, 0)
        XCTAssertEqual(pricingCount.value, 1)
        XCTAssertEqual(supportCount.value, 0)
        XCTAssertEqual(openCount.value, 1)
        XCTAssertEqual(openedURLs.value, [URL(string: "http://test.test/pricing")!])
    }

    /// ONB-002-open_access_help_tapped: access help CTA가 support URL을 한 번 열고 다른 URL은 호출하지 않는다.
    /// 접근 도움 CTA가 checkoutURLClient의 supportURL → openURL 경로를 타는지 검증합니다.
    /// - 검증 내용: `.openAccessHelpTapped` 전송 후 supportURL 1회, openURL 1회, 나머지 URL 메서드 0회.
    /// - 사전 조건: checkoutURLClient spy 설정, 초기 상태.
    /// - 기대 결과: support URL이 브라우저 열기 경로로 전달됩니다.
    func testOpenAccessHelpTappedOpensHelpURL() async {
        let openCount = LockIsolated(0)
        let checkoutCount = LockIsolated(0)
        let pricingCount = LockIsolated(0)
        let supportCount = LockIsolated(0)
        let openedURLs = LockIsolated<[URL]>([])

        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.checkoutURLClient = self.makeCheckoutURLClient(
                openCount: openCount,
                checkoutCount: checkoutCount,
                pricingCount: pricingCount,
                supportCount: supportCount,
                openedURLs: openedURLs,
            )
        }

        await store.send(.openAccessHelpTapped)
        await store.finish()

        XCTAssertEqual(checkoutCount.value, 0)
        XCTAssertEqual(pricingCount.value, 0)
        XCTAssertEqual(supportCount.value, 1)
        XCTAssertEqual(openCount.value, 1)
        XCTAssertEqual(openedURLs.value, [URL(string: "http://test.test/support")!])
    }

    /// ONB-002-open_beta_code_help_tapped: beta code help CTA가 support URL을 한 번 열고 다른 URL은 호출하지 않는다.
    /// 베타 코드 도움 CTA가 checkoutURLClient의 supportURL → openURL 경로를 타는지 검증합니다.
    /// - 검증 내용: `.openBetaCodeHelpTapped` 전송 후 supportURL 1회, openURL 1회, 나머지 URL 메서드 0회.
    /// - 사전 조건: checkoutURLClient spy 설정, 초기 상태.
    /// - 기대 결과: support URL이 브라우저 열기 경로로 전달됩니다.
    func testOpenBetaCodeHelpTappedOpensHelpURL() async {
        let openCount = LockIsolated(0)
        let checkoutCount = LockIsolated(0)
        let pricingCount = LockIsolated(0)
        let supportCount = LockIsolated(0)
        let openedURLs = LockIsolated<[URL]>([])

        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.checkoutURLClient = self.makeCheckoutURLClient(
                openCount: openCount,
                checkoutCount: checkoutCount,
                pricingCount: pricingCount,
                supportCount: supportCount,
                openedURLs: openedURLs,
            )
        }

        await store.send(.openBetaCodeHelpTapped)
        await store.finish()

        XCTAssertEqual(checkoutCount.value, 0)
        XCTAssertEqual(pricingCount.value, 0)
        XCTAssertEqual(supportCount.value, 1)
        XCTAssertEqual(openCount.value, 1)
        XCTAssertEqual(openedURLs.value, [URL(string: "http://test.test/support")!])
    }

    /// ONB-002-start_access_unlock_recovery
    /// Deep-link 콜백 URL이 유효하면 restoreSession 후 signed-in 상태로 전이한다.
    /// - 검증 내용: voyager://auth/callback 수신 → restoreSession 성공 → hasAccountSession = true
    /// - 사전 조건: signInInProgress 상태, restoreSession이 세션 반환
    /// - 기대 결과: isSignInInProgress = false, hasAccountSession = true, fetchAccessStatus 트리거
    func testLoginCallbackReceivedWithValidURLRestoresSession() async {
        nonisolated(unsafe) var fetchCalled = false
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.isSignInInProgress = true

        let callbackURL = URL(string: "voyager://auth/callback")!

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: {
                    LicenseAuthSession(accessToken: "restored-token", status: .coreLicenseActive)
                },
                fetchAccessStatus: {
                    fetchCalled = true
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in })
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginCallbackReceived(callbackURL))

        await store.receive(\._loginSessionRestored) { state in
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.fetchGeneration = 1
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.status = .coreLicenseActive
            state.isComplete = true
            state.snapshot = LicenseAuthStatusSnapshot(
                status: .coreLicenseActive,
                entitlements: [.coreLicense],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertTrue(fetchCalled)
        XCTAssertFalse(store.state.isSignInInProgress)
        XCTAssertTrue(store.state.hasAccountSession)
        await store.finish()
    }

    /// ONB-002-start_access_unlock_recovery
    /// Malformed callback URL → sign-in failed, no crash.
    /// - 검증 내용: 유효하지 않은 URL 수신 시 signInFailed 상태로 전이
    /// - 사전 조건: signInInProgress 상태
    /// - 기대 결과: isSignInInProgress = false, didSignInFail = true, fetchAccessStatus 미호출
    func testLoginCallbackReceivedWithMalformedURLFailsSignIn() async {
        nonisolated(unsafe) var fetchCalled = false
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.isSignInInProgress = true

        let malformedURL = URL(string: "voyager://auth/invalid-path")!

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCalled = true
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in })
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginCallbackReceived(malformedURL)) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }

        XCTAssertFalse(fetchCalled)
        XCTAssertTrue(store.state.didSignInFail)
        XCTAssertEqual(store.state.onb002AuthAxis, .signInFailed)
        XCTAssertEqual(store.state.onb002AccessStepState, .blocked)
        await store.finish()
    }

    /// ONB-002-start_access_unlock_recovery
    /// Deep-link 콜백 후 restoreSession이 nil을 반환하면 sign-in failed 상태.
    /// - 검증 내용: 유효한 callback URL이지만 세션 복원 실패 시 signInFailed
    /// - 사전 조건: signInInProgress, restoreSession → nil
    /// - 기대 결과: didSignInFail = true, hasAccountSession = false
    func testLoginCallbackReceivedWithValidURLButNoSessionFails() async {
        nonisolated(unsafe) var fetchCalled = false
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.isSignInInProgress = true

        let callbackURL = URL(string: "voyager://auth/callback")!

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCalled = true
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in })
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginCallbackReceived(callbackURL))

        await store.receive(\._loginSessionRestored) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }

        XCTAssertFalse(fetchCalled)
        XCTAssertTrue(store.state.didSignInFail)
        XCTAssertFalse(store.state.hasAccountSession)
        await store.finish()
    }

    /// ONB-002-start_access_unlock_recovery
    /// Login alone does NOT complete the step — isComplete remains false.
    /// - 검증 내용: loginTapped 후 isComplete == false
    /// - 사전 조건: signed-out 상태
    /// - 기대 결과: isSignInInProgress = true, isComplete = false
    func testLoginAloneDoesNotCompleteStep() async {
        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = .mock
            $0.signInHandoffClient = SignInHandoffClient { .failure }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginTapped) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
        }

        await store.receive(\.signInHandoffCompleted) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }

        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// ONB-002-start_access_unlock_recovery
    /// Non-auth voyager URL (e.g. voyager://other/path) → sign-in failed, no crash.
    /// - 검증 내용: auth/callback이 아닌 voyager URL은 무시/실패 처리
    /// - 사전 조건: signInInProgress 상태
    /// - 기대 결과: didSignInFail = true, fetchAccessStatus 미호출
    func testNonAuthVoyagerURLReturnsSignInFailed() async {
        nonisolated(unsafe) var fetchCalled = false
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.isSignInInProgress = true

        let otherURL = URL(string: "voyager://other/path")!

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCalled = true
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in })
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginCallbackReceived(otherURL)) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }

        XCTAssertFalse(fetchCalled)
        XCTAssertTrue(store.state.didSignInFail)
        await store.finish()
    }

    /// ONB-002-start_access_unlock_recovery
    /// Login failure → signed-out/sign-in-failed blocked 상태에서 Login CTA 다시 노출.
    /// - 검증 내용: signInFailed 후에도 canStartLogin == true
    /// - 사전 조건: didSignInFail = true
    /// - 기대 결과: canStartLogin == true, onb002AuthAxis == .signInFailed
    func testLoginFailureAllowsRetry() async {
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.isSignInInProgress = true

        let callbackURL = URL(string: "voyager://auth/callback")!

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in })
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginCallbackReceived(callbackURL))

        await store.receive(\._loginSessionRestored) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }

        XCTAssertTrue(store.state.canStartLogin)
        XCTAssertEqual(store.state.onb002AuthAxis, .signInFailed)
        await store.finish()
    }

    // MARK: - ONB-002-apply_access_unlock_result (Access Status Fetch Responses)

    /// ONB-002-apply_access_unlock_result
    /// Signed-in onAppear → access_status fetch returns blocked (none) → step blocked, Next disabled
    /// - 검증: fetchAccessStatus가 PRODUCT access_status `none` 반환 시 step이 blocked
    /// - 사전 조건: restoreSession이 세션 반환, fetchAccessStatus가 `.none` 반환
    /// - 기대 결과: onb002AccessStepState == .blocked, isComplete == false, errorMessage 설정
    func testOnAppearFetchesBlockedStatusShowsBlocked() async {
        let store = makeTestStore(
            licenseAuthClient: LicenseAuthClient(
                restoreSession: {
                    LicenseAuthSession(accessToken: "test-token", status: .none)
                },
                fetchAccessStatus: {
                    LicenseAuthStatusResponse(status: LicenseAuthStatus.none, entitlements: [])
                },
                signOut: {},
            ),
        )
        // store.exhaustivity = .off: didBecomeActive 관찰 effect는 장기 수명이라 종료를 기다리지 않는다.
        store.exhaustivity = .off

        await store.send(.onAppear)

        await store.receive(\._onAppearSessionRestored) { state in
            state.hasAccountSession = true
            state.fetchGeneration = 1
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.status = LicenseAuthStatus.none
            state.isComplete = false
            state.errorMessage = "Access denied."
            state.snapshot = LicenseAuthStatusSnapshot(
                status: LicenseAuthStatus.none,
                entitlements: [],
                fetchedAt: self.referenceDate,
            )
        }

        XCTAssertEqual(store.state.onb002AccessStepState, .blocked)
        XCTAssertFalse(store.state.isComplete)
    }

    /// ONB-002-apply_access_unlock_result
    /// Signed-in onAppear → access_status fetch returns network failure → step error
    /// - 검증: fetchAccessStatus 네트워크 실패 시 error 상태 + retry 가능
    /// - 사전 조건: restoreSession 성공, fetchAccessStatus가 networkFailure throw
    /// - 기대 결과: onb002AccessStepState == .error, canRetry == true
    func testOnAppearFetchNetworkFailureShowsError() async {
        let store = makeTestStore(
            licenseAuthClient: LicenseAuthClient(
                restoreSession: {
                    LicenseAuthSession(accessToken: "test-token", status: .coreLicenseActive)
                },
                fetchAccessStatus: {
                    throw LicenseAuthError.networkFailure
                },
                signOut: {},
            ),
        )
        // store.exhaustivity = .off: didBecomeActive 관찰 effect는 장기 수명이라 종료를 기다리지 않는다.
        store.exhaustivity = .off

        await store.send(.onAppear)

        await store.receive(\._onAppearSessionRestored) { state in
            state.hasAccountSession = true
            state.fetchGeneration = 1
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.isComplete = false
            state.errorMessage = "Network error. Please check your connection and try again."
            state.status = .networkFailure
        }

        XCTAssertEqual(store.state.onb002AccessStepState, .error)
        XCTAssertTrue(store.state.canRetry)
    }

    /// ONB-002-apply_access_unlock_result
    /// 서버가 클라이언트가 인식하지 못하는 status 값(예: "unexpected_future_status")을 반환하면
    /// decodingFailure가 발생한다. fetchAccessStatus가 decodingFailure를 throw할 때
    /// retry 가능한 error 상태로 표시되고 crash가 발생하지 않는지 검증한다.
    /// - 검증: fetchAccessStatus가 LicenseAuthError.decodingFailure throw 시 error message 표시, isComplete=false, crash 없음
    /// - 사전 조건: restoreSession 성공, fetchAccessStatus가 decodingFailure throw
    /// - 기대 결과: errorMessage="Failed to process the response.", isComplete=false, canRefreshAccess=true
    func testOnAppearFetchDecodingFailureShowsError() async {
        let store = makeTestStore(
            licenseAuthClient: LicenseAuthClient(
                restoreSession: {
                    LicenseAuthSession(accessToken: "test-token", status: .coreLicenseActive)
                },
                fetchAccessStatus: {
                    throw LicenseAuthError.decodingFailure
                },
                signOut: {},
            ),
        )
        // store.exhaustivity = .off: didBecomeActive 관찰 effect는 장기 수명이라 종료를 기다리지 않는다.
        store.exhaustivity = .off

        await store.send(.onAppear)

        await store.receive(\._onAppearSessionRestored) { state in
            state.hasAccountSession = true
            state.fetchGeneration = 1
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.isComplete = false
            state.errorMessage = "Failed to process the response."
        }

        XCTAssertFalse(store.state.isComplete)
        XCTAssertNotNil(store.state.errorMessage)
        XCTAssertTrue(store.state.canRefreshAccess)
    }

    // MARK: - ONB-002-start_access_unlock_recovery (Refresh Access)

    /// ONB-002-start_access_unlock_recovery
    /// `.refreshAccessTapped` when signed in triggers fetchAccessStatus and increments generation
    /// - 검증: refreshAccessTapped이 fetchAccessStatus를 트리거하고 generation을 증가시킴
    /// - 사전 조건: hasAccountSession == true (signed in)
    /// - 기대 결과: fetchGeneration 증가, fetchAccessStatus 호출됨, active 응답 시 isComplete = true
    func testRefreshAccessTappedWhenSignedInTriggersFetch() async {
        nonisolated(unsafe) var fetchCount = 0
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.hasAccountSession = true

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCount += 1
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.refreshAccessTapped) { state in
            state.fetchGeneration = 1
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.status = .coreLicenseActive
            state.isComplete = true
            state.snapshot = LicenseAuthStatusSnapshot(
                status: .coreLicenseActive,
                entitlements: [.coreLicense],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(store.state.fetchGeneration, 1)
        XCTAssertTrue(store.state.isComplete)
        await store.finish()
    }

    /// ONB-002-start_access_unlock_recovery
    /// `.refreshAccessTapped` when signed out → no-op, no fetch triggered
    /// - 검증: signed-out 상태에서 refreshAccessTapped 무시
    /// - 사전 조건: hasAccountSession == false
    /// - 기대 결과: fetchGeneration 변화 없음, fetchAccessStatus 미호출
    func testRefreshAccessTappedWhenSignedOutIgnored() async {
        nonisolated(unsafe) var fetchCalled = false
        let store = makeTestStore(
            licenseAuthClient: LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCalled = true
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            ),
        )

        await store.send(.refreshAccessTapped)

        XCTAssertFalse(fetchCalled)
        XCTAssertEqual(store.state.fetchGeneration, 0)
        await store.finish()
    }

    /// ONB-002-start_access_unlock_recovery
    /// `.refreshAccessTapped` during submit → no-op
    /// - 검증: isSubmitting 상태에서 refreshAccessTapped 무시
    /// - 사전 조건: hasAccountSession == true, isSubmitting == true
    /// - 기대 결과: fetchAccessStatus 미호출, 상태 변화 없음
    func testRefreshAccessTappedDuringSubmitIgnored() async {
        nonisolated(unsafe) var fetchCalled = false
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.hasAccountSession = true
        initialState.isSubmitting = true

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCalled = true
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.refreshAccessTapped)

        XCTAssertFalse(fetchCalled)
        await store.finish()
    }

    // MARK: - ONB-002-start_access_unlock_recovery (Foreground Activation Refresh)

    /// ONB-002-start_access_unlock_recovery
    /// 앱이 foreground로 돌아오면 signed-in 상태에서 access status를 다시 조회한다.
    /// - 검증 내용: appDidBecomeActive가 fetchAccessStatus를 트리거하고 generation을 증가시킴
    /// - 사전 조건: hasAccountSession == true
    /// - 기대 결과: fetchGeneration 증가, fetchAccessStatus 호출됨, response가 reducer에 반영됨
    func testAppDidBecomeActive_TriggersFetchAccessStatus() async {
        nonisolated(unsafe) var fetchCount = 0
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.hasAccountSession = true
        initialState.status = .revoked

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCount += 1
                    return LicenseAuthStatusResponse(status: LicenseAuthStatus.none, entitlements: [])
                },
                signOut: {},
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.appDidBecomeActive) { state in
            state.fetchGeneration = 1
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.status = LicenseAuthStatus.none
            state.isComplete = false
            state.errorMessage = "Access denied."
            state.snapshot = LicenseAuthStatusSnapshot(
                status: LicenseAuthStatus.none,
                entitlements: [],
                fetchedAt: self.referenceDate,
            )
        }

        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(store.state.fetchGeneration, 1)
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// ONB-002-start_access_unlock_recovery
    /// signed-out 상태에서는 foreground 진입해도 access status를 조회하지 않는다.
    /// - 검증 내용: appDidBecomeActive가 signed-out 상태에서 no-op
    /// - 사전 조건: hasAccountSession == false
    /// - 기대 결과: fetchAccessStatus 미호출, 상태 변화 없음
    func testAppDidBecomeActive_WhenSignedOut_DoesNotFetchStatus() async {
        nonisolated(unsafe) var fetchCalled = false
        let store = makeTestStore(
            licenseAuthClient: LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCalled = true
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            ),
        )

        await store.send(.appDidBecomeActive)

        XCTAssertFalse(fetchCalled)
        XCTAssertEqual(store.state.fetchGeneration, 0)
        XCTAssertFalse(store.state.hasAccountSession)
        await store.finish()
    }

    /// ONB-002-start_access_unlock_recovery
    /// foreground refresh 결과가 blocked에서 complete로 전환되면 delegate unlock을 보낸다.
    /// - 검증 내용: appDidBecomeActive 이후 active 응답이 complete 상태와 snapshot을 갱신
    /// - 사전 조건: signed-in 상태, 초기 accessStepState == blocked
    /// - 기대 결과: complete 전환, snapshot 저장, delegate.unlocked 발행
    func testAppDidBecomeActive_StatusChangesFromBlockedToComplete() async {
        nonisolated(unsafe) var fetchCount = 0
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.hasAccountSession = true
        initialState.status = LicenseAuthStatus.none
        initialState.isComplete = false

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCount += 1
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.appDidBecomeActive) { state in
            state.fetchGeneration = 1
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.status = .coreLicenseActive
            state.isComplete = true
            state.errorMessage = nil
            state.snapshot = LicenseAuthStatusSnapshot(
                status: .coreLicenseActive,
                entitlements: [.coreLicense],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(store.state.fetchGeneration, 1)
        XCTAssertTrue(store.state.isComplete)
        XCTAssertEqual(store.state.onb002AccessStepState, .complete)
        await store.finish()
    }

    // MARK: - ONB-002-start_access_unlock_recovery (Latest Response Semantics)

    // ONB-002-start_access_unlock_recovery
    // Second refresh overrides first blocked result with active
    // - 검증: 두 번째 refresh의 active 응답이 첫 번째 blocked 응답을 올바르게 대체
    // - 사전 조건: signed in 상태에서 첫 fetch → blocked, 두 번째 fetch → active
    // - 기대 결과: 최종 상태가 active, fetchGeneration == 2, isComplete == true
    // swiftlint:disable:next function_body_length
    func testRefreshOverridesPreviousBlockedResult() async {
        nonisolated(unsafe) var fetchCount = 0
        var initialState = UnlockLicenseAuthFeature.State()
        initialState.hasAccountSession = true

        let store = TestStore(initialState: initialState) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: {
                    fetchCount += 1
                    if fetchCount == 1 {
                        return LicenseAuthStatusResponse(status: LicenseAuthStatus.none, entitlements: [])
                    }
                    return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        // First refresh → blocked (none)
        await store.send(.refreshAccessTapped) { state in
            state.fetchGeneration = 1
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.status = LicenseAuthStatus.none
            state.isComplete = false
            state.errorMessage = "Access denied."
            state.snapshot = LicenseAuthStatusSnapshot(
                status: LicenseAuthStatus.none,
                entitlements: [],
                fetchedAt: self.referenceDate,
            )
        }

        XCTAssertEqual(store.state.onb002AccessStepState, .blocked)

        // Second refresh → active, overrides blocked
        await store.send(.refreshAccessTapped) { state in
            state.fetchGeneration = 2
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.status = .coreLicenseActive
            state.isComplete = true
            state.errorMessage = nil
            state.snapshot = LicenseAuthStatusSnapshot(
                status: .coreLicenseActive,
                entitlements: [.coreLicense],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertEqual(store.state.onb002AccessStepState, .complete)
        XCTAssertTrue(store.state.isComplete)
        XCTAssertEqual(store.state.fetchGeneration, 2)
        await store.finish()
    }

    // MARK: - ONB-002-mock_sign_in_handoff

    /// ONB-002-mock_sign_in_handoff: mock sign-in 성공 시 로컬 콜백 → restoreSession → fetchAccessStatus → unlock 경로를 따른다.
    /// signInHandoffClient가 .success(callbackURL)을 반환하면 reducer가 callback URL을 받아 기존 인증 플로우를 그대로 수행하는지 검증한다.
    /// - 검증 내용: mock handoff 성공 → loginCallbackReceived → restoreSession → fetchAccessStatus → isComplete = true
    /// - 사전 조건: signed-out 상태, signInHandoffClient가 .success 반환, restoreSession이 세션 반환
    /// - 기대 결과: isSignInInProgress = true(진행 중) → 최종 isComplete = true, hasAccountSession = true
    func testMockSignInSuccessRoutesThroughLocalCallback() async {
        let callbackURL = URL(string: "voyager://auth/callback")!

        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: {
                    LicenseAuthSession(accessToken: "mock-token", status: .coreLicenseActive)
                },
                fetchAccessStatus: {
                    LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.signInHandoffClient = SignInHandoffClient {
                .success(callbackURL: callbackURL)
            }
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in })
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        // loginTapped → signInHandoffClient Effect 시작, isSignInInProgress = true
        await store.send(.loginTapped) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
        }

        // signInHandoffClient가 .success를 반환하면 reducer가 .signInHandoffCompleted(.success)를 수신
        await store.receive(\.signInHandoffCompleted)

        // 기존 callback 처리 경로: loginCallbackReceived → restoreSession → fetchAccessStatus
        await store.receive(\.loginCallbackReceived)

        await store.receive(\._loginSessionRestored) { state in
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.fetchGeneration = 1
        }

        await store.receive(\.licenseAuthStatusResponse) { state in
            state.status = .coreLicenseActive
            state.isComplete = true
            state.snapshot = LicenseAuthStatusSnapshot(
                status: .coreLicenseActive,
                entitlements: [.coreLicense],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertTrue(store.state.isComplete)
        await store.finish()
    }

    /// ONB-002-mock_sign_in_handoff: mock sign-in은 외부 브라우저를 열지 않는다.
    /// signInHandoffClient를 사용하면 loginURLClient.openLoginURL이 호출되지 않아야 한다.
    /// - 검증 내용: loginTapped 후 loginURLClient.openLoginURL 호출 횟수 = 0
    /// - 사전 조건: signInHandoffClient가 .success 반환, loginURLClient spy 설정
    /// - 기대 결과: loginURLClient.openLoginURL이 호출되지 않음
    func testMockSignInDoesNotOpenExternalBrowser() async {
        nonisolated(unsafe) var openURLCallCount = 0

        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = .mock
            $0.signInHandoffClient = SignInHandoffClient {
                .success(callbackURL: URL(string: "voyager://auth/callback")!)
            }
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in
                openURLCallCount += 1
            })
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginTapped) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
        }

        // reducer가 signInHandoffClient를 사용하면 loginURLClient를 호출하지 않아야 함
        XCTAssertEqual(openURLCallCount, 0, "mock sign-in은 외부 브라우저를 열지 않아야 함")

        // signInHandoffClient가 success를 반환 → loginCallbackReceived → restoreSession(nil) → 실패
        // (.mock client의 restoreSession은 nil을 반환)
        await store.receive(\.signInHandoffCompleted)
        await store.receive(\.loginCallbackReceived)
        await store.receive(\._loginSessionRestored) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }
        await store.finish()
    }

    /// ONB-002-mock_sign_in_handoff: dependency-controlled failure는 isSignInInProgress를 해제하고 didSignInFail을 설정하며 재시도를
    /// 허용한다.
    /// signInHandoffClient가 .failure를 반환하면 reducer가 sign-in 실패 상태로 전이하는지 검증한다.
    /// - 검증 내용: handoff .failure → isSignInInProgress = false, didSignInFail = true, canStartLogin = true
    /// - 사전 조건: signInHandoffClient가 .failure 반환
    /// - 기대 결과: isSignInInProgress = false, didSignInFail = true, canStartLogin = true
    func testMockSignInFailureClearsPendingAndAllowsRetry() async {
        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = .mock
            $0.signInHandoffClient = SignInHandoffClient {
                .failure
            }
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in })
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginTapped) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
        }

        // signInHandoffClient .failure → signInHandoffCompleted(.failure) 수신
        await store.receive(\.signInHandoffCompleted) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }

        XCTAssertFalse(store.state.isSignInInProgress)
        XCTAssertTrue(store.state.didSignInFail)
        XCTAssertTrue(store.state.canStartLogin)
        await store.finish()
    }

    /// ONB-002-mock_sign_in_handoff: dependency-controlled cancel은 failure와 동일하게 동작한다.
    /// signInHandoffClient가 .cancelled을 반환해도 failure와 동일한 상태 전이가 발생하는지 검증한다.
    /// - 검증 내용: handoff .cancelled → isSignInInProgress = false, didSignInFail = true, canStartLogin = true
    /// - 사전 조건: signInHandoffClient가 .cancelled 반환
    /// - 기대 결과: failure와 동일 — isSignInInProgress = false, didSignInFail = true, canStartLogin = true
    func testMockSignInCancelBehavesSameAsFailure() async {
        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = .mock
            $0.signInHandoffClient = SignInHandoffClient {
                .cancelled
            }
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in })
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.loginTapped) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
        }

        // signInHandoffClient .cancelled → signInHandoffCompleted(.cancelled) 수신
        await store.receive(\.signInHandoffCompleted) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }

        XCTAssertFalse(store.state.isSignInInProgress)
        XCTAssertTrue(store.state.didSignInFail)
        XCTAssertTrue(store.state.canStartLogin)
        await store.finish()
    }
}

// swiftlint:enable force_unwrapping

import Clocks
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-001-start_account_sign_in spec-owner 테스트

 interaction_id: ACC-001-start_account_sign_in
 spec: docs/canonical/PRODUCT/05_FEATURE_SPECS/acc/ACC-001-manage_account_auth/ACC-001-start_account_sign_in.md

 auth_state 매핑 (현재 모델):
 - logged_out     → AccountAccessState 기본 상태 (hasAccountSession=false, didSignInFail=false)
 - session_expired → didSignInFail=true (재로그인 필요 상태, canStartLogin=true)
 - logged_in      → hasAccountSession=true
 */

@MainActor
final class ACC001StartAccountSignInTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let handoffURLBuilder = AppHandoffURLBuilder(
        webBaseURL: "https://example.com",
        gatewayURL: "https://gw.example.com",
    )

    private actor HandoffStartCancellationGate {
        private var didStart = false
        private var didCancel = false
        private var startWaiters: [CheckedContinuation<Void, Never>] = []
        private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

        func markStarted() {
            didStart = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
        }

        func markCancelled() {
            didCancel = true
            cancellationWaiters.forEach { $0.resume() }
            cancellationWaiters.removeAll()
        }

        func waitUntilStarted() async {
            guard !didStart else { return }
            await withCheckedContinuation { startWaiters.append($0) }
        }

        func waitUntilCancelled() async {
            guard !didCancel else { return }
            await withCheckedContinuation { cancellationWaiters.append($0) }
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        await resetHandoffStore()
    }

    override func tearDown() async throws {
        await resetHandoffStore()
        try await super.tearDown()
    }

    private func resetHandoffStore() async {
        for (state, owner) in [
            ("onboarding-state-123", AccountAccessHandoffScope.onboarding),
            ("settings-state-456", .settings),
            ("secondary-state-789", .settings),
        ] {
            _ = await AppHandoffStateStore.shared.clear(expectedState: state, owner: owner)
        }
    }

    private func makeTestStore(
        signInHandoffClient: SignInHandoffClient = SignInHandoffClient { _ in .failure },
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
        continuousClock: TestClock<Duration> = TestClock(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = .testValue
            $0.authNetworkClient = .testValue
            $0.signInHandoffClient = signInHandoffClient
            $0.date = .constant(referenceDate)
            $0.continuousClock = continuousClock
        }
    }

    private func cancellationAwareHandoffClient(
        pending: PendingAppHandoff,
        gate: HandoffStartCancellationGate,
    ) -> SignInHandoffClient {
        SignInHandoffClient(
            beginHandoff: { _, _ in
                guard await AppHandoffStateStore.shared.begin(pending) else {
                    return .rejected
                }
                await gate.markStarted()

                return await withTaskCancellationHandler(operation: {
                    do {
                        try await ContinuousClock().sleep(for: .seconds(60))
                        return .awaitingCallback(state: pending.state)
                    } catch {
                        return .cancelled
                    }
                }, onCancel: {
                    Task {
                        _ = await AppHandoffStateStore.shared.clear(
                            expectedState: pending.state,
                            owner: pending.owner,
                        )
                        await gate.markCancelled()
                    }
                })
            },
        )
    }

    /// session_expired 상태 (재로그인 필요). didSignInFail=true로 모델링.
    private func sessionExpiredInitialState() -> AccountAccessFeature.State {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true
        return state
    }

    private func assertSignedInPendingReauthentication(
        initialState: AccountAccessFeature.State,
        pendingState: String,
    ) async {
        nonisolated(unsafe) var handoffCallCount = 0
        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient { _ in
                handoffCallCount += 1
                return .awaitingCallback(state: pendingState)
            },
            initialState: initialState,
        )

        XCTAssertEqual(store.state.accessUnlockPrimaryCTA, .pending)
        XCTAssertTrue(store.state.canStartLogin)
        await store.send(.loginTapped(context: .paywall, scope: .lifecycle)) { state in
            state.isSubmitting = false
            state.isSignInInProgress = true
            state.didSignInFail = false
            state.handoffTransaction = AccountAccessHandoffTransaction(
                context: .paywall,
                scope: .lifecycle,
                startedWithAccountSession: true,
            )
            state.handoffGeneration = 1
            state.syncGeneration = 8
            state.revalidationGeneration = 4
        }
        await store.receive(\.signInHandoffCompleted) { state in
            state.handoffPendingState = pendingState
        }

        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertEqual(handoffCallCount, 1)
        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.handoffPendingState = nil
            state.handoffTransaction = nil
            state.refreshDeadlineGeneration = 9
        }
        await store.skipInFlightEffects()
        await store.finish()
    }

    // MARK: - ACC-001-start_account_sign_in

    /// ACC-001-start_account_sign_in: Voyager에서 시작한 로그인 URL은 Voyager 대상임을 포함한다.
    /// 로그인 handoff URL 생성 시 Voyager 앱 대상이 명시되는지 검증한다.
    /// - 검증 내용: app_target query 값이 voyager
    /// - 사전 조건: onboarding context와 Voyager app target
    /// - 기대 결과: 로그인 URL에 app_target=voyager 포함
    func testBuildLoginURLIncludesAppTargetForVoyager() throws {
        let url = try XCTUnwrap(handoffURLBuilder.buildLoginURL(
            state: "abc",
            context: .onboarding,
            appTarget: .voyager,
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let appTarget = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "app_target" })?.value)
        XCTAssertEqual(appTarget, "voyager")
    }

    /// ACC-001-start_account_sign_in: Onboarding Host에서 시작한 로그인 URL은 Onboarding Host 대상임을 포함한다.
    /// 로그인 handoff URL 생성 시 Onboarding Host 앱 대상이 명시되는지 검증한다.
    /// - 검증 내용: app_target query 값이 onboarding_host
    /// - 사전 조건: onboarding context와 Onboarding Host app target
    /// - 기대 결과: 로그인 URL에 app_target=onboarding_host 포함
    func testBuildLoginURLIncludesAppTargetForOnboardingHost() throws {
        let url = try XCTUnwrap(handoffURLBuilder.buildLoginURL(
            state: "abc",
            context: .onboarding,
            appTarget: .onboardingHost,
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let appTarget = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "app_target" })?.value)
        XCTAssertEqual(appTarget, "onboarding_host")
    }

    /// ACC-001-start_account_sign_in: 로그인 URL에 대상을 추가해도 기존 query가 보존된다.
    /// app_target을 추가한 URL이 mode, state, context query를 모두 유지하는지 검증한다.
    /// - 검증 내용: mode, state, context, app_target query 값
    /// - 사전 조건: state=abc 및 onboarding context로 Voyager 대상 로그인 URL 생성
    /// - 기대 결과: 기존 query와 app_target=voyager가 함께 포함
    func testBuildLoginURLPreservesExistingQueries() throws {
        let url = try XCTUnwrap(handoffURLBuilder.buildLoginURL(
            state: "abc",
            context: .onboarding,
            appTarget: .voyager,
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try XCTUnwrap(components.queryItems)

        XCTAssertEqual(queryItems.first(where: { $0.name == "mode" })?.value, "app")
        XCTAssertEqual(queryItems.first(where: { $0.name == "state" })?.value, "abc")
        XCTAssertEqual(queryItems.first(where: { $0.name == "context" })?.value, "onboarding")
        XCTAssertEqual(queryItems.first(where: { $0.name == "app_target" })?.value, "voyager")
    }

    /// ACC-001-start_account_sign_in: 앱 대상을 생략한 로그인 URL은 Voyager를 기본 대상으로 사용한다.
    /// appTarget 기본 인자가 Voyager 대상 값을 생성하는지 검증한다.
    /// - 검증 내용: app_target query 값이 voyager
    /// - 사전 조건: appTarget 없이 onboarding context 로그인 URL 생성
    /// - 기대 결과: 로그인 URL에 app_target=voyager 포함
    func testBuildLoginURLDefaultAppTargetIsVoyager() throws {
        let url = try XCTUnwrap(handoffURLBuilder.buildLoginURL(state: "abc", context: .onboarding))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let appTarget = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "app_target" })?.value)
        XCTAssertEqual(appTarget, "voyager")
    }

    /// ACC-001-start_account_sign_in: logged_out 상태에서 Login CTA 선택 시 브라우저 로그인 URL이 열린다.
    /// logged_out 상태에서 loginTapped가 signInHandoffClient.performHandoff를 호출하는지 검증한다.
    /// - 검증 내용: isSignInInProgress=true, didSignInFail=false, handoffClient가 호출됨
    /// - 사전 조건: AccountAccessFeature.State 기본 상태 (logged_out)
    /// - 기대 결과: isSignInInProgress=true, handoffPendingState 저장, hasAccountSession=false 유지
    func testLoggedOutLoginCTATriggersBrowserLoginURL() async {
        nonisolated(unsafe) var handoffCalled = false
        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient { _ in
                handoffCalled = true
                return .awaitingCallback(state: "test-state-123")
            },
        )

        await store.send(.loginTapped(context: .onboarding, scope: .onboarding)) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
            state.handoffTransaction = AccountAccessHandoffTransaction(context: .onboarding, scope: .onboarding)
            state.handoffGeneration = 1
        }

        XCTAssertTrue(handoffCalled, "signInHandoffClient가 호출되어 브라우저 로그인 URL이 열려야 함")
        XCTAssertTrue(store.state.isSignInInProgress)

        // awaitingCallback → handoffPendingState 저장, auth_state 미변경
        await store.receive(\.signInHandoffCompleted) { state in
            state.handoffPendingState = "test-state-123"
        }

        XCTAssertFalse(store.state.hasAccountSession, "로그인 완료 전까지 logged_out 유지")
        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.handoffPendingState = nil
            state.handoffTransaction = nil
        }
        await store.finish()
    }

    /// ACC-001-start_account_sign_in: session_expired 상태에서 Login CTA 선택 시 로그인 진입이 시작된다.
    /// session_expired (didSignInFail=true) 상태에서 loginTapped가 동일하게 handoff를 시작하는지 검증한다.
    /// - 검증 내용: isSignInInProgress=true, didSignInFail=false (새 흐름 시작), handoffClient 호출됨
    /// - 사전 조건: didSignInFail=true (session_expired), canStartLogin=true
    /// - 기대 결과: isSignInInProgress=true, didSignInFail=false, handoffClient 호출됨
    func testSessionExpiredLoginCTAStartsLogin() async {
        nonisolated(unsafe) var handoffCalled = false
        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient { _ in
                handoffCalled = true
                return .failure
            },
            initialState: sessionExpiredInitialState(),
        )

        // 전제: session_expired 상태에서 canStartLogin == true
        XCTAssertTrue(store.state.canStartLogin, "session_expired 상태에서 Login CTA 활성화")
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signInFailed)

        await store.send(.loginTapped(context: .onboarding, scope: .onboarding)) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
            state.handoffTransaction = AccountAccessHandoffTransaction(context: .onboarding, scope: .onboarding)
            state.handoffGeneration = 1
        }

        XCTAssertTrue(handoffCalled, "session_expired에서도 동일하게 handoff 시작")
        XCTAssertTrue(store.state.isSignInInProgress)

        await store.receive(\.signInHandoffCompleted) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.errorMessage = "Check your network connection and try again."
            state.handoffTransaction = nil
        }
        await store.finish()
    }
}

extension ACC001StartAccountSignInTests {
    /// ACC-001-start_account_sign_in: signed-in pending recovery에서 Sign in CTA는 새 handoff를 정확히 한 번 시작한다.
    /// - 검증 내용: submitting sync를 무효화하고 handoff를 한 번 시작하며 persisted session 상태를 유지한다.
    /// - 사전 조건: hasAccountSession=true, isSubmitting=true인 signed-in pending recovery 상태.
    /// - 기대 결과: isSubmitting=false, sync/revalidation generation 증가, handoff client 1회 호출.
    func testSignedInPendingLoginCTAStartsReauthenticationOnce() async {
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.isSubmitting = true
        initialState.syncGeneration = 7
        initialState.revalidationGeneration = 3

        await assertSignedInPendingReauthentication(
            initialState: initialState,
            pendingState: "reauth-state-123",
        )
    }

    /// ACC-001-start_account_sign_in: 재인증 시작은 이전 refresh deadline을 무효화한다.
    /// - 검증 내용: reauthentication이 refresh deadline generation을 증가시켜 stale deadline이 persisted session 재검증을 시작하지 않는다.
    /// - 사전 조건: signed-in pending recovery 상태와 generation 7의 활성 refresh deadline.
    /// - 기대 결과: handoff 시작 후 generation은 8이고, generation 7 deadline은 revalidatePersistedSession action을 만들지 않는다.
    func testSignedInPendingLoginCTACancelsActiveRefreshDeadline() async {
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.refreshDeadlineGeneration = 7
        initialState.ttlTimerActive = true
        initialState.sessionExpiresAt = referenceDate.addingTimeInterval(600)

        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient { _ in
                .awaitingCallback(state: "refresh-deadline-reauth-state")
            },
            initialState: initialState,
        )

        await store.send(.loginTapped(context: .paywall, scope: .lifecycle)) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
            state.handoffTransaction = AccountAccessHandoffTransaction(
                context: .paywall,
                scope: .lifecycle,
                startedWithAccountSession: true,
            )
            state.handoffGeneration = 1
            state.syncGeneration = 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 8
        }
        await store.receive(\.signInHandoffCompleted) { state in
            state.handoffPendingState = "refresh-deadline-reauth-state"
        }

        await store.send(._refreshDeadlineReached(generation: 7))

        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.handoffPendingState = nil
            state.handoffTransaction = nil
        }
        await store.finish()
    }

    /// ACC-001-start_account_sign_in: access status가 아직 확정되지 않은 signed-in pending recovery도 재인증을 시작한다.
    /// - 검증 내용: nil status의 pending CTA가 sync/revalidation generation을 무효화하고 handoff를 시작한다.
    /// - 사전 조건: hasAccountSession=true, status=nil, errorMessage=nil, isSubmitting=false.
    /// - 기대 결과: persisted session을 유지한 채 handoff client가 한 번 호출된다.
    func testSignedInUnknownPendingLoginCTAStartsReauthentication() async {
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.syncGeneration = 7
        initialState.revalidationGeneration = 3

        await assertSignedInPendingReauthentication(
            initialState: initialState,
            pendingState: "unknown-reauth-state-123",
        )
    }

    /// ACC-001-start_account_sign_in: active access가 아직 complete가 아닌 signed-in pending recovery도 재인증을 시작한다.
    /// - 검증 내용: active-but-incomplete pending CTA가 sync/revalidation generation을 무효화하고 handoff를 시작한다.
    /// - 사전 조건: hasAccountSession=true, status=coreLicenseActive, isComplete=false, isSubmitting=false.
    /// - 기대 결과: persisted session을 유지한 채 handoff client가 한 번 호출된다.
    func testSignedInActiveIncompletePendingLoginCTAStartsReauthentication() async {
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.status = .coreLicenseActive
        initialState.syncGeneration = 7
        initialState.revalidationGeneration = 3

        await assertSignedInPendingReauthentication(
            initialState: initialState,
            pendingState: "active-reauth-state-123",
        )
    }

    /// ACC-001-start_account_sign_in: 인증 흐름 시작 후 callback/token 교환 전까지 auth_state가 변경되지 않는다.
    /// loginTapped 후 awaitingCallback 수신 시까지 hasAccountSession이 false로 유지되는지 검증한다.
    /// - 검증 내용: 인증 대기 중 hasAccountSession 변화 없음, status nil 유지
    /// - 사전 조건: AccountAccessFeature.State 기본 상태, signInHandoffClient가 awaitingCallback 반환
    /// - 기대 결과: hasAccountSession=false, status=nil 유지
    func testAuthStateUnchangedUntilCallbackAndTokenExchange() async {
        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient { _ in
                .awaitingCallback(state: "pending-state-abc")
            },
        )

        await store.send(.loginTapped(context: .onboarding, scope: .onboarding)) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
            state.handoffTransaction = AccountAccessHandoffTransaction(context: .onboarding, scope: .onboarding)
            state.handoffGeneration = 1
        }

        // callback 수신 전: auth_state 변경 없음 (logged_out 유지)
        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertNil(store.state.status)

        await store.receive(\.signInHandoffCompleted) { state in
            state.handoffPendingState = "pending-state-abc"
        }

        // 여전히 token 교환 전이므로 auth_state 미변경
        XCTAssertFalse(store.state.hasAccountSession, "callback 수신 및 token 교환 전까지 auth_state 변경 안 함")
        XCTAssertNil(store.state.status)
        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.handoffPendingState = nil
            state.handoffTransaction = nil
        }
        await store.finish()
    }

    /// ACC-001-start_account_sign_in: 진행 중인 Login CTA 재선택은 기존 handoff를 유지한 채 무시된다.
    /// 활성 인증 흐름의 중복 요청이 새 브라우저 handoff를 시작하지 않는지 검증한다.
    /// - 검증 내용: handoff client 미호출, 기존 pending state와 진행 상태 유지
    /// - 사전 조건: callback 대기 중인 sign-in
    /// - 기대 결과: 기존 handoff가 대체되지 않고 유지됨
    func testDuplicateLoginTappedDuringSignInInProgressIsIgnored() async {
        nonisolated(unsafe) var handoffCallCount = 0
        var initialState = AccountAccessFeature.State()
        initialState.isSignInInProgress = true
        initialState.handoffPendingState = "old-state"

        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient { _ in
                handoffCallCount += 1
                return .failure
            },
            initialState: initialState,
        )

        // 진행 중에는 canStartLogin이 false이므로 중복 요청을 무시한다.
        XCTAssertFalse(store.state.canStartLogin)

        await store.send(.loginTapped(context: .onboarding, scope: .onboarding))

        XCTAssertEqual(handoffCallCount, 0)
        XCTAssertTrue(store.state.isSignInInProgress)
        XCTAssertEqual(store.state.handoffPendingState, "old-state")
        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.handoffPendingState = nil
        }
        await store.finish()
    }

    /// ACC-001-start_account_sign_in: 서로 다른 표면의 동시 handoff 시작은 하나만 승인한다.
    /// - 검증 내용: 두 owner의 begin 결과 중 하나만 true이고, claim이 승인된 owner와 일치
    /// - 사전 조건: onboarding 및 settings surface가 활성 handoff 없이 동시에 시작 요청
    /// - 기대 결과: 하나의 PendingAppHandoff만 유지되고 뒤 요청은 기존 owner를 덮어쓰지 않음
    func testSimultaneousCrossScopeAdmissionAllowsOnlyOneOwner() async {
        let onboardingPending = PendingAppHandoff(
            state: "onboarding-state-123",
            context: .onboarding,
            owner: .onboarding,
            createdAt: referenceDate,
        )
        let settingsPending = PendingAppHandoff(
            state: "settings-state-456",
            context: .paywall,
            owner: .settings,
            createdAt: referenceDate,
        )

        async let onboardingAccepted = AppHandoffStateStore.shared.begin(onboardingPending)
        async let settingsAccepted = AppHandoffStateStore.shared.begin(settingsPending)
        let admissions = await (onboardingAccepted, settingsAccepted)

        XCTAssertEqual([admissions.0, admissions.1].count(where: { $0 }), 1)
        if admissions.0 {
            let claimed = await AppHandoffStateStore.shared.claim(
                expectedState: onboardingPending.state,
                context: onboardingPending.context,
                owner: .onboarding,
            )
            XCTAssertEqual(claimed?.owner, .onboarding)
        } else {
            let claimed = await AppHandoffStateStore.shared.claim(
                expectedState: settingsPending.state,
                context: settingsPending.context,
                owner: .settings,
            )
            XCTAssertEqual(claimed?.owner, .settings)
        }
    }

    /// ACC-001-start_account_sign_in: 전역 admission 거절 시 시작하지 못한 표면만 진행 상태를 종료한다.
    /// - 검증 내용: settings reducer의 progress 종료와 onboarding owner 보존
    /// - 사전 조건: onboarding owner의 pending handoff가 먼저 활성화되고 settings가 시작 요청
    /// - 기대 결과: settings는 실패 상태 없이 종료되고 활성 onboarding handoff는 유지
    func testRejectedCrossScopeAdmissionExitsSecondaryProgressWithoutClearingActiveOwner() async {
        let activePending = PendingAppHandoff(
            state: "onboarding-state-123",
            context: .onboarding,
            owner: .onboarding,
            createdAt: referenceDate,
        )
        let activeAdmission = await AppHandoffStateStore.shared.begin(activePending)
        XCTAssertTrue(activeAdmission)

        let createdAt = referenceDate
        let initialState = AccountAccessFeature.State()
        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient(
                beginHandoff: { context, owner in
                    let pending = PendingAppHandoff(
                        state: "secondary-state-789",
                        context: context,
                        owner: owner,
                        createdAt: createdAt,
                    )
                    return await AppHandoffStateStore.shared.begin(pending)
                        ? .awaitingCallback(state: pending.state)
                        : .rejected
                },
            ),
            initialState: initialState,
        )

        await store.send(.loginTapped(context: .paywall, scope: .settings)) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
            state.handoffTransaction = AccountAccessHandoffTransaction(context: .paywall, scope: .settings)
            state.handoffGeneration = 1
        }
        await store.receive(\.signInHandoffCompleted) { state in
            state.isSignInInProgress = false
            state.handoffTransaction = nil
        }

        XCTAssertFalse(store.state.didSignInFail)
        XCTAssertNil(store.state.handoffPendingState)
        let claimed = await AppHandoffStateStore.shared.claim(
            expectedState: activePending.state,
            context: activePending.context,
            owner: .onboarding,
        )
        XCTAssertEqual(claimed?.owner, .onboarding)
        await store.finish()
    }

    /// ACC-001-start_account_sign_in: callback 대기는 120초 경계에서만 sign-in 실패로 종료한다.
    /// - 검증 내용: 119초에는 pending state를 보존하고 120초에 한 번만 pending state와 progress 상태 제거
    /// - 사전 조건: callback 대기 중 handoff와 TestClock
    /// - 기대 결과: 120초 후 didSignInFail=true
    func testAwaitingCallbackTimeoutResetsSignInStateAt120Seconds() async {
        let clock = TestClock()
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.sessionExpiresAt = referenceDate.addingTimeInterval(600)
        initialState.ttlTimerActive = true
        initialState.refreshDeadlineGeneration = 8
        initialState.isSignInInProgress = true
        initialState.handoffTransaction = AccountAccessHandoffTransaction(
            context: .onboarding,
            scope: .onboarding,
            startedWithAccountSession: true,
        )
        let store = TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.signInHandoffCompleted(
            .awaitingCallback(state: "pending-state"),
            transaction: AccountAccessHandoffTransaction(
                context: .onboarding,
                scope: .onboarding,
                startedWithAccountSession: true,
            ),
            generation: 0,
        )) { state in
            state.handoffPendingState = "pending-state"
        }
        await clock.advance(by: .seconds(119))
        XCTAssertTrue(store.state.isSignInInProgress)
        XCTAssertFalse(store.state.didSignInFail)
        XCTAssertEqual(store.state.handoffPendingState, "pending-state")
        XCTAssertNotNil(store.state.handoffTransaction)

        await clock.advance(by: .seconds(1))
        await store.receive(\._handoffCallbackTimedOut) { state in
            state.isSignInInProgress = false
            state.didSignInFail = false
            state.handoffPendingState = nil
            state.handoffTransaction = nil
            state.refreshDeadlineGeneration = 9
        }
        await store.skipInFlightEffects()
        await store.finish()
    }

    /// ACC-001-start_account_sign_in: 재인증 시작 결과가 거절·실패·취소로 끝나면 기존 refresh deadline을 복구한다.
    /// 기존 session authority를 유지한 terminal begin 결과가 deadline generation을 다시 예약하는지 검증한다.
    /// - 검증 내용: 세 begin terminal 결과마다 refresh deadline generation이 취소 후 다시 증가한다.
    /// - 사전 조건: 유효한 expiry를 가진 signed-in reauthentication 상태.
    /// - 기대 결과: 기존 session은 유지되고 replacement deadline effect가 정리된다.
    func testReauthenticationBeginTerminalResultsRestoreRefreshDeadline() async {
        for result in [SignInHandoffResult.rejected, .failure, .cancelled] {
            var initialState = AccountAccessFeature.State()
            initialState.hasAccountSession = true
            initialState.sessionExpiresAt = referenceDate.addingTimeInterval(600)
            initialState.ttlTimerActive = true
            initialState.refreshDeadlineGeneration = 7

            let store = makeTestStore(
                signInHandoffClient: SignInHandoffClient { _ in result },
                initialState: initialState,
                continuousClock: TestClock(),
            )

            await store.send(.loginTapped(context: .paywall, scope: .lifecycle)) { state in
                state.isSignInInProgress = true
                state.didSignInFail = false
                state.handoffTransaction = AccountAccessHandoffTransaction(
                    context: .paywall,
                    scope: .lifecycle,
                    startedWithAccountSession: true,
                )
                state.handoffGeneration = 1
                state.syncGeneration = 1
                state.revalidationGeneration = 1
                state.refreshDeadlineGeneration = 8
            }
            await store.receive(\.signInHandoffCompleted) { state in
                state.isSignInInProgress = false
                state.handoffTransaction = nil
                state.refreshDeadlineGeneration = 9
                if result == .failure {
                    state.errorMessage = "Check your network connection and try again."
                }
            }

            XCTAssertTrue(store.state.hasAccountSession)
            XCTAssertFalse(store.state.didSignInFail)
            await store.skipInFlightEffects()
            await store.finish()
        }
    }

    func testCancelSignInClearsPendingHandoffState() async {
        var initialState = AccountAccessFeature.State()
        initialState.isSignInInProgress = true
        initialState.handoffPendingState = "pending-state-abc"

        let store = makeTestStore(initialState: initialState)

        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.didSignInFail = false
            state.handoffPendingState = nil
        }

        await store.finish()
    }

    /// ACC-001-start_account_sign_in: admission 성공 후 완료 액션 전 취소는 해당 scope의 handoff만 해제한다.
    /// - 검증 내용: 취소 뒤 새 handoff admission 성공 및 다른 owner로의 조건 불일치 clear 거부
    /// - 사전 조건: onboarding scope가 pending handoff를 저장한 뒤 awaitingCallback을 반환하기 전 취소
    /// - 기대 결과: 기존 onboarding handoff 제거, 후속 settings handoff 승인, settings owner 보존
    func testCancelBeforeHandoffCompletionClearsOnlyAdmittedScope() async {
        let gate = HandoffStartCancellationGate()
        let pending = PendingAppHandoff(
            state: "onboarding-state-123",
            context: .onboarding,
            owner: .onboarding,
            createdAt: referenceDate,
        )
        let store = makeTestStore(
            signInHandoffClient: cancellationAwareHandoffClient(pending: pending, gate: gate),
        )

        await store.send(.loginTapped(context: .onboarding, scope: .onboarding)) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
            state.handoffTransaction = AccountAccessHandoffTransaction(context: .onboarding, scope: .onboarding)
            state.handoffGeneration = 1
        }
        await gate.waitUntilStarted()
        let mismatchedClaim = await AppHandoffStateStore.shared.claim(
            expectedState: pending.state,
            context: pending.context,
            owner: .settings,
        )
        XCTAssertNil(mismatchedClaim)

        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.didSignInFail = false
            state.handoffTransaction = nil
        }
        await gate.waitUntilCancelled()
        let futurePending = PendingAppHandoff(
            state: "settings-state-456",
            context: .paywall,
            owner: .settings,
            createdAt: referenceDate,
        )
        let futureAdmission = await AppHandoffStateStore.shared.begin(futurePending)
        XCTAssertTrue(futureAdmission)
        let mismatchedClear = await AppHandoffStateStore.shared.clear(
            expectedState: futurePending.state,
            owner: .onboarding,
        )
        XCTAssertFalse(mismatchedClear)
        let claimedFutureHandoff = await AppHandoffStateStore.shared.claim(
            expectedState: futurePending.state,
            context: futurePending.context,
            owner: futurePending.owner,
        )
        XCTAssertEqual(claimedFutureHandoff?.owner, .settings)
        await store.finish()
    }

    /// ACC-001-start_account_sign_in: initiating surface가 명시한 handoff context와 scope를 transaction으로 고정한다.
    /// - 검증 내용: beginHandoff에 .paywall/.settings가 전달되고 승인 대기 상태가 같은 transaction을 유지한다.
    /// - 사전 조건: 기본 AccountAccess state에서 Settings surface의 login action을 전송한다.
    /// - 기대 결과: capturedContext == .paywall, capturedScope == .settings, handoffTransaction이 .paywall/.settings다.
    func testLoginTappedCapturesExplicitHandoffTransaction() async {
        let capturedContext = LockIsolated<AppHandoffContext?>(nil),
            capturedScope = LockIsolated<AccountAccessHandoffScope?>(nil)
        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient(
                beginHandoff: { context, scope in
                    capturedContext.setValue(context)
                    capturedScope.setValue(scope)
                    return .awaitingCallback(state: "paywall-state-123")
                },
            ),
            continuousClock: TestClock(),
        )

        await store.send(.loginTapped(context: .paywall, scope: .settings)) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
            state.handoffTransaction = AccountAccessHandoffTransaction(context: .paywall, scope: .settings)
            state.handoffGeneration = 1
        }

        XCTAssertEqual(capturedContext.value, .paywall)
        XCTAssertEqual(capturedScope.value, .settings)
        await store.receive(\.signInHandoffCompleted) { state in
            state.handoffPendingState = "paywall-state-123"
        }

        XCTAssertEqual(
            store.state.handoffTransaction,
            AccountAccessHandoffTransaction(context: .paywall, scope: .settings),
        )
        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.handoffPendingState = nil
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
        }
        await store.finish()
    }
}

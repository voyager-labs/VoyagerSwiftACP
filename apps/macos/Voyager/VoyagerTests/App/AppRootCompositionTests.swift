import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesUpdateVersion
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
@testable import VoyagerPagesSettings
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class AppRootCompositionTests: XCTestCase {
    func testAppPreferencesUpdatedRoutesToWindowManager() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        var preferences = Voyager.AppPreferencesState()
        preferences.showHiddenFiles = true
        preferences.viewLayout = EntryViewLayoutState.Mode.grid
        preferences.sidebarVisible = false

        await store.send(.appPreferences(.delegate(.updated(preferences)))) {
            $0.appPreferences = preferences
        }
        await store.receive(\.windowManager.lifecycle.applyAppPreferences) {
            $0.windowManager.appPreferences = preferences
        }
    }

    func testMenuCommandRoutesToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.menuCommands(.delegate(.updater(.checkForUpdates))))
        await store.receive(\.updater.checkForUpdates)
    }

    // MARK: - Launch bootstrap

    func testAppRootLaunchWillFinishLaunchingForwardsSettingsBootstrapLocalPreferences() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.launch(.willFinishLaunching)))
        await store.receive(\.settings.bootstrapLocalPreferences)
        await store.receive(\.settings.ai.onAppear)
    }

    // MARK: - ACC-001-settings_lifecycle_bridge

    /// ACC-001-settings_lifecycle_bridge: signed-out Settings Sign In은 canonical lifecycle에 한 번만 전달된다.
    /// Settings가 local AccountAccess runtime 없이 narrow delegate로 sign-in을 요청하는 경로를 검증한다.
    /// - 검증 내용: signInRequested가 lifecycle AccountAccess.loginTapped 한 번과 presentation 갱신으로 번역됨
    /// - 사전 조건: canonical lifecycle AccountAccess가 signed-out이고 Settings는 projection consumer임
    /// - 기대 결과: lifecycle만 handoff를 시작하고 Settings에는 sign-in progress projection만 반영됨
    func testSettingsSignedOutSignInRoutesToCanonicalLifecycleExactlyOnce() async {
        let store = makeSettingsAccountBridgeStore(
            signInHandoffClient: SignInHandoffClient { _ in
                .failure
            },
        )
        // store.exhaustivity = .off: root, lifecycle, AccountAccess의 multi-reducer 효과 순서를 함께 검증함
        store.exhaustivity = .off

        await store.send(.settings(.delegate(.account(.signInRequested))))
        await store.receive(\.lifecycle.accountAccess.loginTapped) { state in
            state.lifecycle.accountAccess.isSignInInProgress = true
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(
                isSignInInProgress: true,
            )
        }
        await store.receive(\.lifecycle.accountAccess.signInHandoffCompleted) { state in
            state.lifecycle.accountAccess.isSignInInProgress = false
            state.lifecycle.accountAccess.didSignInFail = true
            state.lifecycle.accountAccess.errorMessage = "Check your network connection and try again."
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(didSignInFail: true)
        }
        await store.finish()
    }

    /// ACC-001-settings_lifecycle_bridge: signed-in Settings Sign In은 canonical session 기준으로 no-op이다.
    /// 오래된 Settings projection이 signed-out을 표시해도 canonical lifecycle session을 재인증하지 않는지 검증한다.
    /// - 검증 내용: signInRequested에 lifecycle AccountAccess.loginTapped effect가 없음
    /// - 사전 조건: lifecycle AccountAccess는 signed-in이고 Settings projection은 의도적으로 stale signed-out임
    /// - 기대 결과: state와 effect가 변하지 않음
    func testSettingsSignedInSignInIsDeterministicNoOp() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.hasAccountSession = true
        let store = makeSettingsAccountBridgeStore(initialState: initialState)

        await store.send(.settings(.delegate(.account(.signInRequested))))
        await store.finish()
    }

    /// ACC-001-settings_lifecycle_bridge: confirmed Settings Sign Out은 canonical lifecycle에서 한 번 처리된다.
    /// Settings confirmation reducer가 만든 signOutRequested delegate의 composition boundary를 검증한다.
    /// - 검증 내용: signOutRequested가 lifecycle AccountAccess.signOut으로 번역되고 signed-out projection이 반영됨
    /// - 사전 조건: canonical lifecycle AccountAccess에 활성 session이 있음
    /// - 기대 결과: Settings는 local session을 지우지 않고 canonical 결과 projection만 수신함
    func testSettingsConfirmedSignOutRoutesToCanonicalLifecycleExactlyOnce() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.hasAccountSession = true
        let store = makeSettingsAccountBridgeStore(initialState: initialState)
        // store.exhaustivity = .off: sign-out은 persistence cleanup과 lifecycle delegate를 함께 생성함
        store.exhaustivity = .off

        await store.send(.settings(.delegate(.account(.signOutRequested))))
        await store.receive(\.lifecycle.accountAccess.signOut) { state in
            state.lifecycle.accountAccess.revalidationGeneration = 1
            state.lifecycle.accountAccess.hasAccountSession = false
            state.lifecycle.accountAccess.isSessionExpired = true
            state.lifecycle.accountAccess.fetchGeneration = 1
            state.lifecycle.accountAccess.syncGeneration = 1
            state.lifecycle.accountAccess.refreshDeadlineGeneration = 1
        }
        await store.receive(\.settings.accountAccessPresentationUpdated)
        await store.receive(\.lifecycle.accountAccess.delegate) { state in
            state.lifecycle.accessGatePhase = .signedOut
        }
        await store.receive(\.settings.accountAccessPresentationUpdated)

        XCTAssertFalse(store.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertEqual(store.state.settings.accountSettings.presentation, AccountAccessPresentation())
        await store.finish()
    }

    /// ACC-001-settings_lifecycle_bridge: Settings Retry는 canonical lifecycle sync intent로 한 번만 전달된다.
    /// Settings가 local fetch를 시작하지 않고 canonical AccountAccess public action만 요청하는지 검증한다.
    /// - 검증 내용: retryRequested가 retryTapped와 sessionSyncRequested로 이어짐
    /// - 사전 조건: signed-out canonical lifecycle state
    /// - 기대 결과: Settings local state/effect 없이 canonical reducer가 retry를 판정함
    func testSettingsRetryRoutesToCanonicalLifecycleExactlyOnce() async {
        let store = makeSettingsAccountBridgeStore()
        // store.exhaustivity = .off: retry의 downstream sync policy는 AccountAccess suite에서 별도로 검증됨
        store.exhaustivity = .off

        await store.send(.settings(.delegate(.account(.retryRequested))))
        await store.receive(\.lifecycle.accountAccess.retryTapped)
        await store.finish()
    }

    /// ACC-001-settings_lifecycle_bridge: canonical lifecycle presentation은 Settings value projection을 갱신한다.
    /// lifecycle unlocked delegate가 Settings에 AccountAccess state나 store를 노출하지 않는 경로를 검증한다.
    /// - 검증 내용: canonical account facts가 accountAccessPresentationUpdated로 전달됨
    /// - 사전 조건: lifecycle AccountAccess는 active session snapshot을 보유하고 access gate는 이미 granted임
    /// - 기대 결과: Settings access status와 equatable presentation이 canonical facts와 일치함
    func testCanonicalLifecycleAccountAccessUpdatesSettingsProjection() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.lifecycle.accountAccess.hasAccountSession = true
        initialState.lifecycle.accountAccess.status = snapshot.status
        initialState.lifecycle.accountAccess.snapshot = snapshot
        let store = makeSettingsAccountBridgeStore(initialState: initialState)

        await store.send(.lifecycle(.accountAccess(.delegate(.unlocked(snapshot)))))
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            let presentation = AccountAccessPresentation(
                hasAccountSession: true,
                accessStatus: .coreLicenseActive,
            )
            state.settings.accessStatus = .coreLicenseActive
            state.settings.accountSettings.presentation = presentation
        }

        XCTAssertEqual(store.state.settings.accountSettings.setAuthState, .signedIn)
        XCTAssertEqual(store.state.settings.accountSettings.setEntitlementState, .entitlementActive)
        await store.finish()
    }

    /// ACC-001-settings_lifecycle_bridge: session expiry는 canonical lifecycle failure projection으로 Settings를 갱신한다.
    /// session-end notification이 legacy Settings child action 없이 lifecycle AccountAccess만 종료하는지 검증한다.
    /// - 검증 내용: sessionExpiredDetected가 canonical child teardown과 signed-out failure presentation으로 이어짐
    /// - 사전 조건: active session을 가진 lifecycle AccountAccess와 recoveryRequired gate
    /// - 기대 결과: Settings는 didSignInFail=true, accessStatus=.none projection을 수신함
    func testSessionExpiryUpdatesSettingsFromCanonicalLifecycleProjection() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .recoveryRequired
        initialState.lifecycle.accountAccess.hasAccountSession = true
        initialState.lifecycle.accountAccess.status = .coreLicenseActive
        let store = makeSettingsAccountBridgeStore(initialState: initialState)
        // store.exhaustivity = .off: session-expiry cleanup과 lifecycle recovery delegate를 함께 검증함
        store.exhaustivity = .off

        await store.send(.lifecycle(.sessionExpiredDetected(reason: .sessionExpired))) { state in
            state.lifecycle.sessionEndReason = .sessionExpired
        }
        await store.receive(\.lifecycle.accountAccess._sessionExpiredDetected) { state in
            state.lifecycle.accountAccess.revalidationGeneration = 1
            state.lifecycle.accountAccess.hasAccountSession = false
            state.lifecycle.accountAccess.didSignInFail = true
            state.lifecycle.accountAccess.isSessionExpired = true
            state.lifecycle.accountAccess.status = nil
            state.lifecycle.accountAccess.fetchGeneration = 1
            state.lifecycle.accountAccess.syncGeneration = 1
            state.lifecycle.accountAccess.refreshDeadlineGeneration = 1
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(didSignInFail: true)
        }
        XCTAssertEqual(store.state.settings.accessStatus, AccessStatus.none)
        XCTAssertTrue(store.state.settings.accountSettings.presentation.didSignInFail)
        await store.finish()
    }

    /// ACC-001-settings_lifecycle_bridge: callback은 owner resolver 없이 canonical lifecycle AccountAccess로 직접 전달된다.
    /// - 검증 내용: receiveAuthCallbackURL이 lifecycle AccountAccess.loginCallbackReceived 한 번으로 직접 번역됨
    /// - 사전 조건: canonical lifecycle AccountAccess가 callback 대기 중임
    /// - 기대 결과: compatibility action이나 surface owner resolution 없이 canonical child가 callback을 처리함
    func testAuthCallbackRoutesDirectlyToCanonicalLifecycleAccountAccess() async throws {
        let callbackURL = try XCTUnwrap(
            URL(string: "voyager://auth/callback?ticket=legacy-ticket&state=legacy-state&context=paywall"),
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.isSignInInProgress = true
        initialState.lifecycle.accountAccess.handoffPendingState = "legacy-state"
        let store = makeSettingsAccountBridgeStore(initialState: initialState)
        // store.exhaustivity = .off: callback claim/exchange atomics는 AccountAccess spec suite가 소유함
        store.exhaustivity = .off

        await store.send(.receiveAuthCallbackURL(callbackURL))
        await store.receive(\.lifecycle.accountAccess.loginCallbackReceived)
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(
                isSignInInProgress: true,
            )
        }
        await store.receive(\.lifecycle.accountAccess._handoffClaimCompleted)
        await store.receive(\.settings.accountAccessPresentationUpdated)

        XCTAssertEqual(store.state.lifecycle.accountAccess.handoffScope, .lifecycle)
        XCTAssertTrue(store.state.lifecycle.accountAccess.isSignInInProgress)
        await store.finish()
    }

    /// ACC-001-settings_lifecycle_bridge: cancellation은 canonical lifecycle handoff만 종료하고 Settings projection을 갱신한다.
    /// - 검증 내용: cancelSignIn이 canonical pending state를 제거하고 signed-out projection을 발행함
    /// - 사전 조건: lifecycle canonical child가 legacy settings scope의 pending handoff를 보유함
    /// - 기대 결과: pending state가 제거되고 Settings는 projection만 갱신됨
    func testCanonicalLifecycleHandoffCancellationUpdatesSettingsProjection() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.isSignInInProgress = true
        initialState.lifecycle.accountAccess.handoffPendingState = "cancel-state"
        initialState.lifecycle.accountAccess.handoffScope = .lifecycle
        let store = makeSettingsAccountBridgeStore(initialState: initialState)

        await store.send(.lifecycle(.accountAccess(.cancelSignIn))) { state in
            state.lifecycle.accountAccess.isSignInInProgress = false
            state.lifecycle.accountAccess.handoffPendingState = nil
            state.lifecycle.accountAccess.handoffScope = .lifecycle
        }
        await store.receive(\.settings.accountAccessPresentationUpdated)

        XCTAssertEqual(store.state.lifecycle.accountAccess.handoffScope, .lifecycle)
        await store.finish()
    }

    /// ACC-001-settings_lifecycle_bridge: timeout 뒤 late callback은 canonical state를 되살리지 않는다.
    /// timeout과 stale callback이 canonical direct routing을 우회해 terminal state를 바꾸지 않는지 검증한다.
    /// - 검증 내용: timeout failure projection 뒤 late callback은 claim/exchange 없이 canonical ingress에서 종료됨
    /// - 사전 조건: legacy settings scope pending handoff와 timeout 이후 동일 callback URL
    /// - 기대 결과: didSignInFail=true를 유지하고 pending/exchange state가 재생성되지 않음
    func testCanonicalLifecycleHandoffTimeoutRejectsLateCallback() async throws {
        let callbackURL = try XCTUnwrap(
            URL(string: "voyager://auth/callback?ticket=late-ticket&state=timeout-state&context=paywall"),
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.isSignInInProgress = true
        initialState.lifecycle.accountAccess.handoffPendingState = "timeout-state"
        initialState.lifecycle.accountAccess.handoffScope = .lifecycle
        let store = makeSettingsAccountBridgeStore(initialState: initialState)
        // store.exhaustivity = .off: stale callback은 terminal timeout state의 no-op 여부만 검증함
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(._handoffCallbackTimedOut(state: "timeout-state")))) { state in
            state.lifecycle.accountAccess.isSignInInProgress = false
            state.lifecycle.accountAccess.didSignInFail = true
            state.lifecycle.accountAccess.handoffPendingState = nil
            state.lifecycle.accountAccess.handoffScope = .lifecycle
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(didSignInFail: true)
        }

        await store.send(.receiveAuthCallbackURL(callbackURL))
        await store.receive(\.lifecycle.accountAccess.loginCallbackReceived)

        XCTAssertTrue(store.state.lifecycle.accountAccess.didSignInFail)
        XCTAssertNil(store.state.lifecycle.accountAccess.handoffPendingState)
        XCTAssertNil(store.state.lifecycle.accountAccess.handoffExchangeState)
        await store.finish()
    }

    func testOpenAISettingsSelectsAISectionWhenAccessStatusIsActive() async {
        var initialState = AppRootFeature.State()
        initialState.settings.accessStatus = .coreLicenseActive
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.openAISettings)
        await store.receive(\.settings.selectSection) { state in
            state.settings.selectedSection = .ai
        }
    }

    func testOpenAISettingsDoesNotSelectAISectionWhenAccessStatusIsInactive() async {
        var initialState = AppRootFeature.State()
        initialState.settings.accessStatus = .none
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.openAISettings)
        await store.finish()
    }

    // MARK: - Task 3: canonical child launch verification

    /// Task 3: lifecycle는 AccountAccess child가 소유한 access 조회를 직접 시작하지 않는다.
    /// launch → child onAppear → session restore(nil) → recoveryRequired delegate chain을 검증.
    func testLifecycleLaunchDelegatesAccessToCanonicalChild() async {
        let directFetchCount = LockIsolated(0)
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.authNetworkClient.fetchAccessStatus = {
                directFetchCount.withValue { $0 += 1 }
                return AccessStatusResponse(hasAccess: false, status: "trial_expired", productKey: "trial")
            }
            $0.accountSessionClient.read = { nil }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { true }
        }
        store.exhaustivity = .off

        await store.send(.launch(.didFinishLaunching)) {
            $0.didFinishLaunching = true
            $0.accessGatePhase = .checking
        }

        await store.receive(\.accountAccess.onAppear)
        await store.receive(\.accountAccess._onAppearSessionRestored)
        await store.receive(\.accountAccess.delegate) {
            $0.accessGatePhase = .recoveryRequired
        }

        XCTAssertEqual(directFetchCount.value, 0)
        await store.skipInFlightEffects()
        await store.finish()
    }

    /// Task 3: unlocked delegate가 helper 시작과 initial window를 정확히 한 번 트리거한다.
    func testLifecycleUnlockedStartsHelperAndOpensWindowOnce() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
            deviceBindingVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        var initialState = AppLifecycleFeature.State()
        initialState.accessGatePhase = .checking
        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.helperAppClient.terminationEvents = {
                AsyncStream { $0.finish() }
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.unlocked(snapshot))))

        XCTAssertEqual(store.state.accessGatePhase, .granted)
        XCTAssertTrue(store.state.didStartHelper)
        await store.finish()
    }

    /// Task 3: recoveryRequired delegate는 helper를 시작하지 않고 phase만 설정한다.
    func testLifecycleRecoveryRequiredDoesNotStartHelper() async {
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.helperAppClient.start = {}
            $0.onboardingWindowClient.isRequired = { false }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.recoveryRequired(.sessionRequired)))) {
            $0.accessGatePhase = .recoveryRequired
        }

        await store.receive(\.delegate.openInitialWindowIfNeeded)

        XCTAssertEqual(store.state.accessGatePhase, .recoveryRequired)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    /// Task 3: terminating 상태에서는 unlocked delegate를 거부한다.
    func testLifecycleUnlockedRejectedWhenTerminating() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
            deviceBindingVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        var initialState = AppLifecycleFeature.State()
        initialState.terminationAttemptID = UUID(0)
        initialState.accessGatePhase = .terminating

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.unlocked(snapshot))))

        XCTAssertEqual(store.state.accessGatePhase, .terminating)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    // MARK: - Task 4: session-end and termination child routing

    /// Task 4: sessionExpiredDetected는 reason을 app-level에 저장하고 child _sessionExpiredDetected로 라우팅한다.
    /// RED: 현재 코드는 child action을 보내지 않으므로 이 receive가 실패한다.
    func testSessionExpiredDetectedRoutesChildSessionExpiredDetected() async {
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.accountSessionClient.delete = { _ in }
            $0.accessStatusSnapshotClient.remove = {}
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.sessionExpiredDetected(reason: .sessionExpired)) {
            $0.sessionEndReason = .sessionExpired
        }

        // Task 4가 적용되면 child가 _sessionExpiredDetected를 수신한다.
        await store.receive(\.accountAccess._sessionExpiredDetected) { _ in }
        await store.finish()
    }

    /// Task 4: termination(.willTerminate)는 child appWillTerminate를 보낸다.
    /// RED: 현재 코드는 보내지 않으므로 이 receive가 실패한다.
    func testTerminationWillTerminateSendsChildAppWillTerminate() async {
        var initialState = AppLifecycleFeature.State()
        initialState.terminationAttemptID = UUID(0)

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.termination(.willTerminate)) {
            $0.accessGatePhase = .terminating
        }

        // Task 4가 적용되면 child가 appWillTerminate를 수신한다.
        await store.receive(\.accountAccess.appWillTerminate)
        await store.finish()
    }

    /// Task 4: terminating 상태에서는 recoveryRequired delegate를 거부한다.
    func testLifecycleRecoveryRequiredRejectedWhenTerminating() async {
        var initialState = AppLifecycleFeature.State()
        initialState.terminationAttemptID = UUID(0)
        initialState.accessGatePhase = .terminating

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.recoveryRequired(.sessionRequired))))

        XCTAssertEqual(store.state.accessGatePhase, .terminating)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    /// Task 4 QA: terminating phase는 nil attemptID에서도 unlocked delegate를 거부한다.
    func testLifecycleUnlockedRejectedWhenTerminatingPhaseOnly() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
            deviceBindingVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        var initialState = AppLifecycleFeature.State()
        initialState.accessGatePhase = .terminating
        // terminationAttemptID는 nil — completeTerminationAttempt 이후 상태 시뮬레이션

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.unlocked(snapshot))))

        XCTAssertEqual(store.state.accessGatePhase, .terminating)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    /// Task 4 QA: terminating phase는 nil attemptID에서도 recoveryRequired delegate를 거부한다.
    func testLifecycleRecoveryRequiredRejectedWhenTerminatingPhaseOnly() async {
        var initialState = AppLifecycleFeature.State()
        initialState.accessGatePhase = .terminating

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.recoveryRequired(.sessionRequired))))

        XCTAssertEqual(store.state.accessGatePhase, .terminating)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    /// Task 4 QA: terminating phase는 nil attemptID에서도 signedOut delegate를 거부한다.
    func testLifecycleSignedOutRejectedWhenTerminatingPhaseOnly() async {
        var initialState = AppLifecycleFeature.State()
        initialState.accessGatePhase = .terminating

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.signedOut)))

        XCTAssertEqual(store.state.accessGatePhase, .terminating)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    // MARK: - External route flush

    /// Task 3 QA: presentedAccountAccess는 guard가 없는 phase에서 nil을 반환한다.
    func testPresentedAccountAccessNilOutsideGuardPhases() {
        let phases: [AppLifecycleAccessGatePhase] = [
            .unresolved,
            .checking,
            .granted,
            .terminating,
        ]
        for phase in phases {
            var state = AppLifecycleFeature.State()
            state.accessGatePhase = phase
            XCTAssertNil(
                state.presentedAccountAccess,
                "\(phase) should not present guard overlay",
            )
        }
    }

    func testPresentedAccountAccessReturnsCanonicalChildDuringRecovery() {
        var state = AppLifecycleFeature.State()
        state.accessGatePhase = .recoveryRequired
        state.accountAccess.status = .trialExpired
        state.accountAccess.hasAccountSession = true

        let presented = state.presentedAccountAccess
        XCTAssertNotNil(presented)
        XCTAssertEqual(presented, state.accountAccess)
        XCTAssertEqual(presented?.status, .trialExpired)
        XCTAssertEqual(presented?.hasAccountSession, true)
    }

    func testOpenInitialWindowDefersPendingExternalRoutesWhenRecoveryRequired() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        var initialState = AppRootFeature.State()
        initialState.pendingExternalURLs = [deepLink]
        initialState.lifecycle.accessGatePhase = .recoveryRequired

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.continuousClock = ImmediateClock()
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)

        XCTAssertEqual(store.state.pendingExternalURLs, [deepLink])
        await store.finish()
    }

    func testOpenInitialWindowDefersPendingExternalRoutesWhenSignedOut() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        var initialState = AppRootFeature.State()
        initialState.pendingExternalURLs = [deepLink]
        initialState.lifecycle.accessGatePhase = .signedOut

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))

        XCTAssertEqual(store.state.pendingExternalURLs, [deepLink])
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        await store.finish()
    }

    func testOpenInitialWindowDoesNotOpenEmptyWindowWhileChecking() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        var initialState = AppRootFeature.State()
        initialState.pendingExternalURLs = [deepLink]
        initialState.isExternalURLFlushDelegateScheduled = true
        initialState.lifecycle.accessGatePhase = .checking

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded))) {
            $0.isExternalURLFlushDelegateScheduled = false
        }

        XCTAssertEqual(store.state.pendingExternalURLs, [deepLink])
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        await store.finish()
    }

    func testAccountAccessUnlockFlushesQueuedRoutes() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
        )
        var initialState = AppRootFeature.State()
        initialState.pendingExternalURLs = [deepLink]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.accountSessionClient.delete = { _ in }
            $0.accessStatusSnapshotClient.save = { _ in }
            $0.accessStatusSnapshotClient.remove = {}
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.delegate(.unlocked(snapshot))))) {
            // Unlock should set phase to .granted synchronously
            $0.lifecycle.accessGatePhase = .granted
        }

        // The lifecycle delegate effect should flush queued routes.
        // Assert route delivery to prove the flush chain works.
        await store.receive(\.externalFileRouter.receive)

        XCTAssertTrue(
            store.state.pendingExternalURLs.isEmpty,
            "pendingExternalURLs should be cleared after unlock flush, phase=\(store.state.lifecycle.accessGatePhase)",
        )
        await store.finish()
    }

    // MARK: - VOY-521 Auth callback canonical routing

    /// ACC-001-complete_auth_handoff_callback: main AppDelegate는 유효 auth callback을 AppRoot에 정확히 한 번 전달한다.
    /// - 검증 내용: receiveAuthCallbackURL 원본 callback이 한 번만 전송됨
    /// - 사전 조건: main AppDelegate가 구성되고 Prod callback scheme을 사용함
    /// - 기대 결과: main-app onboarding resolver 없이 AppRoot ingress가 유일한 수신자임
    func testAppDelegateRoutesAuthCallbackToAppRootExactlyOnce() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager" // Prod identity for test focus

        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [url])

        let callbackActions = box.actions.compactMap { action -> URL? in
            guard case let .receiveAuthCallbackURL(received) = action else { return nil }
            return received
        }
        XCTAssertEqual(callbackActions, [url])
    }

    /// ACC-001-complete_auth_handoff_callback: AppRoot는 surface owner resolution 없이 callback을 lifecycle AccountAccess로
    /// 직접 전달한다.
    /// - 검증 내용: lifecycle AccountAccess child action이 한 번 수신됨
    /// - 사전 조건: canonical lifecycle AccountAccess가 callback 대기 중임
    /// - 기대 결과: Settings와 main-app Onboarding branch 없이 canonical owner만 callback을 수신함
    func testAppRootRoutesAuthCallbackDirectlyToLifecycleAccountAccess() async throws {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.isSignInInProgress = true
        initialState.lifecycle.accountAccess.handoffPendingState = "lifecycle-state"
        initialState.settings.accountSettings.presentation = AccountAccessPresentation(
            isSignInInProgress: true,
        )
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        let callbackURL = try XCTUnwrap(
            URL(string: "voyager://auth/callback?ticket=old&state=old-state&context=onboarding"),
        )

        await store.send(.receiveAuthCallbackURL(callbackURL))
        await store.receive(\.lifecycle.accountAccess.loginCallbackReceived)
        await store.receive(\.settings.accountAccessPresentationUpdated)

        XCTAssertEqual(
            store.state.settings.accountSettings.presentation,
            AccountAccessPresentation(isSignInInProgress: true),
        )
        await store.finish()
    }

    func testAppDelegateIgnoresUnsupportedURLsAndRoutesVoyagerDeepLinks() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager" // Prod identity for test focus

        try appDelegate.application(NSApp, open: [XCTUnwrap(URL(string: "https://example.com"))])
        appDelegate.application(NSApp, open: [])

        XCTAssertTrue(box.actions.isEmpty)

        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        appDelegate.application(NSApp, open: [deepLink])

        let routed = box.actions.contains { action in
            if case let .receiveExternalURL(received) = action {
                return received == deepLink
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    // MARK: - Scheme acceptance (Dev/Prod)

    /// Dev callbackScheme에서 voyager-dev:// auth/callback이 routeAuthCallback으로 라우팅되는지 검증
    func testAppDelegateWithDevSchemeAcceptsVoyagerDevCallback() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager-dev"

        let url = try XCTUnwrap(URL(string: "voyager-dev://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [url])

        let routed = box.actions.contains { action in
            if case let .receiveAuthCallbackURL(received) = action {
                return received == url
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    /// Dev callbackScheme에서 voyager:// URL은 무시되는지 검증 (cross-scheme rejection)
    func testAppDelegateWithDevSchemeRejectsVoyagerURL() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager-dev"

        let voyagerURL = try XCTUnwrap(URL(string: "voyager://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [voyagerURL])

        let anyExternalAction = box.actions.contains { action in
            if case .receiveExternalURL = action { return true }
            if case .receiveAuthCallbackURL = action { return true }
            return false
        }
        XCTAssertFalse(anyExternalAction)
    }

    /// Prod callbackScheme에서 voyager-dev:// URL은 무시되는지 검증 (cross-scheme rejection)
    func testAppDelegateWithProdSchemeRejectsVoyagerDevURL() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager"

        let devURL = try XCTUnwrap(URL(string: "voyager-dev://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [devURL])

        let anyExternalAction = box.actions.contains { action in
            if case .receiveExternalURL = action { return true }
            if case .receiveAuthCallbackURL = action { return true }
            return false
        }
        XCTAssertFalse(anyExternalAction)
    }

    /// Prod callbackScheme에서 voyager:// deep link는 정상 라우팅되는지 검증
    func testAppDelegateWithProdSchemeAcceptsVoyagerDeepLink() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager"

        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        appDelegate.application(NSApp, open: [deepLink])

        let routed = box.actions.contains { action in
            if case let .receiveExternalURL(received) = action {
                return received == deepLink
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    /// Dev callbackScheme에서 voyager-dev:// deep link는 정상 라우팅되는지 검증
    func testAppDelegateWithDevSchemeAcceptsVoyagerDevDeepLink() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager-dev"

        let deepLink = try XCTUnwrap(URL(string: "voyager-dev://open"))
        appDelegate.application(NSApp, open: [deepLink])

        let routed = box.actions.contains { action in
            if case let .receiveExternalURL(received) = action {
                return received == deepLink
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    // MARK: - Test support

    private func makeSettingsAccountBridgeStore(
        initialState: AppRootFeature.State = AppRootFeature.State(),
        signInHandoffClient: SignInHandoffClient = SignInHandoffClient { _ in .failure },
    ) -> TestStore<AppRootFeature.State, AppRootFeature.Action> {
        TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.accountSessionClient.delete = { _ in }
            $0.accessStatusSnapshotClient.save = { _ in }
            $0.accessStatusSnapshotClient.remove = {}
            $0.signInHandoffClient = signInHandoffClient
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.fileManagerWindowClient.open = { _ in }
            $0.appHandoffTarget = .voyager
        }
    }
}

private final class SnapshotCaptureBox: @unchecked Sendable {
    var value: AccessStatusSnapshot?
}

// MARK: - VOY-521 Task 1 test support

private final class ActionBox<T>: @unchecked Sendable {
    var actions: [T] = []
}

private struct _ActionRecordingAppRoot: Reducer {
    typealias State = AppRootState
    typealias Action = AppRootAction

    let box: ActionBox<AppRootAction>

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            box.actions.append(action)
            return .none
        }
    }
}

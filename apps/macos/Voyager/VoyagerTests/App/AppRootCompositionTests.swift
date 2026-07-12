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

    // MARK: - AccountAccess delegate routing

    func testAppRootAccountAccessUnlockedForwardsSettingsAccessSnapshotHydration() async {
        let expiry = Date(timeIntervalSince1970: 4_102_444_800)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: expiry,
            deviceBindingVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let store = makeAccountAccessGrantedStore()

        await store.send(.lifecycle(.accountAccess(.delegate(.unlocked(snapshot)))))

        await store.receive(\.settings.appLifecycleAccessSnapshotReady) { state in
            state.settings.accessStatus = snapshot.status
        }
        await store.receive(\.settings.account.access.hydrateLaunchSnapshot) { state in
            state.settings.accountSettings.access.status = .coreLicenseActive
            state.settings.accountSettings.access.snapshot = snapshot
            state.settings.accountSettings.access.isComplete = true
            state.settings.accountSettings.access.sessionExpiresAt = expiry
            state.settings.accountSettings.access.hasAccountSession = true
            state.settings.accountSettings.access.didBootstrap = true
        }

        XCTAssertEqual(store.state.settings.accountSettings.access.sessionExpiresAt, expiry)
        XCTAssertTrue(store.state.settings.accountSettings.access.hasAccountSession)
        await store.finish()
    }

    // MARK: - Task 5: AccountAccess delegate signedOut clears Settings

    func testAccountAccessSignedOutClearsSettingsTopLevelAccess() async {
        var initialState = AppRootFeature.State()
        initialState.settings.accessStatus = .coreLicenseActive
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.delegate(.signedOut))))

        await store.receive(\.settings.accessStatusLoaded) { state in
            state.settings.accessStatus = .none
        }

        XCTAssertEqual(store.state.settings.accessStatus, .none)
        await store.finish()
    }

    func testSessionExpiredDetectedClearsSettingsAccountChildAccessState() async {
        let expiry = Date(timeIntervalSince1970: 4_102_444_800)
        var initialState = AppRootFeature.State()
        initialState.settings.accessStatus = .coreLicenseActive
        initialState.settings.accountSettings.access.status = .coreLicenseActive
        initialState.settings.accountSettings.access.snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: expiry,
        )
        initialState.settings.accountSettings.access.isComplete = true
        initialState.settings.accountSettings.access.hasAccountSession = true
        initialState.settings.accountSettings.access.sessionExpiresAt = expiry

        let store = makeAccountAccessGrantedStore(initialState: initialState)

        await store.send(.lifecycle(.sessionExpiredDetected(reason: .sessionExpired)))

        await store.receive(\.settings.accessStatusLoaded) { state in
            state.settings.accessStatus = .none
        }
        await store.receive(\.settings.account.access._sessionExpiredDetected) { state in
            state.settings.accountSettings.access.status = nil
            state.settings.accountSettings.access.snapshot = nil
            state.settings.accountSettings.access.isComplete = false
            state.settings.accountSettings.access.hasAccountSession = false
            state.settings.accountSettings.access.didSignInFail = true
            state.settings.accountSettings.access.isSessionExpired = true
            state.settings.accountSettings.access.sessionExpiresAt = nil
        }

        XCTAssertEqual(store.state.settings.accessStatus, .none)
        await store.finish()
    }

    func testExplicitSignOutSetsSignedOutPhase() async {
        var initialState = AppRootFeature.State()
        initialState.settings.accessStatus = .coreLicenseActive
        initialState.settings.accountSettings.access.hasAccountSession = true

        let store = makeAccountAccessGrantedStore(initialState: initialState)

        await store.send(.lifecycle(.sessionExpiredDetected(reason: .explicitSignOut)))

        // lifecycle scope가 child _sessionExpiredDetected를 먼저 수신
        await store.receive(\.lifecycle.accountAccess._sessionExpiredDetected)
        // AppRoot reduceAppLifecycle이 settings 라우팅
        await store.receive(\.settings.accessStatusLoaded) { state in
            state.settings.accessStatus = .none
        }
        // child가 delegate recoveryRequired → parent가 explicitSignOut 감지 후 signedOut
        await store.receive(\.lifecycle.accountAccess.delegate) { state in
            state.lifecycle.accessGatePhase = .signedOut
        }

        XCTAssertTrue(store.state.settings.accountSettings.access.hasAccountSession)
        XCTAssertFalse(store.state.settings.accountSettings.access.didSignInFail)
        XCTAssertEqual(store.state.lifecycle.accessGatePhase, .signedOut)
        XCTAssertNotNil(store.state.lifecycle.presentedAccountAccess)
        XCTAssertEqual(
            store.state.lifecycle.presentedAccountAccess,
            store.state.lifecycle.accountAccess,
        )
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

    // MARK: - VOY-521 Auth callback fallback routing

    func testAppDelegateSkipsAppRootFallbackWhenOnboardingHandlesCallback() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.resolveAuthCallbackRouting = { _ in true }

        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [url])

        let sentFallback = box.actions.contains { action in
            if case .lifecycle(.accountAccess(.loginCallbackReceived)) = action {
                return true
            }
            return false
        }
        XCTAssertFalse(sentFallback)
    }

    func testAppDelegateFallsBackToCanonicalChildWhenOnboardingAbsent() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.resolveAuthCallbackRouting = { _ in false }

        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [url])

        let routed = box.actions.contains { action in
            if case let .lifecycle(.accountAccess(.loginCallbackReceived(received))) = action {
                return received == url
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    func testAppDelegateIgnoresUnsupportedURLsAndRoutesVoyagerDeepLinks() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)

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

    // MARK: - Test support

    private func makeAccountAccessGrantedStore(
        initialState: AppRootFeature.State = AppRootFeature.State(),
    ) -> TestStore<AppRootFeature.State, AppRootFeature.Action> {
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
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off
        return store
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

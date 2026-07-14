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

    // MARK: - VOY-521 Auth callback canonical routing

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

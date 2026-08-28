// FLOW-ID: acc.auth_session
import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerFeaturesAccountAccess
import VoyagerPagesFileManager
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class AuthSessionFlowTests: XCTestCase {
    func testLateSessionRestoreAfterShellReadinessDoesNotManipulateWindows() async {
        let windowID = UUID(900)
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [
            .init(id: windowID, window: .makeInitial(path: "/existing")),
        ]
        initialState.windowManager.focusedWindowID = windowID
        initialState.windowManager.lastUsedWindowIDs = [windowID]

        let store = AccountAccessFlowTestSupport.makeRootStore(
            initialState: initialState,
            session: AccountAccessFlowTestSupport.validSession,
        )
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.onAppear)))
        await store.receive(\.lifecycle.accountAccess._onAppearSessionRestored)

        XCTAssertTrue(store.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertEqual(store.state.windowManager.windows.map(\.id), [windowID])
        XCTAssertEqual(store.state.windowManager.focusedWindowID, windowID)
        XCTAssertEqual(store.state.windowManager.lastUsedWindowIDs, [windowID])
        await store.skipInFlightEffects()
    }

    // FLOW-PATH: happy_path

    func testRootExchangeCompletionKeepsOptionalAuthChainAvailable() async {
        let state = "guard-recovery-state"
        let session = AccountAccessFlowTestSupport.validSession
        let syncResult = SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(
                hasAccess: true,
                status: "active",
                ownershipStatus: "owned",
                updateStatus: "active",
                updatesThrough: Date(timeIntervalSince1970: 2_000_000_000),
            ),
            deviceBindingOutcome: .bound,
            connectedDeviceAvailability: .available,
            sessionExpiresAt: session.expiresAt,
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.accountAccess.isSignInInProgress = true
        initialState.lifecycle.accountAccess.handoffExchangeState = state
        initialState.lifecycle.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
            context: .paywall,
            scope: .lifecycle,
        )
        let store = AccountAccessFlowTestSupport.makeRootStore(
            initialState: initialState,
            exchangeSession: session,
            syncResult: syncResult,
        )
        // root projection의 부수 액션은 이 exchange-completion-to-unlock flow 검증 범위 밖이다.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(._handoffExchangeCompleted(
            state: state,
            generation: 0,
            result: .success(AccountAccessHandoffCompletion(
                expiresAt: session.expiresAt,
                sessionBindingID: UUID(),
            )),
        ))))
        await store.receive(\.lifecycle.accountAccess.sessionSyncRequested)
        await store.receive(\.lifecycle.accountAccess._sessionSyncActivationCompleted)
        await store.receive(\.lifecycle.accountAccess._sessionSyncCompleted)
        XCTAssertTrue(store.state.lifecycle.accountAccess.hasAccountSession)
        await store.skipInFlightEffects()
    }

    func testLoginHandoffCreatesCanonicalSessionAndStartsEntitlementValidation() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.isSignInInProgress = true
        initialState.lifecycle.accountAccess.handoffExchangeState = "handoff-state"
        initialState.lifecycle.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
            context: .onboarding,
            scope: .onboarding,
        )
        let store = AccountAccessFlowTestSupport.makeRootStore(initialState: initialState)
        // store.exhaustivity = .off: root, lifecycle, and AccountAccess effect chain is the flow boundary.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(._handoffExchangeCompleted(
            state: "handoff-state",
            generation: 0,
            result: .success(AccountAccessHandoffCompletion(
                expiresAt: AccountAccessFlowTestSupport.validSession.expiresAt,
                sessionBindingID: AccountAccessFlowTestSupport.validSession.sessionBindingID,
            )),
        ))))
        await store.receive(\.lifecycle.accountAccess.sessionSyncRequested)

        XCTAssertTrue(store.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertFalse(store.state.lifecycle.accountAccess.isSignInInProgress)
        XCTAssertFalse(store.state.lifecycle.accountAccess.didSignInFail)
        XCTAssertEqual(
            store.state.lifecycle.accountAccess.sessionExpiresAt,
            AccountAccessFlowTestSupport.validSession.expiresAt,
        )
        await store.skipInFlightEffects()
    }

    // FLOW-PATH: session_restore_background_return

    func testForegroundReturnRevalidatesPersistedSession() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.hasAccountSession = true
        initialState.lifecycle.accountAccess.sessionExpiresAt = AccountAccessFlowTestSupport.validSession.expiresAt
        initialState.lifecycle.accountAccess.ttlTimerActive = true
        let store = AccountAccessFlowTestSupport.makeRootStore(
            initialState: initialState,
            session: AccountAccessFlowTestSupport.validSession,
        )
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.appDidBecomeActive)))
        await store.receive(\.lifecycle.accountAccess.revalidatePersistedSession)
        await store.receive(\.lifecycle.accountAccess._persistedSessionRevalidated)
        await store.receive(\.lifecycle.accountAccess.sessionSyncRequested)

        XCTAssertEqual(store.state.lifecycle.accountAccess.revalidationGeneration, 1)
        XCTAssertEqual(
            store.state.lifecycle.accountAccess.sessionExpiresAt,
            AccountAccessFlowTestSupport.validSession.expiresAt,
        )
        await store.skipInFlightEffects()
    }

    // FLOW-PATH: handoff_token_exchange_failure

    func testHandoffExchangeFailureKeepsLoggedOutAndExposesRetrySurface() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.isSignInInProgress = true
        initialState.lifecycle.accountAccess.handoffExchangeState = "failed-state"
        initialState.lifecycle.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
            context: .onboarding,
            scope: .onboarding,
        )
        let store = AccountAccessFlowTestSupport.makeRootStore(initialState: initialState)
        // store.exhaustivity = .off: handoff failure의 Settings projection은 flow assertion 범위 밖임.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(._handoffExchangeCompleted(
            state: "failed-state",
            generation: 0,
            result: .failure(.networkFailure),
        ))))

        XCTAssertFalse(store.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertTrue(store.state.lifecycle.accountAccess.didSignInFail)
        XCTAssertTrue(store.state.lifecycle.accountAccess.canStartLogin)
        await store.finish()
    }

    // FLOW-PATH: auth_flow_reexecution_during_active_auth

    func testSupersededAuthFlowIgnoresLateCallbackAndAcceptsLatestCallback() async throws {
        let staleCallback = try XCTUnwrap(
            URL(string: "voyager://auth/callback?ticket=stale-ticket&state=stale-state&context=paywall"),
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.isSignInInProgress = true
        initialState.lifecycle.accountAccess.handoffPendingState = "latest-state"
        initialState.lifecycle.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
            context: .paywall,
            scope: .lifecycle,
        )
        let store = AccountAccessFlowTestSupport.makeRootStore(initialState: initialState)
        store.exhaustivity = .off

        await store.send(.receiveAuthCallbackURL(staleCallback))

        XCTAssertEqual(store.state.lifecycle.accountAccess.handoffPendingState, "latest-state")
        XCTAssertNil(store.state.lifecycle.accountAccess.handoffExchangeState)
        await store.finish()

        var acceptedState = AppRootFeature.State()
        acceptedState.lifecycle.accountAccess.isSignInInProgress = true
        acceptedState.lifecycle.accountAccess.handoffExchangeState = "latest-state"
        acceptedState.lifecycle.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
            context: .paywall,
            scope: .lifecycle,
        )
        let acceptedStore = AccountAccessFlowTestSupport.makeRootStore(initialState: acceptedState)
        acceptedStore.exhaustivity = .off

        // 최신 callback은 canonical handoff claim 이후에만 만든 exchange completion으로 적용한다.
        await acceptedStore.send(.lifecycle(.accountAccess(._handoffExchangeCompleted(
            state: "latest-state",
            generation: 0,
            result: .success(AccountAccessHandoffCompletion(
                expiresAt: AccountAccessFlowTestSupport.validSession.expiresAt,
                sessionBindingID: AccountAccessFlowTestSupport.validSession.sessionBindingID,
            )),
        ))))
        await acceptedStore.receive(\.lifecycle.accountAccess.sessionSyncRequested)

        XCTAssertTrue(acceptedStore.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertFalse(acceptedStore.state.lifecycle.accountAccess.didSignInFail)
        await acceptedStore.finish()
    }
}

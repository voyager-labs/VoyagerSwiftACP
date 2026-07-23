// FLOW-ID: acc.auth_session
import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class AuthSessionFlowTests: XCTestCase {
    // FLOW-PATH: happy_path

    func testRootExchangeCompletionDismissesSessionLapseGuard() async {
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
        initialState.lifecycle.accessGatePhase = .recoveryRequired
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
        await store.receive(\.lifecycle.accountAccess.delegate)

        XCTAssertEqual(store.state.lifecycle.accessGatePhase, .granted)
        XCTAssertNil(store.state.lifecycle.presentedAccountAccess)
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

    // FLOW-PATH: session_restore_cold_start

    func testColdStartRestoresValidSessionAndKeepsCanonicalLifecycleLoggedIn() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: AccountAccessFlowTestSupport.referenceDate,
            sessionExpiresAt: AccountAccessFlowTestSupport.validSession.expiresAt,
        )
        let store = AccountAccessFlowTestSupport.makeRootStore()
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.hydrateLaunchSnapshot(snapshot))))

        XCTAssertTrue(store.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertFalse(store.state.lifecycle.accountAccess.isSessionExpired)
        XCTAssertEqual(store.state.lifecycle.accountAccess.accountAccessAuthAxis, .signedIn)
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

    // FLOW-PATH: session_expiry_during_use

    func testRefreshTokenExpiryTransitionsToSessionLapseGuardAndReauthenticationRecovers() async {
        var expiredState = AppRootFeature.State()
        expiredState.lifecycle.accountAccess.hasAccountSession = true
        expiredState.lifecycle.accountAccess.status = .coreLicenseActive
        let expiryStore = AccountAccessFlowTestSupport.makeRootStore(initialState: expiredState)
        expiryStore.exhaustivity = .off

        await expiryStore.send(.lifecycle(.sessionExpiredDetected(reason: .sessionExpired)))
        await expiryStore.receive(\.lifecycle.accountAccess._sessionExpiredDetected)
        await expiryStore.receive(\.lifecycle.accountAccess.delegate)

        XCTAssertFalse(expiryStore.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertTrue(expiryStore.state.lifecycle.accountAccess.isSessionExpired)
        XCTAssertEqual(expiryStore.state.lifecycle.accessGatePhase, .recoveryRequired)
        XCTAssertNotNil(expiryStore.state.lifecycle.presentedAccountAccess)
        await expiryStore.finish()

        var reauthenticationState = AppRootFeature.State()
        reauthenticationState.lifecycle.accessGatePhase = .recoveryRequired
        reauthenticationState.lifecycle.accountAccess.isSessionExpired = true
        reauthenticationState.lifecycle.accountAccess.isSignInInProgress = true
        reauthenticationState.lifecycle.accountAccess.handoffExchangeState = "reauthentication-state"
        reauthenticationState.lifecycle.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
            context: .paywall,
            scope: .lifecycle,
        )
        let reauthenticationStore = AccountAccessFlowTestSupport.makeRootStore(initialState: reauthenticationState)
        reauthenticationStore.exhaustivity = .off

        await reauthenticationStore.send(.lifecycle(.accountAccess(._handoffExchangeCompleted(
            state: "reauthentication-state",
            generation: 0,
            result: .success(AccountAccessHandoffCompletion(
                expiresAt: AccountAccessFlowTestSupport.validSession.expiresAt,
                sessionBindingID: AccountAccessFlowTestSupport.validSession.sessionBindingID,
            )),
        ))))
        await reauthenticationStore.receive(\.lifecycle.accountAccess.sessionSyncRequested)

        XCTAssertTrue(reauthenticationStore.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertFalse(reauthenticationStore.state.lifecycle.accountAccess.isSessionExpired)
        await reauthenticationStore.finish()
    }

    // FLOW-PATH: sign_out

    func testSettingsSignOutClearsCanonicalSessionAndShowsSessionLapseGuard() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.lifecycle.accountAccess.hasAccountSession = true
        initialState.lifecycle.accountAccess.status = .coreLicenseActive
        let store = AccountAccessFlowTestSupport.makeRootStore(initialState: initialState)
        store.exhaustivity = .off

        await store.send(.settings(.delegate(.account(.signOutRequested))))
        await store.receive(\.lifecycle.accountAccess.signOut)

        XCTAssertFalse(store.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertTrue(store.state.lifecycle.accountAccess.isSessionExpired)
        await store.receive(\.lifecycle.accountAccess.delegate)
        XCTAssertEqual(store.state.lifecycle.accessGatePhase, .signedOut)
        XCTAssertNotNil(store.state.lifecycle.presentedAccountAccess)
        await store.finish()
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

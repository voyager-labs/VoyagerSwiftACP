import Clocks
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC002CheckEntitlementStatusTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let eligibleUpdatesThrough = Date(timeIntervalSince1970: 2_000_000_000)

    private func session(expiresAt: Date? = nil, binding: UUID? = nil) -> AccountSession {
        AccountSession(
            accessToken: "test-access-token",
            status: .coreLicenseActive,
            expiresAt: expiresAt ?? referenceDate.addingTimeInterval(3600),
            sessionBindingID: binding ?? UUID(),
        )
    }

    private func response(
        hasAccess: Bool = true,
        status: String = "active",
        productKey: String = "core",
        currentPeriodEnd: Date? = nil,
    ) -> AccessStatusResponse {
        AccessStatusResponse(
            hasAccess: hasAccess,
            status: status,
            ownershipStatus: hasAccess ? "owned" : nil,
            updateStatus: hasAccess ? "active" : nil,
            reason: hasAccess ? "active_entitlement" : "expired_entitlement",
            productKey: productKey,
            currentPeriodEnd: currentPeriodEnd,
            source: "polar",
            updatesThrough: hasAccess ? eligibleUpdatesThrough : nil,
        )
    }

    private func syncResult(
        access: AccessStatusResponse = AccessStatusResponse(hasAccess: true, status: "active"),
        outcome: SessionSyncDeviceBindingOutcome = .bound,
        status: SessionSyncStatus = .complete,
        expiry: Date? = nil,
    ) -> SessionSyncResult {
        SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: status,
            accessStatus: access,
            deviceBindingOutcome: outcome,
            connectedDeviceAvailability: .available,
            sessionExpiresAt: expiry,
        )
    }

    private func makeStore(
        result: Result<SessionSyncResult, SessionSyncError>,
        state: AccountAccessFeature.State = .init(),
        session: AccountSession? = nil,
        snapshotClient: AccessStatusSnapshotClient = .testValue,
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        let clock = TestClock()
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in session },
                persist: { _ in },
                delete: { _ in },
            )
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { _, _ in try result.get() },
            )
            $0.accessStatusSnapshotClient = snapshotClient
            $0.date = .constant(referenceDate)
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        return store
    }

    private func sync(
        _ store: TestStore<AccountAccessFeature.State, AccountAccessFeature.Action>,
        intent: SessionSyncIntent = .validate,
        reason: SyncReason = .manual,
    ) async {
        await store.send(.sessionSyncRequested(intent: intent, reason: reason))
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted)
    }

    private func signedInState(expiry: Date? = nil, binding: UUID? = nil) -> AccountAccessFeature.State {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionExpiresAt = expiry ?? referenceDate.addingTimeInterval(3600)
        state.sessionBindingID = binding
        return state
    }

    func testOnAppearSessionRestoredTriggersFetch() async {
        let expiry = referenceDate.addingTimeInterval(3600)
        let store = makeStore(
            result: .success(syncResult(access: response(), expiry: expiry)),
            session: session(expiresAt: expiry),
        )
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\._onAppearSessionRestored)
        await store.receive(\.sessionSyncRequested)
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.unlocked)
        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertTrue(store.state.isComplete)
        await store.skipInFlightEffects()
    }

    func testOnAppearIsIdempotentOnReentry() async {
        let expiry = referenceDate.addingTimeInterval(3600)
        let store = makeStore(
            result: .success(syncResult(access: response(), expiry: expiry)),
            session: session(expiresAt: expiry),
        )
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\._onAppearSessionRestored)
        await store.receive(\.sessionSyncRequested)
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.unlocked)
        let generation = store.state.syncGeneration
        await store.send(.onAppear)
        XCTAssertEqual(store.state.syncGeneration, generation)
        await store.skipInFlightEffects()
    }

    func testOpenPricingMissingURLConfigProjectsErrorWithoutCrash() async {
        var state = signedInState()
        state.status = AccessStatus.none
        let store = makeStore(
            result: .success(syncResult()),
            state: state,
        )
        await store.send(.openPricingTapped)
        await store.receive(\._webURLResult)
        XCTAssertEqual(store.state.accountAccessStepState, .blocked)
        XCTAssertFalse(store.state.canRetry)
    }

    func testInvalidWebURLConfigThrowsNotConfiguredWithoutCrash() {
        for value in ["not a url", "ftp://voyager.fm", "https://"] {
            XCTAssertThrowsError(try CheckoutURLClient.validatedWebURL(for: "PUBLIC_WEB_BASE_URL", value: value)) {
                XCTAssertEqual($0 as? AccessError, .notConfigured)
            }
        }
    }

    func testFetchAccessStatusSuccessUpdatesStatusAndSnapshot() async {
        let store = makeStore(result: .success(syncResult(access: response())), state: signedInState())
        await sync(store)
        await store.receive(\.delegate.unlocked)
        XCTAssertEqual(store.state.status, .coreLicenseActive)
        XCTAssertEqual(store.state.snapshot?.status, .coreLicenseActive)
        XCTAssertTrue(store.state.isComplete)
    }

    func testFetchAccessStatusSuccessActiveSendsDelegateUnlocked() async {
        let store = makeStore(result: .success(syncResult(access: response())), state: signedInState())
        await sync(store)
        await store.receive(\.delegate.unlocked)
        XCTAssertTrue(store.state.isComplete)
    }

    func testActiveAccessDeviceBindingSeatCapacityDoesNotUnlock() async {
        let store = makeStore(
            result: .success(syncResult(access: response(), outcome: .deviceLimitReached)),
            state: signedInState(),
        )
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertEqual(store.state.deviceBindingFailure, .seatCapacityExceeded)
        XCTAssertEqual(store.state.accessUnlockPrimaryCTA, .account)
        XCTAssertFalse(store.state.isComplete)
    }

    func testActiveAccessDeviceBindingTransientFailureIsRetryable() async {
        let store = makeStore(
            result: .success(syncResult(access: response(), outcome: .notAttempted)),
            state: signedInState(),
        )
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertEqual(store.state.status, .networkFailure)
        XCTAssertEqual(store.state.deviceBindingFailure, .retryable)
        XCTAssertTrue(store.state.canRetry)
    }

    func testRepeatedDeviceBindingTransientFailureEscalatesToAccountSupport() async {
        var state = signedInState()
        state.deviceBindingRetryCount = 2
        let store = makeStore(result: .success(syncResult(access: response(), outcome: .notAttempted)), state: state)
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertEqual(store.state.deviceBindingRetryCount, 3)
        XCTAssertEqual(store.state.accessUnlockPrimaryCTA, .account)
    }

    func testStaleDeviceBindingSuccessIgnored() async {
        var state = signedInState()
        state.syncGeneration = 2
        let store = makeStore(result: .success(syncResult()), state: state)
        await store.send(._sessionSyncCompleted(generation: 1, result: .success(syncResult())))
        XCTAssertNil(store.state.snapshot)
        XCTAssertFalse(store.state.isComplete)
    }

    func testDeviceBindingUnauthorizedTriggersSessionExpired() async {
        let store = makeStore(result: .failure(.invalidCredential), state: signedInState())
        await sync(store)
        await store.receive(\._sessionExpiredDetected)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertTrue(store.state.isSessionExpired)
    }

    func testFetchAccessStatusNetworkFailureSetsErrorState() async {
        let store = makeStore(result: .success(SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .partial,
            accessStatus: response(hasAccess: false, status: "expired", productKey: "trial"),
            deviceBindingOutcome: .notAttempted,
            connectedDeviceAvailability: .unknown,
        )), state: signedInState())
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertEqual(store.state.status, .trialExpired)
        XCTAssertFalse(store.state.isComplete)
    }

    private func assertTerminalFailure(_ error: SessionSyncError, message: String) async {
        var state = signedInState()
        state.status = .coreLicenseActive
        state.snapshot = AccessStatusSnapshot(status: .coreLicenseActive, fetchedAt: referenceDate)
        state.isComplete = true
        let store = makeStore(result: .failure(error), state: state)
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertNil(store.state.status)
        XCTAssertNil(store.state.snapshot)
        XCTAssertEqual(store.state.errorMessage, message)
        XCTAssertFalse(store.state.isComplete)
    }

    func testFetchAccessStatusNotConfiguredFailureClearsStaleActiveEntitlementFacts() async {
        await assertTerminalFailure(.capabilityMiss, message: "Access service is not configured.")
    }

    func testFetchAccessStatusDecodingFailureClearsStaleActiveEntitlementFacts() async {
        await assertTerminalFailure(.storageFailure, message: "Access service is not configured.")
    }

    func testFetchAccessStatusUnknownGatewayCodeFailureClearsStaleActiveEntitlementFacts() async {
        await assertTerminalFailure(.capabilityMiss, message: "Access service is not configured.")
    }

    func testStaleGenerationResponseIgnored() async {
        var state = signedInState()
        state.syncGeneration = 2
        let store = makeStore(result: .success(syncResult()), state: state)
        await store.send(._sessionSyncCompleted(generation: 1, result: .success(syncResult())))
        XCTAssertNil(store.state.status)
        XCTAssertFalse(store.state.isComplete)
    }

    func testRetryTappedIncrementsGenerationAndTriggersFetch() async {
        let expiry = referenceDate.addingTimeInterval(3600)
        let store = makeStore(
            result: .success(syncResult(access: response())),
            state: signedInState(expiry: expiry),
            session: session(expiresAt: expiry),
        )
        store.exhaustivity = .off
        await store.send(.retryTapped)
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated)
        await store.receive(\.sessionSyncRequested)
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.unlocked)
        XCTAssertEqual(store.state.revalidationGeneration, 1)
        XCTAssertTrue(store.state.isComplete)
        await store.skipInFlightEffects()
    }

    func testFetchAccessStatusInactiveDoesNotUnlock() async {
        let store = makeStore(
            result: .success(syncResult(
                access: response(hasAccess: false, status: "expired", productKey: "trial"),
                outcome: .notAttempted,
            )),
            state: signedInState(),
        )
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertEqual(store.state.status, .trialExpired)
        XCTAssertFalse(store.state.isComplete)
    }

    func testInactiveAccessSendsTerminalRecoveryDelegate() async {
        let store = makeStore(
            result: .success(syncResult(access: response(hasAccess: false, status: "revoked"), outcome: .notAttempted)),
            state: signedInState(),
        )
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertEqual(store.state.status, .revoked)
    }

    func testDeviceBindingFailureSendsTerminalRecoveryDelegate() async {
        let store = makeStore(
            result: .success(syncResult(access: response(), outcome: .deviceLimitReached)),
            state: signedInState(),
        )
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertEqual(store.state.deviceBindingFailure, .seatCapacityExceeded)
    }

    private func restoreSnapshot(_ snapshot: AccessStatusSnapshot?, validUntil: Date?) async -> AccountAccessFeature
        .State
    {
        var state = signedInState()
        state.syncGeneration = 1
        let store = makeStore(result: .success(syncResult()), state: state)
        await store.send(._cachedSnapshotRestored(
            generation: 1,
            binding: nil,
            snapshot: snapshot,
            validUntil: validUntil,
        ))
        if snapshot != nil, validUntil != nil {
            await store.receive(\.delegate)
        } else {
            await store.receive(\.delegate.recoveryRequired)
        }
        return store.state
    }

    func testCachedSnapshotRestoredAfterThreeFailures() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
            sessionExpiresAt: referenceDate.addingTimeInterval(3600),
            deviceBindingVerifiedAt: referenceDate,
            ownershipStatus: "owned",
            updateStatus: "active",
            updatesThrough: eligibleUpdatesThrough,
        )
        let state = await restoreSnapshot(snapshot, validUntil: referenceDate.addingTimeInterval(60))
        XCTAssertEqual(state.snapshot, snapshot)
        XCTAssertTrue(state.isComplete)
    }

    func testConservativeFallbackAfterThreeFailuresNoCache() async {
        let state = await restoreSnapshot(nil, validUntil: nil)
        XCTAssertEqual(state.status, .networkFailure)
        XCTAssertTrue(state.canRetry)
    }

    func testRetryableNetworkFailureStaysErrorNotNone() async {
        let store = makeStore(result: .failure(.capabilityMiss), state: signedInState())
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertNil(store.state.status)
        XCTAssertEqual(store.state.accountAccessStepState, .error)
    }

    func testTrialActivePreservesTrialExpiresAtDetail() async {
        let end = referenceDate.addingTimeInterval(7200)
        let store = makeStore(
            result: .success(syncResult(access: response(productKey: "trial", currentPeriodEnd: end))),
            state: signedInState(),
        )
        await sync(store)
        await store.receive(\.delegate.unlocked)
        XCTAssertEqual(store.state.status, .trialActive)
        XCTAssertEqual(store.state.trialExpiresAt, end)
    }

    func testExpiredSnapshotRejectedOnRestore() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
            sessionExpiresAt: referenceDate.addingTimeInterval(-1),
            deviceBindingVerifiedAt: referenceDate,
        )
        let state = await restoreSnapshot(snapshot, validUntil: referenceDate.addingTimeInterval(-1))
        XCTAssertEqual(state.status, .networkFailure)
        XCTAssertFalse(state.isComplete)
    }

    func testCachedSnapshotRestoredWithSessionExpiresAtRestoresSessionAxis() async {
        let expiry = referenceDate.addingTimeInterval(3600)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
            sessionExpiresAt: expiry,
            deviceBindingVerifiedAt: referenceDate,
            ownershipStatus: "owned",
            updateStatus: "active",
            updatesThrough: eligibleUpdatesThrough,
        )
        let state = await restoreSnapshot(snapshot, validUntil: referenceDate.addingTimeInterval(60))
        XCTAssertTrue(state.hasAccountSession)
        XCTAssertEqual(state.sessionExpiresAt, expiry)
    }

    func testCachedSnapshotRestoredWithoutSessionDoesNotFakeSession() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
            deviceBindingVerifiedAt: referenceDate,
        )
        let state = await restoreSnapshot(snapshot, validUntil: referenceDate.addingTimeInterval(60))
        XCTAssertFalse(state.isComplete)
        XCTAssertEqual(state.status, .coreLicenseActive)
    }

    func testFetchRetryCountResetOnSuccess() async {
        var state = signedInState()
        state.fetchRetryCount = 3
        let store = makeStore(result: .success(syncResult(access: response())), state: state)
        await sync(store)
        await store.receive(\.delegate.unlocked)
        XCTAssertEqual(store.state.fetchRetryCount, 0)
    }

    func testAccessStatusSuccessPersistsSessionExpiryInSnapshot() async {
        let expiry = referenceDate.addingTimeInterval(3600)
        nonisolated(unsafe) var saved: AccessStatusSnapshot?
        let client = AccessStatusSnapshotClient(
            activate: { _, _ in 0 },
            load: { _, _ in nil },
            save: { snapshot, _, _, _ in saved = snapshot },
            remove: { _, _, _ in },
        )
        let store = makeStore(
            result: .success(syncResult(access: response())),
            state: signedInState(expiry: expiry),
            snapshotClient: client,
        )
        await sync(store)
        await store.receive(\.delegate.unlocked)
        XCTAssertEqual(saved?.sessionExpiresAt, expiry)
    }

    func testFetchAccessStatusRetryScheduledOnNetworkFailure() async {
        let store = makeStore(result: .failure(.capabilityMiss), state: signedInState())
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertNil(store.state.status)
    }

    func testFetchAccessStatusPermanentErrorNoRetry() async {
        let store = makeStore(result: .failure(.capabilityMiss), state: signedInState())
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertEqual(store.state.fetchRetryCount, 0)
        XCTAssertNil(store.state.status)
    }

    func testHydrateLaunchSnapshotWithTrialExpiredSessionMapsToBlockedAndSignedIn() async {
        let expiry = referenceDate.addingTimeInterval(3600)
        let store = makeStore(result: .success(syncResult()), state: .init())
        await store.send(.hydrateLaunchSnapshot(AccessStatusSnapshot(
            status: .trialExpired,
            fetchedAt: referenceDate,
            sessionExpiresAt: expiry,
        )))
        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertEqual(store.state.accountAccessStepState, .blocked)
        await store.skipInFlightEffects()
    }

    func testHydrateLaunchSnapshotWithNetworkFailureSessionMapsToErrorAndSignedIn() async {
        let expiry = referenceDate.addingTimeInterval(3600)
        let store = makeStore(result: .success(syncResult()), state: .init())
        await store.send(.hydrateLaunchSnapshot(AccessStatusSnapshot(
            status: .networkFailure,
            fetchedAt: referenceDate,
            sessionExpiresAt: expiry,
        )))
        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertEqual(store.state.accountAccessStepState, .error)
        await store.skipInFlightEffects()
    }

    func testIntegrationOnAppearToUnlockedFullPipeline() async {
        await testOnAppearSessionRestoredTriggersFetch()
    }

    func testIntegrationFetchFailureRetryChainToCachedFallback() async {
        await testConservativeFallbackAfterThreeFailuresNoCache()
    }

    func testFreshVerifiedCacheRefreshesSessionExpiryBeforeUnlock() async {
        let expiry = referenceDate.addingTimeInterval(7200)
        var state = signedInState(expiry: expiry)
        state.syncGeneration = 1
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
            sessionExpiresAt: referenceDate.addingTimeInterval(3600),
            deviceBindingVerifiedAt: referenceDate,
            ownershipStatus: "owned",
            updateStatus: "active",
            updatesThrough: eligibleUpdatesThrough,
        )
        let store = makeStore(result: .success(syncResult()), state: state)
        await store.send(._cachedSnapshotRestored(
            generation: 1,
            binding: nil,
            snapshot: snapshot,
            validUntil: referenceDate.addingTimeInterval(60),
        ))
        await store.receive(\.delegate.unlocked)
        XCTAssertEqual(store.state.sessionExpiresAt, expiry)
        XCTAssertEqual(store.state.snapshot?.sessionExpiresAt, snapshot.sessionExpiresAt)
    }

    func testDeviceBindingFailureDoesNotOverwriteVerifiedCache() async {
        nonisolated(unsafe) var saves = 0
        let client = AccessStatusSnapshotClient(
            activate: { _, _ in 0 },
            load: { _, _ in nil },
            save: { _, _, _, _ in saves += 1 },
            remove: { _, _, _ in },
        )
        let store = makeStore(
            result: .success(syncResult(access: response(), outcome: .deviceLimitReached)),
            state: signedInState(),
            snapshotClient: client,
        )
        await sync(store)
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertEqual(saves, 0)
    }

    func testIntegrationRetryTappedToUnlockedFullPipeline() async {
        await testRetryTappedIncrementsGenerationAndTriggersFetch()
    }
}

import AppKit
import ComposableArchitecture
import Foundation
import VoyagerShared

@Reducer
public struct AccountAccessFeature {
    public typealias State = AccountAccessState
    public typealias Action = AccountAccessAction

    @Dependency(\.accountSessionClient)
    var sessionClient

    @Dependency(\.authNetworkClient)
    var authNetwork

    @Dependency(\.accessStatusSnapshotClient)
    var snapshotClient

    @Dependency(\.signInHandoffClient)
    var signInHandoffClient

    @Dependency(\.date)
    var date

    @Dependency(\.continuousClock)
    var continuousClock

    @Dependency(\.checkoutURLClient)
    var checkoutURLClient

    @Dependency(\.notificationCenterClient)
    var notificationCenterClient

    @Dependency(\.appHandoffTarget)
    var appHandoffTarget

    @Dependency(\.deviceIdentityClient)
    var deviceIdentityClient

    enum CancelID: Hashable {
        case signInHandoff(AccountAccessHandoffScope)
        case handoffClaim(AccountAccessHandoffScope)
        case handoffCallbackTimeout(AccountAccessHandoffScope)
        case handoffExchange(AccountAccessHandoffScope)
        static let appDidBecomeActiveObserver = "accountAccessAppDidBecomeActiveObserver"
        static let sessionRevalidation = "accountAccessSessionRevalidation"
        static let sessionSync = "accountAccessSessionSync"
        static let refreshDeadline = "accountAccessRefreshDeadline"
    }

    static let handoffCallbackTimeout: Duration = .seconds(300)
    static let sessionSyncFreshness: TimeInterval = 5 * 60
    static let sessionSyncRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return handleOnAppear(&state)

            case .retryTapped:
                return .send(.sessionSyncRequested(intent: .validate, reason: .retry))

            case let .loginTapped(context: context, scope: scope):
                return handleLoginTapped(&state, context: context, scope: scope)

            case .cancelSignIn:
                return handleCancelSignIn(&state)

            case let .signInHandoffCompleted(result, transaction: transaction, generation: generation):
                return handleSignInHandoffCompleted(
                    &state,
                    result: result,
                    transaction: transaction,
                    generation: generation,
                )

            case let .loginCallbackReceived(url):
                return handleLoginCallbackReceived(&state, url: url)

            case let ._handoffCallbackTimedOut(pendingState):
                return handleHandoffCallbackTimedOut(&state, pendingState: pendingState)

            case let ._handoffClaimCompleted(completion):
                return handleHandoffClaimCompleted(&state, completion: completion)

            case let ._handoffCommitAuthorized(pendingState, generation, session):
                return handleHandoffCommitAuthorized(
                    &state,
                    pendingState: pendingState,
                    generation: generation,
                    session: session,
                )

            case let ._handoffExchangeCompleted(pendingState, generation, result):
                return handleHandoffExchangeCompleted(
                    &state,
                    pendingState: pendingState,
                    generation: generation,
                    result: result,
                )

            case let ._handoffPersistenceRollbackFailed(generation):
                guard state.handoffGeneration == generation else { return .none }
                state.isSignInInProgress = false
                state.didSignInFail = true
                state.hasAccountSession = false
                state.errorMessage = "Saved sign-in data could not be cleared. Quit Voyager and try again."
                return .none

            case let ._onAppearSessionRestored(restoration):
                return handleOnAppearSessionRestored(&state, restoration: restoration)

            case let ._loginSessionRestored(restoration):
                return handleLoginSessionRestored(&state, restoration: restoration)

            case let .sessionSyncRequested(intent, reason):
                return requestSessionSync(&state, intent: intent, reason: reason)

            case let ._sessionSyncCompleted(generation, result):
                return handleSessionSyncCompleted(&state, generation: generation, result: result)

            case .accessStatusResponse:
                return .none

            case .deviceBindingResponse:
                return .none

            case .refreshAccessTapped:
                return handleRefreshAccessTapped(&state)

            case .appDidBecomeActive:
                guard state.hasAccountSession, !state.isSessionExpired else {
                    return .none
                }
                state.revalidationGeneration += 1
                return .merge(
                    scheduleRefreshDeadline(&state),
                    .send(
                        .revalidatePersistedSession(
                            generation: state.revalidationGeneration,
                        ),
                    ),
                )

            case let .revalidatePersistedSession(generation: generation):
                return revalidatePersistedSession(state: state, generation: generation)

            case let ._persistedSessionRevalidated(generation: generation, result: result):
                return handlePersistedSessionRevalidated(
                    &state,
                    generation: generation,
                    result: result,
                )

            case .openCheckoutTapped:
                return handleOpenCheckout(&state)

            case .openPricingTapped:
                return handleOpenPricing(&state)

            case .openAccountTapped:
                return handleOpenAccount(&state)

            case .openAccessHelpTapped:
                return handleOpenAccessHelp(&state)

            case .openBetaCodeHelpTapped:
                return handleOpenBetaCodeHelp(&state)

            case let ._webURLResult(result):
                return handleWebURLResult(&state, result: result)

            case let ._refreshDeadlineReached(generation):
                return handleRefreshDeadlineReached(&state, generation: generation)

            case ._sessionExpiredDetected:
                return handleSessionExpiredDetected(&state)

            case let ._cachedSnapshotRestored(generation: generation, snapshot: snapshot):
                return handleCachedSnapshotRestored(
                    &state,
                    generation: generation,
                    snapshot: snapshot,
                )

            case let .hydrateLaunchSnapshot(snapshot):
                return handleHydrateLaunchSnapshot(&state, snapshot: snapshot)

            case let .hydrateAccessFailure(error: error, sessionExpiresAt: sessionExpiresAt):
                state.hydrateAccessFailureState(error: error, sessionExpiresAt: sessionExpiresAt)
                return .none

            case ._fetchRetryScheduled:
                return .send(.sessionSyncRequested(intent: .validate, reason: .retry))

            case .signOut:
                return handleSignOut(&state)

            case .appWillTerminate:
                return handleAppWillTerminate(&state)

            case .delegate:
                return .none
            }
        }
    }

    private func handleOnAppear(_ state: inout State) -> Effect<Action> {
        guard !state.didBootstrap else { return .none }
        state.didBootstrap = true
        return .merge(
            .run { [sessionClient] send in
                let restoration: AccountSessionRestoration = if let session = try? await sessionClient.read(),
                                                                let expiresAt = session.expiresAt
                {
                    .available(sessionExpiresAt: expiresAt)
                } else {
                    .missing
                }
                await send(._onAppearSessionRestored(restoration))
            },
            observeAppDidBecomeActive(),
        )
    }

    private func handleOnAppearSessionRestored(
        _ state: inout State,
        restoration: AccountSessionRestoration,
    ) -> Effect<Action> {
        let scope = handoffScope(state)
        let expectedState = ownedHandoffState(state)
        let sessionExpiresAt: Date?
        switch restoration {
        case let .available(expiresAt):
            state.hasAccountSession = true
            sessionExpiresAt = expiresAt
        case .missing:
            state.hasAccountSession = false
            sessionExpiresAt = nil
        }
        state.handoffPendingState = nil
        state.handoffExchangeState = nil

        guard state.hasAccountSession else {
            clearStaleActiveAccessFacts(&state)
            resetSessionRetryBudget(&state)
            state.fetchGeneration += 1
            invalidateSessionSync(&state)
            state.lastCompleteSyncAt = nil
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            return .merge(
                .cancel(id: CancelID.sessionSync),
                cancelRefreshDeadline(&state),
                .cancel(id: CancelID.handoffCallbackTimeout(scope)),
                cancelHandoffClaimAndExchange(scope: scope),
                clearStoredHandoff(expectedState: expectedState, owner: scope),
                .send(.delegate(.recoveryRequired(.sessionRequired))),
            )
        }

        state.sessionExpiresAt = sessionExpiresAt
        state.isSessionExpired = false
        resetSessionRetryBudget(&state)
        state.fetchGeneration += 1
        invalidateSessionSync(&state)

        state.ttlTimerActive = true
        let refreshDeadlineEffect = scheduleRefreshDeadline(&state)

        return .merge(
            .cancel(id: CancelID.handoffCallbackTimeout(scope)),
            cancelHandoffClaimAndExchange(scope: scope),
            clearStoredHandoff(expectedState: expectedState, owner: scope),
            .cancel(id: CancelID.sessionSync),
            .send(.sessionSyncRequested(intent: .validate, reason: .foreground)),
            refreshDeadlineEffect,
        )
    }

    private func handlePersistedSessionRevalidated(
        _ state: inout State,
        generation: Int,
        result: Action.PersistedSessionRevalidationResult,
    ) -> Effect<Action> {
        guard state.hasAccountSession, !state.isSessionExpired, generation == state.revalidationGeneration else {
            return .none
        }
        switch result {
        case let .valid(sessionExpiresAt):
            state.sessionExpiresAt = sessionExpiresAt
            return .merge(
                scheduleRefreshDeadline(&state),
                .send(.sessionSyncRequested(intent: .validate, reason: .foreground)),
            )

        case .missing:
            return .send(._sessionExpiredDetected)

        case .storageUnavailable:
            return .none
        }
    }

    private func handleLoginCallbackReceived(_ state: inout State, url: URL) -> Effect<Action> {
        if let callback = AppHandoffCallback(url: url, expectedScheme: appHandoffTarget.callbackScheme) {
            return handleRealHandoffCallback(&state, callback: callback)
        }

        guard isValidAuthCallback(url, expectedScheme: appHandoffTarget.callbackScheme), !hasQueryItems(url) else {
            return .none
        }

        return .run { [sessionClient] send in
            let restoration: AccountSessionRestoration = if let session = try? await sessionClient.read(),
                                                            let expiresAt = session.expiresAt
            {
                .available(sessionExpiresAt: expiresAt)
            } else {
                .missing
            }
            await send(._loginSessionRestored(restoration))
        }
    }

    private func hasQueryItems(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return !(components.queryItems?.isEmpty ?? true)
    }

    private func handleLoginSessionRestored(
        _ state: inout State,
        restoration: AccountSessionRestoration,
    ) -> Effect<Action> {
        let scope = handoffScope(state)
        let expectedState = ownedHandoffState(state)
        state.isSignInInProgress = false
        state.handoffPendingState = nil
        state.handoffExchangeState = nil
        state.handoffTransaction = nil

        guard case let .available(sessionExpiresAt) = restoration else {
            return .merge(
                .cancel(id: CancelID.handoffCallbackTimeout(scope)),
                cancelHandoffClaimAndExchange(scope: scope),
                clearStoredHandoff(expectedState: expectedState, owner: scope),
                .send(._sessionExpiredDetected),
            )
        }

        state.didSignInFail = false
        state.hasAccountSession = true
        state.isSessionExpired = false
        state.sessionExpiresAt = sessionExpiresAt
        state.ttlTimerActive = true
        resetSessionRetryBudget(&state)
        state.fetchGeneration += 1
        invalidateSessionSync(&state)
        state.lastCompleteSyncAt = nil
        return .merge(
            .cancel(id: CancelID.handoffCallbackTimeout(scope)),
            cancelHandoffClaimAndExchange(scope: scope),
            clearStoredHandoff(expectedState: expectedState, owner: scope),
            .cancel(id: CancelID.sessionSync),
            .send(.sessionSyncRequested(intent: .validate, reason: .login)),
            scheduleRefreshDeadline(&state),
        )
    }

    private func isValidAuthCallback(_ url: URL, expectedScheme: String) -> Bool {
        guard url.scheme == expectedScheme else { return false }
        guard url.host == "auth" else { return false }
        guard url.path == "/callback" else { return false }
        return true
    }
}

extension AccountAccessFeature {
    private func revalidatePersistedSession(
        state: State,
        generation: Int,
    ) -> Effect<Action> {
        guard state.hasAccountSession, !state.isSessionExpired, generation == state.revalidationGeneration else {
            return .none
        }
        return .run { [sessionClient] send in
            let result: Action.PersistedSessionRevalidationResult
            do {
                if let session = try await sessionClient.read(),
                   let expiresAt = session.expiresAt
                {
                    result = .valid(sessionExpiresAt: expiresAt)
                } else {
                    result = .missing
                }
            } catch {
                result = .storageUnavailable
            }
            await send(
                ._persistedSessionRevalidated(
                    generation: generation,
                    result: result,
                ),
            )
        }
        .cancellable(id: CancelID.sessionRevalidation, cancelInFlight: true)
    }

    /// launch snapshot은 이미 완료된 sync 결과이므로 bootstrap에서 원격 재조회를 시작하지 않는다.
    private func handleHydrateLaunchSnapshot(
        _ state: inout State,
        snapshot: AccessStatusSnapshot,
    ) -> Effect<Action> {
        state.hydrateLaunchSnapshotState(snapshot)

        if snapshot.hasSession {
            state.ttlTimerActive = true
            return .merge(
                observeAppDidBecomeActive(),
                .cancel(id: CancelID.sessionSync),
                scheduleRefreshDeadline(&state),
            )
        } else {
            state.ttlTimerActive = false
            return .merge(
                .cancel(id: CancelID.sessionSync),
                cancelRefreshDeadline(&state),
                .cancel(id: CancelID.handoffCallbackTimeout(handoffScope(state))),
                .cancel(id: CancelID.appDidBecomeActiveObserver),
            )
        }
    }

    /// 앱이 foreground로 돌아올 때 access_status를 자동 갱신한다.
    private func observeAppDidBecomeActive() -> Effect<Action> {
        .run { [notificationCenterClient] send in
            for await _ in notificationCenterClient.notifications(
                NSApplication.didBecomeActiveNotification,
                nil,
            ) {
                await send(.appDidBecomeActive)
            }
        }
        .cancellable(id: CancelID.appDidBecomeActiveObserver, cancelInFlight: true)
    }

    func scheduleRefreshDeadline(_ state: inout State) -> Effect<Action> {
        guard let expiresAt = state.sessionExpiresAt else {
            return cancelRefreshDeadline(&state)
        }

        state.refreshDeadlineGeneration += 1
        let generation = state.refreshDeadlineGeneration
        let delay = expiresAt.addingTimeInterval(-360).timeIntervalSince(date())
        guard delay > 0 else {
            return .merge(
                .cancel(id: CancelID.refreshDeadline),
                .send(.sessionSyncRequested(intent: .refresh, reason: .refreshDeadline)),
            )
        }

        return .run { [continuousClock] send in
            do {
                try await continuousClock.sleep(for: .seconds(delay))
                await send(._refreshDeadlineReached(generation: generation))
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .cancellable(id: CancelID.refreshDeadline, cancelInFlight: true)
    }

    private func cancelRefreshDeadline(_ state: inout State) -> Effect<Action> {
        state.refreshDeadlineGeneration += 1
        return .cancel(id: CancelID.refreshDeadline)
    }

    private func handleRefreshDeadlineReached(
        _ state: inout State,
        generation: UInt64,
    ) -> Effect<Action> {
        guard state.hasAccountSession,
              !state.isSessionExpired,
              state.ttlTimerActive,
              generation == state.refreshDeadlineGeneration
        else {
            return .none
        }
        return .send(.sessionSyncRequested(intent: .refresh, reason: .refreshDeadline))
    }

    /// 사용자 로그아웃 처리.
    private func handleSignOut(_ state: inout State) -> Effect<Action> {
        let scope = handoffScope(state)
        let expectedState = ownedHandoffState(state)
        guard state.hasAccountSession else {
            guard state.isSignInInProgress || state.handoffPendingState != nil else {
                return .none
            }
            state.isSignInInProgress = false
            state.didSignInFail = false
            state.handoffPendingState = nil
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
            return .merge(
                .cancel(id: CancelID.signInHandoff(scope)),
                .cancel(id: CancelID.handoffCallbackTimeout(scope)),
                cancelHandoffClaimAndExchange(scope: scope),
                clearStoredHandoff(expectedState: expectedState, owner: scope),
            )
        }
        state.revalidationGeneration += 1
        state.hasAccountSession = false
        state.didSignInFail = false
        state.isSessionExpired = true
        clearStaleActiveAccessFacts(&state)
        state.ttlTimerActive = false
        state.sessionExpiresAt = nil
        state.fetchGeneration += 1
        invalidateSessionSync(&state)
        state.lastCompleteSyncAt = nil
        state.handoffTransaction = nil
        return .merge(
            .run { [sessionClient, snapshotClient] send in
                try? await sessionClient.delete(.explicitSignOut)
                await snapshotClient.remove()
                await send(.delegate(.signedOut))
            },
            cancelRefreshDeadline(&state),
            .cancel(id: CancelID.sessionSync),
            .cancel(id: CancelID.sessionRevalidation),
            .cancel(id: CancelID.handoffCallbackTimeout(scope)),
            cancelHandoffClaimAndExchange(scope: scope),
            clearStoredHandoff(expectedState: expectedState, owner: scope),
        )
    }

    /// 세션 만료 처리.
    private func handleSessionExpiredDetected(_ state: inout State) -> Effect<Action> {
        guard !state.isSessionExpired else { return .none }

        let expectedState = ownedHandoffState(state)
        state.revalidationGeneration += 1
        state.hasAccountSession = false
        state.didSignInFail = true
        state.isSessionExpired = true
        // VOY-397: 세션 만료 시 stale active facts 제거.
        clearStaleActiveAccessFacts(&state)
        resetSessionRetryBudget(&state)
        // VOY-397: 세션 만료 시 in-flight access_status 응답 재주입 방지.
        state.fetchGeneration += 1
        invalidateSessionSync(&state)
        state.lastCompleteSyncAt = nil
        state.ttlTimerActive = false
        state.sessionExpiresAt = nil
        state.consecutiveRefreshFailures = 0
        state.handoffPendingState = nil
        state.handoffExchangeState = nil

        return .merge(
            .run { [sessionClient, snapshotClient] _ in
                try? await sessionClient.delete(.sessionExpired)
                await snapshotClient.remove()
            },
            .cancel(id: CancelID.sessionSync),
            cancelRefreshDeadline(&state),
            .cancel(id: CancelID.sessionRevalidation),
            .cancel(id: CancelID.handoffCallbackTimeout(handoffScope(state))),
            cancelHandoffClaimAndExchange(scope: handoffScope(state)),
            clearStoredHandoff(expectedState: expectedState, owner: handoffScope(state)),
            .send(.delegate(.recoveryRequired(.sessionRequired))),
        )
    }

    private func handleAppWillTerminate(_ state: inout State) -> Effect<Action> {
        let scope = handoffScope(state)
        let expectedState = ownedHandoffState(state)
        state.fetchGeneration += 1
        invalidateSessionSync(&state)
        state.revalidationGeneration += 1
        state.isSubmitting = false
        state.isSignInInProgress = false
        state.handoffGeneration &+= 1
        state.handoffPendingState = nil
        state.handoffExchangeState = nil
        state.handoffTransaction = nil
        state.ttlTimerActive = false
        state.fetchRetryCount = 0
        state.deviceBindingFailure = nil
        state.deviceBindingRetryCount = 0
        state.errorMessage = nil

        return .merge(
            .cancel(id: CancelID.sessionSync),
            .cancel(id: CancelID.sessionRevalidation),
            cancelRefreshDeadline(&state),
            .cancel(id: CancelID.appDidBecomeActiveObserver),
            .cancel(id: CancelID.signInHandoff(scope)),
            .cancel(id: CancelID.handoffCallbackTimeout(scope)),
            cancelHandoffClaimAndExchange(scope: scope),
            clearStoredHandoff(expectedState: expectedState, owner: scope),
        )
    }

    private func clearStaleActiveAccessFacts(_ state: inout State) {
        state.status = nil
        state.snapshot = nil
        state.trialExpiresAt = nil
        state.deviceBindingFailure = nil
        state.deviceBindingRetryCount = 0
        state.isSubmitting = false
        state.isComplete = false
        state.errorMessage = nil
    }

    private func clearStaleSignInState(_ state: inout State) {
        state.isSignInInProgress = false
        state.didSignInFail = false
        state.handoffPendingState = nil
        state.handoffExchangeState = nil
        state.deviceBindingFailure = nil
        state.deviceBindingRetryCount = 0
        state.errorMessage = nil
    }

    func resetSessionRetryBudget(_ state: inout State) {
        state.fetchRetryCount = 0
        state.deviceBindingRetryCount = 0
    }

    private func handleOpenCheckout(_: inout State) -> Effect<Action> {
        openWebURL(makeURL: checkoutURLClient.checkoutURL)
    }

    private func handleOpenPricing(_: inout State) -> Effect<Action> {
        openWebURL(makeURL: checkoutURLClient.pricingURL)
    }

    private func handleOpenAccount(_: inout State) -> Effect<Action> {
        openWebURL(makeURL: checkoutURLClient.accountURL)
    }

    private func handleOpenAccessHelp(_: inout State) -> Effect<Action> {
        openWebURL(makeURL: checkoutURLClient.supportURL)
    }

    private func handleOpenBetaCodeHelp(_: inout State) -> Effect<Action> {
        openWebURL(makeURL: checkoutURLClient.supportURL)
    }

    private func openWebURL(makeURL: @escaping @Sendable () throws -> URL) -> Effect<Action> {
        .run { [checkoutURLClient] send in
            do {
                let url = try makeURL()
                checkoutURLClient.openURL(url)
                await send(._webURLResult(.success(())))
            } catch let error as AccessError {
                await send(._webURLResult(.failure(error)))
            } catch {
                await send(._webURLResult(.failure(.notConfigured)))
            }
        }
    }

    private func handleWebURLResult(
        _ state: inout State,
        result: Result<Void, AccessError>,
    ) -> Effect<Action> {
        switch result {
        case .success:
            return .none

        case let .failure(error):
            state.status = nil
            state.isComplete = false
            state.errorMessage = errorMessage(for: error)
            return .none
        }
    }
}

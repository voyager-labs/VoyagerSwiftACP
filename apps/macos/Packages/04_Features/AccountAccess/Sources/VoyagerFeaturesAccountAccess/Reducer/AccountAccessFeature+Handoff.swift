import ComposableArchitecture
import Foundation

extension AccountAccessFeature {
    func cancelHandoffClaimAndExchange(scope: AccountAccessHandoffScope) -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.handoffExchange(scope)),
            .cancel(id: CancelID.handoffClaim(scope)),
        )
    }

    func startHandoffCallbackTimeout(
        pendingState: String,
        scope: AccountAccessHandoffScope,
    ) -> Effect<Action> {
        .run { [continuousClock] send in
            do {
                try await continuousClock.sleep(for: Self.handoffCallbackTimeout)
                await send(._handoffCallbackTimedOut(state: pendingState))
            } catch {
                return
            }
        }
        .cancellable(id: CancelID.handoffCallbackTimeout(scope), cancelInFlight: true)
    }

    func handleHandoffCallbackTimedOut(
        _ state: inout State,
        pendingState: String,
    ) -> Effect<Action> {
        guard state.handoffPendingState == pendingState else {
            return .none
        }

        state.isSignInInProgress = false
        state.didSignInFail = true
        state.handoffPendingState = nil
        state.handoffExchangeState = nil
        return .merge(
            .cancel(
                id: CancelID.handoffCallbackTimeout(state.handoffScope),
            ),
            cancelHandoffClaimAndExchange(scope: state.handoffScope),
            clearStoredHandoff(expectedState: pendingState, owner: state.handoffScope),
        )
    }

    func handleRealHandoffCallback(
        _ state: inout State,
        callback: AppHandoffCallback,
    ) -> Effect<Action> {
        guard state.isSignInInProgress, callback.context == state.handoffContext else { return .none }
        guard state.handoffExchangeState == nil else { return .none }
        guard state.handoffPendingState == nil || state.handoffPendingState == callback.state else { return .none }

        return claimHandoff(callback: callback, scope: state.handoffScope)
    }

    func handleHandoffClaimCompleted(
        _ state: inout State,
        ticket: String,
        pendingState: String,
        context: AppHandoffContext,
        claimed: Bool,
    ) -> Effect<Action> {
        guard state.isSignInInProgress,
              state.handoffExchangeState == nil,
              context == state.handoffContext,
              state.handoffPendingState == nil || state.handoffPendingState == pendingState
        else { return .none }

        guard claimed else { return .none }

        state.handoffPendingState = nil
        state.handoffExchangeState = pendingState
        return .merge(
            .cancel(id: CancelID.handoffCallbackTimeout(state.handoffScope)),
            performHandoffExchange(
                ticket: ticket,
                state: pendingState,
                context: context,
                scope: state.handoffScope,
            ),
        )
    }

    func handleHandoffExchangeCompleted(
        _ state: inout State,
        pendingState: String,
        result: Result<Date?, AppHandoffExchangeError>,
    ) -> Effect<Action> {
        guard state.handoffExchangeState == pendingState else { return .none }
        state.handoffExchangeState = nil

        switch result {
        case let .success(sessionExpiresAt):
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.isSessionExpired = false
            resetSessionRetryBudget(&state)
            state.sessionExpiresAt = sessionExpiresAt
            state.ttlTimerActive = true
            state.fetchGeneration += 1
            invalidateSessionSync(&state)
            state.lastCompleteSyncAt = nil
            return .merge(
                .cancel(id: CancelID.handoffCallbackTimeout(state.handoffScope)),
                .cancel(id: CancelID.sessionSync),
                .send(.sessionSyncRequested(intent: .validate, reason: .login)),
                scheduleRefreshDeadline(&state),
            )

        case .failure:
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.hasAccountSession = false
            state.handoffPendingState = nil
            return .cancel(id: CancelID.handoffCallbackTimeout(state.handoffScope))
        }
    }

    func performHandoffExchange(
        ticket: String,
        state: String,
        context: AppHandoffContext,
        scope: AccountAccessHandoffScope,
    ) -> Effect<Action> {
        .run { [authNetwork, sessionClient] send in
            do {
                let session = try await authNetwork.exchangeHandoff(ticket, state, context)
                try Task.checkCancellation()
                try await sessionClient.persist(session)
                try Task.checkCancellation()
                guard let persistedSession = try await sessionClient.read() else {
                    throw AppHandoffExchangeError.decodingFailure
                }
                try Task.checkCancellation()
                await send(._handoffExchangeCompleted(
                    state: state,
                    result: .success(persistedSession.expiresAt),
                ))
            } catch is CancellationError {
                return
            } catch {
                let mappedError: AppHandoffExchangeError = if let exchangeError = error as? AppHandoffExchangeError {
                    exchangeError
                } else {
                    .networkFailure
                }
                await send(._handoffExchangeCompleted(state: state, result: .failure(mappedError)))
            }
        }
        .cancellable(id: CancelID.handoffExchange(scope), cancelInFlight: true)
    }

    func claimHandoff(
        callback: AppHandoffCallback,
        scope: AccountAccessHandoffScope,
    ) -> Effect<Action> {
        .run { send in
            let pending = await AppHandoffStateStore.shared.claim(
                expectedState: callback.state,
                context: callback.context,
                owner: scope,
            )
            guard !Task.isCancelled else { return }
            await send(._handoffClaimCompleted(
                ticket: callback.ticket,
                state: callback.state,
                context: callback.context,
                claimed: pending != nil,
            ))
        }
        .cancellable(id: CancelID.handoffClaim(scope), cancelInFlight: true)
    }

    func clearStoredHandoff(
        expectedState: String?,
        owner: AccountAccessHandoffScope,
    ) -> Effect<Action> {
        guard let expectedState else { return .none }
        return .run { _ in
            await AppHandoffStateStore.shared.clear(expectedState: expectedState, owner: owner)
        }
    }

    func ownedHandoffState(_ state: State) -> String? {
        state.handoffPendingState ?? state.handoffExchangeState
    }
}

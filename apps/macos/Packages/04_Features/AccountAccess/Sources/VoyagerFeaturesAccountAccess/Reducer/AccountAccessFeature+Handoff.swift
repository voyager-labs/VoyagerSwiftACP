import ComposableArchitecture
import Foundation

extension AccountAccessFeature {
    func handleLoginTapped(
        _ state: inout State,
        context: AppHandoffContext,
        scope: AccountAccessHandoffScope,
    ) -> Effect<Action> {
        guard state.canStartLogin else {
            return .none
        }

        let isReauthentication = state.canStartReauthentication
        if isReauthentication {
            state.isSubmitting = false
            invalidateSessionSync(&state)
            state.revalidationGeneration += 1
        }

        let transaction = AccountAccessHandoffTransaction(
            context: context,
            scope: scope,
            startedWithAccountSession: isReauthentication,
        )
        state.isSignInInProgress = true
        state.didSignInFail = false
        state.handoffGeneration &+= 1
        state.handoffTransaction = transaction
        let generation = state.handoffGeneration

        return .merge(
            isReauthentication ? .cancel(id: CancelID.sessionSync) : .none,
            isReauthentication ? .cancel(id: CancelID.sessionRevalidation) : .none,
            .cancel(id: CancelID.handoffCallbackTimeout(scope)),
            cancelHandoffClaimAndExchange(scope: scope),
            .run { [signInHandoffClient] send in
                let result = await signInHandoffClient.beginHandoff(context, scope)
                await send(.signInHandoffCompleted(result, transaction: transaction, generation: generation))
            }
            .cancellable(id: CancelID.signInHandoff(scope), cancelInFlight: true),
        )
    }

    func handleCancelSignIn(_ state: inout State) -> Effect<Action> {
        guard state.isSignInInProgress || state.handoffPendingState != nil || state.handoffExchangeState != nil else {
            return .none
        }

        let scope = handoffScope(state)
        let expectedState = ownedHandoffState(state)
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

    func handleSignInHandoffCompleted(
        _ state: inout State,
        result: SignInHandoffResult,
        transaction: AccountAccessHandoffTransaction,
        generation: UInt64,
    ) -> Effect<Action> {
        guard state.handoffGeneration == generation, state.handoffTransaction == transaction else {
            return .none
        }

        switch result {
        case let .success(callbackURL):
            return .send(.loginCallbackReceived(callbackURL))

        case let .awaitingCallback(handoffState):
            guard state.isSignInInProgress, state.handoffExchangeState == nil else {
                return .none
            }
            state.handoffPendingState = handoffState
            return startHandoffCallbackTimeout(pendingState: handoffState, scope: handoffScope(state))

        case .rejected:
            let scope = transaction.scope
            state.isSignInInProgress = false
            state.didSignInFail = false
            state.errorMessage = nil
            state.handoffPendingState = nil
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
            return .merge(
                .cancel(id: CancelID.handoffCallbackTimeout(scope)),
                cancelHandoffClaimAndExchange(scope: scope),
            )

        case .failure:
            return finishFailedSignInHandoff(
                &state,
                transaction: transaction,
                errorMessage: "Check your network connection and try again.",
            )

        case .cancelled:
            return finishFailedSignInHandoff(&state, transaction: transaction)
        }
    }

    private func finishFailedSignInHandoff(
        _ state: inout State,
        transaction: AccountAccessHandoffTransaction,
        errorMessage: String? = nil,
    ) -> Effect<Action> {
        let scope = transaction.scope
        let expectedState = ownedHandoffState(state)
        let preservesPriorSessionAuthority = preservesPriorSessionAuthority(state, transaction: transaction)
        state.isSignInInProgress = false
        state.didSignInFail = !preservesPriorSessionAuthority
        state.errorMessage = errorMessage ?? state.errorMessage
        state.handoffPendingState = nil
        state.handoffExchangeState = nil
        state.handoffTransaction = nil
        return .merge(
            .cancel(id: CancelID.handoffCallbackTimeout(scope)),
            cancelHandoffClaimAndExchange(scope: scope),
            clearStoredHandoff(expectedState: expectedState, owner: scope),
        )
    }

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
        guard let transaction = state.handoffTransaction,
              state.handoffPendingState == pendingState
        else {
            return .none
        }

        let scope = handoffScope(state)
        let preservesPriorSessionAuthority = preservesPriorSessionAuthority(state, transaction: transaction)
        state.isSignInInProgress = false
        state.didSignInFail = !preservesPriorSessionAuthority
        state.handoffPendingState = nil
        state.handoffExchangeState = nil
        state.handoffTransaction = nil
        return .merge(
            .cancel(
                id: CancelID.handoffCallbackTimeout(scope),
            ),
            cancelHandoffClaimAndExchange(scope: scope),
            clearStoredHandoff(expectedState: pendingState, owner: scope),
        )
    }

    func handleRealHandoffCallback(
        _ state: inout State,
        callback: AppHandoffCallback,
    ) -> Effect<Action> {
        guard let transaction = state.handoffTransaction,
              state.isSignInInProgress,
              callback.context == transaction.context
        else { return .none }
        guard state.handoffExchangeState == nil else { return .none }
        guard state.handoffPendingState == nil || state.handoffPendingState == callback.state else { return .none }

        return claimHandoff(
            callback: callback,
            scope: transaction.scope,
            generation: state.handoffGeneration,
        )
    }

    func handleHandoffClaimCompleted(
        _ state: inout State,
        completion: AccountAccessHandoffClaimCompletion,
    ) -> Effect<Action> {
        guard let transaction = state.handoffTransaction,
              state.handoffGeneration == completion.generation,
              state.isSignInInProgress,
              state.handoffExchangeState == nil,
              completion.context == transaction.context,
              completion.scope == transaction.scope,
              state.handoffPendingState == nil || state.handoffPendingState == completion.state
        else { return .none }

        guard completion.claimed else { return .none }

        state.handoffPendingState = nil
        state.handoffExchangeState = completion.state
        return .merge(
            .cancel(id: CancelID.handoffCallbackTimeout(completion.scope)),
            performHandoffExchange(
                ticket: completion.ticket,
                state: completion.state,
                context: transaction.context,
                scope: completion.scope,
                generation: completion.generation,
            ),
        )
    }

    func handleHandoffExchangeCompleted(
        _ state: inout State,
        pendingState: String,
        generation: UInt64,
        result: Result<AccountAccessHandoffCompletion, AppHandoffExchangeError>,
    ) -> Effect<Action> {
        guard let transaction = state.handoffTransaction,
              state.handoffGeneration == generation,
              state.handoffExchangeState == pendingState
        else { return .none }
        let scope = handoffScope(state)
        let preservesPriorSessionAuthority = preservesPriorSessionAuthority(state, transaction: transaction)
        state.handoffExchangeState = nil
        state.handoffTransaction = nil

        switch result {
        case let .success(completion):
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.isSessionExpired = false
            resetSessionRetryBudget(&state)
            state.sessionExpiresAt = completion.expiresAt
            state.sessionBindingID = completion.sessionBindingID
            state.ttlTimerActive = true
            state.fetchGeneration += 1
            invalidateSessionSync(&state)
            state.lastCompleteSyncAt = nil
            return .merge(
                .cancel(id: CancelID.handoffCallbackTimeout(scope)),
                .cancel(id: CancelID.sessionSync),
                .send(.sessionSyncRequested(intent: .validate, reason: .login)),
                scheduleRefreshDeadline(&state),
            )

        case .failure:
            state.isSignInInProgress = false
            state.didSignInFail = !preservesPriorSessionAuthority
            if !preservesPriorSessionAuthority {
                state.hasAccountSession = false
            }
            state.handoffPendingState = nil
            return .cancel(id: CancelID.handoffCallbackTimeout(scope))
        }
    }

    func handleHandoffCommitAuthorized(
        _ state: inout State,
        pendingState: String,
        generation: UInt64,
        session: AccountSession,
    ) -> Effect<Action> {
        guard state.handoffTransaction != nil,
              state.handoffGeneration == generation,
              state.handoffExchangeState == pendingState
        else {
            return .none
        }

        state.isSignInInProgress = false
        return .run { [sessionClient] send in
            let terminalCommit = Task {
                try await sessionClient.commitHandoffPersistence(session)
            }
            do {
                try await terminalCommit.value
                await send(._handoffExchangeCompleted(
                    state: pendingState,
                    generation: generation,
                    result: .success(AccountAccessHandoffCompletion(
                        expiresAt: session.expiresAt,
                        sessionBindingID: session.sessionBindingID,
                    )),
                ))
            } catch {
                do {
                    try await sessionClient.discardPersistedSession(session)
                } catch {
                    await send(._handoffPersistenceRollbackFailed(generation: generation))
                    return
                }
                await send(._handoffExchangeCompleted(
                    state: pendingState,
                    generation: generation,
                    result: .failure(.networkFailure),
                ))
            }
        }
    }

    func performHandoffExchange(
        ticket: String,
        state: String,
        context: AppHandoffContext,
        scope: AccountAccessHandoffScope,
        generation: UInt64,
    ) -> Effect<Action> {
        .run { [authNetwork, sessionClient] send in
            var sessionToRollback: AccountSession?
            do {
                let session = try await authNetwork.exchangeHandoff(ticket, state, context)
                try Task.checkCancellation()
                sessionToRollback = session
                let persistedSession = try await sessionClient.prepareHandoffPersistence(session)
                try Task.checkCancellation()
                let authorizationDelivery = Task { @MainActor in
                    await send(._handoffCommitAuthorized(
                        state: state,
                        generation: generation,
                        session: persistedSession,
                    ))
                }
                await authorizationDelivery.value
                sessionToRollback = nil
            } catch is CancellationError {
                if let sessionToRollback {
                    do {
                        try await sessionClient.discardPersistedSession(sessionToRollback)
                    } catch {
                        // 취소된 effect의 send는 TCA가 버리므로 새 task에서 실패를 전달한다.
                        await Task {
                            await send(._handoffPersistenceRollbackFailed(generation: generation))
                        }.value
                    }
                }
                return
            } catch {
                if let sessionToRollback {
                    do {
                        try await sessionClient.discardPersistedSession(sessionToRollback)
                    } catch {
                        await send(._handoffPersistenceRollbackFailed(generation: generation))
                        return
                    }
                }
                let mappedError: AppHandoffExchangeError = if let exchangeError = error as? AppHandoffExchangeError {
                    exchangeError
                } else {
                    .networkFailure
                }
                await send(._handoffExchangeCompleted(
                    state: state,
                    generation: generation,
                    result: .failure(mappedError),
                ))
            }
        }
        .cancellable(id: CancelID.handoffExchange(scope), cancelInFlight: true)
    }

    func claimHandoff(
        callback: AppHandoffCallback,
        scope: AccountAccessHandoffScope,
        generation: UInt64,
    ) -> Effect<Action> {
        .run { send in
            let pending = await AppHandoffStateStore.shared.claim(
                expectedState: callback.state,
                context: callback.context,
                owner: scope,
            )
            guard !Task.isCancelled else { return }
            await send(._handoffClaimCompleted(
                AccountAccessHandoffClaimCompletion(
                    ticket: callback.ticket,
                    state: callback.state,
                    context: callback.context,
                    scope: scope,
                    generation: generation,
                    claimed: pending != nil,
                ),
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

    func handoffScope(_ state: State) -> AccountAccessHandoffScope {
        state.handoffTransaction?.scope ?? .onboarding
    }

    private func preservesPriorSessionAuthority(
        _ state: State,
        transaction: AccountAccessHandoffTransaction,
    ) -> Bool {
        transaction.startedWithAccountSession && state.hasAccountSession && !state.isSessionExpired
    }
}

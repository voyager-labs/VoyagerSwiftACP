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

    enum CancelID {
        static let fetchStatus = "accountAccessFetchStatus"
        static let fetchRetry = "accountAccessFetchRetry"
        static let appDidBecomeActiveObserver = "accountAccessAppDidBecomeActiveObserver"
        static let signInHandoff = "accountAccessSignInHandoff"
        static let refreshToken = "accountAccessRefreshToken"
        static let ttlTimer = "accountAccessTtlTimer"
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return handleOnAppear(&state)

            case .retryTapped:
                state.fetchGeneration += 1
                return fetchAccessStatusEffect(generation: state.fetchGeneration)

            case .loginTapped:
                return handleLoginTapped(&state)

            case .cancelSignIn:
                return handleCancelSignIn(&state)

            case let .signInHandoffCompleted(result):
                return handleSignInHandoffCompleted(&state, result: result)

            case let .loginCallbackReceived(url):
                return handleLoginCallbackReceived(&state, url: url)

            case let ._handoffExchangeCompleted(result):
                return handleHandoffExchangeCompleted(&state, result: result)

            case let ._onAppearSessionRestored(session):
                return handleOnAppearSessionRestored(&state, session: session)

            case let ._loginSessionRestored(session):
                return handleLoginSessionRestored(&state, session: session)

            case let .accessStatusResponse(generation: gen, result: result):
                return handleAccessStatusResponse(&state, generation: gen, result: result)

            case let .deviceBindingResponse(generation: gen, snapshot: snapshot, result: result):
                return handleDeviceBindingResponse(&state, generation: gen, snapshot: snapshot, result: result)

            case .refreshAccessTapped:
                return handleRefreshAccessTapped(&state)

            case .appDidBecomeActive:
                guard state.hasAccountSession else {
                    return .none
                }
                state.fetchGeneration += 1
                return fetchAccessStatusEffect(generation: state.fetchGeneration)

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

            case ._ttlTimerTicked:
                return handleTtlTimerTicked(&state)

            case let ._refreshTokenResult(result):
                return handleRefreshTokenResult(&state, result: result)

            case ._sessionExpiredDetected:
                return handleSessionExpiredDetected(&state)

            case let ._cachedSnapshotRestored(snapshot):
                return handleCachedSnapshotRestored(&state, snapshot: snapshot)

            case let .hydrateLaunchSnapshot(snapshot):
                return handleHydrateLaunchSnapshot(&state, snapshot: snapshot)

            case let .hydrateAccessFailure(error: error, sessionExpiresAt: sessionExpiresAt):
                state.hydrateAccessFailureState(error: error, sessionExpiresAt: sessionExpiresAt)
                return .none

            case let ._fetchRetryScheduled(retryStep):
                return handleFetchRetryScheduled(&state, retryStep: retryStep)

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
                let session = try? await sessionClient.read()
                await send(._onAppearSessionRestored(session))
            },
            observeAppDidBecomeActive(),
        )
    }

    private func handleOnAppearSessionRestored(_ state: inout State, session: AccountSession?) -> Effect<Action> {
        state.hasAccountSession = session != nil

        guard let session else {
            clearStaleActiveAccessFacts(&state)
            resetSessionRetryBudget(&state)
            state.fetchGeneration += 1
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            return .merge(
                .cancel(id: CancelID.fetchStatus),
                .cancel(id: CancelID.ttlTimer),
                .send(.delegate(.recoveryRequired(.sessionRequired))),
            )
        }

        state.sessionExpiresAt = session.expiresAt
        state.isSessionExpired = false
        resetSessionRetryBudget(&state)
        state.fetchGeneration += 1

        state.ttlTimerActive = true
        let ttlEffect = startTtlTimer()

        return .merge(
            fetchAccessStatusEffect(generation: state.fetchGeneration),
            ttlEffect,
        )
    }

    func fetchAccessStatusEffect(generation: Int) -> Effect<Action> {
        .run { [authNetwork] send in
            let result: Result<AccessStatusResponse, AccessError>
            do {
                let response = try await authNetwork.fetchAccessStatus()
                result = .success(response)
            } catch let error as AccessError {
                result = .failure(error)
            } catch {
                result = .failure(.networkFailure)
            }
            await send(.accessStatusResponse(generation: generation, result: result))
        }
        .cancellable(id: CancelID.fetchStatus, cancelInFlight: true)
    }

    private func handleLoginTapped(_ state: inout State) -> Effect<Action> {
        guard state.canStartLogin else {
            return .none
        }

        state.isSignInInProgress = true
        state.didSignInFail = false
        let requestedContext = state.handoffContext

        return .run { [signInHandoffClient] send in
            let result = await signInHandoffClient.performHandoff(requestedContext)
            await send(.signInHandoffCompleted(result))
        }
        .cancellable(id: CancelID.signInHandoff, cancelInFlight: true)
    }

    private func handleCancelSignIn(_ state: inout State) -> Effect<Action> {
        guard state.isSignInInProgress || state.handoffPendingState != nil else {
            return .none
        }

        state.isSignInInProgress = false
        state.didSignInFail = false
        state.handoffPendingState = nil

        return .merge(
            .cancel(id: CancelID.signInHandoff),
            .run { _ in
                await AppHandoffStateStore.shared.clear()
            },
        )
    }

    private func handleSignInHandoffCompleted(
        _ state: inout State,
        result: SignInHandoffResult,
    ) -> Effect<Action> {
        switch result {
        case let .success(callbackURL):
            return .send(.loginCallbackReceived(callbackURL))

        case let .awaitingCallback(handoffState):
            state.handoffPendingState = handoffState
            return .none

        case .failure:
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.errorMessage = "Check your network connection and try again."
            return .none

        case .cancelled:
            state.isSignInInProgress = false
            state.didSignInFail = true
            return .none
        }
    }

    private func handleLoginCallbackReceived(_ state: inout State, url: URL) -> Effect<Action> {
        if let callback = AppHandoffCallback(url: url, expectedScheme: appHandoffTarget.callbackScheme) {
            return handleRealHandoffCallback(&state, callback: callback)
        }

        guard isValidAuthCallback(url, expectedScheme: appHandoffTarget.callbackScheme), !hasQueryItems(url) else {
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.handoffPendingState = nil
            return .none
        }

        return .run { [sessionClient] send in
            let session = try? await sessionClient.read()
            await send(._loginSessionRestored(session))
        }
    }

    private func handleRealHandoffCallback(
        _ state: inout State,
        callback: AppHandoffCallback,
    ) -> Effect<Action> {
        guard let pendingState = state.handoffPendingState else {
            state.isSignInInProgress = false
            state.didSignInFail = true
            return .none
        }

        guard callback.state == pendingState else {
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.handoffPendingState = nil
            return .none
        }

        guard callback.context == state.handoffContext else {
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.handoffPendingState = nil
            return .none
        }

        state.handoffPendingState = nil

        return performHandoffExchange(ticket: callback.ticket, state: callback.state, context: callback.context)
    }

    private func handleHandoffExchangeCompleted(
        _ state: inout State,
        result: Result<AccountSession, AppHandoffExchangeError>,
    ) -> Effect<Action> {
        switch result {
        case let .success(session):
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.isSessionExpired = false
            resetSessionRetryBudget(&state)
            state.sessionExpiresAt = session.expiresAt
            state.ttlTimerActive = true
            state.fetchGeneration += 1
            return .merge(
                fetchAccessStatusEffect(generation: state.fetchGeneration),
                startTtlTimer(),
            )

        case .failure:
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.hasAccountSession = false
            return .none
        }
    }

    private func hasQueryItems(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return !(components.queryItems?.isEmpty ?? true)
    }

    private func handleLoginSessionRestored(_ state: inout State, session: AccountSession?) -> Effect<Action> {
        state.isSignInInProgress = false

        guard let session else {
            return .send(._sessionExpiredDetected)
        }

        state.didSignInFail = false
        return handleOnAppearSessionRestored(&state, session: session)
    }

    private func isValidAuthCallback(_ url: URL, expectedScheme: String) -> Bool {
        guard url.scheme == expectedScheme else { return false }
        guard url.host == "auth" else { return false }
        guard url.path == "/callback" else { return false }
        return true
    }

    // MARK: - Cross-seam coordination helpers

    // Per design rule: sequence cross-seam operations via reducer-private helper.
    // Do NOT introduce a new DependencyKey for the coordinator.

    /// Handoff exchange → persist session (network + file I/O cross-seam).
    private func performHandoffExchange(
        ticket: String, state: String, context: AppHandoffContext,
    ) -> Effect<Action> {
        .run { [authNetwork, sessionClient] send in
            let session = try await authNetwork.exchangeHandoff(ticket, state, context)
            try await sessionClient.persist(session)
            guard let persistedSession = try await sessionClient.read() else {
                throw AppHandoffExchangeError.decodingFailure
            }
            await send(._handoffExchangeCompleted(.success(persistedSession)))
        } catch: { error, send in
            let mappedError: AppHandoffExchangeError = if let exchangeError = error as? AppHandoffExchangeError {
                exchangeError
            } else {
                .networkFailure
            }
            await send(._handoffExchangeCompleted(.failure(mappedError)))
        }
    }

    private func performTokenRefresh() -> Effect<Action> {
        .run { [authNetwork, sessionClient] send in
            do {
                let session = try await authNetwork.refreshToken()
                try Task.checkCancellation()
                try await sessionClient.persist(session)
                try Task.checkCancellation()
                await send(._refreshTokenResult(.success(session)))
            } catch is CancellationError {
                return
            } catch {
                let mappedError: AccessError = if let accessError = error as? AccessError {
                    accessError
                } else {
                    .networkFailure
                }
                await send(._refreshTokenResult(.failure(mappedError)))
            }
        }
        .cancellable(id: CancelID.refreshToken, cancelInFlight: true)
    }
}

private extension AccountAccessFeature {
    /// handleOnAppearSessionRestored/handleHandoffExchangeCompleted와 동일한 session ownership path를 따르되
    /// 네트워크 재조회(fetchAccessStatusEffect)는 수행하지 않는다 — launch snapshot이 곧 초기 상태.
    private func handleHydrateLaunchSnapshot(
        _ state: inout State,
        snapshot: AccessStatusSnapshot,
    ) -> Effect<Action> {
        state.hydrateLaunchSnapshotState(snapshot)

        if snapshot.hasSession {
            state.ttlTimerActive = true
            return .merge(
                observeAppDidBecomeActive(),
                .cancel(id: CancelID.fetchStatus),
                .cancel(id: CancelID.ttlTimer),
                startTtlTimer(),
            )
        } else {
            state.ttlTimerActive = false
            return .merge(
                .cancel(id: CancelID.fetchStatus),
                .cancel(id: CancelID.ttlTimer),
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

    /// 60초 간격으로 TTL을 확인하는 타이머를 시작한다.
    private func startTtlTimer() -> Effect<Action> {
        .run { send in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await send(._ttlTimerTicked)
            }
        }
        .cancellable(id: CancelID.ttlTimer, cancelInFlight: true)
    }

    /// TTL 타이머 틱: access token이 90% 이상 소모되었거나 5분 미만 남았으면 refresh를 트리거한다.
    private func handleTtlTimerTicked(_ state: inout State) -> Effect<Action> {
        guard state.hasAccountSession, state.ttlTimerActive else { return .none }
        guard let expiresAt = state.sessionExpiresAt else { return .none }

        let now = date()
        let remaining = expiresAt.timeIntervalSince(now)

        // 90% elapsed (remaining <= 360s for typical 1h TTL)
        guard remaining <= 360 else { return .none }

        return performTokenRefresh()
    }

    /// refresh token 결과 처리.
    private func handleRefreshTokenResult(
        _ state: inout State,
        result: Result<AccountSession, AccessError>,
    ) -> Effect<Action> {
        switch result {
        case let .success(session):
            state.consecutiveRefreshFailures = 0
            state.sessionExpiresAt = session.expiresAt
            if let snapshot = state.snapshot {
                state.snapshot = AccessStatusSnapshot.fetchResult(
                    status: snapshot.status,
                    currentPeriodEnd: snapshot.currentPeriodEnd,
                    sessionExpiresAt: session.expiresAt,
                    fetchedAt: snapshot.fetchedAt,
                    deviceBindingVerifiedAt: snapshot.deviceBindingVerifiedAt,
                )
            }
            return .none

        case let .failure(error):
            let isPermanent = error == .decodingFailure
                || error == .notConfigured
                || error == .unauthorized

            if isPermanent {
                return .send(._sessionExpiredDetected)
            }

            state.consecutiveRefreshFailures += 1

            if state.consecutiveRefreshFailures >= 3 {
                return .send(._sessionExpiredDetected)
            }

            return .none
        }
    }

    /// 사용자 로그아웃 처리.
    private func handleSignOut(_ state: inout State) -> Effect<Action> {
        guard state.hasAccountSession else { return .none }
        state.hasAccountSession = false
        state.didSignInFail = false
        state.isSessionExpired = true
        clearStaleActiveAccessFacts(&state)
        state.ttlTimerActive = false
        state.sessionExpiresAt = nil
        state.fetchGeneration += 1
        return .merge(
            .run { [sessionClient, snapshotClient] send in
                try? await sessionClient.delete(.explicitSignOut)
                await snapshotClient.remove()
                await send(.delegate(.signedOut))
            },
            .cancel(id: CancelID.ttlTimer),
            .cancel(id: CancelID.fetchStatus),
            .cancel(id: CancelID.fetchRetry),
            .cancel(id: CancelID.refreshToken),
        )
    }

    /// 세션 만료 처리.
    private func handleSessionExpiredDetected(_ state: inout State) -> Effect<Action> {
        guard !state.isSessionExpired else { return .none }

        state.hasAccountSession = false
        state.didSignInFail = true
        state.isSessionExpired = true
        // VOY-397: 세션 만료 시 stale active facts 제거.
        clearStaleActiveAccessFacts(&state)
        resetSessionRetryBudget(&state)
        // VOY-397: 세션 만료 시 in-flight access_status 응답 재주입 방지.
        state.fetchGeneration += 1
        state.ttlTimerActive = false
        state.sessionExpiresAt = nil
        state.consecutiveRefreshFailures = 0

        return .merge(
            .run { [sessionClient, snapshotClient] _ in
                try? await sessionClient.delete(.sessionExpired)
                await snapshotClient.remove()
            },
            .cancel(id: CancelID.fetchStatus),
            .cancel(id: CancelID.ttlTimer),
            .cancel(id: CancelID.fetchRetry),
            .cancel(id: CancelID.refreshToken),
            .send(.delegate(.recoveryRequired(.sessionRequired))),
        )
    }

    private func handleAppWillTerminate(_ state: inout State) -> Effect<Action> {
        state.fetchGeneration += 1
        state.isSubmitting = false
        state.isSignInInProgress = false
        state.handoffPendingState = nil
        state.ttlTimerActive = false
        state.fetchRetryCount = 0
        state.deviceBindingFailure = nil
        state.deviceBindingRetryCount = 0
        state.errorMessage = nil

        return .merge(
            .cancel(id: CancelID.fetchStatus),
            .cancel(id: CancelID.fetchRetry),
            .cancel(id: CancelID.refreshToken),
            .cancel(id: CancelID.ttlTimer),
            .cancel(id: CancelID.appDidBecomeActiveObserver),
            .cancel(id: CancelID.signInHandoff),
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
        state.deviceBindingFailure = nil
        state.deviceBindingRetryCount = 0
        state.errorMessage = nil
    }

    private func resetSessionRetryBudget(_ state: inout State) {
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

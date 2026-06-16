import AppKit
import ComposableArchitecture
import Foundation

@Reducer
public struct AccountAccessFeature {
    public typealias State = AccountAccessState
    public typealias Action = AccountAccessAction

    @Dependency(\.accountAccessClient)
    var accountAccessClient

    @Dependency(\.accessStatusSnapshotClient)
    var snapshotClient

    @Dependency(\.signInHandoffClient)
    var signInHandoffClient

    @Dependency(\.date)
    var date

    @Dependency(\.checkoutURLClient)
    var checkoutURLClient

    @Dependency(\.notificationCenterClient)
    var notificationCenterClient

    private enum CancelID {
        static let fetchStatus = "accountAccessFetchStatus"
        static let appDidBecomeActiveObserver = "accountAccessAppDidBecomeActiveObserver"
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

            case let .signInHandoffCompleted(result):
                return handleSignInHandoffCompleted(&state, result: result)

            case let .loginCallbackReceived(url):
                return handleLoginCallbackReceived(&state, url: url)

            case let ._handoffExchangeCompleted(result):
                return handleHandoffExchangeCompleted(&state, result: result)

            case let ._onAppearSessionRestored(session):
                return handleOnAppearSessionRestored(&state, session: session)

            case let ._loginSessionRestored(hasSession):
                return handleLoginSessionRestored(&state, hasSession: hasSession)

            case let .accessStatusResponse(generation: gen, result: result):
                return handleAccessStatusResponse(&state, generation: gen, result: result)

            case .refreshAccessTapped:
                return handleRefreshAccessTapped(&state)

            case .appDidBecomeActive:
                // 세션이 있을 때만 status 갱신 (불필요한 네트워크 요청 방지)
                guard state.hasAccountSession else {
                    return .none
                }
                state.fetchGeneration += 1
                return fetchAccessStatusEffect(generation: state.fetchGeneration)

            case .openCheckoutTapped:
                return handleOpenCheckout(&state)

            case .openPricingTapped:
                return handleOpenPricing(&state)

            case .openAccessHelpTapped:
                return handleOpenAccessHelp(&state)

            case .openBetaCodeHelpTapped:
                return handleOpenBetaCodeHelp(&state)

            case ._ttlTimerTicked:
                return handleTtlTimerTicked(&state)

            case let ._refreshTokenResult(result):
                return handleRefreshTokenResult(&state, result: result)

            case ._sessionExpiredDetected:
                return handleSessionExpiredDetected(&state)

            case .delegate:
                return .none
            }
        }
    }

    private func handleOnAppear(_: inout State) -> Effect<Action> {
        .merge(
            .run { [accountAccessClient] send in
                let session = try? await accountAccessClient.restoreSession()
                await send(._onAppearSessionRestored(session))
            },
            observeAppDidBecomeActive(),
        )
    }

    private func handleOnAppearSessionRestored(_ state: inout State, session: AccountSession?) -> Effect<Action> {
        state.hasAccountSession = session != nil

        guard let session else {
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            return .cancel(id: CancelID.ttlTimer)
        }

        state.sessionExpiresAt = session.expiresAt
        state.isSessionExpired = false
        state.fetchGeneration += 1

        // TTL 타이머 시작: 세션이 복원되면 access token 만료를 추적한다.
        state.ttlTimerActive = true
        let ttlEffect = startTtlTimer()

        return .merge(
            fetchAccessStatusEffect(generation: state.fetchGeneration),
            ttlEffect,
        )
    }

    private func fetchAccessStatusEffect(generation: Int) -> Effect<Action> {
        .run { [accountAccessClient] send in
            let result: Result<AccessStatusResponse, AccessError>
            do {
                let response = try await accountAccessClient.fetchAccessStatus()
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

        return .run { [signInHandoffClient] send in
            let result = await signInHandoffClient.performHandoff()
            await send(.signInHandoffCompleted(result))
        }
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

        case .failure, .cancelled:
            state.isSignInInProgress = false
            state.didSignInFail = true
            return .none
        }
    }

    private func handleLoginCallbackReceived(_ state: inout State, url: URL) -> Effect<Action> {
        // real handoff callback: AppHandoffCallback이 파싱되면 exchange 경로
        if let callback = AppHandoffCallback(url: url) {
            return handleRealHandoffCallback(&state, callback: callback)
        }

        // legacy mock callback: 기존 scheme/host/path + query 없음 → restoreSession 경로
        guard isValidAuthCallback(url), !hasQueryItems(url) else {
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.handoffPendingState = nil
            return .none
        }

        return .run { [accountAccessClient] send in
            let session = try? await accountAccessClient.restoreSession()
            await send(._loginSessionRestored(session != nil))
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

        let expectedContext: AppHandoffContext = .onboarding
        guard callback.context == expectedContext else {
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.handoffPendingState = nil
            return .none
        }

        state.handoffPendingState = nil

        return .run { [accountAccessClient] send in
            let result: Result<AccountSession, AppHandoffExchangeError>
            do {
                let session = try await accountAccessClient.exchangeAppHandoff(
                    callback.ticket, callback.state, callback.context,
                )
                result = .success(session)
            } catch let error as AppHandoffExchangeError {
                result = .failure(error)
            } catch {
                result = .failure(.networkFailure)
            }
            await send(._handoffExchangeCompleted(result))
        }
    }

    private func handleHandoffExchangeCompleted(
        _ state: inout State,
        result: Result<AccountSession, AppHandoffExchangeError>,
    ) -> Effect<Action> {
        switch result {
        case .success:
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.isSessionExpired = false
            state.fetchGeneration += 1
            return fetchAccessStatusEffect(generation: state.fetchGeneration)

        case .failure:
            state.isSignInInProgress = false
            return .send(._sessionExpiredDetected)
        }
    }

    private func hasQueryItems(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return !(components.queryItems?.isEmpty ?? true)
    }

    private func handleLoginSessionRestored(_ state: inout State, hasSession: Bool) -> Effect<Action> {
        state.isSignInInProgress = false

        if hasSession {
            state.hasAccountSession = true
            state.didSignInFail = false
            state.fetchGeneration += 1
            return fetchAccessStatusEffect(generation: state.fetchGeneration)
        } else {
            return .send(._sessionExpiredDetected)
        }
    }

    private func isValidAuthCallback(_ url: URL) -> Bool {
        guard url.scheme == "voyager" else { return false }
        guard url.host == "auth" else { return false }
        guard url.path == "/callback" else { return false }
        return true
    }
}

private extension AccountAccessFeature {
    // MARK: - ONB-002-start_access_unlock_recovery

    private func handleRefreshAccessTapped(_ state: inout State) -> Effect<Action> {
        guard state.canRefreshAccess else {
            return .none
        }
        state.fetchGeneration += 1
        return fetchAccessStatusEffect(generation: state.fetchGeneration)
    }

    private func handleAccessStatusResponse(
        _ state: inout State,
        generation: Int,
        result: Result<AccessStatusResponse, AccessError>,
    ) -> Effect<Action> {
        guard generation == state.fetchGeneration else {
            return .none
        }

        switch result {
        case let .success(response):
            state.status = response.status
            state.trialExpiresAt = response.expiresAt

            let snapshot = AccessStatusSnapshot(
                status: response.status,
                expiresAt: response.expiresAt,
                entitlements: response.entitlements,
                fetchedAt: date(),
            )
            state.snapshot = snapshot

            if response.status.isActive {
                state.isComplete = true
                state.errorMessage = nil
                return .run { [snapshotClient] send in
                    await snapshotClient.save(snapshot)
                    await send(.delegate(.unlocked(snapshot)))
                }
            } else {
                state.isComplete = false
                state.errorMessage = errorMessageForStatus(response.status)
                return .run { [snapshotClient] _ in
                    await snapshotClient.save(snapshot)
                }
            }

        case let .failure(error):
            state.isComplete = false
            state.errorMessage = errorMessage(for: error)
            if error == .networkFailure {
                state.status = .networkFailure
            }
            return .none
        }
    }

    private func errorMessage(for error: AccessError) -> String {
        switch error {
        case .networkFailure: "Network error. Please check your connection and try again."
        case .notConfigured: "Access service is not configured."
        case .decodingFailure: "Failed to process the response."
        case .unknownGatewayCode: "An unexpected error occurred."
        }
    }

    private func errorMessageForStatus(_ status: AccessStatus) -> String {
        switch status {
        case .trialExpired: "This trial has expired."
        case .revoked: "This license has been revoked."
        case .refunded: "This license has been refunded."
        case .networkFailure: "Network error. Please check your connection and try again."
        case .none: "Access denied."
        default: "An unexpected status was returned."
        }
    }

    // MARK: - Foreground 활성화 관찰

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

    // MARK: - TTL 타이머

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

        return .run { [accountAccessClient] send in
            do {
                let session = try await accountAccessClient.refreshToken()
                await send(._refreshTokenResult(.success(session)))
            } catch let error as AccessError {
                await send(._refreshTokenResult(.failure(error)))
            } catch {
                await send(._refreshTokenResult(.failure(.networkFailure)))
            }
        }
    }

    /// refresh token 결과 처리.
    private func handleRefreshTokenResult(_ state: inout State,
                                          result: Result<AccountSession, AccessError>) -> Effect<Action>
    {
        switch result {
        case let .success(session):
            state.consecutiveRefreshFailures = 0
            state.sessionExpiresAt = session.expiresAt
            return .none

        case let .failure(error):
            let isPermanent = error == .decodingFailure
                || error == .notConfigured

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

    /// 세션 만료 처리. dedup guard: 이미 만료 상태면 무시.
    private func handleSessionExpiredDetected(_ state: inout State) -> Effect<Action> {
        guard !state.isSessionExpired else { return .none }

        state.hasAccountSession = false
        state.didSignInFail = true
        state.isSessionExpired = true
        state.ttlTimerActive = false
        state.sessionExpiresAt = nil
        state.consecutiveRefreshFailures = 0

        return .cancel(id: CancelID.ttlTimer)
    }

    // MARK: - 외부 URL 리다이렉트

    /// 체크아웃(구매) 페이지를 브라우저에서 연다.
    private func handleOpenCheckout(_: inout State) -> Effect<Action> {
        .run { [checkoutURLClient] _ in
            let url = checkoutURLClient.checkoutURL()
            checkoutURLClient.openURL(url)
        }
    }

    /// 요금제 페이지를 브라우저에서 연다.
    private func handleOpenPricing(_: inout State) -> Effect<Action> {
        .run { [checkoutURLClient] _ in
            let url = checkoutURLClient.pricingURL()
            checkoutURLClient.openURL(url)
        }
    }

    /// 접근 권한 도움 페이지를 브라우저에서 연다.
    private func handleOpenAccessHelp(_: inout State) -> Effect<Action> {
        .run { [checkoutURLClient] _ in
            let url = checkoutURLClient.supportURL()
            checkoutURLClient.openURL(url)
        }
    }

    /// 베타 코드 도움 페이지를 브라우저에서 연다.
    private func handleOpenBetaCodeHelp(_: inout State) -> Effect<Action> {
        .run { [checkoutURLClient] _ in
            let url = checkoutURLClient.supportURL()
            checkoutURLClient.openURL(url)
        }
    }
}

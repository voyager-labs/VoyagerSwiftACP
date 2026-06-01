import AppKit
import ComposableArchitecture
import Foundation

@Reducer
public struct UnlockLicenseAuthFeature {
    public typealias State = UnlockLicenseAuthState
    public typealias Action = UnlockLicenseAuthAction

    @Dependency(\.licenseAuthClient)
    var licenseAuthClient

    @Dependency(\.licenseAuthStatusSnapshotClient)
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
        static let fetchStatus = "unlockLicenseAuthFetchStatus"
        static let appDidBecomeActiveObserver = "unlockLicenseAuthAppDidBecomeActiveObserver"
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

            case let ._onAppearSessionRestored(hasSession):
                return handleOnAppearSessionRestored(&state, hasSession: hasSession)

            case let ._loginSessionRestored(hasSession):
                return handleLoginSessionRestored(&state, hasSession: hasSession)

            case let .licenseAuthStatusResponse(generation: gen, result: result):
                return handleLicenseAuthStatusResponse(&state, generation: gen, result: result)

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

            case .delegate:
                return .none
            }
        }
    }

    private func handleOnAppear(_: inout State) -> Effect<Action> {
        .merge(
            .run { [licenseAuthClient] send in
                let session = try? await licenseAuthClient.restoreSession()
                await send(._onAppearSessionRestored(session != nil))
            },
            observeAppDidBecomeActive(),
        )
    }

    private func handleOnAppearSessionRestored(_ state: inout State, hasSession: Bool) -> Effect<Action> {
        state.hasAccountSession = hasSession

        guard hasSession else {
            return .none
        }

        state.fetchGeneration += 1
        return fetchAccessStatusEffect(generation: state.fetchGeneration)
    }

    private func fetchAccessStatusEffect(generation: Int) -> Effect<Action> {
        .run { [licenseAuthClient] send in
            let result: Result<LicenseAuthStatusResponse, LicenseAuthError>
            do {
                let response = try await licenseAuthClient.fetchAccessStatus()
                result = .success(response)
            } catch let error as LicenseAuthError {
                result = .failure(error)
            } catch {
                result = .failure(.networkFailure)
            }
            await send(.licenseAuthStatusResponse(generation: generation, result: result))
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
            // 성공: 기존 callback → restoreSession → fetchAccessStatus 경로로 진입
            return .send(.loginCallbackReceived(callbackURL))

        case .failure, .cancelled:
            // 실패/취소: 동일하게 처리
            state.isSignInInProgress = false
            state.didSignInFail = true
            return .none
        }
    }

    private func handleLoginCallbackReceived(_ state: inout State, url: URL) -> Effect<Action> {
        guard isValidAuthCallback(url) else {
            state.isSignInInProgress = false
            state.didSignInFail = true
            return .none
        }

        return .run { [licenseAuthClient] send in
            let session = try? await licenseAuthClient.restoreSession()
            await send(._loginSessionRestored(session != nil))
        }
    }

    private func handleLoginSessionRestored(_ state: inout State, hasSession: Bool) -> Effect<Action> {
        state.isSignInInProgress = false

        if hasSession {
            state.hasAccountSession = true
            state.didSignInFail = false
            state.fetchGeneration += 1
            return fetchAccessStatusEffect(generation: state.fetchGeneration)
        } else {
            state.didSignInFail = true
            return .none
        }
    }

    private func isValidAuthCallback(_ url: URL) -> Bool {
        guard url.scheme == "voyager" else { return false }
        guard url.host == "auth" else { return false }
        guard url.path == "/callback" else { return false }
        return true
    }

    // MARK: - ONB-002-start_access_unlock_recovery

    private func handleRefreshAccessTapped(_ state: inout State) -> Effect<Action> {
        guard state.canRefreshAccess else {
            return .none
        }
        state.fetchGeneration += 1
        return fetchAccessStatusEffect(generation: state.fetchGeneration)
    }

    private func handleLicenseAuthStatusResponse(
        _ state: inout State,
        generation: Int,
        result: Result<LicenseAuthStatusResponse, LicenseAuthError>,
    ) -> Effect<Action> {
        guard generation == state.fetchGeneration else {
            return .none
        }

        switch result {
        case let .success(response):
            state.status = response.status
            state.trialExpiresAt = response.expiresAt

            let snapshot = LicenseAuthStatusSnapshot(
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

    private func errorMessage(for error: LicenseAuthError) -> String {
        switch error {
        case .networkFailure: "Network error. Please check your connection and try again."
        case .notConfigured: "Access service is not configured."
        case .decodingFailure: "Failed to process the response."
        case .unknownGatewayCode: "An unexpected error occurred."
        }
    }

    private func errorMessageForStatus(_ status: LicenseAuthStatus) -> String {
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

import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

@Reducer
public struct AiConnectionRowReducer {
    public typealias State = AiConnectionRowState
    public typealias Action = AiConnectionRowAction

    @Dependency(\.codexNativeAuthClient)
    var nativeAuthClient
    @Dependency(\.aiProviderConnectionClient)
    var connectionClient
    @Dependency(\.aiProviderVerificationClient)
    var verificationClient

    private enum CancelID: Hashable {
        case connectFlow
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .connectButtonTapped, .retryButtonTapped:
                return handleConnect(&state)

            case .disconnectButtonTapped:
                guard state.connectionState == .connected else { return .none }
                state.isShowingDisconnectConfirmation = true
                return .none

            case .disconnectConfirm:
                state.isShowingDisconnectConfirmation = false
                state.flowState = .disconnecting
                state.connectionState = .disconnecting
                let provider = state.provider
                return .run { [connectionClient] send in
                    let result = await connectionClient.disconnect(provider)
                    await send(.disconnectResponse(result))
                }

            case .disconnectCancel:
                state.isShowingDisconnectConfirmation = false
                return .none

            case .cancelButtonTapped:
                state.flowState = .idle
                state.isVerifying = false
                if state.connectionState == .connectInProgress {
                    state.connectionState = .notVerified
                }
                return .merge(
                    .cancel(id: CancelID.connectFlow),
                    .run { [nativeAuthClient] _ in
                        await nativeAuthClient.cancelCurrentFlow()
                    },
                )

            case .startBrowserLogin:
                return handleStartBrowserLogin(&state)

            case .browserLoginCompleted:
                state.connectionState = .connected
                state.flowState = .idle
                state.statusReason = .none
                return .none

            case let .browserLoginFailed(error):
                return handleAuthError(&state, error: error)

            case let .verificationFailed(reason):
                state.flowState = .idle
                state.isVerifying = false
                state.connectionState = reason == .providerUnsupportedInBuild
                    ? .unavailable
                    : .connectionFailed
                state.statusReason = reason
                return .none

            case .startDeviceAuth:
                return handleStartDeviceAuth(&state)

            case .deviceAuthCompleted:
                state.connectionState = .connected
                state.flowState = .idle
                state.statusReason = .none
                return .none

            case let .deviceAuthFailed(error):
                return handleAuthError(&state, error: error)

            case let .enteredKeyChanged(key):
                state.enteredKey = key
                return .none

            case let .submitAPIKey(key):
                return handleSubmitAPIKey(&state, key: key)

            case let .verificationResponse(result):
                return handleVerificationResponse(&state, result: result)

            case let .connectionResponse(result):
                return handleConnectionResponse(&state, result: result)

            case let .disconnectResponse(result):
                state.flowState = .idle
                switch result.state {
                case .notVerified:
                    state.connectionState = .notVerified
                    state.statusReason = .none
                    state.enteredKey = ""
                default:
                    state.connectionState = .connected
                    state.statusReason = .none
                }
                return .none
            }
        }
    }

    private func handleConnect(_ state: inout State) -> Effect<Action> {
        guard state.flowState == .idle else { return .none }
        switch state.connectionState {
        case .notVerified, .connectionFailed, .disconnected:
            break
        default:
            return .none
        }

        let descriptor = ProviderDescriptor.descriptor(for: state.provider)
        guard let descriptor else { return .none }

        if descriptor.authMethod == .oauth {
            return .send(.startBrowserLogin)
        }
        return .none
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleStartBrowserLogin(_ state: inout State) -> Effect<Action> {
        guard state.connectionState != .unavailable else { return .none }
        state.flowState = .browserLoginInProgress
        state.connectionState = .connectInProgress

        return .run { [nativeAuthClient, connectionClient, verificationClient] send in
            let stream = nativeAuthClient.startBrowserLogin()
            var credential: OAuthCredentialFile?
            streamLoop: do {
                for try await event in stream {
                    switch event {
                    case .inProgress:
                        break
                    case let .completed(cred):
                        credential = cred
                        break streamLoop
                    case let .failed(error):
                        await send(.browserLoginFailed(error))
                        return
                    }
                }
            } catch {
                await send(.browserLoginFailed(.networkError(error.localizedDescription)))
                return
            }

            guard let credential else {
                await send(.browserLoginFailed(.networkError("No credential received")))
                return
            }

            let verification = await verificationClient.verify(.chatgptCodex, .oauth(credential))

            switch verification {
            case .valid:
                let result = await connectionClient.connectOAuth(.chatgptCodex, credential, .connected)
                guard result.state == .connected else {
                    await send(.browserLoginFailed(.networkError("Connection failed")))
                    return
                }
                await send(.connectionResponse(result))
                await send(.browserLoginCompleted(credential))
            case let .invalid(reason):
                await send(.verificationFailed(reason))
            case .unsupportedProvider:
                await send(.verificationFailed(.providerUnsupportedInBuild))
            case .networkError:
                await send(.verificationFailed(.networkUnavailable))
            }
        }
        .cancellable(id: CancelID.connectFlow, cancelInFlight: true)
    }

    private func handleStartDeviceAuth(_ state: inout State) -> Effect<Action> {
        guard state.connectionState != .unavailable else { return .none }
        state.flowState = .deviceAuthInProgress
        state.connectionState = .connectInProgress

        return .run { [nativeAuthClient, connectionClient, verificationClient] send in
            do {
                let challenge = try await nativeAuthClient.startDeviceAuth()
                let credential = try await nativeAuthClient.completeDeviceAuth(challenge)

                let verification = await verificationClient.verify(.chatgptCodex, .oauth(credential))

                switch verification {
                case .valid:
                    let result = await connectionClient.connectOAuth(.chatgptCodex, credential, .connected)
                    guard result.state == .connected else {
                        await send(.deviceAuthFailed(.networkError("Connection failed")))
                        return
                    }
                    await send(.connectionResponse(result))
                    await send(.deviceAuthCompleted(credential))
                case let .invalid(reason):
                    await send(.verificationFailed(reason))
                case .unsupportedProvider:
                    await send(.verificationFailed(.providerUnsupportedInBuild))
                case .networkError:
                    await send(.verificationFailed(.networkUnavailable))
                }
            } catch let error as CodexNativeAuthError {
                await send(.deviceAuthFailed(error))
            } catch {
                await send(.deviceAuthFailed(.networkError(error.localizedDescription)))
            }
        }
        .cancellable(id: CancelID.connectFlow, cancelInFlight: true)
    }

    private func handleAuthError(
        _ state: inout State,
        error: CodexNativeAuthError,
    ) -> Effect<Action> {
        state.flowState = .idle
        state.connectionState = .connectionFailed
        switch error {
        case .cancelled:
            state.connectionState = .notVerified
            state.statusReason = .none
        case .timeout:
            state.statusReason = .networkUnavailable
        case .callbackMismatch:
            state.statusReason = .oauthRejected
        case .loginUnavailable:
            state.statusReason = .providerUnsupportedInBuild
        case .networkError:
            state.statusReason = .networkUnavailable
        }
        return .none
    }

    private func handleSubmitAPIKey(_ state: inout State, key: String) -> Effect<Action> {
        guard state.connectionState != .unavailable else { return .none }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        state.enteredKey = trimmed
        state.connectionState = .connectInProgress
        state.flowState = .connecting
        state.isVerifying = true

        let provider = state.provider
        let credential = StoredCredentialPayload.apiKey(
            APIKeyCredentialFile(secret: trimmed),
        )
        return .run { [verificationClient] send in
            let result = await verificationClient.verify(provider, credential)
            await send(.verificationResponse(result))
        }
        .cancellable(id: CancelID.connectFlow, cancelInFlight: true)
    }

    private func handleVerificationResponse(
        _ state: inout State,
        result: AiProviderVerificationResult,
    ) -> Effect<Action> {
        state.isVerifying = false
        let provider = state.provider
        let key = state.enteredKey

        switch result {
        case .valid:
            return .run { [connectionClient] send in
                let connectionResult = await connectionClient.connectAPIKey(
                    provider, key, .connected,
                )
                await send(.connectionResponse(connectionResult))
            }
            .cancellable(id: CancelID.connectFlow, cancelInFlight: true)
        case let .invalid(reason):
            state.connectionState = .connectionFailed
            state.statusReason = reason
            state.flowState = .idle
            return .none
        case .unsupportedProvider:
            state.connectionState = .connectionFailed
            state.statusReason = .providerUnsupportedInBuild
            state.flowState = .idle
            return .none
        case .networkError:
            state.connectionState = .connectionFailed
            state.statusReason = .networkUnavailable
            state.flowState = .idle
            return .none
        }
    }

    private func handleConnectionResponse(
        _ state: inout State,
        result: AiProviderConnectionResult,
    ) -> Effect<Action> {
        state.connectionState = result.state
        state.statusReason = result.reason
        state.flowState = .idle
        if result.state == .connected {
            state.enteredKey = ""
        }
        return .none
    }
}

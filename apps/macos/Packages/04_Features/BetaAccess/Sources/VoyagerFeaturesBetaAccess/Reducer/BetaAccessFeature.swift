import ComposableArchitecture
import Foundation

@Reducer
public struct BetaAccessFeature {
    public typealias State = BetaAccessState
    public typealias Action = BetaAccessAction

    @Dependency(\.betaAccessClient)
    var betaAccessClient

    private enum CancelID {
        static let verification = "betaAccessVerification"
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                if state.isComplete, state.status == .active {
                    return .none
                }
                return verify(&state)

            case let .emailChanged(email):
                let wasComplete = state.isComplete
                let didChange = state.email != email
                state.email = email
                return handleInputChange(&state, wasComplete: wasComplete, didChange: didChange)

            case let .tokenChanged(token):
                let wasComplete = state.isComplete
                let didChange = state.token != token
                state.token = token
                return handleInputChange(&state, wasComplete: wasComplete, didChange: didChange)

            case .checkTapped, .retryTapped:
                return verify(&state)

            case let .verificationResponse(result):
                state.isVerifying = false
                state.updateStatus(result.status, reason: result.reason)
                return .none
            }
        }
    }

    private func handleInputChange(
        _ state: inout State, wasComplete: Bool, didChange: Bool,
    ) -> Effect<Action> {
        if wasComplete, didChange {
            state.updateStatus(.notActive, reason: .none)
        }
        if state.email.isEmpty || state.token.isEmpty {
            state.updateStatus(.notActive, reason: .missingInput)
        } else if state.status == .notActive, state.reason == .missingInput {
            state.reason = .none
        }
        return .none
    }

    private func verify(_ state: inout State) -> Effect<Action> {
        guard !state.email.isEmpty, !state.token.isEmpty else {
            state.isVerifying = false
            state.updateStatus(.notActive, reason: .missingInput)
            return .none
        }

        state.isVerifying = true
        let email = state.email
        let token = state.token

        return .run { [betaAccessClient] send in
            let outcome: Result<BetaAccessVerifyResponse, BetaAccessVerificationError>
            do {
                let response = try await betaAccessClient.verify(email, token)
                outcome = .success(response)
            } catch {
                let mappedError = error as? BetaAccessVerificationError ?? .networkError
                outcome = .failure(mappedError)
            }
            let result = await MainActor.run {
                mapVerificationOutcome(outcome)
            }
            await send(.verificationResponse(result))
        }
        .cancellable(id: CancelID.verification, cancelInFlight: true)
    }
}

private func mapVerificationOutcome(
    _ outcome: Result<BetaAccessVerifyResponse, BetaAccessVerificationError>,
) -> BetaAccessVerificationResult {
    switch outcome {
    case let .success(response):
        if response.ok {
            return BetaAccessVerificationResult(status: .active)
        }
        return BetaAccessVerificationResult(status: .checkFailed, reason: .internalError)
    case let .failure(error):
        return mapVerificationError(error)
    }
}

private func mapVerificationError(_ error: BetaAccessVerificationError) -> BetaAccessVerificationResult {
    switch error {
    case .invalidRequest:
        BetaAccessVerificationResult(status: .checkFailed, reason: .invalidRequest)
    case .deviceIdUnavailable:
        BetaAccessVerificationResult(status: .checkFailed, reason: .deviceIdUnavailable)
    case .decodingError:
        BetaAccessVerificationResult(status: .checkFailed, reason: .internalError)
    case .networkError:
        BetaAccessVerificationResult(status: .checkFailed, reason: .networkError)
    case let .gatewayError(code):
        mapGatewayError(code)
    }
}

private func mapGatewayError(_ code: String) -> BetaAccessVerificationResult {
    switch code {
    case "missing_token":
        BetaAccessVerificationResult(status: .checkFailed, reason: .missingToken)
    case "invalid_token":
        BetaAccessVerificationResult(status: .notActive, reason: .invalidToken)
    case "invalid_request":
        BetaAccessVerificationResult(status: .notActive, reason: .invalidRequest)
    case "email_mismatch":
        BetaAccessVerificationResult(status: .notActive, reason: .emailMismatch)
    case "device_mismatch":
        BetaAccessVerificationResult(status: .notActive, reason: .deviceMismatch)
    case "auth_backend_error":
        BetaAccessVerificationResult(status: .checkFailed, reason: .authBackendError)
    case "invalid_gateway_url":
        BetaAccessVerificationResult(status: .checkFailed, reason: .invalidGatewayUrl)
    default:
        BetaAccessVerificationResult(status: .checkFailed, reason: .networkError)
    }
}

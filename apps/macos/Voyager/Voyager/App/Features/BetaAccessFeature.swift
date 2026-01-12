import ComposableArchitecture
import Foundation

@Reducer
struct BetaAccessFeature {
    @ObservableState
    struct State: Equatable, Sendable {
        var email: String = ""
        var token: String = ""
        var status: BetaAccessStatus = .notActive
        var reason: BetaAccessReason = .missingInput
        var isVerifying: Bool = false
        var isComplete: Bool = false

        var canSubmit: Bool {
            !email.isEmpty && !token.isEmpty && !isVerifying
        }

        var showsRetry: Bool {
            status == .checkFailed
        }

        var statusTitle: String {
            status.rawValue
        }

        var statusMessage: String? {
            switch status {
            case .active:
                "Your invite is verified and beta access is enabled. You can proceed."
            case .checkFailed:
                switch reason {
                case .invalidRequest:
                    "Verification request is invalid. Check your input and try again."
                case .deviceIdUnavailable:
                    "Couldn't access the device ID. Check system access and retry."
                case .internalError:
                    "We hit an internal error. Try again shortly."
                case .networkError:
                    "Network error. Check your connection and try again."
                case .invalidGatewayUrl:
                    "Gateway configuration is invalid. Please contact support."
                case .none, .missingInput, .invalidCredentials, .alreadyUsed:
                    "Verification failed. Check your network and try again."
                }
            case .notActive:
                switch reason {
                case .missingInput:
                    "Beta access isn't active yet. Enter your email and token, then click Check."
                case .invalidCredentials:
                    "That email and token don't match. Check your invite and try again."
                case .alreadyUsed:
                    "This token is already registered to another device. Request a reissue."
                case .invalidRequest:
                    "Check your input and try again."
                case .none, .deviceIdUnavailable, .internalError, .networkError, .invalidGatewayUrl:
                    nil
                }
            }
        }

        mutating func updateStatus(_ status: BetaAccessStatus, reason: BetaAccessReason = .none) {
            self.status = status
            self.reason = reason
            isComplete = status == .active
        }
    }

    enum Action: Sendable {
        case onAppear
        case emailChanged(String)
        case tokenChanged(String)
        case checkTapped
        case retryTapped
        case verificationResponse(BetaAccessVerificationResult)
    }

    @Dependency(\.betaAccessClient)
    var betaAccessClient

    private enum CancelID {
        static let verification = "betaAccessVerification"
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return verify(&state)

            case let .emailChanged(email):
                state.email = email
                return handleInputChange(&state)

            case let .tokenChanged(token):
                state.token = token
                return handleInputChange(&state)

            case .checkTapped, .retryTapped:
                return verify(&state)

            case let .verificationResponse(result):
                state.isVerifying = false
                state.updateStatus(result.status, reason: result.reason)
                return .none
            }
        }
    }

    private func handleInputChange(_ state: inout State) -> Effect<Action> {
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
        response.ok
            ? BetaAccessVerificationResult(status: .active)
            : BetaAccessVerificationResult(status: .checkFailed, reason: .internalError)
    case let .failure(error):
        mapVerificationError(error)
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
    case "invalid_request":
        BetaAccessVerificationResult(status: .notActive, reason: .invalidRequest)
    case "invalid_credentials":
        BetaAccessVerificationResult(status: .notActive, reason: .invalidCredentials)
    case "already_used":
        BetaAccessVerificationResult(status: .notActive, reason: .alreadyUsed)
    default:
        BetaAccessVerificationResult(status: .checkFailed, reason: .networkError)
    }
}

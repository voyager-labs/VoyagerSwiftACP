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
        var scenarioIndex: Int = 0
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
                "Your beta access is confirmed. You can continue to the next step."
            case .checkFailed:
                "We couldn't verify right now. Check your connection and try again."
            case .notActive:
                switch reason {
                case .missingInput:
                    "Please enter both your email and token. Check your invitation email for the details."
                case .mismatch:
                    "That email and token don't match. Please double-check the invitation email."
                case .tokenAlreadyRegistered:
                    "Each token can be registered to one device only. If you want to switch devices, please contact the invite owner."
                case .none:
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
        let scenarioIndex = state.scenarioIndex
        state.scenarioIndex = (state.scenarioIndex + 1) % 4
        let email = state.email
        let token = state.token

        return .run { [betaAccessClient] send in
            let result = await betaAccessClient.verify(email, token, scenarioIndex)
            await send(.verificationResponse(result))
        }
        .cancellable(id: CancelID.verification, cancelInFlight: true)
    }
}

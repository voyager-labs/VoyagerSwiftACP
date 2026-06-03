import ComposableArchitecture
import Foundation

@ObservableState
public struct BetaAccessState: Equatable, Sendable {
    public var email: String = ""
    public var token: String = ""
    public var status: BetaAccessStatus = .notActive
    public var reason: BetaAccessReason = .missingInput
    public var isVerifying: Bool = false
    public var isComplete: Bool = false

    public init(
        email: String = "",
        token: String = "",
        status: BetaAccessStatus = .notActive,
        reason: BetaAccessReason = .missingInput,
        isVerifying: Bool = false,
        isComplete: Bool = false,
    ) {
        self.email = email
        self.token = token
        self.status = status
        self.reason = reason
        self.isVerifying = isVerifying
        self.isComplete = isComplete
    }

    public var canSubmit: Bool {
        !email.isEmpty && !token.isEmpty && !isVerifying
    }

    /// `true` when beta access was restored from a legacy snapshot that lacked credential fields.
    /// The UI shows a restored-verified message instead of blank input fields.
    public var isRestoredVerifiedAccess: Bool {
        isComplete && status == .active && email.isEmpty && token.isEmpty
    }

    public var showsRetry: Bool {
        status == .checkFailed
    }

    public var statusTitle: String {
        status.rawValue
    }

    public var statusMessage: String? {
        switch status {
        case .active:
            "Your invite is verified and beta access is enabled. You can proceed."
        case .checkFailed:
            switch reason {
            case .missingToken:
                "Missing authorization token. Re-enter your invite and try again."
            case .invalidToken:
                "That token is invalid. Check your invite and try again."
            case .invalidRequest:
                "Verification request is invalid. Check your input and try again."
            case .deviceIdUnavailable:
                "Couldn't access the device ID. Check system access and retry."
            case .internalError:
                "We hit an internal error. Try again shortly."
            case .networkError:
                "Network error. Check your connection and try again."
            case .authBackendError:
                "Verification service is unavailable. Try again shortly."
            default:
                "Verification failed. Check your input and try again."
            }
        case .notActive:
            switch reason {
            case .missingInput:
                "Beta access isn't active yet. Enter your email and token, then click Check."
            case .missingToken:
                "Missing authorization token. Re-enter your invite and try again."
            case .invalidToken:
                "That token is invalid. Check your invite and try again."
            case .emailMismatch:
                "That email doesn't match this token. Check your invite and try again."
            case .deviceMismatch:
                "This token is registered to another device. Request a reissue."
            case .invalidRequest:
                "Check your input and try again."
            case .authBackendError:
                "Verification service is unavailable. Try again shortly."
            default:
                nil
            }
        }
    }

    public mutating func updateStatus(_ status: BetaAccessStatus, reason: BetaAccessReason = .none) {
        self.status = status
        self.reason = reason
        isComplete = status == .active
    }
}

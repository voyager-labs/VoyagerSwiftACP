import ComposableArchitecture
import Foundation

@ObservableState
public struct AccountAccessState: Equatable {
    public var status: AccessStatus?
    public var snapshot: AccessStatusSnapshot?
    public var isSubmitting: Bool = false
    public var errorMessage: String?
    public var isComplete: Bool = false
    public var trialExpiresAt: Date?
    public var hasAccountSession: Bool = false
    public var isSignInInProgress: Bool = false
    public var didSignInFail: Bool = false
    public var fetchGeneration: Int = 0
    /// 현재 대기 중인 handoff state. awaitingCallback에서 설정, callback 처리 후 초기화.
    public var handoffPendingState: String?

    public init() {}

    public var showsRetry: Bool {
        guard let status else { return false }
        return !status.isActive
    }

    // MARK: - ONB-002 Interpretation

    public var accountAccessAuthAxis: AccountAccessAuthAxis {
        if isSignInInProgress {
            return .signInInProgress
        }
        if didSignInFail {
            return .signInFailed
        }
        if hasAccountSession {
            return .signedIn
        }
        return .signedOut
    }

    public var accountAccessStepState: AccountAccessStepState {
        if isSignInInProgress {
            return .pending
        }
        if !hasAccountSession {
            return .blocked
        }
        guard let status else {
            return .pending
        }
        switch status {
        case .coreLicenseActive, .betaTrialActive, .internalTestActive:
            return .complete
        case .networkFailure:
            return .error
        case .none, .trialExpired, .revoked, .refunded:
            return .blocked
        }
    }

    // MARK: - ONB-002 Affordances

    public var canStartLogin: Bool {
        accountAccessAuthAxis == .signedOut || accountAccessAuthAxis == .signInFailed
    }

    public var canRefreshAccess: Bool {
        accountAccessAuthAxis == .signedIn && !isSubmitting && !isSignInInProgress
    }

    public var canRetry: Bool {
        accountAccessStepState == .error && !isSubmitting
    }

    public var requiresAccountSession: Bool {
        !hasAccountSession
    }
}

import ComposableArchitecture
import Foundation

@ObservableState
public struct UnlockLicenseAuthState: Equatable {
    public var status: LicenseAuthStatus?
    public var snapshot: LicenseAuthStatusSnapshot?
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

    public var onb002AuthAxis: Onb002AuthAxis {
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

    public var onb002AccessStepState: Onb002AccessStepState {
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
        onb002AuthAxis == .signedOut || onb002AuthAxis == .signInFailed
    }

    public var canRefreshAccess: Bool {
        onb002AuthAxis == .signedIn && !isSubmitting && !isSignInInProgress
    }

    public var canRetry: Bool {
        onb002AccessStepState == .error && !isSubmitting
    }

    public var requiresAccountSession: Bool {
        !hasAccountSession
    }
}

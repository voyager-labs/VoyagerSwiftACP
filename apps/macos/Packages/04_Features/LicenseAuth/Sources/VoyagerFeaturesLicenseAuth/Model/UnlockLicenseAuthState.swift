import ComposableArchitecture
import Foundation

@ObservableState
public struct UnlockLicenseAuthState: Equatable {
    public var claimMode: LicenseAuthClaimMode = .licenseKey
    public var licenseKey: String = ""
    public var betaCode: String = ""
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

    public init() {}

    public var showsRetry: Bool {
        guard let status else { return false }
        return !status.isActive
    }

    public var canSubmit: Bool {
        switch claimMode {
        case .licenseKey: !licenseKey.isEmpty
        case .betaCode: !betaCode.isEmpty
        }
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

    public var canSubmitClaim: Bool {
        onb002AuthAxis == .signedIn && canSubmit && !isSubmitting
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

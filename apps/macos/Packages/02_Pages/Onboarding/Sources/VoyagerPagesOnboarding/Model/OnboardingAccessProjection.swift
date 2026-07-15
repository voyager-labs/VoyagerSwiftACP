import Foundation
import VoyagerFeaturesAccountAccess

struct OnboardingAccessProjection: Equatable {
    var hasAccountSession: Bool
    var isSignInInProgress: Bool
    var didSignInFail: Bool
    var isComplete: Bool
    var status: AccessStatus?
    var errorMessage: String?
    var trialExpiresAt: Date?
    var isSubmitting: Bool
    var hasDeviceBindingFailure: Bool
    var canStartLogin: Bool
    var canRefreshAccess: Bool
    var canRetry: Bool
    var canCancelSignIn: Bool
    var isBlocked: Bool
    var primaryCTA: PrimaryCTA
    var snapshot: AccessStatusSnapshot?
    var entitlementState: EntitlementState

    init(
        hasAccountSession: Bool = false,
        isSignInInProgress: Bool = false,
        didSignInFail: Bool = false,
        isComplete: Bool = false,
        status: AccessStatus? = nil,
        errorMessage: String? = nil,
        trialExpiresAt: Date? = nil,
        isSubmitting: Bool = false,
        hasDeviceBindingFailure: Bool = false,
        canStartLogin: Bool = false,
        canRefreshAccess: Bool = false,
        canRetry: Bool = false,
        canCancelSignIn: Bool = false,
        isBlocked: Bool = true,
        primaryCTA: PrimaryCTA = .login,
        snapshot: AccessStatusSnapshot? = nil,
        entitlementState: EntitlementState = .unknown,
    ) {
        self.hasAccountSession = hasAccountSession
        self.isSignInInProgress = isSignInInProgress
        self.didSignInFail = didSignInFail
        self.isComplete = isComplete
        self.status = status
        self.errorMessage = errorMessage
        self.trialExpiresAt = trialExpiresAt
        self.isSubmitting = isSubmitting
        self.hasDeviceBindingFailure = hasDeviceBindingFailure
        self.canStartLogin = canStartLogin
        self.canRefreshAccess = canRefreshAccess
        self.canRetry = canRetry
        self.canCancelSignIn = canCancelSignIn
        self.isBlocked = isBlocked
        self.primaryCTA = primaryCTA
        self.snapshot = snapshot
        self.entitlementState = entitlementState
    }

    init(accountAccess: AccountAccessFeature.State) {
        self.init(
            hasAccountSession: accountAccess.hasAccountSession,
            isSignInInProgress: accountAccess.isSignInInProgress,
            didSignInFail: accountAccess.didSignInFail,
            isComplete: accountAccess.isComplete,
            status: accountAccess.status,
            errorMessage: accountAccess.errorMessage,
            trialExpiresAt: accountAccess.trialExpiresAt,
            isSubmitting: accountAccess.isSubmitting,
            hasDeviceBindingFailure: accountAccess.deviceBindingFailure != nil,
            canStartLogin: accountAccess.canStartLogin,
            canRefreshAccess: accountAccess.canRefreshAccess,
            canRetry: accountAccess.canRetry,
            canCancelSignIn: accountAccess.isSignInInProgress || accountAccess.handoffPendingState != nil,
            isBlocked: accountAccess.accountAccessStepState == .blocked,
            primaryCTA: PrimaryCTA(accountAccess.accessUnlockPrimaryCTA),
            snapshot: accountAccess.snapshot,
            entitlementState: EntitlementState(accountAccess.status),
        )
    }

    enum EntitlementState: Equatable {
        case unknown
        case unavailable
        case active
        case none
        case expired
        case revoked
        case refunded

        init(_ status: AccessStatus?) {
            guard let status else {
                self = .unknown
                return
            }

            switch status {
            case .coreLicenseActive, .trialActive, .internalTestActive:
                self = .active
            case .none:
                self = .none
            case .trialExpired:
                self = .expired
            case .revoked:
                self = .revoked
            case .refunded:
                self = .refunded
            case .networkFailure:
                self = .unavailable
            }
        }
    }

    enum PrimaryCTA: Equatable {
        case account
        case retry
        case login
        case webPricing
        case next
        case pending

        init(_ primaryCTA: AccessUnlockPrimaryCTA) {
            switch primaryCTA {
            case .account:
                self = .account
            case .retry:
                self = .retry
            case .login:
                self = .login
            case .webPricing:
                self = .webPricing
            case .next:
                self = .next
            case .pending:
                self = .pending
            }
        }
    }
}

enum OnboardingAccessIntent: Equatable {
    case login
    case refresh
    case retry
    case cancelSignIn
    case openPricing
    case openAccount
    case openAccessHelp

    var accountAccessAction: AccountAccessAction {
        switch self {
        case .login:
            .loginTapped(context: .onboarding, scope: .onboarding)
        case .refresh:
            .refreshAccessTapped
        case .retry:
            .retryTapped
        case .cancelSignIn:
            .cancelSignIn
        case .openPricing:
            .openPricingTapped
        case .openAccount:
            .openAccountTapped
        case .openAccessHelp:
            .openAccessHelpTapped
        }
    }
}

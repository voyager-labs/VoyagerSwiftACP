import ComposableArchitecture
import VoyagerFeaturesAccountAccess

public enum SetAuthState: Equatable, Sendable {
    case signedOut
    case signInInProgress
    case signedIn
    case signInFailed
}

public enum SetEntitlementState: Equatable, Sendable {
    case entitlementUnknown
    case entitlementUnavailable
    case entitlementActive
    case entitlementNone
    case entitlementExpired
    case entitlementRevoked
    case entitlementRefunded
}

/// Canonical AccountAccess runtime에서 Settings가 표시하는 사실만 복사한 값 projection.
public struct AccountAccessPresentation: Equatable, Sendable {
    public var hasAccountSession: Bool
    public var isSignInInProgress: Bool
    public var didSignInFail: Bool
    public var accessStatus: AccessStatus?

    public init(
        hasAccountSession: Bool = false,
        isSignInInProgress: Bool = false,
        didSignInFail: Bool = false,
        accessStatus: AccessStatus? = nil,
    ) {
        self.hasAccountSession = hasAccountSession
        self.isSignInInProgress = isSignInInProgress
        self.didSignInFail = didSignInFail
        self.accessStatus = accessStatus
    }

    public init(snapshot: AccessStatusSnapshot) {
        self.init(
            hasAccountSession: snapshot.sessionExpiresAt != nil,
            accessStatus: snapshot.status,
        )
    }
}

@ObservableState
public struct AccountSettingsState: Equatable {
    public var presentation = AccountAccessPresentation()
    public var isShowingSignOutConfirmation = false

    public init() {}

    public var setAuthState: SetAuthState {
        if presentation.isSignInInProgress { return .signInInProgress }
        if presentation.didSignInFail { return .signInFailed }
        return presentation.hasAccountSession ? .signedIn : .signedOut
    }

    public var setEntitlementState: SetEntitlementState {
        guard let status = presentation.accessStatus else { return .entitlementUnknown }
        switch status {
        case .coreLicenseActive, .trialActive, .internalTestActive:
            return .entitlementActive
        case .none:
            return .entitlementNone
        case .trialExpired:
            return .entitlementExpired
        case .revoked:
            return .entitlementRevoked
        case .refunded:
            return .entitlementRefunded
        case .networkFailure:
            return .entitlementUnavailable
        }
    }

    public var isManageAccountAvailable: Bool {
        guard presentation.hasAccountSession else { return false }
        switch setEntitlementState {
        case .entitlementActive, .entitlementNone, .entitlementExpired, .entitlementRevoked, .entitlementRefunded:
            return true
        case .entitlementUnknown, .entitlementUnavailable:
            return false
        }
    }
}

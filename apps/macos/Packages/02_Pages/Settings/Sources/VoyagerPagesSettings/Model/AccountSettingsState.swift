import ComposableArchitecture
import VoyagerFeaturesAccountAccess

/// SET-008 auth status 표시용 상태 (5 states)
public enum SetAuthState: Equatable, Sendable {
    case signedOut
    case signInInProgress
    case signedIn
    case signInFailed
    case signOutInProgress
}

/// SET-008 entitlement status 표시용 상태 (3 states)
public enum SetEntitlementState: Equatable, Sendable {
    case entitlementUnknown
    case entitlementActive
    case entitlementInactive
}

@ObservableState
public struct AccountSettingsState: Equatable {
    public var access: AccountAccessFeature.State = .init()
    public var isShowingSignOutConfirmation: Bool = false

    public init() {}

    /// SET-008 surface auth 상태 매핑 (read-only display mapping).
    /// ACC-001 auth 상태를 SET의 5개 user-visible status로 변환한다.
    public var setAuthState: SetAuthState {
        if access.isSignInInProgress { return .signInInProgress }
        if access.didSignInFail { return .signInFailed }
        if access.hasAccountSession { return .signedIn }
        return .signedOut
    }

    /// SET-008 surface entitlement 상태 매핑 (read-only display mapping).
    /// ACC-002 entitlement 상태를 SET의 3개 user-visible status로 변환한다.
    public var setEntitlementState: SetEntitlementState {
        guard let status = access.status else { return .entitlementUnknown }
        if status.isActive { return .entitlementActive }
        return .entitlementInactive
    }
}

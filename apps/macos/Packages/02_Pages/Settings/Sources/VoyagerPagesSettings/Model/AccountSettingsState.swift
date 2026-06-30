import ComposableArchitecture
import VoyagerFeaturesAccountAccess

/// SET-008 auth status 표시용 상태 (4 states)
/// sign-out은 동기적으로 처리하여 별도 진행 상태 없이 즉시 signed_out으로 전환한다.
public enum SetAuthState: Equatable, Sendable {
    case signedOut
    case signInInProgress
    case signedIn
    case signInFailed
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

    /// SET-008 web-bridge CTA 게이트 (T1 contract).
    /// entitlement_management_action_for_entitlement = ["entitlement_active"] 에 따라,
    /// Manage Account CTA는 entitlementActive 상태에서만 노출된다.
    /// inactive/unknown 상태에서는 Settings 내 recovery CTA가 존재하지 않는다
    /// (entitlement_inactive_has_no_in_settings_recovery_cta).
    public var isManageAccountAvailable: Bool {
        setEntitlementState == .entitlementActive
    }
}

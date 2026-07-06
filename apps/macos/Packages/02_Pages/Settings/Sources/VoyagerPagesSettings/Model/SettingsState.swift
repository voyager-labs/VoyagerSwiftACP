import ComposableArchitecture
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess

@ObservableState
public struct SettingsState: Equatable {
    public var selectedSection: SettingsSection = .general
    var generalSettings = GeneralSettingsState()
    var appearanceSettings = AppearanceSettingsState()
    var aiSettings = AiSettingsState()
    var accountSettings = AccountSettingsState()
    // Settings content gate: access_status != full일 때 SettingsView가 locked overlay를 render한다.
    public var accessStatus: AccessStatus = .none
    public var isContentLocked: Bool {
        !accessStatus.isActive
    }

    public init() {}

    /// Host-mount preset factory. Settings package-owned이므로 child internals를 직접 채운다.
    /// Host app은 이 팩토리만 호출 — child state를 밖에서 건드리지 않는다.
    ///
    /// ponytail: 5축 중 SettingsState 초기값에 의미있게 반영되는 건 accessStatus(accountAuth 파생)와
    /// appearanceSettings.theme(persistence 파생) 두 축뿐. 나머지 축(aiConnection/permissions/failureLatency)은
    /// SettingsHostSandbox 의존성이 런타임에 비동기 로드하므로 초기 상태에서 건드릴 값 없음.
    ///
    /// Task 16: AccountAccess session/entitlement 사실축도 factory에서 prehydrate한다.
    /// handleHydrateLaunchSnapshot이 런타임 action에서 채우는 축과 동일하지만,
    /// effect 기반 상태(ttlTimerActive, fetchGeneration)는 런타임 effect 소유이므로
    /// 초기 상태에서는 건드리지 않는다. SettingsHost가 AppLifecycle 없이도
    /// signedIn/signedOut/authExpired 시나리오를 즉시 렌더링하도록 한다.
    public static func hostPreset(for scenario: SettingsHostScenario) -> SettingsState {
        var state = SettingsState()
        let accessStatus: AccessStatus = switch scenario.accountAuth {
        case .signedIn:
            .coreLicenseActive
        case .authExpired:
            .trialExpired
        case .signedOut, .loading, .error:
            .none
        }
        state.accessStatus = accessStatus

        // AccountAccess launch hydration: preset 시나리오의 session/entitlement 사실을
        // 초기 상태로 주입. hostPreset이 곧 launch 상태이므로 didBootstrap을 세워
        // 이후 handleOnAppear가 중복 session read/fetch를 수행하지 않도록 차단한다.
        // sessionExpiresAt == nil이면 hasAccountSession=false (가짜 세션 주입 금지).
        // status/snapshot은 session이 있는 시나리오(signedIn/authExpired)만 주입한다 —
        // session 없는 시나리오(signedOut/loading/error)는 status=nil로 두어
        // setEntitlementState가 .entitlementUnknown을 derive하도록 한다.
        let sessionExpiry = scenario.sessionExpiresAt
        state.accountSettings.access.didBootstrap = true
        state.accountSettings.access.sessionExpiresAt = sessionExpiry
        state.accountSettings.access.hasAccountSession = sessionExpiry != nil
        state.accountSettings.access.isSessionExpired = false
        if sessionExpiry != nil {
            state.accountSettings.access.status = accessStatus
            // fetchedAt은 deterministic 기준 시각을 사용해 테스트 wall-clock 의존 제거.
            state.accountSettings.access.snapshot = AccessStatusSnapshot(
                status: accessStatus,
                fetchedAt: .sessionExpiryPast,
                sessionExpiresAt: sessionExpiry,
            )
        }

        if scenario.persistence == .populated {
            state.appearanceSettings.theme = .dark
        }
        return state
    }
}

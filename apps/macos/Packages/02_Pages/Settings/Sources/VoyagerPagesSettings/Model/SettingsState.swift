import ComposableArchitecture
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
}

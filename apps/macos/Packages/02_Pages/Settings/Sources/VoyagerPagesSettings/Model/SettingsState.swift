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
    public var accessStatus: AccessStatus = .none

    /// SettingsView 호환용 shim.
    /// Settings 창은 accessStatus에 따라 잠기지 않으므로 항상 false를 유지한다.
    public var isContentLocked: Bool {
        false
    }

    public init(
        accessStatus: AccessStatus = .none,
        accountPresentation: AccountAccessPresentation = .init(),
        appearanceTheme: AppTheme? = nil,
    ) {
        self.accessStatus = accessStatus
        accountSettings.presentation = accountPresentation

        if let appearanceTheme {
            appearanceSettings.theme = appearanceTheme
        }
    }
}

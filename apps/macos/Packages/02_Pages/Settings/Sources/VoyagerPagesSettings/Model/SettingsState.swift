import ComposableArchitecture
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess

@ObservableState
public struct SettingsState: Equatable {
    public var selectedSection: SettingsSection = .general
    var generalSettings = GeneralSettingsState()
    var appearanceSettings = AppearanceSettingsState()
    var aiSettings = AiSettingsState()
    public var accountSettings = AccountSettingsState()
    public var accessStatus: AccessStatus = .none

    public init(
        accountPresentation: AccountAccessPresentation = .init(),
        accessStatus: AccessStatus = .none,
        appearanceTheme: AppTheme? = nil,
    ) {
        accountSettings.presentation = accountPresentation
        self.accessStatus = accessStatus

        if let appearanceTheme {
            appearanceSettings.theme = appearanceTheme
        }
    }
}

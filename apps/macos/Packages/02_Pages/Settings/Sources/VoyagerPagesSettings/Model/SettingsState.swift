import ComposableArchitecture
import VoyagerEntitiesAppPreferences

@ObservableState
public struct SettingsState: Equatable {
    public var selectedSection: SettingsSection = .general
    var generalSettings = GeneralSettingsState()
    var appearanceSettings = AppearanceSettingsState()
    var aiSettings = AiSettingsState()
    public var accountSettings = AccountSettingsState()

    public init(
        accountPresentation: AccountAccessPresentation = .init(),
        appearanceTheme: AppTheme? = nil,
    ) {
        accountSettings.presentation = accountPresentation

        if let appearanceTheme {
            appearanceSettings.theme = appearanceTheme
        }
    }
}

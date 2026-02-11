import ComposableArchitecture

@ObservableState
struct SettingsState: Equatable {
    var selectedSection: SettingsSection = .general
    var generalSettings = GeneralSettingsState()
    var appearanceSettings = AppearanceSettingsState()
}

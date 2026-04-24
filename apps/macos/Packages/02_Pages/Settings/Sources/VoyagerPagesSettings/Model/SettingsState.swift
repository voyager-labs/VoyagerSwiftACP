import ComposableArchitecture

@ObservableState
public struct SettingsState: Equatable {
    var selectedSection: SettingsSection = .general
    var generalSettings = GeneralSettingsState()
    var appearanceSettings = AppearanceSettingsState()

    public init() {}
}

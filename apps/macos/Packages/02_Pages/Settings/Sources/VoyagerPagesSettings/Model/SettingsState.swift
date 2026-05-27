import ComposableArchitecture

@ObservableState
public struct SettingsState: Equatable {
    public var selectedSection: SettingsSection = .general
    var generalSettings = GeneralSettingsState()
    var appearanceSettings = AppearanceSettingsState()
    var aiSettings = AiSettingsState()

    public init() {}
}

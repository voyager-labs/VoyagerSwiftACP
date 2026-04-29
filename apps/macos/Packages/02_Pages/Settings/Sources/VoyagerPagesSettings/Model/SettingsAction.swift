import ComposableArchitecture

@CasePathable
public enum SettingsAction: CasePathable, Sendable {
    case onAppear
    case selectSection(SettingsSection)
    case closeWindow

    case general(GeneralSettingsAction)
    case appearance(AppearanceSettingsAction)
    case ai(AiSettingsAction)
}

import ComposableArchitecture
import VoyagerEntitiesAi

@CasePathable
public enum SettingsAction: CasePathable, Sendable {
    case delegate(Delegate)

    case onAppear
    case bootstrapLocalPreferences
    case selectSection(SettingsSection)
    case closeWindow
    case resetSectionForFreshOpen
    case accountAccessPresentationUpdated(AccountAccessPresentation)

    case general(GeneralSettingsAction)
    case appearance(AppearanceSettingsAction)
    case ai(AiSettingsAction)
    case account(AccountSettingsAction)
    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case aiConnectionsFileUpdated(AIConnectionsFile)
        case account(AccountSettingsAction.Delegate)
    }
}

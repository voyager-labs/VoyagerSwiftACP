import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerFeaturesAccountAccess

@CasePathable
public enum SettingsAction: CasePathable, Sendable {
    case delegate(Delegate)

    case onAppear
    // ponytail: AppRoot가 launch(.willFinishLaunching)에서 1회 전송 (onAppear reload 대체).
    case bootstrapLocalPreferences
    case selectSection(SettingsSection)
    case closeWindow
    case resetSectionForFreshOpen
    case accessStatusLoaded(AccessStatus)
    // ponytail: AppRoot가 accountAccessGate(.accountAccessGranted)에서 AppLifecycle snapshot 전달.
    case appLifecycleAccessSnapshotReady(AccessStatusSnapshot)

    case general(GeneralSettingsAction)
    case appearance(AppearanceSettingsAction)
    case ai(AiSettingsAction)
    case account(AccountSettingsAction)
    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case aiConnectionsFileUpdated(AIConnectionsFile)
    }
}

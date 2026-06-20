import ComposableArchitecture
import VoyagerFeaturesAccountAccess

@CasePathable
public enum AccountSettingsAction: CasePathable, Sendable {
    case access(AccountAccessAction)
    case signOutTapped
    case signOutConfirmed
    case signOutCancelled
    case manageAccountTapped
    case openAccountURLCompleted(Bool)
}

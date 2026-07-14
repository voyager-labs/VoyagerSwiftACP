import ComposableArchitecture

@CasePathable
public enum AccountSettingsAction: CasePathable, Sendable {
    case delegate(Delegate)
    case signInTapped
    case signOutTapped
    case signOutConfirmed
    case signOutCancelled
    case retryTapped
    case manageAccountTapped

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case signInRequested
        case signOutRequested
        case retryRequested
    }
}

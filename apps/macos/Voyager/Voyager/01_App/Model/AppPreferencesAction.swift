import ComposableArchitecture

@CasePathable
enum AppPreferencesAction: CasePathable, Sendable {
    case load
    case reloadFromUserDefaults
    case delegate(Delegate)

    enum Delegate: Sendable {
        case updated(AppPreferencesState)
    }
}

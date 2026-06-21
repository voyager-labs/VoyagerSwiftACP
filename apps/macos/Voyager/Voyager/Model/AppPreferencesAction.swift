import ComposableArchitecture

@CasePathable
enum AppPreferencesAction: CasePathable {
    case load
    case reloadFromUserDefaults
    case delegate(Delegate)

    enum Delegate {
        case updated(AppPreferencesState)
    }
}

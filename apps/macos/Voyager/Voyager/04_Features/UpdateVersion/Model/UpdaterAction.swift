import ComposableArchitecture

@CasePathable
enum UpdaterAction: CasePathable, Sendable {
    case configureAtLaunch
    case startAtLaunch
    case checkForUpdates
    case setAutomaticUpdate(Bool)
}

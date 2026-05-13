import ComposableArchitecture

@CasePathable
public enum UpdaterAction: CasePathable, Equatable, Sendable {
    case configureAtLaunch
    case startAtLaunch
    case checkForUpdates
    case setAutomaticUpdate(Bool)
}

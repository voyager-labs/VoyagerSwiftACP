import ComposableArchitecture

@CasePathable
public enum UpdaterAction: CasePathable, Sendable {
    case configureAtLaunch
    case startAtLaunch
    case checkForUpdates
    case setAutomaticUpdate(Bool)
}

import ComposableArchitecture

@CasePathable
public enum UpdaterAction: CasePathable, Equatable, Sendable {
    case launchReady
    case checkForUpdates
    case setAutomaticUpdate(Bool)
}

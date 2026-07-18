import ComposableArchitecture
import Foundation

@CasePathable
public enum UpdaterAction: CasePathable, Equatable, Sendable {
    case accessGranted(updateStatus: String?, updatesThrough: Date?)
    case accessRevoked
    case configureAtLaunch
    case startAtLaunch
    case checkForUpdates
    case setAutomaticUpdate(Bool)
}

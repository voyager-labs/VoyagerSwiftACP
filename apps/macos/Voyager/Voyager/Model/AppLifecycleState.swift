import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@ObservableState
struct AppLifecycleState: Equatable {
    var didStartHelper = false
    var didFinishLaunching = false
    var terminationAttemptID: UUID?
    var isCheckingAccountAccess = false
    var lastAccessStatus: AccessStatus?
    var accountAccessGateResolved = false
    var sessionLapseGuard: AccountAccessFeature.State?
    var sessionEndReason: AccountSessionEndReason?
}

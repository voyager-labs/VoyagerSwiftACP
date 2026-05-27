import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccess

@ObservableState
struct AppLifecycleState: Equatable {
    var didStartHelper = false
    var terminationAttemptID: UUID?
    var isCheckingAccess = false
    var lastAccessStatus: AccessStatus?
    var accessGateResolved = false
}

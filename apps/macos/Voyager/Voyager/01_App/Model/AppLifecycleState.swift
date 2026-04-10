import ComposableArchitecture
import Foundation

@ObservableState
struct AppLifecycleState: Equatable {
    var didStartHelper = false
    var terminationAttemptID: UUID?
}

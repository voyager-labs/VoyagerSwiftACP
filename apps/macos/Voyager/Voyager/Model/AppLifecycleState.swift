import ComposableArchitecture
import Foundation

@ObservableState
struct AppLifecycleState: Equatable {
    var didStartHelper = false
    var didFinishLaunching = false
    var terminationAttemptID: UUID?
}

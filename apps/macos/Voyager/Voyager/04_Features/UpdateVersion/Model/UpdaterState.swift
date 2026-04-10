import ComposableArchitecture
import Foundation

@ObservableState
struct UpdaterState: Equatable {
    var didConfigure = false
    var didStartAtLaunch = false
}

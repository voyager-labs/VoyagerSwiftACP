import ComposableArchitecture
import Foundation

@ObservableState
public struct UpdaterState: Equatable {
    public var didConfigure = false
    public var didStartAtLaunch = false

    public init() {}
}

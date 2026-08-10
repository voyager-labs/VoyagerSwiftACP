import ComposableArchitecture

@ObservableState
public struct UpdaterState: Equatable {
    public var didConfigure = false
    public var didStartAtLaunch = false

    public init(
        didConfigure: Bool = false,
        didStartAtLaunch: Bool = false,
    ) {
        self.didConfigure = didConfigure
        self.didStartAtLaunch = didStartAtLaunch
    }
}

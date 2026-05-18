public struct ContentPageNavigationHistorySnapshot: Equatable, Sendable {
    public let navigationState: ContentPageNavigationRoute

    public init(navigationState: ContentPageNavigationRoute) {
        self.navigationState = navigationState
    }
}

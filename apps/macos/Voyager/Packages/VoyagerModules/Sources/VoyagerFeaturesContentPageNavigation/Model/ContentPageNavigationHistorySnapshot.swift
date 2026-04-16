public struct ContentPageNavigationHistorySnapshot: Equatable, @unchecked Sendable {
    public let navigationState: ContentPageNavigationRoute

    public init(navigationState: ContentPageNavigationRoute) {
        self.navigationState = navigationState
    }
}

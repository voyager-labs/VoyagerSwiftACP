import ComposableArchitecture

@Reducer
public struct ContentPageNavigationFeature {
    public typealias State = ContentPageNavigationState
    public typealias Action = ContentPageNavigationAction

    public var body: some Reducer<State, Action> {
        ContentPageNavigationDirectReducer()
        ContentPageNavigationHistoryReducer()
        ContentPageNavigationStateReducer()
    }
}

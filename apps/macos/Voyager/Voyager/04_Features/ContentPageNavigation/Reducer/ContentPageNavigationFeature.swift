import ComposableArchitecture

@Reducer
struct ContentPageNavigationFeature {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    var body: some Reducer<State, Action> {
        ContentPageNavigationDirectReducer()
        ContentPageNavigationHistoryReducer()
        ContentPageNavigationStateReducer()
    }
}

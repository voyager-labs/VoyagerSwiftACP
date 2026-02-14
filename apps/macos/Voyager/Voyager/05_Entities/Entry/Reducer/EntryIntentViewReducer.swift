import ComposableArchitecture

@Reducer
struct EntryIntentViewReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .updateGridColumnCount(count):
                state.gridColumnCount = max(1, count)
                return .none

            default:
                return .none
            }
        }
    }
}

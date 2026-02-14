import ComposableArchitecture

// TODO(voy-142): 타입명과 맞추기 위해 파일명을 EntryIntentViewReducer.swift로 변경 필요.
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

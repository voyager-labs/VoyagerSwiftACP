import ComposableArchitecture

// TODO(voy-142): 타입명과 맞추기 위해 파일명을 EntryIntentReducer.swift로 변경 필요.
@Reducer
struct EntryIntentReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    var body: some Reducer<State, Action> {
        CombineReducers {
            EntryIntentOpenReducer()
            EntryIntentClipboardReducer()
            EntryIntentDragDropReducer()
            EntryIntentRenameReducer()
            EntryIntentOperationReducer()
            EntryIntentViewReducer()
        }
    }
}

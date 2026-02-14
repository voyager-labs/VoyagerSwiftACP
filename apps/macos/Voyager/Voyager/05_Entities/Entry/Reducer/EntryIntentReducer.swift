import ComposableArchitecture

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

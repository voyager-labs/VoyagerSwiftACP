import ComposableArchitecture

@Reducer
struct EntryFeature {
    typealias State = EntryState
    typealias Action = EntryAction

    var body: some Reducer<State, Action> {
        CombineReducers {
            EntryLoadingReducer()
            EntryUndoReducer()
            EntrySelectionReducer()
            EntryIntentReducer()
        }
    }
}

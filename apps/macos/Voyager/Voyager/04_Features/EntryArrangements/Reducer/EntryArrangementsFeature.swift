import ComposableArchitecture

@Reducer
struct EntryArrangementsFeature {
    typealias State = FileManagerContentState
    typealias Action = EntryArrangementsAction

    var body: some Reducer<State, Action> {
        CombineReducers {
            EntryArrangementsSortingReducer()
            EntryArrangementsGroupingReducer()
        }
    }
}

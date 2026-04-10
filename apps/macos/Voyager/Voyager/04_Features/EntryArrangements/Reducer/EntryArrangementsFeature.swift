import ComposableArchitecture

@Reducer
struct EntryArrangementsFeature {
    typealias State = EntryArrangementsState
    typealias Action = EntryArrangementsAction

    var body: some Reducer<State, Action> {
        CombineReducers {
            EntryArrangementsSortingReducer()
            EntryArrangementsGroupingReducer()
            EntryArrangementsApplyReducer()
        }
    }
}

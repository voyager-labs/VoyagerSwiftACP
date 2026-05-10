import ComposableArchitecture

@Reducer
public struct EntryArrangementsFeature {
    public typealias State = EntryArrangementsState
    public typealias Action = EntryArrangementsAction

    public var body: some Reducer<State, Action> {
        CombineReducers {
            EntryArrangementsSortingReducer()
            EntryArrangementsGroupingReducer()
            EntryArrangementsApplyReducer()
        }
    }
}

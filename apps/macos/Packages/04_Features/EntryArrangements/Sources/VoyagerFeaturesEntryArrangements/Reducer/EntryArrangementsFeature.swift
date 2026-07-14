import ComposableArchitecture

@Reducer
public struct EntryArrangementsFeature {
    public typealias State = EntryArrangementsState
    public typealias Action = EntryArrangementsAction

    public init() {}

    public var body: some Reducer<State, Action> {
        CombineReducers {
            EntryArrangementsSortingReducer()
            EntryArrangementsGroupingReducer()
            EntryArrangementsApplyReducer()
        }
    }
}

import ComposableArchitecture

@Reducer
struct MenuCommandsFeature {
    typealias State = MenuCommandsState
    typealias Action = MenuCommandsAction

    var body: some Reducer<State, Action> {
        CombineReducers {
            MenuCommandsAppFeature()
            MenuCommandsEditFeature()
            MenuCommandsViewFeature()
        }
    }
}

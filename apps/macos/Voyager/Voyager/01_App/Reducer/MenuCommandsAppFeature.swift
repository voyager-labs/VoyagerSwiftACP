import ComposableArchitecture

@Reducer
struct MenuCommandsAppFeature {
    typealias State = MenuCommandsState
    typealias Action = MenuCommandsAction

    var body: some Reducer<State, Action> {
        Reduce { _, _ in
            .none
        }
    }
}

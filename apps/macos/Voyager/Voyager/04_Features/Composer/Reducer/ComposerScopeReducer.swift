import ComposableArchitecture

@Reducer
struct ComposerScopeReducer {
    @Dependency(\.searchClient)
    var searchClient

    typealias State = ComposerState
    typealias Action = ComposerAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .view(.addScope(path: path)):
                handleAddScope(state: &state, path: path, searchClient: searchClient)

            case let .view(.removeScope(path: path)):
                handleRemoveScope(state: &state, path: path, searchClient: searchClient)

            case let .view(.updateScope(oldPath: oldPath, newPath: newPath)):
                handleUpdateScope(
                    state: &state,
                    oldPath: oldPath,
                    newPath: newPath,
                    searchClient: searchClient,
                )

            case .view(.clearAll):
                handleClearAll(state: &state)

            default:
                .none
            }
        }
    }
}

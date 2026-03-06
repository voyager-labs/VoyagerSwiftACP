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
            case let .addScope(path):
                handleAddScope(state: &state, path: path, searchClient: searchClient)

            case let .removeScope(path):
                handleRemoveScope(state: &state, path: path, searchClient: searchClient)

            case let .updateScope(oldPath, newPath):
                handleUpdateScope(
                    state: &state,
                    oldPath: oldPath,
                    newPath: newPath,
                    searchClient: searchClient,
                )

            case .clearAll:
                handleClearAll(state: &state)

            default:
                .none
            }
        }
    }
}

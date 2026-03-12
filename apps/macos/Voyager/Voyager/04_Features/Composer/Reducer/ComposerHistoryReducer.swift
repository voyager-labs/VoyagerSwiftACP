import ComposableArchitecture

@Reducer
struct ComposerHistoryReducer {
    typealias State = ComposerState
    typealias Action = ComposerAction

    @Dependency(\.searchClient)
    var searchClient
    @Dependency(\.registryClient)
    var registryClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.undo):
                guard !state.isLoadingSearch else { return .none }
                let before = buildFilters(from: state)
                guard let previous = state.history.popLast() else { return .none }
                let current = FilterSnapshot(scopes: state.scopes, conditions: state.conditions)
                state.redoHistory.append(current)
                state.scopes = previous.scopes
                state.conditions = previous.conditions
                updateOperatorOptions(state: &state, registryClient: registryClient)
                let after = buildFilters(from: state)
                if before != after {
                    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
                }
                return .none

            case .view(.redo):
                guard !state.isLoadingSearch else { return .none }
                let before = buildFilters(from: state)
                guard let next = state.redoHistory.popLast() else { return .none }
                let current = FilterSnapshot(scopes: state.scopes, conditions: state.conditions)
                state.history.append(current)
                state.scopes = next.scopes
                state.conditions = next.conditions
                updateOperatorOptions(state: &state, registryClient: registryClient)
                let after = buildFilters(from: state)
                if before != after {
                    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
                }
                return .none

            default:
                return .none
            }
        }
    }
}

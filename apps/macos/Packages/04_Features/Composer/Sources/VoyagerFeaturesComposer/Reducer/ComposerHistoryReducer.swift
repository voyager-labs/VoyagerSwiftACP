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
                let current = FilterSnapshot(
                    scopeSelection: state.scopeEditor.selection,
                    conditions: state.conditions,
                    conditionDisplayByKey: state.conditionDisplayByKey,
                    includeSubfolders: state.scopeEditor.includeSubfolders,
                )
                state.redoHistory.append(current)
                state.scopeEditor.selection = previous.scopeSelection
                state.conditions = previous.conditions
                state.conditionDisplayByKey = previous.conditionDisplayByKey
                state.scopeEditor.includeSubfolders = previous.includeSubfolders
                updateOperatorOptions(state: &state, registryClient: registryClient)
                let after = buildFilters(from: state)
                if before != after, state.shouldAutoApplyScopeChange {
                    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
                }
                return .none

            case .view(.redo):
                guard !state.isLoadingSearch else { return .none }
                let before = buildFilters(from: state)
                guard let next = state.redoHistory.popLast() else { return .none }
                let current = FilterSnapshot(
                    scopeSelection: state.scopeEditor.selection,
                    conditions: state.conditions,
                    conditionDisplayByKey: state.conditionDisplayByKey,
                    includeSubfolders: state.scopeEditor.includeSubfolders,
                )
                state.history.append(current)
                state.scopeEditor.selection = next.scopeSelection
                state.conditions = next.conditions
                state.conditionDisplayByKey = next.conditionDisplayByKey
                state.scopeEditor.includeSubfolders = next.includeSubfolders
                updateOperatorOptions(state: &state, registryClient: registryClient)
                let after = buildFilters(from: state)
                if before != after, state.shouldAutoApplyScopeChange {
                    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
                }
                return .none

            default:
                return .none
            }
        }
    }
}

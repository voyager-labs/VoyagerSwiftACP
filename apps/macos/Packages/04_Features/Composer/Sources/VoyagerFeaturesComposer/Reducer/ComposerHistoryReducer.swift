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
                    conditionEditors: state.conditionEditors,
                    includeSubfolders: state.scopeEditor.includeSubfolders,
                    includeDirectories: state.includeDirectories,
                )
                state.redoHistory.append(current)
                state.scopeEditor.selection = previous.scopeSelection
                state.conditionEditors = IdentifiedArray(uniqueElements: previous.conditionEditors.map { editor in
                    var editor = editor
                    editor.resetTransientState()
                    return editor
                })
                state.scopeEditor.includeSubfolders = previous.includeSubfolders
                state.includeDirectories = previous.includeDirectories
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
                    conditionEditors: state.conditionEditors,
                    includeSubfolders: state.scopeEditor.includeSubfolders,
                    includeDirectories: state.includeDirectories,
                )
                state.history.append(current)
                state.scopeEditor.selection = next.scopeSelection
                state.conditionEditors = IdentifiedArray(uniqueElements: next.conditionEditors.map { editor in
                    var editor = editor
                    editor.resetTransientState()
                    return editor
                })
                state.scopeEditor.includeSubfolders = next.includeSubfolders
                state.includeDirectories = next.includeDirectories
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

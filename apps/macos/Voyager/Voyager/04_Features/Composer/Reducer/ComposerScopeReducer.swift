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

private func handleAddScope(
    state: inout ComposerFeature.State,
    path: String,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    guard !state.scopes.contains(path) else { return .none }
    state.pushHistory()
    if state.scopes.isEmpty || state.scopes == [ComposerScopeUtils.rootScopePath] {
        state.scopes = [path]
    } else {
        state.scopes.append(path)
    }
    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
}

private func handleRemoveScope(
    state: inout ComposerFeature.State,
    path: String,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    if state.scopes.contains(path) {
        state.pushHistory()
        state.scopes.removeAll { $0 == path }
        if state.scopes.isEmpty {
            state.scopes = [ComposerScopeUtils.rootScopePath]
        }
    }
    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
}

private func handleUpdateScope(
    state: inout ComposerFeature.State,
    oldPath: String,
    newPath: String,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    if let index = state.scopes.firstIndex(of: oldPath), oldPath != newPath {
        state.pushHistory()
        state.scopes[index] = newPath
    }
    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
}

private func handleClearAll(state: inout ComposerFeature.State) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    state.pushHistory()
    state.text = ""
    state.scopes = [ComposerScopeUtils.rootScopePath]
    state.conditions = []
    state.conditionDisplayByKey = [:]
    state.operatorOptionsByKey = [:]
    state.propertyPicker = .init()
    state.operatorPicker = .init()
    state.valuePicker = .init()
    state.isLoadingFilters = false
    state.lastFiltersResponse = nil
    applyQueryPhaseTransition(.reset, state: &state)
    return .cancel(id: ComposerFeature.CancelID.filters)
}

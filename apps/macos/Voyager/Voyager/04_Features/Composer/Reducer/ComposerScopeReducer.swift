import ComposableArchitecture
import Foundation

@Reducer
struct ComposerScopeReducer {
    typealias State = ComposerState
    typealias Action = ComposerAction

    @Dependency(\.searchClient)
    var searchClient
    @Dependency(\.entryLoadingClient)
    var entryLoadingClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .view(.scopeEditorOpen(editingPath: editingPath, favorites: favorites, backHistory: backHistory)):
                return handleScopeEditorOpen(
                    state: &state,
                    editingPath: editingPath,
                    favorites: favorites,
                    backHistory: backHistory,
                    entryLoadingClient: entryLoadingClient,
                )

            case let .view(.scopeEditorSetPresented(isPresented)):
                return handleScopeEditorPresented(
                    state: &state,
                    isPresented: isPresented,
                    entryLoadingClient: entryLoadingClient,
                )

            case let .view(.scopeEditorSetIncludeSubfolders(includeSubfolders)):
                state.scopeEditor.includeSubfolders = includeSubfolders
                return .none

            case let .view(.scopeEditorSetQueryText(queryText)):
                return handleScopeEditorQueryText(
                    state: &state,
                    queryText: queryText,
                    entryLoadingClient: entryLoadingClient,
                )

            case let .view(.candidateScope(.add(path: path))):
                return handleAddScope(
                    state: &state,
                    path: path,
                    searchClient: searchClient,
                    entryLoadingClient: entryLoadingClient,
                )

            case let .view(.currentScope(.remove(path: path))):
                return handleRemoveScope(
                    state: &state,
                    path: path,
                    searchClient: searchClient,
                    entryLoadingClient: entryLoadingClient,
                )

            case let .view(.currentScope(.replace(oldPath: oldPath, newPath: newPath))):
                return handleUpdateScope(
                    state: &state,
                    oldPath: oldPath,
                    newPath: newPath,
                    searchClient: searchClient,
                    entryLoadingClient: entryLoadingClient,
                )

            case .view(.clearAll):
                return handleClearAll(state: &state, entryLoadingClient: entryLoadingClient)

            case let .internal(.scopeEditorSeedCurrentPath(currentPath)):
                return handleScopeEditorSeedCurrentPath(state: &state, currentPath: currentPath)

            case let .internal(.scopeEditorSearchResponse(query, .success(items))):
                return handleScopeEditorSearchResponse(
                    state: &state,
                    query: query,
                    items: items,
                )

            case let .internal(.scopeEditorSearchResponse(query, .failure(error))):
                return handleScopeEditorSearchFailure(
                    state: &state,
                    query: query,
                    error: error,
                )

            default:
                return .none
            }
        }
    }
}

private func handleScopeEditorOpen(
    state: inout ComposerFeature.State,
    editingPath: String?,
    favorites: [ScopeFavoriteItem],
    backHistory: [String],
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    state.scopeEditor.favorites = favorites
    state.scopeEditor.backHistory = backHistory
    state.scopeEditor.editingPath = editingPath
    state.scopeEditor.entryMode = editingPath == nil ? .add : .edit
    state.scopeEditor.isPresented = true
    state.scopeEditor.queryText = ""
    state.scopeEditor.listState = .defaultCandidates
    state.scopeEditor.candidateItems = makeDefaultScopeEditorCandidates(
        favorites: favorites,
        backHistory: backHistory,
        entryLoadingClient: entryLoadingClient,
    )
    return .cancel(id: ComposerFeature.CancelID.scopeEditorSearch)
}

private func handleScopeEditorPresented(
    state: inout ComposerFeature.State,
    isPresented: Bool,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    if isPresented {
        state.scopeEditor.isPresented = true
        if state.scopeEditor.editingPath == nil {
            state.scopeEditor.entryMode = .add
            state.scopeEditor.queryText = ""
        } else {
            state.scopeEditor.entryMode = .edit
        }
        if state.scopeEditor.candidateItems.isEmpty {
            state.scopeEditor.candidateItems = makeDefaultScopeEditorCandidates(
                favorites: state.scopeEditor.favorites,
                backHistory: state.scopeEditor.backHistory,
                entryLoadingClient: entryLoadingClient,
            )
        }
        return .none
    }

    state.scopeEditor.isPresented = false
    state.resetScopeEditorInteractionState(clearQuery: true)
    state.scopeEditor.entryMode = .add
    state.scopeEditor.listState = .defaultCandidates
    state.scopeEditor.candidateItems = makeDefaultScopeEditorCandidates(
        favorites: state.scopeEditor.favorites,
        backHistory: state.scopeEditor.backHistory,
        entryLoadingClient: entryLoadingClient,
    )
    return .cancel(id: ComposerFeature.CancelID.scopeEditorSearch)
}

private func handleScopeEditorQueryText(
    state: inout ComposerFeature.State,
    queryText: String,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    state.scopeEditor.queryText = queryText
    let trimmedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard state.scopeEditor.isPresented else { return .none }

    if trimmedQuery.isEmpty {
        state.scopeEditor.listState = .defaultCandidates
        state.scopeEditor.candidateItems = makeDefaultScopeEditorCandidates(
            favorites: state.scopeEditor.favorites,
            backHistory: state.scopeEditor.backHistory,
            entryLoadingClient: entryLoadingClient,
        )
        return .cancel(id: ComposerFeature.CancelID.scopeEditorSearch)
    }

    state.scopeEditor.listState = .searchResults(query: trimmedQuery)
    state.scopeEditor.candidateItems = []

    return .run { [trimmedQuery, entryLoadingClient] send in
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
            try Task.checkCancellation()
            let items = try await ComposerScopeUtils.searchDirectories(
                query: trimmedQuery,
                entryLoadingClient: entryLoadingClient,
                maxResults: 50,
                initialMaxDepth: 2,
                timeout: 2.0,
            )
            try Task.checkCancellation()
            await send(.internal(.scopeEditorSearchResponse(trimmedQuery, .success(items))))
        } catch is CancellationError {
            return
        } catch {
            await send(.internal(.scopeEditorSearchResponse(trimmedQuery, .failure(error))))
        }
    }
    .cancellable(id: ComposerFeature.CancelID.scopeEditorSearch, cancelInFlight: true)
}

private func handleScopeEditorSeedCurrentPath(
    state: inout ComposerFeature.State,
    currentPath: String,
) -> Effect<ComposerFeature.Action> {
    guard state.scopeEditor.selection.isRootOnly,
          state.conditions.isEmpty,
          state.text.isEmpty
    else {
        return .none
    }

    let selection = ComposerScopeSelection.fromLegacyScopes([currentPath])
    state.scopeEditor.selection = selection
    state.scopes = selection.legacyScopePaths
    return .none
}

private func handleScopeEditorSearchResponse(
    state: inout ComposerFeature.State,
    query: String,
    items: [ComposerScopeUtils.DirectoryItem],
) -> Effect<ComposerFeature.Action> {
    guard state.scopeEditor.trimmedQueryText == query else {
        return .none
    }

    state.scopeEditor.listState = items.isEmpty ? .noResults(query: query) : .searchResults(query: query)
    state.scopeEditor.candidateItems = items.map {
        ComposerScopeEditorCandidateItem(path: $0.path, name: $0.name, iconName: $0.iconName)
    }
    return .none
}

private func handleScopeEditorSearchFailure(
    state: inout ComposerFeature.State,
    query: String,
    error _: Error,
) -> Effect<ComposerFeature.Action> {
    guard state.scopeEditor.trimmedQueryText == query else {
        return .none
    }

    state.scopeEditor.listState = .noResults(query: query)
    state.scopeEditor.candidateItems = []
    return .none
}

private func handleAddScope(
    state: inout ComposerFeature.State,
    path: String,
    searchClient: SearchClient,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
    let currentPaths = state.scopeEditor.selection.legacyScopePaths
    let canonicalPaths = collapseScopePaths(existing: currentPaths, adding: normalizedPath)
    guard canonicalPaths != currentPaths else {
        return settleScopeEditorAfterSelectionChange(
            state: &state,
            entryLoadingClient: entryLoadingClient,
        )
    }
    state.pushHistory()
    let selection = ComposerScopeSelection.fromLegacyScopes(canonicalPaths)
    state.scopeEditor.selection = selection
    state.scopes = selection.legacyScopePaths
    let settleEffect = settleScopeEditorAfterSelectionChange(
        state: &state,
        entryLoadingClient: entryLoadingClient,
    )
    guard state.shouldAutoApplyScopeChange else {
        return settleEffect
    }
    let filterEffect = applyFiltersIfNeeded(state: &state, searchClient: searchClient)
    return .merge(settleEffect, filterEffect)
}

private func handleRemoveScope(
    state: inout ComposerFeature.State,
    path: String,
    searchClient: SearchClient,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
    let currentPaths = state.scopeEditor.selection.legacyScopePaths
    guard currentPaths.contains(normalizedPath) else { return .none }

    state.pushHistory()
    let updatedPaths = currentPaths.filter { $0 != normalizedPath }
    let selection = ComposerScopeSelection.fromLegacyScopes(updatedPaths)
    state.scopeEditor.selection = selection
    state.scopes = selection.legacyScopePaths
    if state.scopeEditor.editingPath == normalizedPath {
        state.resetScopeEditorInteractionState(clearQuery: false)
    }
    let settleEffect = settleScopeEditorAfterSelectionChange(
        state: &state,
        entryLoadingClient: entryLoadingClient,
    )
    guard state.shouldAutoApplyScopeChange else {
        return settleEffect
    }
    let filterEffect = applyFiltersIfNeeded(state: &state, searchClient: searchClient)
    return .merge(settleEffect, filterEffect)
}

private func handleUpdateScope(
    state: inout ComposerFeature.State,
    oldPath: String,
    newPath: String,
    searchClient: SearchClient,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    let normalizedOldPath = ComposerScopeUtils.normalizeScopePath(oldPath)
    let normalizedNewPath = ComposerScopeUtils.normalizeScopePath(newPath)
    var currentPaths = state.scopeEditor.selection.legacyScopePaths
    guard let index = currentPaths.firstIndex(of: normalizedOldPath), normalizedOldPath != normalizedNewPath else {
        return .none
    }

    state.pushHistory()
    var updatedPaths = currentPaths
    updatedPaths[index] = normalizedNewPath
    let selection = ComposerScopeSelection.fromLegacyScopes(
        collapseScopePaths(existing: updatedPaths, adding: normalizedNewPath),
    )
    state.scopeEditor.selection = selection
    state.scopes = selection.legacyScopePaths
    if state.scopeEditor.editingPath == normalizedOldPath {
        state.scopeEditor.editingPath = normalizedNewPath
        state.scopeEditor.entryMode = .edit
    }
    let settleEffect = settleScopeEditorAfterSelectionChange(
        state: &state,
        entryLoadingClient: entryLoadingClient,
    )
    guard state.shouldAutoApplyScopeChange else {
        return settleEffect
    }
    let filterEffect = applyFiltersIfNeeded(state: &state, searchClient: searchClient)
    return .merge(settleEffect, filterEffect)
}

private func handleClearAll(
    state: inout ComposerFeature.State,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    state.pushHistory()
    state.text = ""
    state.scopeEditor.selection = .rootOnly
    state.scopes = [ComposerScopeUtils.rootScopePath]
    state.scopeEditor.isPresented = false
    state.resetScopeEditorInteractionState(clearQuery: true)
    state.scopeEditor.entryMode = .add
    state.scopeEditor.listState = .defaultCandidates
    state.scopeEditor.candidateItems = makeDefaultScopeEditorCandidates(
        favorites: state.scopeEditor.favorites,
        backHistory: state.scopeEditor.backHistory,
        entryLoadingClient: entryLoadingClient,
    )
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

private func settleScopeEditorAfterSelectionChange(
    state: inout ComposerFeature.State,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    state.scopeEditor.isPresented = true
    state.scopeEditor.entryMode = state.scopeEditor.editingPath == nil ? .add : .edit
    if state.scopeEditor.trimmedQueryText.isEmpty {
        state.scopeEditor.listState = .defaultCandidates
        state.scopeEditor.candidateItems = makeDefaultScopeEditorCandidates(
            favorites: state.scopeEditor.favorites,
            backHistory: state.scopeEditor.backHistory,
            entryLoadingClient: entryLoadingClient,
        )
    }
    return .cancel(id: ComposerFeature.CancelID.scopeEditorSearch)
}

private func collapseScopePaths(existing: [String], adding candidate: String) -> [String] {
    let normalizedCandidate = ComposerScopeUtils.normalizeScopePath(candidate)
    var result: [String] = []

    func isAncestorOrSame(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        if lhs == ComposerScopeUtils.rootScopePath { return true }
        return rhs.hasPrefix(lhs + "/")
    }

    for path in existing.map(ComposerScopeUtils.normalizeScopePath) {
        if isAncestorOrSame(path, normalizedCandidate) || isAncestorOrSame(normalizedCandidate, path) {
            continue
        }
        if !result.contains(path) {
            result.append(path)
        }
    }

    if !result.contains(normalizedCandidate) {
        result.append(normalizedCandidate)
    }

    return result
}

private func makeDefaultScopeEditorCandidates(
    favorites: [ScopeFavoriteItem],
    backHistory: [String],
    entryLoadingClient: EntryLoadingClient,
) -> [ComposerScopeEditorCandidateItem] {
    ComposerScopeUtils.buildCombinedList(
        history: backHistory,
        favorites: favorites,
        entryLoadingClient: entryLoadingClient,
        maxCount: 10,
    )
    .map {
        ComposerScopeEditorCandidateItem(path: $0.path, name: $0.name, iconName: $0.iconName)
    }
}

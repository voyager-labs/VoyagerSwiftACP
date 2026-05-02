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
                    searchClient: searchClient,
                    entryLoadingClient: entryLoadingClient,
                )

            case let .view(.scopeEditorSetIncludeSubfolders(includeSubfolders)):
                state.scopeEditor.includeSubfolders = includeSubfolders
                state.scopeEditor.selection = ComposerScopeSelection.fromCanonicalScopes(
                    bases: state.scopeEditor.selection.explicitBases.map(\.path),
                    exceptions: state.scopeEditor.selection.exceptions.map(\.path),
                    includeSubfolders: includeSubfolders,
                )
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

            case let .view(.exceptionScope(.exclude(path: path))):
                return handleExcludeScope(
                    state: &state,
                    path: path,
                    entryLoadingClient: entryLoadingClient,
                )

            case let .view(.exceptionScope(.restore(path: path))):
                return handleRestoreScope(
                    state: &state,
                    path: path,
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
    let shouldSeedCommittedScopeRule = !state.scopeEditor.isPresented
    let committedSelection = state.collectionContext
        .map {
            ComposerScopeSelection.fromCanonicalScopes(
                bases: $0.scopes,
                exceptions: $0.excludedScopes,
                includeSubfolders: $0.includeSubfolders,
            )
        }
        ?? state.scopeEditor.selection
    let committedIncludeSubfolders = state.collectionContext?.includeSubfolders
        ?? state.scopeEditor.includeSubfolders

    state.scopeEditor.favorites = favorites
    state.scopeEditor.backHistory = backHistory
    state.scopeEditor.editingPath = editingPath
    state.scopeEditor.entryMode = editingPath == nil ? .add : .edit
    if shouldSeedCommittedScopeRule {
        state.scopeEditor.selection = committedSelection
        state.scopeEditor.includeSubfolders = committedIncludeSubfolders
        state.scopeEditor.committedSelection = committedSelection
        state.scopeEditor.committedIncludeSubfolders = committedIncludeSubfolders
    }
    state.scopeEditor.isPresented = true
    state.scopeEditor.queryText = ""
    seedScopeEditorCandidatesForCurrentMode(state: &state, entryLoadingClient: entryLoadingClient)
    return .cancel(id: ComposerFeature.CancelID.scopeEditorSearch)
}

private func handleScopeEditorPresented(
    state: inout ComposerFeature.State,
    isPresented: Bool,
    searchClient _: SearchClient,
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
            seedScopeEditorCandidatesForCurrentMode(state: &state, entryLoadingClient: entryLoadingClient)
        }
        return .none
    }

    let shouldReapplyFilters = state.shouldAutoApplyScopeChange
        && state.scopeEditor.hasPendingScopeRuleChanges

    state.scopeEditor.isPresented = false
    state.resetScopeEditorInteractionState(clearQuery: true)
    state.scopeEditor.entryMode = .add
    state.scopeEditor.listState = .defaultCandidates
    state.scopeEditor.candidateItems = makeDefaultScopeEditorCandidates(
        favorites: state.scopeEditor.favorites,
        backHistory: state.scopeEditor.backHistory,
        entryLoadingClient: entryLoadingClient,
    )
    let dismissEffect = Effect<ComposerFeature.Action>.cancel(id: ComposerFeature.CancelID.scopeEditorSearch)
    guard shouldReapplyFilters else {
        return dismissEffect
    }

    return .merge(dismissEffect, reexecuteCurrentCollectionSearch(state: &state))
}

private func reexecuteCurrentCollectionSearch(
    state: inout ComposerFeature.State,
) -> Effect<ComposerFeature.Action> {
    let query = state.pendingSearchQuery
        ?? state.collectionContext?.query
        ?? state.text
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
        return .send(.applyFilters)
    }

    state.text = trimmedQuery
    state.pendingSearchQuery = trimmedQuery
    return .send(.submit)
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
        seedScopeEditorCandidatesForCurrentMode(state: &state, entryLoadingClient: entryLoadingClient)
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

    let disambiguatedItems = ComposerScopeUtils.applyCandidateDisambiguationPolicy(items)
    state.scopeEditor.listState = disambiguatedItems.isEmpty ? .noResults(query: query) : .searchResults(query: query)
    state.scopeEditor.candidateItems = disambiguatedItems.map {
        ComposerScopeEditorCandidateItem(
            path: $0.path,
            name: $0.name,
            iconName: $0.iconName,
            locationIdentifier: $0.locationIdentifier,
            secondaryText: $0.secondaryText,
        )
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
    searchClient _: SearchClient,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
    let currentBases = state.scopeEditor.selection.explicitBases.map(\.path)
    let currentExceptions = state.scopeEditor.selection.exceptions.map(\.path)
    let selection = ComposerScopeSelection.fromCanonicalScopes(
        bases: collapseScopePaths(existing: currentBases, adding: normalizedPath),
        exceptions: currentExceptions,
        includeSubfolders: state.scopeEditor.includeSubfolders,
    )
    guard selection != state.scopeEditor.selection else {
        return settleScopeEditorAfterSelectionChange(
            state: &state,
            entryLoadingClient: entryLoadingClient,
        )
    }
    state.pushHistory()
    state.scopeEditor.selection = selection
    let settleEffect = settleScopeEditorAfterSelectionChange(
        state: &state,
        entryLoadingClient: entryLoadingClient,
    )
    return settleEffect
}

private func handleRemoveScope(
    state: inout ComposerFeature.State,
    path: String,
    searchClient _: SearchClient,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
    let currentBases = state.scopeEditor.selection.explicitBases.map(\.path)
    guard currentBases.contains(normalizedPath) else { return .none }

    state.pushHistory()
    let updatedBases = currentBases.filter { $0 != normalizedPath }
    let selection = ComposerScopeSelection.fromCanonicalScopes(
        bases: updatedBases,
        exceptions: state.scopeEditor.selection.exceptions.map(\.path),
        includeSubfolders: state.scopeEditor.includeSubfolders,
    )
    state.scopeEditor.selection = selection
    if state.scopeEditor.editingPath == normalizedPath {
        state.resetScopeEditorInteractionState(clearQuery: false)
    }
    let settleEffect = settleScopeEditorAfterSelectionChange(
        state: &state,
        entryLoadingClient: entryLoadingClient,
    )
    return settleEffect
}

private func handleUpdateScope(
    state: inout ComposerFeature.State,
    oldPath: String,
    newPath: String,
    searchClient _: SearchClient,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    let normalizedOldPath = ComposerScopeUtils.normalizeScopePath(oldPath)
    let normalizedNewPath = ComposerScopeUtils.normalizeScopePath(newPath)
    let currentBases = state.scopeEditor.selection.explicitBases.map(\.path)
    guard let index = currentBases.firstIndex(of: normalizedOldPath), normalizedOldPath != normalizedNewPath else {
        return .none
    }

    state.pushHistory()
    var updatedBases = currentBases
    updatedBases[index] = normalizedNewPath
    let selection = ComposerScopeSelection.fromCanonicalScopes(
        bases: collapseScopePaths(existing: updatedBases, adding: normalizedNewPath),
        exceptions: state.scopeEditor.selection.exceptions.map(\.path),
        includeSubfolders: state.scopeEditor.includeSubfolders,
    )
    state.scopeEditor.selection = selection
    if state.scopeEditor.editingPath == normalizedOldPath {
        state.scopeEditor.editingPath = normalizedNewPath
        state.scopeEditor.entryMode = .edit
    }
    let settleEffect = settleScopeEditorAfterSelectionChange(
        state: &state,
        entryLoadingClient: entryLoadingClient,
    )
    return settleEffect
}

private func handleExcludeScope(
    state: inout ComposerFeature.State,
    path: String,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    guard !state.scopeEditor.selection.isRootOnly else { return settleScopeEditorAfterSelectionChange(
        state: &state,
        entryLoadingClient: entryLoadingClient,
    ) }

    let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
    let selection = ComposerScopeSelection.fromCanonicalScopes(
        bases: state.scopeEditor.selection.explicitBases.map(\.path),
        exceptions: state.scopeEditor.selection.exceptions.map(\.path) + [normalizedPath],
        includeSubfolders: state.scopeEditor.includeSubfolders,
    )
    guard selection != state.scopeEditor.selection else {
        return settleScopeEditorAfterSelectionChange(
            state: &state,
            entryLoadingClient: entryLoadingClient,
        )
    }

    state.pushHistory()
    state.scopeEditor.selection = selection
    return settleScopeEditorAfterSelectionChange(
        state: &state,
        entryLoadingClient: entryLoadingClient,
    )
}

private func handleRestoreScope(
    state: inout ComposerFeature.State,
    path: String,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    guard !state.scopeEditor.selection.isRootOnly else { return settleScopeEditorAfterSelectionChange(
        state: &state,
        entryLoadingClient: entryLoadingClient,
    ) }

    let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
    let remainingExceptions = state.scopeEditor.selection.exceptions.map(\.path).filter { $0 != normalizedPath }
    let selection = ComposerScopeSelection.fromCanonicalScopes(
        bases: state.scopeEditor.selection.explicitBases.map(\.path),
        exceptions: remainingExceptions,
        includeSubfolders: state.scopeEditor.includeSubfolders,
    )
    guard selection != state.scopeEditor.selection else {
        return settleScopeEditorAfterSelectionChange(
            state: &state,
            entryLoadingClient: entryLoadingClient,
        )
    }

    state.pushHistory()
    state.scopeEditor.selection = selection
    return settleScopeEditorAfterSelectionChange(
        state: &state,
        entryLoadingClient: entryLoadingClient,
    )
}

private func handleClearAll(
    state: inout ComposerFeature.State,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    state.pushHistory()
    state.text = ""
    state.scopeEditor.selection = .rootOnly
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
        seedScopeEditorCandidatesForCurrentMode(state: &state, entryLoadingClient: entryLoadingClient)
    }
    return .cancel(id: ComposerFeature.CancelID.scopeEditorSearch)
}

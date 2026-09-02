import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

func seedScopeEditorTreeNeighborhoodForCurrentMode(
    state: inout ComposerFeature.State,
    entryLoadingClient: EntryLoadingClient,
) {
    guard state.scopeEditor.entryMode == .edit else {
        state.scopeEditor.treeNeighborhoodSeedItems = []
        return
    }

    state.scopeEditor.treeNeighborhoodSeedItems = ComposerScopeTreeNeighborhoodCandidates.make(
        editingPath: state.scopeEditor.editingPath,
        selection: state.scopeEditor.selection,
        entryLoadingClient: entryLoadingClient,
    )
}

func collapseScopePaths(existing: [String], adding candidate: String) -> [String] {
    let normalizedCandidate = ComposerScopeUtils.normalizeScopePath(candidate)
    var result: [String] = []

    for path in existing.map(ComposerScopeUtils.normalizeScopePath) where !result.contains(path) {
        result.append(path)
    }

    if !result.contains(normalizedCandidate) {
        result.append(normalizedCandidate)
    }

    return result
}

func seedScopeEditorCandidatesForCurrentMode(
    state: inout ComposerFeature.State,
    entryLoadingClient: EntryLoadingClient,
) {
    if state.scopeEditor.entryMode == .edit,
       let editingPath = state.scopeEditor.editingPath
    {
        let normalizedEditingPath = ComposerScopeUtils.normalizeScopePath(editingPath)
        state.scopeEditor.listState = .childFolders(parentPath: normalizedEditingPath)
        state.scopeEditor.candidateItems = makeChildScopeEditorCandidates(
            parentPath: normalizedEditingPath,
            entryLoadingClient: entryLoadingClient,
        )
        seedScopeEditorTreeNeighborhoodForCurrentMode(state: &state, entryLoadingClient: entryLoadingClient)
        return
    }

    state.scopeEditor.listState = .defaultCandidates
    state.scopeEditor.candidateItems = makeDefaultScopeEditorCandidates(
        favorites: state.scopeEditor.favorites,
        backHistory: state.scopeEditor.backHistory,
        entryLoadingClient: entryLoadingClient,
    )
    state.scopeEditor.treeNeighborhoodSeedItems = []
}

func makeChildScopeEditorCandidates(
    parentPath: String,
    entryLoadingClient: EntryLoadingClient,
) -> [ComposerScopeEditorCandidateItem] {
    ComposerScopeChildDirectoryCandidates.make(
        parentPath: parentPath,
        entryLoadingClient: entryLoadingClient,
    )
    .map {
        ComposerScopeEditorCandidateItem(
            path: $0.path,
            name: $0.name,
            iconName: $0.iconName,
            locationIdentifier: $0.locationIdentifier,
            secondaryText: $0.secondaryText,
        )
    }
}

func makeDefaultScopeEditorCandidates(
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
        ComposerScopeEditorCandidateItem(
            path: $0.path,
            name: $0.name,
            iconName: $0.iconName,
            locationIdentifier: $0.locationIdentifier,
            secondaryText: $0.secondaryText,
        )
    }
}

func scopeChangeSnapshot(state: ComposerFeature.State) -> ComposerScopeSnapshot {
    ComposerScopeSnapshot(
        scopeSelection: state.scopeEditor.selection,
        includeSubfolders: state.scopeEditor.includeSubfolders,
    )
}

func recordScopeChangeFeedback(
    state: inout ComposerFeature.State,
    beforeScope: ComposerScopeSnapshot,
    origin: ComposerScopeChangeFeedbackOrigin,
) {
    state.lastScopeChangeFeedback = ComposerScopeChangeFeedback(
        id: UUID(),
        beforeScope: beforeScope,
        afterScope: scopeChangeSnapshot(state: state),
        origin: origin,
        phase: .visible,
        pendingResultRequest: nil,
        historyDepthAfterCommit: state.history.count,
        redoDepthAfterCommit: state.redoHistory.count,
    )
}

func handleClearAll(
    state: inout ComposerFeature.State,
    entryLoadingClient: EntryLoadingClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }

    state.pushHistory()
    state.replaceTextAndDiscardQueryRecovery("")
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
    state.scopeEditor.treeNeighborhoodSeedItems = []
    state.conditionEditors = []
    state.includeDirectories = false
    state.propertyPicker = .init()
    state.valuePicker = .init()
    state.isLoadingFilters = false
    state.isFilteringInFlight = false
    state.activeFiltersRequestID = nil
    state.lastAcceptedFiltersRequestID = nil
    state.filtersStartedAt = nil
    state.activeFiltersMetricSource = nil
    state.lastFiltersResponse = nil
    state.lastScopeChangeFeedback = nil
    applyQueryPhaseTransition(.reset, state: &state)
    return .cancel(id: ComposerFeature.CancelID.filters(ownerID: state.cancellationOwnerID))
}

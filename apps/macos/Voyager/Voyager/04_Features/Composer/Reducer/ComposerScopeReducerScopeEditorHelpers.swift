import ComposableArchitecture
import Foundation

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
        return
    }

    state.scopeEditor.listState = .defaultCandidates
    state.scopeEditor.candidateItems = makeDefaultScopeEditorCandidates(
        favorites: state.scopeEditor.favorites,
        backHistory: state.scopeEditor.backHistory,
        entryLoadingClient: entryLoadingClient,
    )
}

func makeChildScopeEditorCandidates(
    parentPath: String,
    entryLoadingClient: EntryLoadingClient,
) -> [ComposerScopeEditorCandidateItem] {
    ComposerScopeUtils.applyCandidateDisambiguationPolicy(
        ComposerScopeChildDirectoryCandidates.make(
            parentPath: parentPath,
            entryLoadingClient: entryLoadingClient,
        ),
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
    ComposerScopeUtils.applyCandidateDisambiguationPolicy(
        ComposerScopeUtils.buildCombinedList(
            history: backHistory,
            favorites: favorites,
            entryLoadingClient: entryLoadingClient,
            maxCount: 10,
        ),
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

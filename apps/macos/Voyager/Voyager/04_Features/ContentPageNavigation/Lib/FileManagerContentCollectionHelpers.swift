import ComposableArchitecture
import Foundation

func exitCollectionMode(
    state: inout FileManagerContentState,
    computerName: String,
) -> Effect<FileManagerContentAction> {
    let wasCollection = if case .collection = state.navigation.navigationState { true } else { false }
    let clearEffect = clearCollectionMode(state: &state)

    guard wasCollection else {
        return clearEffect
    }

    state.navigation.navigationState = FileManagerNavigationUtils.navigationStateFromPath(
        state.navigation.titlePath,
        computerName: computerName,
    )
    return clearEffect
}

func makeCollectionNavigation(
    state: FileManagerContentState,
) -> FileManagerNavigationUtils.CollectionNavigation {
    let kind: FileManagerNavigationUtils.CollectionKind
    if let url = state.collectionSession.openedURL {
        let name = state.collectionSession.openedName ?? url.deletingPathExtension().lastPathComponent
        kind = .file(url: url, name: name)
    } else {
        kind = .temporary
    }

    let context = state.collectionContext
        ?? CollectionContext(query: "", scopes: [], conditions: [])
    return FileManagerNavigationUtils.CollectionNavigation(
        kind: kind,
        context: context,
        sortKey: state.entryArrangements.sortKey,
        sortOrder: state.entryArrangements.sortOrder,
        viewLayout: state.viewLayout,
    )
}

func clearCollectionMode(state: inout FileManagerContentState) -> Effect<FileManagerContentAction> {
    state.collectionContext = nil
    state.pendingSearchQuery = nil
    state.collectionSession = .init()
    state.navigation.pendingNavigation = nil
    state.entries.collectionItems = []
    state.syncComposerCollectionState()
    return .merge(
        .cancel(id: "openCollectionFile"),
        .cancel(id: ComposerFeature.CancelID.search),
        .cancel(id: ComposerFeature.CancelID.filters),
        .send(.entries(.setCollectionMode(false))),
    )
}

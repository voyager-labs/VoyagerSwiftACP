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

    state.navigation.navigationState = ContentPageNavigationUtils.navigationStateFromPath(
        state.navigation.titlePath,
        computerName: computerName,
    )
    return clearEffect
}

func makeCollectionNavigation(
    state: FileManagerContentState,
) -> ContentPageNavigationUtils.CollectionNavigation {
    let kind: ContentPageNavigationUtils.CollectionKind
    if let url = state.collectionSession.openedURL {
        let name = state.collectionSession.openedName ?? url.deletingPathExtension().lastPathComponent
        kind = .file(url: url, name: name)
    } else {
        kind = .temporary
    }

    let context = state.collectionContext
        ?? CollectionContext(query: "", scopes: [], conditions: [])
    return ContentPageNavigationUtils.CollectionNavigation(
        kind: kind,
        context: context,
        sortKey: state.entryArrangements.sortKey,
        sortOrder: state.entryArrangements.sortOrder,
        viewLayout: state.viewLayout,
    )
}

func clearCollectionMode(state: inout FileManagerContentState) -> Effect<FileManagerContentAction> {
    state.collectionContext = nil
    state.composer.pendingSearchQuery = nil
    state.collectionSession = .init()
    state.navigation.pendingNavigation = nil
    state.entryOperations.loadingContext.collectionItems = []
    state.syncComposerCollectionState()
    return .merge(
        .cancel(id: "openCollectionFile"),
        .cancel(id: ComposerFeature.CancelID.search),
        .cancel(id: ComposerFeature.CancelID.filters),
        .send(.entries(.setCollectionMode(false))),
        .send(.entries(.clearCollectionItems)),
    )
}

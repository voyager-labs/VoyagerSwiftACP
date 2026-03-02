import ComposableArchitecture
import Foundation

extension FileManagerContentState {
    mutating func exitCollectionMode(
        computerName: String,
    ) -> Effect<FileManagerContentAction> {
        let wasCollection = if case .collection = navigation.navigationState { true } else { false }
        let clearEffect = clearCollectionMode()

        guard wasCollection else {
            return clearEffect
        }

        let navigationState = ContentPageNavigationRoute.fromPath(
            navigation.titlePath,
            computerName: computerName,
        )

        return .concatenate(
            .send(.requestNavigation(.internal(.setNavigationState(navigationState)))),
            clearEffect,
        )
    }

    func makeCollectionNavigation() -> ContentPageCollectionNavigation {
        let kind: ContentPageCollectionKind
        if let url = collectionSession.openedURL {
            let name = collectionSession.openedName ?? url.deletingPathExtension().lastPathComponent
            kind = .file(url: url, name: name)
        } else {
            kind = .temporary
        }

        let context = collectionContext
            ?? CollectionContext(query: "", scopes: [], conditions: [])

        return ContentPageCollectionNavigation(
            kind: kind,
            context: context,
            sortKey: entryArrangements.sortKey,
            sortOrder: entryArrangements.sortOrder,
            viewLayout: viewLayout,
        )
    }

    mutating func clearCollectionMode() -> Effect<FileManagerContentAction> {
        collectionContext = nil
        composer.pendingSearchQuery = nil
        collectionSession = .init()
        entryOperations.loadingContext.collectionItems = []
        syncComposerCollectionState()

        return .merge(
            .send(.requestNavigation(.internal(.setPendingNavigation(nil)))),
            .cancel(id: "openCollectionFile"),
            .cancel(id: ComposerFeature.CancelID.search),
            .cancel(id: ComposerFeature.CancelID.filters),
            .send(.entries(.setCollectionMode(false))),
            .send(.entries(.clearCollectionItems)),
        )
    }
}

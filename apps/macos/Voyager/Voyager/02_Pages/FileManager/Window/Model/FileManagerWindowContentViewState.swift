import Foundation

struct FileManagerWindowContentViewState: Equatable {
    let isComposerPresented: Bool
    let favorites: [ScopeFavoriteItem]
    let historyPaths: [String]
    let isDiscardEnabled: Bool
    let canSaveCollection: Bool
    let isTemporaryCollection: Bool

    init(state: FileManagerFeature.State) {
        isComposerPresented = state.composer.isPresented
        favorites = state.favorites.map { favorite in
            ScopeFavoriteItem(
                name: favorite.name,
                url: favorite.url,
                iconName: favorite.iconName,
            )
        }
        historyPaths = state.backHistory.compactMap { entry in
            if case let .folder(path) = entry.navigationState {
                return path
            }
            return nil
        }
        isDiscardEnabled = state.entries.isCollectionMode
            && state.openedCollectionBaseline != nil
            && state.isOpenedCollectionDirty
        canSaveCollection = state.canSaveCollection
        isTemporaryCollection = state.openedCollectionURL == nil
    }
}

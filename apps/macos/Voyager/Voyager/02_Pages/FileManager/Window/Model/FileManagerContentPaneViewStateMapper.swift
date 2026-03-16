import Foundation

enum FileManagerContentPaneViewStateMapper {
    static func map(_ state: FileManagerWindowState) -> FileManagerContentPaneViewState {
        FileManagerContentPaneViewState(
            isComposerPresented: state.content.composer.isPresented,
            favorites: state.sidebar.favorites.map { favorite in
                ScopeFavoriteItem(
                    name: favorite.name,
                    url: favorite.url,
                    iconName: favorite.iconName,
                )
            },
            historyPaths: state.content.navigation.backHistory.compactMap { entry in
                if case let .folder(path) = entry.navigationState {
                    return path
                }
                return nil
            },
            isDiscardEnabled: state.content.entryOperations.loadingContext.isCollectionMode
                && state.content.collectionSession.baseline != nil
                && state.content.isOpenedCollectionDirty,
            canSaveCollection: state.content.canSaveCollection,
            isTemporaryCollection: state.content.collectionSession.openedURL == nil,
        )
    }
}

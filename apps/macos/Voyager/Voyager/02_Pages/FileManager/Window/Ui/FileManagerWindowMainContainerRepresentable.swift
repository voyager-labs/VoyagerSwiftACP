import ComposableArchitecture
import SwiftUI

struct FileManagerMainContainerRepresentable: NSViewControllerRepresentable {
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool

    func makeNSViewController(context _: Context) -> FileManagerMainContainerSplitController {
        FileManagerMainContainerSplitController(
            store: store,
            isDark: isDark,
        )
    }

    func updateNSViewController(
        _ nsViewController: FileManagerMainContainerSplitController,
        context _: Context,
    ) {
        nsViewController.updateAppearance(isDark: isDark)
    }

    static func dismantleNSViewController(
        _ nsViewController: FileManagerMainContainerSplitController,
        coordinator _: Void,
    ) {
        nsViewController.tearDown()
    }
}

extension FileManagerContentPaneViewState {
    static func from(windowState state: FileManagerWindowState) -> Self {
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
            isDiscardEnabled: state.content.entries.isCollectionMode
                && state.content.collectionSession.baseline != nil
                && state.content.isOpenedCollectionDirty,
            canSaveCollection: state.content.canSaveCollection,
            isTemporaryCollection: state.content.collectionSession.openedURL == nil,
        )
    }
}

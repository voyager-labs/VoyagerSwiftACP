@preconcurrency import AppKit
import VoyagerEntitiesTag
import VoyagerFeaturesEntryOperations

extension EntryGridCoordinator: EntryGridView.EntryGridCollectionViewMenuProviding {
    func contextMenu(for indexPath: IndexPath?, event: NSEvent) -> NSMenu {
        updateContextMenuAnchor(event)
        let rowEntry = entry(at: indexPath)
        let selectedEntries = selectedEntries(rowEntry: rowEntry)
        preloadOpenWithApplications(selectedEntries: selectedEntries)
        let menuSpec = EntryContextMenuSpecFactory.make(
            selectedIds: state.selectedIds,
            selectedEntries: selectedEntries,
            rowEntry: rowEntry,
            isTrashFolder: isTrashFolder,
            canPaste: !state.entryOperations.clipboardItems.isEmpty,
            favoriteTags: finderFavoritesTagClient.favoriteTags(),
            openWithApplications: openWithApplications(selectedEntries: selectedEntries),
        )
        let coordinator = EntryContextMenuCoordinator(store: store, rowEntry: rowEntry)
        contextMenuCoordinator = coordinator
        return EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: menuSpec.selectedCount,
            rowEntryPathForOpenInNewWindow: menuSpec.rowEntryPathForOpenInNewWindow,
            canPaste: menuSpec.canPaste,
            showCompress: menuSpec.showCompress,
            showExtract: menuSpec.showExtract,
            isTrashFolder: menuSpec.isTrashFolder,
            openWithApplications: menuSpec.openWithApplications,
            showOpenWith: menuSpec.showOpenWith,
            tags: menuSpec.tags,
        ))
    }
}

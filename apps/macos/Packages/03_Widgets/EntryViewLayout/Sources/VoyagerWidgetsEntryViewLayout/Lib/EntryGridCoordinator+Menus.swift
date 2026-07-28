@preconcurrency import AppKit
import VoyagerEntitiesTag

extension EntryGridCoordinator: EntryGridView.EntryGridCollectionViewMenuProviding {
    func contextMenu(for indexPath: IndexPath?, event: NSEvent) -> NSMenu {
        updateContextMenuAnchor(event)
        let rowEntry = entry(at: indexPath)
        let target = EntryContextMenuTarget.resolve(
            displayEntries: state.entries,
            selectedIds: state.selectedIds,
            rowEntry: rowEntry,
        )
        synchronizeContextMenuSelection(target)
        preloadOpenWithApplications(selectedEntries: target.entries)
        let menuSpec = EntryContextMenuSpecFactory.make(
            selectedIds: target.selectedIds,
            selectedEntries: target.entries,
            rowEntry: rowEntry,
            isTrashFolder: isTrashFolder,
            restorableTrashPaths: state.restorableTrashPaths,
            canPaste: !state.clipboardCutPaths.isEmpty,
            favoriteTags: finderFavoritesTagClient.favoriteTags(),
            openWithApplications: openWithApplications(selectedEntries: target.entries),
        )
        let coordinator = EntryContextMenuCoordinator(
            store: store,
            target: target,
            anchorView: collectionView,
            anchorScreenPoint: contextMenuAnchor,
        )
        contextMenuCoordinator = coordinator
        return EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: menuSpec.selectedCount,
            rowEntryPathForOpenInNewWindow: menuSpec.rowEntryPathForOpenInNewWindow,
            canPaste: menuSpec.canPaste,
            showCompress: menuSpec.showCompress,
            showExtract: menuSpec.showExtract,
            isTrashFolder: menuSpec.isTrashFolder,
            canPutBack: menuSpec.canPutBack,
            openWithApplications: menuSpec.openWithApplications,
            showOpenWith: menuSpec.showOpenWith,
            paletteTags: menuSpec.paletteTags,
            knownTags: menuSpec.knownTags,
            canPerformEntryCommands: (!state.isLoading || state.isCollectionMode)
                && !target.containsBusyEntry(busyEntryPaths: state.busyEntryPaths),
        ))
    }

    private func synchronizeContextMenuSelection(_ target: EntryContextMenuTarget) {
        guard state.selectedIds != target.selectedIds else { return }
        _ = MainActor.assumeIsolated {
            store.send(.view(.updateSelection(
                ids: target.selectedIds,
                lastSelectedId: target.entries.last?.id,
                rangeAnchorId: target.entries.last?.id,
                shouldScrollToSelection: false,
            )))
        }
    }
}

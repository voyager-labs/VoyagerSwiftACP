@preconcurrency import AppKit
import UniformTypeIdentifiers
import VoyagerEntitiesTag
import VoyagerFeaturesEntryOperations

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
        let serviceNames = gridContextMenuServiceNames()
        let menuSpec = EntryContextMenuSpecFactory.make(
            selectedIds: target.selectedIds,
            selectedEntries: target.entries,
            rowEntry: rowEntry,
            isTrashFolder: isTrashFolder,
            restorableTrashPaths: state.entryOperations.restorableTrashPaths,
            canPaste: !state.entryOperations.clipboardItems.isEmpty,
            favoriteTags: finderFavoritesTagClient.favoriteTags(),
            openWithApplications: openWithApplications(selectedEntries: target.entries),
            isOpenWithApplicationsLoading: target.entries.contains { entry in
                guard !entry.isFolder else { return false }
                let typeID = UTType(filenameExtension: entry.fileExtension)?.identifier ?? UTType.data.identifier
                return state.entryOperations.openWithInFlightTypeIDs.contains(typeID)
                    || state.entryOperations.applicationsForTypes[typeID] == nil
            },
            serviceNames: serviceNames,
        )
        let coordinator = EntryContextMenuCoordinator(
            store: store,
            target: target,
            anchorView: collectionView,
            anchorScreenPoint: contextMenuAnchor,
        )
        contextMenuCoordinator = coordinator
        return coordinator.observeOpenWithMenu(EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: menuSpec.selectedCount,
            rowEntryPathForOpenInNewWindow: menuSpec.rowEntryPathForOpenInNewWindow,
            openInNewTabPaths: menuSpec.openInNewTabPaths,
            serviceNames: menuSpec.serviceNames,
            canPaste: menuSpec.canPaste,
            showCompress: menuSpec.showCompress,
            showExtract: menuSpec.showExtract,
            isTrashFolder: menuSpec.isTrashFolder,
            canPutBack: menuSpec.canPutBack,
            openWithApplications: menuSpec.openWithApplications,
            showOpenWith: menuSpec.showOpenWith,
            paletteTags: menuSpec.paletteTags,
            knownTags: menuSpec.knownTags,
            canPerformEntryCommands: (!state.entryOperations.isLoading || state.isCollectionMode)
                && !target.containsBusyEntry(itemStates: state.entryOperations.itemStates),
            isOpenWithApplicationsLoading: menuSpec.isOpenWithApplicationsLoading,
        )))
    }

    private func synchronizeContextMenuSelection(_ target: EntryContextMenuTarget) {
        guard state.selectedIds != target.selectedIds else { return }
        _ = MainActor.assumeIsolated {
            store.send(.internal(.setSelectionState(
                ids: target.selectedIds,
                lastSelectedId: target.entries.last?.id,
                rangeAnchorId: target.entries.last?.id,
                shouldScrollToSelection: false,
            )))
        }
    }
}

@MainActor
private func gridContextMenuServiceNames() -> [String] {
    NSApp.servicesMenu?.update()
    return NSApp.servicesMenu?.items.compactMap { item -> String? in
        guard !item.isSeparatorItem,
              item.action != nil,
              !item.title.isEmpty
        else { return nil }
        return item.title
    } ?? []
}

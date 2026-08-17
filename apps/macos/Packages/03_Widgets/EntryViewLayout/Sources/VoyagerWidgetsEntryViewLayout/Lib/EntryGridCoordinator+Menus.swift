@preconcurrency import AppKit
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
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
        let serviceNames = entryOpenClient.serviceNames()
        let menuSpec = makeMenuSpec(target: target, rowEntry: rowEntry, serviceNames: serviceNames)
        let coordinator = EntryContextMenuCoordinator(
            store: store,
            target: target,
            anchorView: collectionView,
            anchorScreenPoint: contextMenuAnchor,
        )
        contextMenuCoordinator = coordinator
        return coordinator.observeOpenWithMenu(EntryContextMenuBuilder.makeMenu(
            configuration: makeMenuConfiguration(target: target, menuSpec: menuSpec, coordinator: coordinator),
        ))
    }

    private func makeMenuSpec(
        target: EntryContextMenuTarget,
        rowEntry: EntryModel?,
        serviceNames: [String],
    ) -> EntryContextMenuSpec {
        EntryContextMenuSpecFactory.make(
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
    }

    private func makeMenuConfiguration(
        target: EntryContextMenuTarget,
        menuSpec: EntryContextMenuSpec,
        coordinator: EntryContextMenuCoordinator,
    ) -> EntryContextMenuBuilder.Configuration {
        .init(
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
                && !target.containsBusyEntry(
                    busyEntryPaths: Set(state.entryOperations.itemStates.filter(\.value.isBusy).map(\.key)),
                ),
            isOpenWithApplicationsLoading: menuSpec.isOpenWithApplicationsLoading,
        )
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

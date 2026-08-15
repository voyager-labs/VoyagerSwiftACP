@preconcurrency import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

extension EntryListCoordinator {
    func configureHeaderMenu() {
        let headerView: EntryListHeaderView
        if let existing = tableView.headerView as? EntryListHeaderView {
            headerView = existing
        } else {
            let newHeaderView = EntryListHeaderView()
            tableView.headerView = newHeaderView
            headerView = newHeaderView
        }
        headerView.menuModelProvider = { [weak self] in
            let visibleColumns = self?.state.listVisibleColumns ?? EntryListColumn.defaultVisibleColumns
            return EntryViewLayoutColumnsMenuModel(visibleColumns: visibleColumns)
        }
        headerView.send = { [weak self] action in
            self?.store.send(.view(action))
        }
    }

    func syncVisibleColumnsFromTableView() {
        let columns = tableView.tableColumns.compactMap { tableColumn in
            EntryListColumn(rawValue: tableColumn.identifier.rawValue)
        }
        let normalized = EntryListColumn.normalizeVisibleColumns(columns)
        if normalized != state.listVisibleColumns {
            store.send(.view(.updateListVisibleColumns(normalized)))
        }
    }

    func updateContextMenuAnchor(forRow row: Int?) {
        guard let row, row >= 0 else {
            contextMenuAnchor = nil
            return
        }
        guard let window = view?.window else {
            contextMenuAnchor = nil
            return
        }

        let rectInTable = tableView.rect(ofRow: row)
        let rectInWindow = tableView.convert(rectInTable, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)
        contextMenuAnchor = CGPoint(x: rectInScreen.midX, y: rectInScreen.midY)
    }

    func preloadOpenWithApplications(selectedEntries: [EntryModel]) {
        store.send(.view(.preloadOpenWithApplications(selectedEntries)))
    }

    func openWithApplications(selectedEntries _: [EntryModel]) -> [ApplicationInfo] {
        state.entryOperations.commonApplicationsForSelectedFiles
    }

    func entryForRow(_ row: Int?) -> EntryModel? {
        guard let row, row >= 0 else { return nil }
        guard let item = tableView.item(atRow: row) as? OutlineItem else { return nil }
        guard case let .entry(entry) = item.kind else { return nil }
        return entry
    }

    func selectedEntries(rowEntry: EntryModel?) -> [EntryModel] {
        state.contextMenuSelectedEntries(rowEntry: rowEntry)
    }

    var isTrashFolder: Bool {
        guard let trashPath = state.trashDirectoryPath else {
            return false
        }
        let path = state.currentPath
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }
}

extension EntryListCoordinator: EntryListView.EntryListTableViewContextMenuProviding {
    func contextMenu(forRow row: Int?, event _: NSEvent) -> NSMenu {
        updateContextMenuAnchor(forRow: row)
        let rowEntry = entryForRow(row)
        let displayEntries = state.hierarchyProjectionIsActive
            ? state.visibleSelectableEntries(isNormalDirectoryPage: true)
            : state.entries
        let target = EntryContextMenuTarget.resolve(
            displayEntries: displayEntries,
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
            restorableTrashPaths: state.entryOperations.restorableTrashPaths,
            canPaste: !state.entryOperations.clipboardItems.isEmpty,
            favoriteTags: finderFavoritesTagClient.favoriteTags(),
            openWithApplications: openWithApplications(selectedEntries: target.entries),
        )
        let coordinator = EntryContextMenuCoordinator(
            store: store,
            target: target,
            anchorView: tableView,
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
            canPerformEntryCommands: (!state.entryOperations.isLoading || state.isCollectionMode)
                && !target.containsBusyEntry(
                    busyEntryPaths: Set(state.entryOperations.itemStates.filter(\.value.isBusy).map(\.key)),
                ),
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

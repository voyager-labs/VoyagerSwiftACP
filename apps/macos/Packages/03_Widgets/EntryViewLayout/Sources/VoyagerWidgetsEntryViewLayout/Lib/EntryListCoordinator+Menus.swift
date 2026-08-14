@preconcurrency import AppKit
import ComposableArchitecture
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesEntryOperations

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
            self?.store.send(action)
        }
    }

    func syncVisibleColumnsFromTableView() {
        let columns = tableView.tableColumns.compactMap { tableColumn in
            EntryListColumn(rawValue: tableColumn.identifier.rawValue)
        }
        let normalized = EntryListColumn.normalizeVisibleColumns(columns)
        if normalized != state.listVisibleColumns {
            store.send(.internal(.setListVisibleColumns(normalized)))
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
        let selectedFiles = selectedEntries.filter { !$0.isFolder }
        if selectedFiles.isEmpty {
            return
        }

        if selectedFiles.count > 1 {
            sendEntryOperations(.openWith(.loadCommonApplicationsForFiles(files: selectedFiles)))
        } else if let file = selectedFiles.first,
                  state.entryOperations
                  .applicationsForTypes[UTType(filenameExtension: file.fileExtension)?.identifier ?? UTType.data
                      .identifier] == nil
        {
            sendEntryOperations(.openWith(.loadApplicationsForFile(file: file)))
        }
    }

    func openWithApplications(selectedEntries: [EntryModel]) -> [ApplicationInfo] {
        let selectedFiles = selectedEntries.filter { !$0.isFolder }
        return if selectedFiles.count > 1 {
            state.entryOperations.commonApplicationsForSelectedFiles
        } else if let file = selectedFiles.first {
            state.entryOperations
                .applicationsForTypes[UTType(filenameExtension: file.fileExtension)?.identifier ?? UTType.data
                    .identifier] ?? []
        } else {
            [] as [ApplicationInfo]
        }
    }

    func entryForRow(_ row: Int?) -> EntryModel? {
        guard let row, row >= 0 else { return nil }
        guard let item = tableView.item(atRow: row) as? OutlineItem else { return nil }
        guard case let .entry(entry) = item.kind else { return nil }
        return entry
    }

    func selectedEntries(rowEntry: EntryModel?) -> [EntryModel] {
        let selectedIds = state.selectedIds
        if selectedIds.isEmpty {
            return rowEntry.map { [$0] } ?? []
        }
        return state.entries.filter { selectedIds.contains($0.id) }
    }

    var isTrashFolder: Bool {
        guard let trashPath = entryOpenClient.trashDirectoryPath() else {
            return false
        }
        let path = state.currentPath
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    func dragOperation(from resolved: EntryDropResolvedOperation) -> NSDragOperation {
        switch resolved {
        case .none:
            []
        case .copy:
            .copy
        case .move:
            .move
        }
    }
}

extension EntryListCoordinator: EntryListView.EntryListTableViewContextMenuProviding {
    func contextMenu(forRow row: Int?, event _: NSEvent) -> NSMenu {
        updateContextMenuAnchor(forRow: row)
        let rowEntry = entryForRow(row)
        let target = EntryContextMenuTarget.resolve(
            displayEntries: state.entries,
            selectedIds: state.selectedIds,
            rowEntry: rowEntry,
        )
        synchronizeContextMenuSelection(target)
        preloadOpenWithApplications(selectedEntries: target.entries)
        let serviceNames = listContextMenuServiceNames()
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
            anchorView: tableView,
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
private func listContextMenuServiceNames() -> [String] {
    NSApp.servicesMenu?.update()
    return NSApp.servicesMenu?.items.compactMap { item -> String? in
        guard !item.isSeparatorItem,
              item.action != nil,
              !item.title.isEmpty
        else { return nil }
        return item.title
    } ?? []
}

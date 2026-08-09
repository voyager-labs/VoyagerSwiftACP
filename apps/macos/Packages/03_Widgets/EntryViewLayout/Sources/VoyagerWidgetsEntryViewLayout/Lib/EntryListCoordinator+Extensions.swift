@preconcurrency import AppKit
import ComposableArchitecture
import SwiftNavigation
import VoyagerEntitiesEntry
import VoyagerShared

public extension EntryListCoordinator {
    func beginRenaming(row: Int) {
        guard row >= 0, row < tableView.numberOfRows else { return }
        guard let nameColumnIndex else { return }

        tableView.scrollRowToVisible(row)
        isUpdatingSelectionFromStore = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isUpdatingSelectionFromStore = false

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            _ = tableView.view(atColumn: nameColumnIndex, row: row, makeIfNecessary: true)

            guard let cell = tableView
                .view(atColumn: nameColumnIndex, row: row, makeIfNecessary: false) as? EntryListEntryCellView
            else {
                return
            }

            cell.beginRenaming()
        }
    }
}

extension EntryListOutlineItem {
    func flattenEntries() -> [(EntryModel.ID, EntryListOutlineItem)] {
        switch kind {
        case let .entry(entry):
            [(entry.id, self)] + children.flatMap { $0.flattenEntries() }
        case .group, .empty, .error:
            children.flatMap { $0.flattenEntries() }
        }
    }

    func flattenItems() -> [(String, EntryListOutlineItem)] {
        [(id, self)] + children.flatMap { $0.flattenItems() }
    }
}

extension EntryListCoordinator: NSOutlineViewDelegate {
    public func outlineView(_: NSOutlineView, rowViewForItem _: Any) -> NSTableRowView? {
        EntryListSelectionRowView()
    }

    public func outlineView(_: NSOutlineView, shouldEdit tableColumn: NSTableColumn?, item: Any) -> Bool {
        guard let tableColumn else { return false }
        guard tableColumn.identifier.rawValue == EntryListColumn.name.rawValue else { return false }
        guard let outlineItem = item as? OutlineItem else { return false }
        guard case let .entry(entry) = outlineItem.kind else { return false }
        guard state.renamingItemId == entry.id else { return false }
        return true
    }

    public func outlineView(
        _: NSOutlineView,
        draggingSession _: NSDraggingSession,
        willBeginAt _: NSPoint,
        forItems items: [Any],
    ) {
        let paths = items.compactMap { item -> String? in
            guard let outlineItem = item as? OutlineItem else { return nil }
            guard case let .entry(entry) = outlineItem.kind else { return nil }
            return entry.fullPath
        }
        guard !paths.isEmpty else { return }
        store.send(.view(.startDrag(paths: paths)))
    }

    public func outlineView(
        _: NSOutlineView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        operation: NSDragOperation,
    ) {
        guard EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation) else { return }
        store.send(.view(.startDrag(paths: [])))
        store.send(.view(.setDropTargeted(false)))
    }

    public func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
        let signature = EntryListCoordinatorSortSignature(descriptors: outlineView.sortDescriptors)
        guard !sortSyncGate.consumeIfSuppressed(signature) else { return }

        guard let change = EntryListCoordinatorSortDescriptorMapper.change(from: outlineView.sortDescriptors)
        else { return }
        guard let needed = EntryListCoordinatorSortDescriptorMapper.actionNeeded(
            currentSortKey: state.sortKey.sharedSortKey,
            currentSortOrder: state.sortOrder,
            change: change,
        ) else { return }
        store.send(.view(.changeSort(
            EntryViewLayoutSortKey.fromShared(needed.sortKey),
            needed.sortOrder,
        )))
    }

    public func outlineViewColumnDidMove(_ notification: Notification) {
        guard !isApplyingColumnsFromStore else { return }

        let userInfo = notification.userInfo ?? [:]
        let oldIndex = userInfo["NSOldColumn"] as? Int
        let newIndex = userInfo["NSNewColumn"] as? Int

        if let oldIndex, let newIndex {
            store.send(.view(.moveListColumn(from: oldIndex, to: newIndex)))
            return
        }

        syncVisibleColumnsFromTableView()
    }

    public func outlineViewColumnDidResize(_ notification: Notification) {
        guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        guard column.identifier.rawValue == EntryListColumn.dateModified.rawValue else { return }
        dateModifiedResizeDebouncer.schedule { [weak self] in
            self?.reloadVisibleDateModifiedCells()
        }
    }

    public func outlineView(_: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        if case .group = outlineItem.kind {
            return true
        }
        return false
    }

    public func outlineView(_: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        switch outlineItem.kind {
        case .entry:
            return true
        case .group, .empty, .error:
            return false
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let outlineItem = item as? OutlineItem else { return outlineView.rowHeight }
        switch outlineItem.kind {
        case .group:
            return 32
        case .entry:
            return max(24, state.listIconSize + 4)
        case .empty, .error:
            return 24
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let outlineItem = item as? OutlineItem else { return nil }

        switch outlineItem.kind {
        case let .group(title, colorCode, _):
            return makeGroupRowView(
                outlineView: outlineView,
                tableColumn: tableColumn,
                title: title,
                colorCode: colorCode,
            )
        case let .entry(entry):
            let resolvedTableColumn = tableColumn ?? outlineView.outlineTableColumn
            let columnId = resolvedTableColumn?.identifier.rawValue ?? EntryListColumn.name.rawValue
            return makeEntryCell(
                outlineView: outlineView,
                columnId: columnId,
                entry: entry,
                isLoadingChildren: outlineItem.isLoadingChildren,
            )
        case .empty:
            return makeStatusCell(
                outlineView: outlineView,
                tableColumn: tableColumn,
                title: "Empty folder",
                retryFolderID: nil,
            )
        case let .error(parent, failure):
            return makeStatusCell(
                outlineView: outlineView,
                tableColumn: tableColumn,
                title: statusTitle(for: failure),
                retryFolderID: parent,
            )
        }
    }

    private func makeEntryCell(
        outlineView: NSOutlineView,
        columnId: String,
        entry: EntryModel,
        isLoadingChildren: Bool,
    ) -> EntryListEntryCellView {
        let entryIdentifier = NSUserInterfaceItemIdentifier("entry-cell-\(columnId)")
        let view = (outlineView.makeView(withIdentifier: entryIdentifier, owner: self) as? EntryListEntryCellView)
            ?? EntryListEntryCellView()
        view.identifier = entryIdentifier

        let columnWidth = outlineView
            .tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(columnId))?
            .width ?? 0
        let thumbnail = thumbnailImagesByPath[entry.fullPath]
        let configuration = makeEntryCellConfiguration(
            entry: entry,
            columnId: columnId,
            columnWidth: columnWidth,
            thumbnail: thumbnail,
            isLoadingChildren: isLoadingChildren,
        )
        view.configure(configuration)
        return view
    }

    public func outlineViewSelectionDidChange(_: Notification) {
        guard !isUpdatingSelectionFromStore, !projectionSession.isApplyingStoreProjection else { return }

        let selectedIndexes = tableView.selectedRowIndexes
        let selectedEntries: [EntryModel] = selectedIndexes.compactMap { index in
            guard let outlineItem = tableView.item(atRow: index) as? OutlineItem else { return nil }
            guard case let .entry(entry) = outlineItem.kind else { return nil }
            return entry
        }
        let clickedRow = tableView.clickedRow
        let lastSelectedId: EntryModel.ID? = if selectedIndexes.contains(clickedRow),
                                                let item = tableView.item(atRow: clickedRow) as? OutlineItem,
                                                case let .entry(entry) = item.kind
        {
            entry.id
        } else if let lastIndex = selectedIndexes.last,
                  let item = tableView.item(atRow: lastIndex) as? OutlineItem,
                  case let .entry(entry) = item.kind
        {
            entry.id
        } else {
            nil
        }

        let acceptedIDs = Set(selectedEntries.map(\.id))
        preloadOpenWithApplications(selectedEntries: selectedEntries)
        store.send(.view(.updateSelection(
            ids: acceptedIDs,
            lastSelectedId: lastSelectedId,
            rangeAnchorId: lastSelectedId,
            shouldScrollToSelection: false,
        )))
    }

    public func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isUpdatingGroupExpansion, !projectionSession.isApplyingStoreProjection else { return }
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
        guard isCurrentOutlineItem(item) else { return }
        switch item.kind {
        case let .group(name, _, _):
            if state.collapsedGroups.contains(name) {
                store.send(.view(.toggleGroup(name)))
            }
        case let .entry(entry) where isHierarchyOutlineEnabled:
            sendProjectionIntent(.disclosureExpand(entry.id, revision: state.outlineProjectionRevision))
        case .entry, .empty, .error:
            return
        }
    }

    public func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isUpdatingGroupExpansion, !projectionSession.isApplyingStoreProjection else { return }
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
        guard isCurrentOutlineItem(item) else { return }
        switch item.kind {
        case let .group(name, _, _):
            if !state.collapsedGroups.contains(name) {
                store.send(.view(.toggleGroup(name)))
            }
        case let .entry(entry) where isHierarchyOutlineEnabled:
            sendProjectionIntent(.disclosureCollapse(entry.id, revision: state.outlineProjectionRevision))
        case .entry, .empty, .error:
            return
        }
    }

    func sendProjectionIntent(_ intent: EntryListCoordinatorProjectionIntent) {
        guard !projectionSession.isApplyingStoreProjection else { return }
        let revision: Int = switch intent {
        case let .disclosureExpand(_, revision), let .disclosureCollapse(_, revision),
             let .retry(_, revision):
            revision
        }
        guard revision == state.outlineProjectionRevision else { return }
        switch intent {
        case let .disclosureExpand(id, _):
            store.send(.view(.expandFolder(id)))
        case let .disclosureCollapse(id, _):
            store.send(.view(.collapseFolder(id)))
        case let .retry(id, _):
            store.send(.view(.retryFolder(id)))
        }
    }
}

extension EntryListCoordinator {
    func reloadTablePreservingScrollAnchor(_ reload: () -> Void) {
        let scrollAnchor = captureScrollAnchor()
        reload()
        restoreScrollAnchor(scrollAnchor)
    }

    public func observeListStore() {
        observeRenderLoop()
    }

    public func observeRenderLoop() {
        observe { [weak self] in
            guard let self else { return }
            let snapshot = RenderSnapshot(state: state)
            guard isRenderObservationEnabled else { return }
            renderThrottler.schedule { [weak self] in
                self?.processRender(snapshot)
            }
        }
    }

    func processRender(_ snapshot: RenderSnapshot) {
        guard let previous = lastRenderSnapshot else {
            lastRenderSnapshot = snapshot
            return
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0)
        handleSnapshotChanges(previous: previous, snapshot: snapshot)
        CATransaction.commit()

        lastRenderSnapshot = snapshot
    }

    func handleSnapshotChanges(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        handleVisibleColumnsChange(previous: previous, snapshot: snapshot)
        let didRebuildRows = rebuildRowsIfNeeded(previous: previous, snapshot: snapshot)
        updateListMetricsIfNeeded(previous: previous, snapshot: snapshot)
        resetThumbnailSessionIfNeeded(previous: previous, snapshot: snapshot)
        if !didRebuildRows {
            syncSelectionIfNeeded(previous: previous, snapshot: snapshot)
        }
        reloadVisibleRowsIfNeeded(previous: previous, snapshot: snapshot)
        if !didRebuildRows {
            syncRenamingIfNeeded(previous: previous, snapshot: snapshot)
        }
        syncSortIndicatorsIfNeeded(previous: previous, snapshot: snapshot)
        saveScrollPositionIfNeeded(previous: previous, snapshot: snapshot)
        scrollToSelectionIfNeeded(previous: previous, snapshot: snapshot)
        updateDropTargetBorderIfNeeded(previous: previous, snapshot: snapshot)
        syncThumbnailProjectionIfNeeded(previous: previous, snapshot: snapshot)
    }

    func handleVisibleColumnsChange(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.listVisibleColumns != snapshot.listVisibleColumns else { return }
        isApplyingColumnsFromStore = true
        view?.applyColumns(snapshot.listVisibleColumns)
        isApplyingColumnsFromStore = false
        syncListSortIndicators(sortKey: snapshot.sortKey.sharedSortKey, sortOrder: snapshot.sortOrder)
        syncListRenamingFromStore()
        reloadTablePreservingScrollAnchor {
            tableView.reloadData()
        }
        requestThumbnailsForVisibleRows()
    }

    @discardableResult
    func rebuildRowsIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) -> Bool {
        guard previous.isHierarchyOutlineEnabled == snapshot.isHierarchyOutlineEnabled else {
            rebuildRowsAndReload()
            return true
        }

        if snapshot.isHierarchyOutlineEnabled {
            if !previous.outlineProjection.hasSameOutlineShape(as: snapshot.outlineProjection) {
                rebuildRowsAndReload()
                return true
            } else if !previous.outlineProjection.hasSameStructure(as: snapshot.outlineProjection) {
                reloadVisibleRowsForContentChange(
                    previous: previous.outlineProjection,
                    snapshot: snapshot.outlineProjection,
                )
            }
            return false
        }

        let pathChanged = previous.currentPath != snapshot.currentPath

        let changes = snapshot.presentation.changes(from: previous.presentation)
        if changes.groupExpansionChanged {
            rebuildRowsAndReload()
            return true
        } else if changes.sectionStructureChanged {
            applyPostReloadPresentation(
                pathChanged: pathChanged,
                structureChanged: true,
                updateKind: .incremental(preservesScrollAnchor: false),
                selectionChanged: false,
            ) {
                projectionSession.reset()
                if !tryIncrementalFlatRowUpdate(
                    previous: previous.presentation,
                    current: snapshot.presentation,
                    changes: changes,
                ) {
                    let flatItems = makeOutlineItems(presentation: snapshot.presentation)
                    outlineItems = flatItems
                    rebuildItemIndexes()
                    lastAppliedVisibleRows = []
                    tableView.reloadData()
                    applyGroupExpansionState()
                }
            }
            return true
        } else if !changes.updatedEntryIDs.isEmpty {
            reloadVisibleRowsForPresentationChange(
                changedEntryIDs: changes.updatedEntryIDs,
                presentation: snapshot.presentation,
            )
        }
        return false
    }

    func tryIncrementalFlatRowUpdate(
        previous: EntryViewLayoutPresentation,
        current: EntryViewLayoutPresentation,
        changes: EntryViewLayoutPresentationChangeSet,
    ) -> Bool {
        guard previous.sections.count == current.sections.count,
              previous.sections.enumerated().allSatisfy({ index, section in
                  let next = current.sections[index]
                  return section.id == next.id
                      && section.title == next.title
                      && section.colorCode == next.colorCode
                      && section.isCollapsed == next.isCollapsed
              })
        else { return false }

        let changedCount = changes.insertedEntryIDs.count + changes.removedEntryIDs.count
        guard changedCount * 2 <= max(previous.entries.count, current.entries.count) else { return false }
        let incomingItems = makeOutlineItems(presentation: current)

        var childUpdates: [(parent: OutlineItem, removed: IndexSet, inserted: IndexSet)] = []
        for (sectionIndex, oldParent) in outlineItems.enumerated() {
            guard sectionIndex < incomingItems.count,
                  oldParent.id == incomingItems[sectionIndex].id
            else { return false }
            let newParent = incomingItems[sectionIndex]
            let oldChildren = oldParent.children
            let newChildren = newParent.children
            let oldIDs = oldChildren.map(\.id)
            let newIDs = newChildren.map(\.id)
            let retained = Set(oldIDs).intersection(newIDs)
            guard retained.count >= min(oldIDs.count, newIDs.count) - 1
            else { return false }
            let retainedOrderPreserved = oldIDs.filter { retained.contains($0) }
                == newIDs.filter { retained.contains($0) }
            guard retainedOrderPreserved else { return false }
            let removed = IndexSet(oldIDs.enumerated().compactMap { newIDs.contains($0.element) ? nil : $0.offset })
            let inserted = IndexSet(newIDs.enumerated().compactMap { oldIDs.contains($0.element) ? nil : $0.offset })
            guard max(removed.count, inserted.count) * 2 <= max(oldIDs.count, newIDs.count) else { return false }
            let retainedChildren = newChildren.map { newItem in
                if let existing = oldChildren.first(where: { $0.id == newItem.id }) {
                    existing.kind = newItem.kind
                    existing.isLoadingChildren = newItem.isLoadingChildren
                    return existing
                }
                return newItem
            }
            oldParent.children = retainedChildren
            childUpdates.append((oldParent, removed, inserted))
        }

        guard childUpdates.contains(where: { !$0.removed.isEmpty || !$0.inserted.isEmpty }) else { return false }

        rebuildItemIndexes()
        tableView.beginUpdates()
        for update in childUpdates {
            if !update.removed.isEmpty {
                tableView.removeItems(at: update.removed, inParent: update.parent, withAnimation: .slideLeft)
            }
            if !update.inserted.isEmpty {
                tableView.insertItems(at: update.inserted, inParent: update.parent, withAnimation: .slideDown)
            }
        }
        tableView.endUpdates()
        let updatedRowIndexes = IndexSet(changes.updatedEntryIDs.flatMap { id in
            entryItemsByID[id, default: []].compactMap { item in
                let row = tableView.row(forItem: item)
                return row >= 0 ? row : nil
            }
        })
        if !updatedRowIndexes.isEmpty {
            let columnIndexes = IndexSet(integersIn: 0 ..< tableView.numberOfColumns)
            tableView.reloadData(forRowIndexes: updatedRowIndexes, columnIndexes: columnIndexes)
        }
        return true
    }

    func reloadVisibleRowsForPresentationChange(
        changedEntryIDs: Set<EntryModel.ID>,
        presentation: EntryViewLayoutPresentation,
    ) {
        let entriesByID = presentation.entries.reduce(into: [EntryModel.ID: EntryModel]()) { result, entry in
            result[entry.id] = entry
        }
        let rowIndexes = IndexSet(changedEntryIDs.flatMap { entryID in
            guard let entry = entriesByID[entryID] else { return [Int]() }
            return entryItemsByID[entryID, default: []].compactMap { item in
                item.kind = .entry(entry)
                let row = tableView.row(forItem: item)
                return row >= 0 ? row : nil
            }
        })
        guard !rowIndexes.isEmpty else { return }
        let columnIndexes = IndexSet(integersIn: 0 ..< tableView.numberOfColumns)
        tableView.reloadData(forRowIndexes: rowIndexes, columnIndexes: columnIndexes)
        requestThumbnailsForVisibleRows()
    }

    func reloadVisibleRowsForContentChange(
        previous: EntryListOutlineProjection,
        snapshot: EntryListOutlineProjection,
    ) {
        let changedItemIDs = snapshot.itemPayloads.compactMap { itemID, payload in
            previous.itemPayloads[itemID] == payload ? nil : itemID
        }
        let rowIndexes = IndexSet(changedItemIDs.compactMap { itemID in
            guard let item = outlineItem(for: itemID), let payload = snapshot.itemPayloads[itemID] else { return nil }
            item.apply(payload)
            let row = tableView.row(forItem: item)
            return row >= 0 ? row : nil
        })
        guard !rowIndexes.isEmpty else { return }
        let columnIndexes = IndexSet(integersIn: 0 ..< tableView.numberOfColumns)
        tableView.reloadData(forRowIndexes: rowIndexes, columnIndexes: columnIndexes)
        requestThumbnailsForVisibleRows()
    }

    func outlineItem(for itemID: EntryListOutlineProjection.ItemID) -> OutlineItem? {
        switch itemID {
        case let .entry(entryID):
            entryItemsByID[entryID]?.first
        case let .empty(parent):
            outlineItemByID["empty:\(parent)"]
        case let .error(parent):
            outlineItemByID["error:\(parent)"]
        }
    }

    func resetThumbnailSessionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.currentPath != snapshot.currentPath {
            resetThumbnailSession()
            restoredScrollForCurrentPath = false
        }
    }

    func syncSelectionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if snapshot.presentation.changes(from: previous.presentation).selectionChanged {
            syncListSelectionFromStore()
        }
    }

    func reloadVisibleRowsIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.clipboardCutPaths != snapshot.clipboardCutPaths
        else {
            return
        }

        let rows = tableView.rows(in: tableView.visibleRect)
        guard rows.location != NSNotFound, rows.length > 0 else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: rows.location ..< NSMaxRange(rows)),
                             columnIndexes: IndexSet(integersIn: 0 ..< tableView.numberOfColumns))
    }

    func syncRenamingIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.renamingItemId != snapshot.renamingItemId { syncListRenamingFromStore() }
    }

    func syncSortIndicatorsIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.sortKey != snapshot.sortKey || previous.sortOrder != snapshot.sortOrder {
            syncListSortIndicators(sortKey: snapshot.sortKey.sharedSortKey, sortOrder: snapshot.sortOrder)
        }
    }

    func saveScrollPositionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.showHiddenFiles != snapshot.showHiddenFiles { saveScrollPosition() }
    }

    func scrollToSelectionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if !previous.shouldScrollToSelection, snapshot.shouldScrollToSelection { scrollToSelectionIfNeeded() }
    }

    func updateDropTargetBorderIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.isDropTargeted != snapshot
            .isDropTargeted { updateDropTargetBorder(isTargeted: snapshot.isDropTargeted) }
    }

    public func syncListSortIndicators(sortKey: SortKey, sortOrder: VoyagerShared.SortOrder) {
        let ascending = sortOrder == .ascending
        let descriptorKey = state.listVisibleColumns
            .first { $0.sortKey == sortKey }?
            .rawValue

        let targetDescriptors: [NSSortDescriptor] = if let descriptorKey {
            [NSSortDescriptor(key: descriptorKey, ascending: ascending)]
        } else {
            []
        }
        let currentSignature = EntryListCoordinatorSortSignature(descriptors: tableView.sortDescriptors)
        let targetSignature = EntryListCoordinatorSortSignature(descriptors: targetDescriptors)
        guard currentSignature != targetSignature else { return }

        sortSyncGate.beginApply(targetSignature)
        tableView.sortDescriptors = targetDescriptors
    }

    public func syncListSelectionFromStore() {
        let selectedIds = state.selectedIds
        let indexes = IndexSet(selectedIds.flatMap { id in
            entryItemsByID[id, default: []].compactMap { item in
                let row = tableView.row(forItem: item)
                return row >= 0 ? row : nil
            }
        })

        isUpdatingSelectionFromStore = true
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        isUpdatingSelectionFromStore = false
    }

    public func syncListRenamingFromStore() {
        let currentRenamingItemId = state.renamingItemId
        let previousRenamingItemId = lastRenamingItemId
        lastRenamingItemId = currentRenamingItemId

        guard let nameColumnIndex else { return }
        let nameColumnIndexes = IndexSet(integer: nameColumnIndex)

        if let previousRenamingItemId {
            let rows = entryItemsByID[previousRenamingItemId, default: []].compactMap { item in
                let row = tableView.row(forItem: item)
                return row >= 0 ? row : nil
            }
            tableView.reloadData(forRowIndexes: IndexSet(rows), columnIndexes: nameColumnIndexes)
        }

        guard let renamingItemId = currentRenamingItemId,
              let row = entryItemsByID[renamingItemId]?
              .lazy
              .map({ self.tableView.row(forItem: $0) })
              .first(where: { $0 >= 0 })
        else {
            view?.window?.makeFirstResponder(tableView)
            return
        }

        let rows = entryItemsByID[renamingItemId, default: []].compactMap { item in
            let itemRow = tableView.row(forItem: item)
            return itemRow >= 0 ? itemRow : nil
        }
        tableView.reloadData(forRowIndexes: IndexSet(rows), columnIndexes: nameColumnIndexes)
        beginRenaming(row: row)
    }
}

public extension EntryListCoordinator {
    func refreshVisibleNameCellIcons(for paths: Set<String>? = nil) {
        guard tableView.numberOfRows > 0 else { return }
        guard let nameColumnIndex else { return }

        let visibleRange = tableView.rows(in: tableView.visibleRect)
        guard visibleRange.length > 0 else { return }

        let dateModifiedWidth = tableView
            .tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(EntryListColumn.dateModified.rawValue))?
            .width ?? 0

        for row in visibleRange.location ..< (visibleRange.location + visibleRange.length) {
            guard let cell = tableView
                .view(atColumn: nameColumnIndex, row: row, makeIfNecessary: false) as? EntryListEntryCellView
            else {
                continue
            }
            guard let outlineItem = tableView.item(atRow: row) as? OutlineItem else { continue }
            guard case let .entry(entry) = outlineItem.kind else { continue }
            if let paths, !paths.contains(entry.fullPath) { continue }

            let thumbnail = thumbnailImagesByPath[entry.fullPath]
            let configuration = makeEntryCellConfiguration(
                entry: entry,
                columnId: EntryListColumn.name.rawValue,
                columnWidth: dateModifiedWidth,
                thumbnail: thumbnail,
                isLoadingChildren: outlineItem.isLoadingChildren,
            )
            cell.configure(configuration)
        }
    }
}

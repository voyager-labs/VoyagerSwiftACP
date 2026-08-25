@preconcurrency import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

extension EntryListCoordinator {
    func requestThumbnailsForVisibleRows() {
        guard tableView.numberOfRows > 0 else { return }
        let visibleRange = tableView.rows(in: tableView.visibleRect)
        guard visibleRange.length > 0 else { return }
        let extraRows = max(visibleRange.length, 20)
        let startRow = max(0, visibleRange.location - extraRows)
        let endRow = min(tableView.numberOfRows, visibleRange.location + visibleRange.length + extraRows)
        var paths: Set<String> = []
        paths.reserveCapacity(visibleRange.length)
        for row in startRow ..< endRow {
            guard let outlineItem = tableView.item(atRow: row) as? OutlineItem else { continue }
            guard case let .entry(entry) = outlineItem.kind else { continue }
            guard !entry.isFolder else { continue }
            paths.insert(entry.fullPath)
        }
        guard !paths.isEmpty else { return }
        pruneThumbnailSession(keeping: paths)
        refreshVisibleNameCellIcons(for: refreshThumbnailProjection(paths: paths))
    }

    func pruneThumbnailSession(keeping paths: Set<String>) {
        thumbnailImagesByPath = thumbnailImagesByPath.filter { paths.contains($0.key) }
    }

    func resetThumbnailSession() {
        thumbnailImagesByPath.removeAll(keepingCapacity: false)
    }

    func refreshThumbnailProjection(paths: Set<String>) -> Set<String> {
        var changedPaths: Set<String> = []

        for path in paths {
            let cachedImage = entryThumbnailCacheClient.getThumbnail(for: path)
            if let cachedImage {
                if thumbnailImagesByPath[path] == nil {
                    changedPaths.insert(path)
                }
                thumbnailImagesByPath[path] = cachedImage
            } else if thumbnailImagesByPath.removeValue(forKey: path) != nil {
                changedPaths.insert(path)
            }
        }

        return changedPaths
    }

    func refreshThumbnailProjectionForVisibleRows() {
        guard tableView.numberOfRows > 0 else { return }
        let visibleRange = tableView.rows(in: tableView.visibleRect)
        guard visibleRange.length > 0 else { return }

        var visiblePaths: Set<String> = []
        for row in visibleRange.location ..< (visibleRange.location + visibleRange.length) {
            guard let outlineItem = tableView.item(atRow: row) as? OutlineItem else { continue }
            guard case let .entry(entry) = outlineItem.kind, !entry.isFolder else { continue }
            visiblePaths.insert(entry.fullPath)
        }

        refreshVisibleNameCellIcons(for: refreshThumbnailProjection(paths: visiblePaths))
    }

    func saveScrollPosition() {
        let offset = scrollView.contentView.bounds.origin
        store.send(.view(.saveScrollOffset(offset, forPath: state.currentPath)))
    }

    @discardableResult
    func scrollToSelectionIfNeeded() -> Bool {
        guard state.shouldScrollToSelection else { return false }
        let targetId = state.lastSelectedId
            ?? state.selectedIds.first
        guard let targetId else {
            store.send(.view(.resetScrollFlag))
            return false
        }
        guard let row = entryItemsByID[targetId]?
            .lazy
            .map({ self.tableView.row(forItem: $0) })
            .first(where: { $0 >= 0 })
        else {
            return false
        }
        tableView.scrollRowToVisible(row)
        store.send(.view(.resetScrollFlag))
        return true
    }

    /// 타자 검색으로 설정된 pending target을 첫 유효 row로 스크롤하고 reset한다.
    /// 성공 여부와 관계없이 resetTypeScrollTarget을 발행해 일회성 소비를 보장한다.
    func scrollToTypeScrollTarget(_ targetId: EntryModel.ID) {
        defer { store.send(.view(.resetTypeScrollTarget)) }
        guard let row = entryItemsByID[targetId]?
            .lazy
            .map({ self.tableView.row(forItem: $0) })
            .first(where: { $0 >= 0 })
        else { return }
        tableView.scrollRowToVisible(row)
    }

    func updateDropTargetBorder(isTargeted: Bool) {
        scrollView.layer?.borderWidth = isTargeted ? 2 : 0
        scrollView.layer?.borderColor = isTargeted ? NSColor.controlAccentColor.cgColor : nil
    }

    func makeOutlineItems(state: EntryViewLayoutState) -> [OutlineItem] {
        makeOutlineItems(presentation: state.presentation)
    }

    func makeOutlineItems(presentation: EntryViewLayoutPresentation) -> [OutlineItem] {
        presentation.sections.flatMap { section -> [OutlineItem] in
            let entries = section.items.map { OutlineItem(kind: .entry($0), identityScope: section.id) }
            guard let title = section.title else { return entries }
            return [
                OutlineItem(
                    kind: .group(
                        name: title,
                        colorCode: section.colorCode,
                        isCollapsed: section.isCollapsed,
                    ),
                    children: entries,
                ),
            ]
        }
    }

    func applyStoreProjection(_ projection: EntryListOutlineProjection, pathChanged: Bool = false) {
        let oldVisibleRows = lastAppliedVisibleRows.isEmpty
            ? outlineItems.compactMap { item in
                guard case let .entry(entry) = item.kind else { return nil }
                return EntryListOutlineProjection.ItemID.entry(entry.id)
            }
            : lastAppliedVisibleRows

        projectionSession.apply(projection) { [weak self] projection, items in
            guard let self else { return }

            applyPostReloadPresentation(
                pathChanged: pathChanged,
                structureChanged: true,
                updateKind: .fullReload,
                selectionChanged: false,
            ) {
                let newVisibleRows = projection.visibleRows
                let hasHierarchyTopology = !projection.childrenByParent.isEmpty
                let hasVisibleHierarchyRows = newVisibleRows.count > projection.rootItemIDs.count
                let shouldForceFullReload = lastProjectionHasHierarchyTopology != hasHierarchyTopology
                    || hasVisibleHierarchyRows
                if shouldForceFullReload || !tryIncrementalRowUpdate(
                    old: oldVisibleRows,
                    new: newVisibleRows,
                    items: items,
                    projection: projection,
                ) {
                    outlineItems = items
                    rebuildItemIndexes()
                    tableView.reloadData()
                    applyFolderExpansionState(for: projection)
                }
                lastAppliedVisibleRows = newVisibleRows
                lastProjectionHasHierarchyTopology = hasHierarchyTopology
            }
        }
    }

    func tryIncrementalRowUpdate(
        old: [EntryListOutlineProjection.ItemID],
        new: [EntryListOutlineProjection.ItemID],
        items: [OutlineItem],
        projection: EntryListOutlineProjection,
    ) -> Bool {
        guard let plan = makeIncrementalRowUpdatePlan(old: old, new: new, items: items, projection: projection)
        else { return false }

        outlineItems = plan.items
        rebuildItemIndexes()

        tableView.beginUpdates()
        if !plan.removedIndexes.isEmpty {
            tableView.removeItems(at: plan.removedIndexes, inParent: nil, withAnimation: .slideLeft)
        }
        if !plan.insertedIndexes.isEmpty {
            tableView.insertItems(at: plan.insertedIndexes, inParent: nil, withAnimation: .slideDown)
        }
        for operation in plan.moves {
            tableView.moveItem(at: operation.from, inParent: nil, to: operation.to, inParent: nil)
        }
        tableView.endUpdates()
        if !plan.updatedRowIndexes.isEmpty {
            let columnIndexes = IndexSet(integersIn: 0 ..< tableView.numberOfColumns)
            tableView.reloadData(forRowIndexes: plan.updatedRowIndexes, columnIndexes: columnIndexes)
        }
        return true
    }

    struct IncrementalRowUpdatePlan {
        let items: [OutlineItem]
        let removedIndexes: IndexSet
        let insertedIndexes: IndexSet
        let moves: [(from: Int, to: Int)]
        let updatedRowIndexes: IndexSet
    }

    func makeIncrementalRowUpdatePlan(
        old: [EntryListOutlineProjection.ItemID],
        new: [EntryListOutlineProjection.ItemID],
        items: [OutlineItem],
        projection: EntryListOutlineProjection,
    ) -> IncrementalRowUpdatePlan? {
        guard isPureEntryRowUpdate(old: old, new: new, projection: projection) else { return nil }

        let oldSet = Set(old)
        let newSet = Set(new)
        let changedCount = oldSet.subtracting(newSet).count + newSet.subtracting(oldSet).count
        guard changedCount * 2 <= max(old.count, new.count) else { return nil }
        guard Set(old).count == old.count, Set(new).count == new.count else { return nil }

        let oldItemsByID = entryItemIDMap(from: outlineItems)
        let incomingItemsByID = entryItemIDMap(from: items.flatMap { $0.flattenItems() }.map(\.1))
        guard oldItemsByID.count == old.count,
              incomingItemsByID.count == new.count
        else { return nil }

        var current = old
        let removed = oldSet.subtracting(newSet)
        let removedIndexes = IndexSet(current.enumerated()
            .compactMap { removed.contains($0.element) ? $0.offset : nil })
        for index in removedIndexes.reversed() {
            current.remove(at: index)
        }
        let inserted = newSet.subtracting(oldSet)
        var insertIndexes = IndexSet()
        for (index, itemID) in new.enumerated() where inserted.contains(itemID) {
            current.insert(itemID, at: index)
            insertIndexes.insert(index)
        }

        guard let moveOperations = makeIncrementalRootMoveOperations(current: current, new: new) else {
            return nil
        }

        let updatedRowIndexes = IndexSet(new.enumerated().compactMap { index, itemID in
            guard let oldItem = oldItemsByID[itemID],
                  let incomingItem = incomingItemsByID[itemID],
                  case let .entry(oldEntry) = oldItem.kind,
                  case let .entry(incomingEntry) = incomingItem.kind
            else { return nil }
            return oldEntry == incomingEntry ? nil : index
        })

        let mergedItems = mergedIncomingItems(
            new: new,
            oldItemsByID: oldItemsByID,
            incomingItemsByID: incomingItemsByID,
        )
        outlineItems = mergedItems
        return .init(
            items: mergedItems,
            removedIndexes: removedIndexes,
            insertedIndexes: insertIndexes,
            moves: moveOperations,
            updatedRowIndexes: updatedRowIndexes,
        )
    }

    func isPureEntryRowUpdate(
        old: [EntryListOutlineProjection.ItemID],
        new: [EntryListOutlineProjection.ItemID],
        projection: EntryListOutlineProjection,
    ) -> Bool {
        guard !old.isEmpty, !new.isEmpty else { return false }
        guard old.allSatisfy({ if case .entry = $0 { true } else { false } }) else { return false }
        guard new.allSatisfy({ if case .entry = $0 { true } else { false } }) else { return false }
        return projection.visibleRows.count == projection.rootItemIDs.count
    }

    func entryItemIDMap(from items: [OutlineItem]) -> [EntryListOutlineProjection.ItemID: OutlineItem] {
        Dictionary(uniqueKeysWithValues: items.compactMap { item -> (
            EntryListOutlineProjection.ItemID,
            OutlineItem
        )? in
            guard case let .entry(entry) = item.kind else { return nil }
            return (.entry(entry.id), item)
        })
    }

    func mergedIncomingItems(
        new: [EntryListOutlineProjection.ItemID],
        oldItemsByID: [EntryListOutlineProjection.ItemID: OutlineItem],
        incomingItemsByID: [EntryListOutlineProjection.ItemID: OutlineItem],
    ) -> [OutlineItem] {
        new.compactMap { itemID in
            guard let existing = oldItemsByID[itemID] else { return incomingItemsByID[itemID] }
            if let incoming = incomingItemsByID[itemID] {
                existing.kind = incoming.kind
                existing.isLoadingChildren = incoming.isLoadingChildren
            }
            return existing
        }
    }

    func makeIncrementalRootMoveOperations(
        current initial: [EntryListOutlineProjection.ItemID],
        new: [EntryListOutlineProjection.ItemID],
    ) -> [(from: Int, to: Int)]? {
        var current = initial
        var moveOperations: [(from: Int, to: Int)] = []
        for (targetIndex, itemID) in new.enumerated() {
            guard let currentIndex = current.firstIndex(of: itemID) else { return nil }
            if currentIndex != targetIndex {
                current.remove(at: currentIndex)
                current.insert(itemID, at: targetIndex)
                moveOperations.append((currentIndex, targetIndex))
            }
        }
        guard current == new,
              moveOperations.count <= Self.maxIncrementalRootMoveOperations
        else { return nil }
        return moveOperations
    }

    func rebuildItemIndexes() {
        entryItemsByID = outlineItems.flatMap { $0.flattenEntries() }.reduce(into: [:]) { itemsByID, element in
            itemsByID[element.0, default: []].append(element.1)
        }
        outlineItemByID = Dictionary(uniqueKeysWithValues: outlineItems.flatMap { $0.flattenItems() })
        entryItemById = Dictionary(
            outlineItems.flatMap { $0.flattenEntries() },
            uniquingKeysWith: { first, _ in first },
        )
        groupItemByName = Dictionary(uniqueKeysWithValues: outlineItems.compactMap { item in
            if case let .group(name, _, _) = item.kind {
                return (name, item)
            }
            return nil
        })
    }

    func applyFolderExpansionState(for projection: EntryListOutlineProjection) {
        for itemID in projection.rootItemIDs {
            applyFolderExpansionState(itemID: itemID, projection: projection)
        }
    }

    func applyFolderExpansionState(itemID: EntryListOutlineProjection.ItemID, projection: EntryListOutlineProjection) {
        guard case let .entry(entryID) = itemID,
              let item = outlineItemByID["entry:\(entryID)"]
        else {
            return
        }
        if projection.childrenByParent[itemID] != nil {
            tableView.expandItem(item)
        } else {
            tableView.collapseItem(item)
        }
        for childID in projection.childrenByParent[itemID, default: []] {
            applyFolderExpansionState(itemID: childID, projection: projection)
        }
    }

    var isHierarchyOutlineEnabled: Bool {
        RenderSnapshot(state: state).isHierarchyOutlineEnabled
    }

    func isCurrentOutlineItem(_ item: OutlineItem) -> Bool {
        outlineItemByID[item.id] === item
    }

    func applyGroupExpansionState() {
        isUpdatingGroupExpansion = true
        for (name, item) in groupItemByName {
            if state.entryArrangements.collapsedGroups.contains(name) {
                tableView.collapseItem(item)
            } else {
                tableView.expandItem(item)
            }
        }
        isUpdatingGroupExpansion = false
    }
}

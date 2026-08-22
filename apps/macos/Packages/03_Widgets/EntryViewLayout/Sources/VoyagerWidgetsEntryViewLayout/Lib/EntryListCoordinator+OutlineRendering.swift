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
                let appliedHierarchyIdentitySwap = hasVisibleHierarchyRows
                    && lastProjectionHasHierarchyTopology == hasHierarchyTopology
                    && tryIncrementalHierarchyIdentitySwap(items: items)
                let shouldForceFullReload = lastProjectionHasHierarchyTopology != hasHierarchyTopology
                    || (hasVisibleHierarchyRows && !appliedHierarchyIdentitySwap)
                if !appliedHierarchyIdentitySwap,
                   shouldForceFullReload || !tryIncrementalRowUpdate(
                       old: oldVisibleRows,
                       new: newVisibleRows,
                       items: items,
                       projection: projection,
                   )
                {
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

    func tryIncrementalFlatRootRowUpdate(
        incomingItems: [OutlineItem],
        changes: EntryViewLayoutPresentationChangeSet,
        presentation: EntryViewLayoutPresentation,
    ) -> Bool {
        let oldEntries = outlineItems.compactMap { item -> EntryModel? in
            guard case let .entry(entry) = item.kind else { return nil }
            return entry
        }
        let newEntries = incomingItems.compactMap { item -> EntryModel? in
            guard case let .entry(entry) = item.kind else { return nil }
            return entry
        }
        guard oldEntries.count == outlineItems.count,
              newEntries.count == incomingItems.count
        else { return false }

        let oldIDs = oldEntries.map(\.id)
        let newIDs = newEntries.map(\.id)
        let oldIDSet = Set(oldIDs)
        let newIDSet = Set(newIDs)
        let removed = IndexSet(oldIDs.enumerated().compactMap { newIDSet.contains($0.element) ? nil : $0.offset })
        let inserted = IndexSet(newIDs.enumerated().compactMap { oldIDSet.contains($0.element) ? nil : $0.offset })
        guard !removed.isEmpty || !inserted.isEmpty,
              max(removed.count, inserted.count) == 1
        else { return false }
        let retained = oldIDSet.intersection(newIDSet)
        guard oldIDs.filter(retained.contains) == newIDs.filter(retained.contains) else { return false }

        let oldItemsByID = Dictionary(uniqueKeysWithValues: zip(oldEntries, outlineItems).map { ($0.id, $1) })
        outlineItems = zip(newEntries, incomingItems).map { entry, incoming in
            guard let existing = oldItemsByID[entry.id] else { return incoming }
            existing.kind = incoming.kind
            existing.isLoadingChildren = incoming.isLoadingChildren
            return existing
        }
        rebuildItemIndexes()
        tableView.beginUpdates()
        if !removed.isEmpty {
            tableView.removeItems(at: removed, inParent: nil, withAnimation: .slideLeft)
        }
        if !inserted.isEmpty {
            tableView.insertItems(at: inserted, inParent: nil, withAnimation: .slideDown)
        }
        tableView.endUpdates()
        if !changes.updatedEntryIDs.isEmpty {
            reloadVisibleRowsForPresentationChange(
                changedEntryIDs: changes.updatedEntryIDs,
                presentation: presentation,
            )
        }
        return true
    }

    func tryIncrementalHierarchyIdentitySwap(items: [OutlineItem]) -> Bool {
        guard let plan = makeHierarchyIdentitySwapPlan(items: items) else { return false }
        applyHierarchyIdentitySwap(plan, items: items)
        let parent = outlineItems[plan.rootIndex]
        rebuildItemIndexes()
        tableView.beginUpdates()
        tableView.removeItems(at: plan.removed, inParent: parent, withAnimation: .slideLeft)
        tableView.insertItems(at: plan.inserted, inParent: parent, withAnimation: .slideDown)
        tableView.endUpdates()
        return true
    }

    private func makeHierarchyIdentitySwapPlan(items: [OutlineItem]) -> HierarchyIdentitySwapPlan? {
        guard outlineItems.count == items.count else { return nil }
        var candidate: HierarchyIdentitySwapPlan?
        for (rootIndex, pair) in zip(outlineItems, items).enumerated() {
            switch hierarchyRootIdentityDelta(existing: pair.0, incoming: pair.1, rootIndex: rootIndex) {
            case .unchanged:
                continue
            case let .swap(plan):
                guard candidate == nil else { return nil }
                candidate = plan
            case .unsupported:
                return nil
            }
        }
        return candidate
    }

    private func hierarchyRootIdentityDelta(
        existing: OutlineItem,
        incoming: OutlineItem,
        rootIndex: Int,
    ) -> HierarchyRootIdentityDelta {
        guard outlineEntryID(existing) == outlineEntryID(incoming) else { return .unsupported }
        let oldIDs = existing.children.compactMap(outlineEntryID)
        let newIDs = incoming.children.compactMap(outlineEntryID)
        guard oldIDs.count == existing.children.count,
              newIDs.count == incoming.children.count
        else { return .unsupported }
        guard oldIDs != newIDs else {
            return outlineEntryShape(existing) == outlineEntryShape(incoming) ? .unchanged : .unsupported
        }

        let oldIDSet = Set(oldIDs)
        let newIDSet = Set(newIDs)
        let removed = IndexSet(oldIDs.enumerated().compactMap { newIDSet.contains($0.element) ? nil : $0.offset })
        let inserted = IndexSet(newIDs.enumerated().compactMap { oldIDSet.contains($0.element) ? nil : $0.offset })
        guard removed.count == 1, inserted.count == 1 else { return .unsupported }
        let retained = oldIDSet.intersection(newIDSet)
        guard oldIDs.filter(retained.contains) == newIDs.filter(retained.contains),
              retainedHierarchyChildrenHaveSameShape(
                  retained,
                  existingChildren: existing.children,
                  incomingChildren: incoming.children,
              )
        else { return .unsupported }
        return .swap(.init(rootIndex: rootIndex, removed: removed, inserted: inserted))
    }

    private func retainedHierarchyChildrenHaveSameShape(
        _ retained: Set<EntryModel.ID>,
        existingChildren: [OutlineItem],
        incomingChildren: [OutlineItem],
    ) -> Bool {
        let existingByID = outlineItemsByEntryID(existingChildren)
        let incomingByID = outlineItemsByEntryID(incomingChildren)
        return retained.allSatisfy { id in
            guard let existing = existingByID[id], let incoming = incomingByID[id] else { return false }
            return outlineEntryShape(existing) == outlineEntryShape(incoming)
        }
    }

    private func applyHierarchyIdentitySwap(_ plan: HierarchyIdentitySwapPlan, items: [OutlineItem]) {
        for (rootIndex, pair) in zip(outlineItems, items).enumerated() {
            let existingRoot = pair.0
            let incomingRoot = pair.1
            guard rootIndex == plan.rootIndex else {
                mergeOutlinePayload(existing: existingRoot, incoming: incomingRoot)
                continue
            }
            let existingChildrenByID = outlineItemsByEntryID(existingRoot.children)
            existingRoot.kind = incomingRoot.kind
            existingRoot.isLoadingChildren = incomingRoot.isLoadingChildren
            existingRoot.children = incomingRoot.children.map { incomingChild in
                guard let id = outlineEntryID(incomingChild), let existingChild = existingChildrenByID[id] else {
                    return incomingChild
                }
                mergeOutlinePayload(existing: existingChild, incoming: incomingChild)
                return existingChild
            }
        }
    }

    private func outlineItemsByEntryID(_ items: [OutlineItem]) -> [EntryModel.ID: OutlineItem] {
        Dictionary(uniqueKeysWithValues: items.compactMap { item in
            outlineEntryID(item).map { ($0, item) }
        })
    }

    func sectionsMatch(
        _ previous: EntryViewLayoutPresentation,
        _ current: EntryViewLayoutPresentation,
    ) -> Bool {
        guard previous.sections.count == current.sections.count else { return false }
        return previous.sections.enumerated().allSatisfy { index, section in
            let next = current.sections[index]
            return section.id == next.id
                && section.title == next.title
                && section.colorCode == next.colorCode
                && section.isCollapsed == next.isCollapsed
        }
    }

    private func outlineEntryID(_ item: OutlineItem) -> EntryModel.ID? {
        guard case let .entry(entry) = item.kind else { return nil }
        return entry.id
    }

    private func outlineEntryShape(_ item: OutlineItem) -> [EntryModel.ID]? {
        guard let id = outlineEntryID(item) else { return nil }
        let childShapes = item.children.compactMap(outlineEntryShape)
        guard childShapes.count == item.children.count else { return nil }
        return [id] + childShapes.flatMap(\.self)
    }

    private func mergeOutlinePayload(existing: OutlineItem, incoming: OutlineItem) {
        existing.kind = incoming.kind
        existing.isLoadingChildren = incoming.isLoadingChildren
        for (existingChild, incomingChild) in zip(existing.children, incoming.children) {
            mergeOutlinePayload(existing: existingChild, incoming: incomingChild)
        }
    }

    private struct HierarchyIdentitySwapPlan {
        let rootIndex: Int
        let removed: IndexSet
        let inserted: IndexSet
    }

    private enum HierarchyRootIdentityDelta {
        case unchanged
        case swap(HierarchyIdentitySwapPlan)
        case unsupported
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
        applyGroupExpansionState(presentation: state.presentation)
    }

    /// state 재유도 없이 전달된 presentation의 접힘 상태를 outline에 적용한다.
    func applyGroupExpansionState(presentation: EntryViewLayoutPresentation) {
        isUpdatingGroupExpansion = true
        for section in presentation.sections {
            guard let name = section.title, let item = groupItemByName[name] else { continue }
            if section.isCollapsed {
                tableView.collapseItem(item)
            } else {
                tableView.expandItem(item)
            }
        }
        isUpdatingGroupExpansion = false
    }
}

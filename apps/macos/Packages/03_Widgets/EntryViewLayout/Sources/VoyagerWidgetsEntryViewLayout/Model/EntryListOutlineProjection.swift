import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

public struct EntryListOutlineProjection: Equatable, Sendable {
    public enum ItemID: Hashable, Sendable {
        case entry(EntryModel.ID)
        case empty(parent: EntryModel.ID)
        case error(parent: EntryModel.ID)
    }

    public enum ItemPayload: Equatable, Sendable {
        case entry(EntryModel, isLoadingChildren: Bool)
        case empty(parent: EntryModel.ID)
        case error(parent: EntryModel.ID, failure: EntryListHierarchyFailure)

        public var isSelectable: Bool {
            if case .entry = self {
                return true
            }
            return false
        }

        public var isRetryable: Bool {
            if case .error = self {
                return true
            }
            return false
        }

        public var retryFolderID: EntryModel.ID? {
            if case let .error(parent, _) = self {
                return parent
            }
            return nil
        }
    }

    public struct Context: Equatable, Sendable {
        public let mode: EntryViewLayoutState.Mode
        public let isNormalDirectoryPage: Bool
        public let hasActiveGrouping: Bool

        public init(
            mode: EntryViewLayoutState.Mode,
            isNormalDirectoryPage: Bool,
            hasActiveGrouping: Bool,
        ) {
            self.mode = mode
            self.isNormalDirectoryPage = isNormalDirectoryPage
            self.hasActiveGrouping = hasActiveGrouping
        }

        public var isHierarchyEnabled: Bool {
            mode == .list && isNormalDirectoryPage && !hasActiveGrouping
        }
    }

    public let revision: Int
    public let rootItemIDs: [ItemID]
    public let childrenByParent: [ItemID: [ItemID]]
    public let itemPayloads: [ItemID: ItemPayload]
    public let visibleRows: [ItemID]
    public let visibleSelectableEntryIDs: [EntryModel.ID]

    public var visibleSelectableEntries: [EntryModel] {
        visibleRows.compactMap { itemID in
            guard case let .entry(entry, _) = itemPayloads[itemID] else { return nil }
            return entry
        }
    }

    /// Compares two projections ignoring the `revision` field.
    /// This is used to detect structural changes without treating a revision bump
    /// (e.g., from selection-only reconciliation) as a structural change.
    func hasSameStructure(as other: EntryListOutlineProjection) -> Bool {
        rootItemIDs == other.rootItemIDs
            && childrenByParent == other.childrenByParent
            && itemPayloads == other.itemPayloads
            && visibleRows == other.visibleRows
            && visibleSelectableEntryIDs == other.visibleSelectableEntryIDs
    }

    public init(
        revision: Int,
        rootEntries: [EntryModel],
        hierarchyState: EntryListHierarchyState,
        context: Context,
        sortKey: SortKey,
        sortOrder: VoyagerShared.SortOrder,
    ) {
        self.revision = revision

        guard context.isHierarchyEnabled else {
            let rootItemIDs = rootEntries.map { ItemID.entry($0.id) }
            let itemPayloads: [ItemID: ItemPayload] = Dictionary(
                uniqueKeysWithValues: rootEntries.map { entry in
                    (ItemID.entry(entry.id), ItemPayload.entry(entry, isLoadingChildren: false))
                },
            )
            self.rootItemIDs = rootItemIDs
            childrenByParent = [:]
            self.itemPayloads = itemPayloads
            visibleRows = rootItemIDs
            visibleSelectableEntryIDs = rootEntries.map(\.id)
            return
        }

        var builder = Builder(
            hierarchyState: hierarchyState,
            sortKey: sortKey,
            sortOrder: sortOrder,
        )
        let sortedRoots = sortEntries(rootEntries, by: sortKey, order: sortOrder)
        let rootItemIDs = builder.append(entries: sortedRoots)

        self.rootItemIDs = rootItemIDs
        childrenByParent = builder.childrenByParent
        itemPayloads = builder.itemPayloads
        visibleRows = builder.visibleRows
        visibleSelectableEntryIDs = builder.visibleSelectableEntryIDs
    }
}

private extension EntryListOutlineProjection {
    struct Builder {
        let hierarchyState: EntryListHierarchyState
        let sortKey: SortKey
        let sortOrder: VoyagerShared.SortOrder
        var childrenByParent: [ItemID: [ItemID]] = [:]
        var itemPayloads: [ItemID: ItemPayload] = [:]
        var visibleRows: [ItemID] = []
        var visibleSelectableEntryIDs: [EntryModel.ID] = []
        var visitedFolders: Set<EntryModel.ID> = []

        mutating func append(entries: [EntryModel]) -> [ItemID] {
            entries.map { entry in
                append(entry: entry)
            }
        }

        mutating func append(entry: EntryModel) -> ItemID {
            let entryID = ItemID.entry(entry.id)
            let folderState = hierarchyState.foldersByID[entry.id]
            let isLoadingChildren = entry.supportsListHierarchyExpansion
                && hierarchyState.expandedFolderIDs.contains(entry.id)
                && folderState?.phase == .loading
                && folderState?.coreFinished == false
            itemPayloads[entryID] = .entry(entry, isLoadingChildren: isLoadingChildren)
            visibleRows.append(entryID)
            visibleSelectableEntryIDs.append(entry.id)

            guard entry.supportsListHierarchyExpansion,
                  hierarchyState.expandedFolderIDs.contains(entry.id),
                  !visitedFolders.contains(entry.id)
            else {
                return entryID
            }

            visitedFolders.insert(entry.id)
            let childItemIDs = childItems(for: entry.id)
            childrenByParent[entryID] = childItemIDs
            return entryID
        }

        mutating func childItems(for folderID: EntryModel.ID) -> [ItemID] {
            let folderState = hierarchyState.foldersByID[folderID] ?? .init()
            switch folderState.phase {
            case .idle:
                return []

            case .loading:
                guard !folderState.coreFinished || !folderState.children.isEmpty else {
                    let itemID = ItemID.empty(parent: folderID)
                    itemPayloads[itemID] = .empty(parent: folderID)
                    visibleRows.append(itemID)
                    return [itemID]
                }
                let sortedChildren = sortEntries(folderState.children, by: sortKey, order: sortOrder)
                return append(entries: sortedChildren)

            case .loaded:
                guard !folderState.children.isEmpty else {
                    let itemID = ItemID.empty(parent: folderID)
                    itemPayloads[itemID] = .empty(parent: folderID)
                    visibleRows.append(itemID)
                    return [itemID]
                }
                let sortedChildren = sortEntries(folderState.children, by: sortKey, order: sortOrder)
                return append(entries: sortedChildren)

            case let .failed(failure):
                var itemIDs = append(entries: sortEntries(folderState.children, by: sortKey, order: sortOrder))
                let itemID = ItemID.error(parent: folderID)
                itemPayloads[itemID] = .error(parent: folderID, failure: failure)
                visibleRows.append(itemID)
                itemIDs.append(itemID)
                return itemIDs
            }
        }
    }
}

private func sortEntries(
    _ items: [EntryModel],
    by sortKey: SortKey,
    order: VoyagerShared.SortOrder,
) -> [EntryModel] {
    items.sorted { item1, item2 in
        let comparison = stableComparison(item1, item2, by: sortKey)
        return order == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
}

private func stableComparison(
    _ item1: EntryModel,
    _ item2: EntryModel,
    by sortKey: SortKey,
) -> ComparisonResult {
    let primary = compareItems(item1, item2, by: sortKey)
    guard primary == .orderedSame else { return primary }
    let nameComparison = item1.name.localizedCaseInsensitiveCompare(item2.name)
    guard nameComparison == .orderedSame else { return nameComparison }
    return item1.fullPath.localizedCaseInsensitiveCompare(item2.fullPath)
}

private func compareItems(
    _ item1: EntryModel,
    _ item2: EntryModel,
    by sortKey: SortKey,
) -> ComparisonResult {
    switch sortKey {
    case .name:
        return item1.name.localizedCaseInsensitiveCompare(item2.name)
    case .kind:
        return item1.facets.kind.localizedCaseInsensitiveCompare(item2.facets.kind)
    case .application:
        let app1 = item1.facets.creatorApplication ?? ""
        let app2 = item2.facets.creatorApplication ?? ""
        return app1.localizedCaseInsensitiveCompare(app2)
    case .dateLastOpened:
        return compareDates(
            item1.facets.lastOpenedDate ?? .distantPast,
            item2.facets.lastOpenedDate ?? .distantPast,
        )
    case .dateAdded:
        return compareDates(item1.facets.addedDate, item2.facets.addedDate)
    case .dateModified:
        return compareDates(item1.modifiedDate, item2.modifiedDate)
    case .dateCreated:
        return compareDates(item1.facets.createdDate, item2.facets.createdDate)
    case .size:
        return compareSizes(item1.size, item2.size)
    case .tags:
        let tag1Name = item1.facets.tags?.first?.name ?? ""
        let tag2Name = item2.facets.tags?.first?.name ?? ""
        return tag1Name.localizedCaseInsensitiveCompare(tag2Name)
    }
}

private func compareDates(_ date1: Date, _ date2: Date) -> ComparisonResult {
    if date1 < date2 { return .orderedAscending }
    if date1 > date2 { return .orderedDescending }
    return .orderedSame
}

private func compareSizes(_ size1: Int64, _ size2: Int64) -> ComparisonResult {
    if size1 < size2 { return .orderedAscending }
    if size1 > size2 { return .orderedDescending }
    return .orderedSame
}

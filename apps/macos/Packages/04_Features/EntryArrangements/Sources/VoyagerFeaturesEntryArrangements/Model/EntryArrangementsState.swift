import Foundation

import VoyagerShared

public struct EntryArrangementsState: Equatable, Sendable {
    public var sortKey: SortKey
    public var sortOrder: VoyagerShared.SortOrder
    public var hasUserSetSortOrder: Bool
    public var groupKey: GroupKey
    public var groupedItems: [GroupedItems]
    public var collapsedGroups: Set<String>

    public init(
        sortKey: SortKey = .name,
        sortOrder: VoyagerShared.SortOrder = .ascending,
        hasUserSetSortOrder: Bool = false,
        groupKey: GroupKey = .none,
        groupedItems: [GroupedItems] = [],
        collapsedGroups: Set<String> = []
    ) {
        self.sortKey = sortKey
        self.sortOrder = sortOrder
        self.hasUserSetSortOrder = hasUserSetSortOrder
        self.groupKey = groupKey
        self.groupedItems = groupedItems
        self.collapsedGroups = collapsedGroups
    }

    public mutating func updateSortKey(_ key: SortKey) {
        sortKey = key
        if !hasUserSetSortOrder {
            sortOrder = defaultSortOrder(for: key)
        }
    }

    public mutating func updateSortOrder(_ order: VoyagerShared.SortOrder) {
        sortOrder = order
        hasUserSetSortOrder = true
    }

    public mutating func updateGroupKey(_ key: GroupKey) {
        groupKey = key
    }

    private func defaultSortOrder(for key: SortKey) -> VoyagerShared.SortOrder {
        switch key {
        case .dateModified, .dateCreated, .dateAdded, .dateLastOpened:
            .descending
        case .name, .kind, .application, .size, .tags:
            .ascending
        }
    }
}

public enum EntryArrangementsPersistenceKey {
    public static let sortKey = "sortKey"
    public static let sortOrder = "sortOrder"
    public static let groupKey = "groupKey"
}

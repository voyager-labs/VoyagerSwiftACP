import Foundation

struct EntryArrangementsState: Equatable, Sendable {
    var sortKey: SortKey
    var sortOrder: SortOrder
    var hasUserSetSortOrder: Bool
    var groupKey: GroupKey
    var groupedItems: [GroupedItems]
    var collapsedGroups: Set<String>

    init(
        sortKey: SortKey = .name,
        sortOrder: SortOrder = .ascending,
        hasUserSetSortOrder: Bool = false,
        groupKey: GroupKey = .none,
        groupedItems: [GroupedItems] = [],
        collapsedGroups: Set<String> = [],
    ) {
        self.sortKey = sortKey
        self.sortOrder = sortOrder
        self.hasUserSetSortOrder = hasUserSetSortOrder
        self.groupKey = groupKey
        self.groupedItems = groupedItems
        self.collapsedGroups = collapsedGroups
    }

    mutating func updateSortKey(_ key: SortKey) {
        sortKey = key
        if !hasUserSetSortOrder {
            sortOrder = defaultSortOrder(for: key)
        }
    }

    mutating func updateSortOrder(_ order: SortOrder) {
        sortOrder = order
        hasUserSetSortOrder = true
    }

    mutating func updateGroupKey(_ key: GroupKey) {
        groupKey = key
    }

    private func defaultSortOrder(for key: SortKey) -> SortOrder {
        switch key {
        case .dateModified, .dateCreated, .dateAdded, .dateLastOpened:
            .descending
        case .name, .kind, .application, .size, .tags:
            .ascending
        }
    }
}

enum EntryArrangementsPersistenceKey {
    static let sortKey = "sortKey"
    static let sortOrder = "sortOrder"
    static let groupKey = "groupKey"
}

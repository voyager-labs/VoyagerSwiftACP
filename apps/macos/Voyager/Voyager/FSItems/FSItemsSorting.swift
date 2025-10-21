import Foundation

enum SortKey: String, Equatable, CaseIterable {
    case name
    case kind
    case dateAdded
    case dateModified
    case dateCreated
    case size
}

enum SortOrder: String, Equatable {
    case ascending
    case descending
}

enum FSItemsSorting {
    static func sortItems(
        _ items: [FSItemModel],
        by sortKey: SortKey,
        order: SortOrder
    ) -> [FSItemModel] {
        items.sorted { item1, item2 in
            let comparison: ComparisonResult
            switch sortKey {
            case .name:
                comparison = item1.name.localizedCaseInsensitiveCompare(item2.name)
            case .kind:
                comparison = item1.kind.localizedCaseInsensitiveCompare(item2.kind)
            case .dateAdded:
                comparison = item1.addedDate < item2.addedDate ? .orderedAscending :
                    item1.addedDate > item2.addedDate ? .orderedDescending : .orderedSame
            case .dateModified:
                comparison = item1.modifiedDate < item2.modifiedDate ? .orderedAscending :
                    item1.modifiedDate > item2.modifiedDate ? .orderedDescending : .orderedSame
            case .dateCreated:
                comparison = item1.createdDate < item2.createdDate ? .orderedAscending :
                    item1.createdDate > item2.createdDate ? .orderedDescending : .orderedSame
            case .size:
                comparison = item1.size < item2.size ? .orderedAscending :
                    item1.size > item2.size ? .orderedDescending : .orderedSame
            }

            switch order {
            case .ascending:
                return comparison == .orderedAscending
            case .descending:
                return comparison == .orderedDescending
            }
        }
    }
}

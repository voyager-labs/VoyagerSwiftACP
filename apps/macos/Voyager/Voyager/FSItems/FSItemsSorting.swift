import Foundation

enum SortKey: String, Equatable, CaseIterable {
    case name
    case size
    case modified
    case type
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
            case .size:
                comparison = item1.size < item2.size ? .orderedAscending :
                    item1.size > item2.size ? .orderedDescending : .orderedSame
            case .modified:
                comparison = item1.modifiedDate < item2.modifiedDate ? .orderedAscending :
                    item1.modifiedDate > item2.modifiedDate ? .orderedDescending : .orderedSame
            case .type:
                comparison = item1.kind.localizedCaseInsensitiveCompare(item2.kind)
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

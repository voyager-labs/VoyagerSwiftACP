import Foundation

enum SortKey: String, Equatable, CaseIterable {
    case name
    case kind
    case application = "Application"
    case dateLastOpened
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
        _ items: [FSItem],
        by sortKey: SortKey,
        order: SortOrder
    ) -> [FSItem] {
        items.sorted { item1, item2 in
            let comparison: ComparisonResult
            switch sortKey {
            case .name:
                comparison = item1.name.localizedCaseInsensitiveCompare(item2.name)
            case .kind:
                comparison = item1.kind.localizedCaseInsensitiveCompare(item2.kind)
            case .application:
                let app1 = item1.creatorApplication ?? ""
                let app2 = item2.creatorApplication ?? ""
                comparison = app1.localizedCaseInsensitiveCompare(app2)
            case .dateLastOpened:
                let date1 = item1.lastOpenedDate ?? .distantPast
                let date2 = item2.lastOpenedDate ?? .distantPast
                comparison = date1 < date2 ? .orderedAscending :
                    date1 > date2 ? .orderedDescending : .orderedSame
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

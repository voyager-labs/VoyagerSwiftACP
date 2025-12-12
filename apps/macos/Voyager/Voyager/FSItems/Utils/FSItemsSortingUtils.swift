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
    case tags = "Tags"
}

enum SortOrder: String, Equatable {
    case ascending
    case descending
}

enum FSItemsSortingUtils {
    static func sortItems(
        _ items: [FSItem],
        by sortKey: SortKey,
        order: SortOrder,
    ) -> [FSItem] {
        items.sorted { item1, item2 in
            let comparison = compareItems(item1, item2, by: sortKey)
            return order == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private static func compareItems(_ item1: FSItem, _ item2: FSItem, by sortKey: SortKey) -> ComparisonResult {
        switch sortKey {
        case .name:
            return item1.name.localizedCaseInsensitiveCompare(item2.name)
        case .kind:
            return item1.kind.localizedCaseInsensitiveCompare(item2.kind)
        case .application:
            let app1 = item1.creatorApplication ?? ""
            let app2 = item2.creatorApplication ?? ""
            return app1.localizedCaseInsensitiveCompare(app2)
        case .dateLastOpened:
            return compareDates(item1.lastOpenedDate ?? .distantPast, item2.lastOpenedDate ?? .distantPast)
        case .dateAdded:
            return compareDates(item1.addedDate, item2.addedDate)
        case .dateModified:
            return compareDates(item1.modifiedDate, item2.modifiedDate)
        case .dateCreated:
            return compareDates(item1.createdDate, item2.createdDate)
        case .size:
            return compareSizes(item1.size, item2.size)
        case .tags:
            let tag1Name = item1.tags?.first?.name ?? ""
            let tag2Name = item2.tags?.first?.name ?? ""
            return tag1Name.localizedCaseInsensitiveCompare(tag2Name)
        }
    }

    private static func compareDates(_ date1: Date, _ date2: Date) -> ComparisonResult {
        if date1 < date2 { return .orderedAscending }
        if date1 > date2 { return .orderedDescending }
        return .orderedSame
    }

    private static func compareSizes(_ size1: Int64, _ size2: Int64) -> ComparisonResult {
        if size1 < size2 { return .orderedAscending }
        if size1 > size2 { return .orderedDescending }
        return .orderedSame
    }
}

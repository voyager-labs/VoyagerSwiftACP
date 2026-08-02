import Foundation
import VoyagerShared

public struct EntrySiblingSorter: Sendable {
    public init() {}

    public func sort(
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
        guard primary == .orderedSame else {
            return primary
        }

        let nameComparison = item1.name.localizedCaseInsensitiveCompare(item2.name)
        guard nameComparison == .orderedSame else {
            return nameComparison
        }

        return item1.fullPath.localizedCaseInsensitiveCompare(item2.fullPath)
    }

    private func compareItems(_ item1: EntryModel, _ item2: EntryModel, by sortKey: SortKey) -> ComparisonResult {
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
}

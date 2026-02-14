import ComposableArchitecture
import Foundation

@Reducer
struct EntryArrangementsSortingReducer {
    typealias State = FileManagerContentState
    typealias Action = EntryArrangementsAction

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setSortKey(key):
                state.entryArrangements.updateSortKey(key)
                applySorting(state: &state)
                userDefaultsClient.setString(key.rawValue, EntryArrangementsPersistenceKey.sortKey)
                return .none

            case let .setSortOrder(order):
                state.entryArrangements.updateSortOrder(order)
                applySorting(state: &state)
                userDefaultsClient.setString(order.rawValue, EntryArrangementsPersistenceKey.sortOrder)
                return .none

            case .reapply:
                applySorting(state: &state)
                return .none

            case .setGroupKey, .toggleCollapsedGroup:
                return .none
            }
        }
    }

    private func applySorting(state: inout State) {
        let arrangements = state.entryArrangements
        let sortedItems = sortItems(
            Array(state.entries.displayItems),
            by: arrangements.sortKey,
            order: arrangements.sortOrder,
        )

        if state.entries.isCollectionMode {
            state.entries.collectionItems = IdentifiedArray(uniqueElements: sortedItems)
        } else {
            state.entries.items = IdentifiedArray(uniqueElements: sortedItems)
        }
    }

    private func sortItems(
        _ items: [Entry],
        by sortKey: SortKey,
        order: SortOrder,
    ) -> [Entry] {
        items.sorted { item1, item2 in
            let comparison = compareItems(item1, item2, by: sortKey)
            return order == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private func compareItems(_ item1: Entry, _ item2: Entry, by sortKey: SortKey) -> ComparisonResult {
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

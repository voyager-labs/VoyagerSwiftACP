import Foundation
import VoyagerWidgetsEntryViewLayout

struct EntryArrangementMenuItem<Key: Hashable & Equatable>: Identifiable, Equatable {
    let key: Key
    let title: String

    var id: Key { key }
}

typealias EntryArrangementSortMenuItem = EntryArrangementMenuItem<SortKey>
typealias EntryArrangementGroupMenuItem = EntryArrangementMenuItem<GroupKey>

enum EntryArrangementMenuItems {
    static let sortItems: [EntryArrangementSortMenuItem] = SortKey.menuKeys.map { key in
        .init(
            key: key,
            title: labelClient.labelForPropertyKey(key.systemPropertyKey),
        )
    }

    static let groupItems: [EntryArrangementGroupMenuItem] = GroupKey.menuKeys.compactMap { key in
        guard let propertyKey = key.systemPropertyKey else {
            return nil
        }
        return .init(
            key: key,
            title: labelClient.labelForPropertyKey(propertyKey),
        )
    }

    private static let labelClient = EntryArrangementMenuLabelClient.live
}

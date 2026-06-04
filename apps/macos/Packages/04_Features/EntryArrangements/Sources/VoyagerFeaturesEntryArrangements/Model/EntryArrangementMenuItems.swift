import Foundation
import VoyagerShared

public struct EntryArrangementMenuItem<Key: Hashable & Equatable & Sendable>: Identifiable, Equatable, Sendable {
    public let key: Key
    public let title: String

    public var id: Key {
        key
    }
}

public typealias EntryArrangementSortMenuItem = EntryArrangementMenuItem<SortKey>
public typealias EntryArrangementGroupMenuItem = EntryArrangementMenuItem<GroupKey>

public enum EntryArrangementMenuItems {
    public static let sortItems: [EntryArrangementSortMenuItem] = SortKey.menuKeys.map { key in
        .init(
            key: key,
            title: labelClient.labelForPropertyKey(key.systemPropertyKey),
        )
    }

    public static let groupItems: [EntryArrangementGroupMenuItem] = GroupKey.menuKeys.compactMap { key in
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

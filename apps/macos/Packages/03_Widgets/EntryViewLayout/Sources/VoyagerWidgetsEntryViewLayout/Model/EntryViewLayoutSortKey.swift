import Foundation
import VoyagerShared

public enum EntryViewLayoutSortKey: String, Equatable, Codable, Sendable, CaseIterable {
    case name
    case kind
    case application
    case size
    case dateModified
    case dateCreated
    case dateAdded
    case dateLastOpened
    case tags
}

public extension EntryViewLayoutSortKey {
    /// Convert to the shared `VoyagerShared.SortKey` for use with outline projection.
    var sharedSortKey: SortKey {
        switch self {
        case .name: .name
        case .kind: .kind
        case .application: .application
        case .size: .size
        case .dateModified: .dateModified
        case .dateCreated: .dateCreated
        case .dateAdded: .dateAdded
        case .dateLastOpened: .dateLastOpened
        case .tags: .tags
        }
    }

    /// Convert from a shared `VoyagerShared.SortKey`.
    static func fromShared(_ sortKey: SortKey) -> EntryViewLayoutSortKey {
        switch sortKey {
        case .name: .name
        case .kind: .kind
        case .application: .application
        case .size: .size
        case .dateModified: .dateModified
        case .dateCreated: .dateCreated
        case .dateAdded: .dateAdded
        case .dateLastOpened: .dateLastOpened
        case .tags: .tags
        }
    }
}

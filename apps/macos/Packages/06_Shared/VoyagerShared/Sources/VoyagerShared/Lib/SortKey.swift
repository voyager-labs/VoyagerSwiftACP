import Foundation

public enum SortKey: String, Equatable, CaseIterable, Sendable {
    case name
    case kind
    case application = "Application"
    case dateLastOpened
    case dateAdded
    case dateModified
    case dateCreated
    case size
    case tags = "Tags"

    public static let menuKeys: [SortKey] = [
        .name,
        .kind,
        .application,
        .dateLastOpened,
        .dateAdded,
        .dateModified,
        .dateCreated,
        .size,
        .tags,
    ]

    public var systemPropertyKey: String {
        switch self {
        case .name: "name_stem"
        case .kind: "file_kind"
        case .application: "creator"
        case .dateLastOpened: "last_used_date"
        case .dateAdded: "added_date"
        case .dateModified: "modification_date"
        case .dateCreated: "creation_date"
        case .size: "size"
        case .tags: "keywords"
        }
    }
}

public enum SortOrder: String, Equatable, Sendable {
    case ascending
    case descending
}

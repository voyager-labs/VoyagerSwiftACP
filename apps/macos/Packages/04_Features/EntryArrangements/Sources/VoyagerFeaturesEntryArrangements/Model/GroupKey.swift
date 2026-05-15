import Foundation

public enum GroupKey: String, Equatable, CaseIterable, Sendable {
    case none = "None"
    case name = "Name"
    case kind = "Kind"
    case application = "Application"
    case dateLastOpened = "Date Last Opened"
    case dateAdded = "Date Added"
    case dateModified = "Date Modified"
    case dateCreated = "Date Created"
    case size = "Size"
    case tags = "Tags"

    public static let menuKeys: [GroupKey] = [
        .none,
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

    public var systemPropertyKey: String? {
        switch self {
        case .none: nil
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

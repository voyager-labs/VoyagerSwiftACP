import CoreGraphics
import Foundation
import VoyagerFeaturesEntryArrangements
import VoyagerShared

enum EntryListColumn: String, CaseIterable, Equatable, Sendable {
    case name
    case application
    case dateAdded
    case dateCreated
    case dateLastOpened
    case dateModified
    case size
    case kind

    static let defaultVisibleColumns: [EntryListColumn] = [
        .name,
        .dateModified,
        .size,
        .kind,
    ]

    static let requiredColumns: Set<EntryListColumn> = [.name]

    var title: String {
        switch self {
        case .name:
            "Name"
        case .application:
            "Application"
        case .dateAdded:
            "Date Added"
        case .dateCreated:
            "Date Created"
        case .dateLastOpened:
            "Date Last Opened"
        case .dateModified:
            "Date Modified"
        case .size:
            "Size"
        case .kind:
            "Kind"
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .name:
            220
        case .application:
            140
        case .dateAdded, .dateCreated, .dateLastOpened, .dateModified:
            150
        case .size:
            90
        case .kind:
            120
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .name:
            2400
        case .application:
            360
        case .dateAdded, .dateCreated, .dateLastOpened, .dateModified:
            420
        case .size:
            220
        case .kind:
            360
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name:
            420
        case .application:
            180
        case .dateAdded, .dateCreated, .dateLastOpened, .dateModified:
            220
        case .size:
            110
        case .kind:
            180
        }
    }

    var sortKey: SortKey? {
        switch self {
        case .name:
            .name
        case .application:
            .application
        case .dateAdded:
            .dateAdded
        case .dateCreated:
            .dateCreated
        case .dateLastOpened:
            .dateLastOpened
        case .dateModified:
            .dateModified
        case .size:
            .size
        case .kind:
            .kind
        }
    }

    var sortDescriptorKey: String? {
        guard sortKey != nil else { return nil }
        return rawValue
    }

    var defaultSortAscending: Bool {
        switch self {
        case .dateAdded, .dateCreated, .dateLastOpened, .dateModified:
            false
        case .name, .application, .size, .kind:
            true
        }
    }

    static func normalizeVisibleColumns(_ columns: [EntryListColumn]) -> [EntryListColumn] {
        var normalized: [EntryListColumn] = []
        normalized.reserveCapacity(columns.count)

        for column in columns where !normalized.contains(column) {
            normalized.append(column)
        }

        if normalized.isEmpty {
            normalized = defaultVisibleColumns
        }

        if !normalized.contains(.name) {
            normalized.insert(.name, at: 0)
        }

        return normalized
    }
}

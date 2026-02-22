import CoreGraphics
import Foundation

enum EntryListColumn: String, CaseIterable, Equatable, Sendable {
    case name
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
        case .dateModified:
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
        case .dateModified:
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
        case .dateModified:
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

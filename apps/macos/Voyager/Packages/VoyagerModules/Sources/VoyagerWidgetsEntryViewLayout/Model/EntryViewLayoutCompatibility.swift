import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

import VoyagerEntitiesEntry
import VoyagerShared

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

struct GroupedItems: Equatable, Sendable {
    let groupName: String
    let colorCode: Int?
    let items: [EntryModel]

    init(groupName: String, items: [EntryModel], colorCode: Int? = nil) {
        self.groupName = groupName
        self.colorCode = colorCode
        self.items = items
    }

    var count: Int { items.count }
}

enum CollectionConstants {
    nonisolated static let fileExtension = "voycoll"
}

struct EntryDisplayModel: Sendable {
    let entry: EntryModel

    var formattedSize: String {
        guard !entry.isFolder else { return "--" }
        return ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
    }

    var supplementaryInfoText: String? {
        guard let metadata = entry.facets.supplementaryMetadata else { return nil }
        switch metadata {
        case let .folderItemCount(count):
            return count == 0 ? "No items" : "\(count) item\(count == 1 ? "" : "s")"
        case let .imageResolution(width, height):
            return "\(width) × \(height)"
        case let .compressedFileSize(bytes):
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }
}

final class TagDotNSView: NSView {
    private let dotSize: CGFloat

    init(tagColor: TagColor, size: CGFloat = 8) {
        dotSize = size
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
        update(tagColor: tagColor)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(tagColor: TagColor) {
        layer?.backgroundColor = tagColor.nsColor.cgColor
        layer?.cornerRadius = dotSize / 2
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: dotSize, height: dotSize)
    }
}

enum TagDotImageFactory {
    static func make(tagColor: TagColor, size: CGFloat = 11, inset: CGFloat = 1) -> NSImage {
        let imageSize = NSSize(width: size, height: size)
        let color = tagColor.nsColor
        let image = NSImage(size: imageSize, flipped: false) { rect in
            let circleRect = rect.insetBy(dx: inset, dy: inset)
            color.setFill()
            NSBezierPath(ovalIn: circleRect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

extension WorkspaceClient {
    public func entryIcon(for entry: EntryModel, thumbnail: NSImage?) -> NSImage {
        entryViewLayoutIcon(for: entry, thumbnail: thumbnail)
    }

    func entryViewLayoutIcon(for entry: EntryModel, thumbnail: NSImage?) -> NSImage {
        if let thumbnail {
            return thumbnail
        }

        if entry.fullPath == "/" {
            return iconForFile("/")
        }
        if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            return iconForType(.data)
        }
        if entry.isFolder {
            return iconForFile(entry.fullPath)
        }
        if let utType = UTType(filenameExtension: entry.fileExtension) {
            return iconForType(utType)
        }
        return iconForType(.data)
    }
}

public struct EntryThumbnailState: Equatable, Sendable {
    public var requestsInFlight: Set<String> = []
    public var readyPaths: Set<String> = []
    public var failedPaths: Set<String> = []
    public var renderVersion: Int = 0

    public init() {}
}

@CasePathable
public enum EntryThumbnailAction: CasePathable, Sendable {
    case requestThumbnails(paths: [String])
    case thumbnailsReady(paths: [String])
    case thumbnailRequestFailed(paths: [String])
}

@Reducer
public struct EntryThumbnailFeature {
    public typealias State = EntryThumbnailState
    public typealias Action = EntryThumbnailAction

    @Dependency(\.entryThumbnailCacheClient)
    private var entryThumbnailCacheClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .requestThumbnails(paths):
                let requestedPaths = Array(Set(paths)).filter { !state.requestsInFlight.contains($0) }
                guard !requestedPaths.isEmpty else { return .none }
                state.requestsInFlight.formUnion(requestedPaths)
                let ready = requestedPaths.filter { entryThumbnailCacheClient.getThumbnail($0) != nil }
                let failed = requestedPaths.filter { !ready.contains($0) }
                state.readyPaths.formUnion(ready)
                state.failedPaths.formUnion(failed)
                state.requestsInFlight.subtract(requestedPaths)
                state.renderVersion += 1
                return .none
            case let .thumbnailsReady(paths):
                state.readyPaths.formUnion(paths)
                state.failedPaths.subtract(paths)
                state.requestsInFlight.subtract(paths)
                state.renderVersion += 1
                return .none
            case let .thumbnailRequestFailed(paths):
                state.failedPaths.formUnion(paths)
                state.requestsInFlight.subtract(paths)
                state.renderVersion += 1
                return .none
            }
        }
    }
}

public struct EntryArrangementsState: Equatable, Sendable {
    public var sortKey: SortKey
    public var sortOrder: SortOrder
    public var hasUserSetSortOrder: Bool
    public var groupKey: GroupKey
    var groupedItems: [GroupedItems]
    var collapsedGroups: Set<String>

    public init(
        sortKey: SortKey = .name,
        sortOrder: SortOrder = .ascending,
        hasUserSetSortOrder: Bool = false,
        groupKey: GroupKey = .none,
    ) {
        self.sortKey = sortKey
        self.sortOrder = sortOrder
        self.hasUserSetSortOrder = hasUserSetSortOrder
        self.groupKey = groupKey
        groupedItems = []
        collapsedGroups = []
    }

    public mutating func updateSortKey(_ key: SortKey) {
        sortKey = key
        if !hasUserSetSortOrder {
            sortOrder = [.dateModified, .dateCreated, .dateAdded, .dateLastOpened]
                .contains(key) ? .descending : .ascending
        }
    }

    public mutating func updateSortOrder(_ order: SortOrder) {
        sortOrder = order
        hasUserSetSortOrder = true
    }

    public mutating func updateGroupKey(_ key: GroupKey) {
        groupKey = key
    }
}

@CasePathable
public enum EntryArrangementsAction: CasePathable, Equatable, Sendable {
    case setSortKey(SortKey)
    case setSortOrder(SortOrder)
    case setGroupKey(GroupKey)
    case toggleCollapsedGroup(String)
    case reapply
    case apply(items: [EntryModel], isCollectionMode: Bool)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: CasePathable, Equatable, Sendable {
        case requestApply
        case applied(sortedItems: [EntryModel], isCollectionMode: Bool)
    }
}

@Reducer
public struct EntryArrangementsFeature {
    public typealias State = EntryArrangementsState
    public typealias Action = EntryArrangementsAction

    @Dependency(\.date)
    private var date
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setSortKey(key):
                state.updateSortKey(key)
                userDefaultsClient.setString(key.rawValue, "sortKey")
                return .send(.delegate(.requestApply))
            case let .setSortOrder(order):
                state.updateSortOrder(order)
                userDefaultsClient.setString(order.rawValue, "sortOrder")
                return .send(.delegate(.requestApply))
            case let .setGroupKey(key):
                state.groupKey = key
                userDefaultsClient.setString(key.rawValue, "groupKey")
                return .send(.delegate(.requestApply))
            case let .toggleCollapsedGroup(name):
                if state.collapsedGroups.contains(name) { state.collapsedGroups.remove(name) }
                else { state.collapsedGroups.insert(name) }
                return .none
            case .reapply:
                return .send(.delegate(.requestApply))
            case let .apply(items, isCollectionMode):
                let sorted = sort(items, key: state.sortKey, order: state.sortOrder)
                state.groupedItems = group(sorted, key: state.groupKey, now: date())
                return .send(.delegate(.applied(sortedItems: sorted, isCollectionMode: isCollectionMode)))
            case .delegate:
                return .none
            }
        }
    }

    private func sort(_ items: [EntryModel], key: SortKey, order: SortOrder) -> [EntryModel] {
        items.sorted {
            let result: ComparisonResult = switch key {
            case .name: $0.name.localizedCaseInsensitiveCompare($1.name)
            case .kind: $0.facets.kind.localizedCaseInsensitiveCompare($1.facets.kind)
            case .application: ($0.facets.creatorApplication ?? "")
                .localizedCaseInsensitiveCompare($1.facets.creatorApplication ?? "")
            case .dateLastOpened: compare(
                    $0.facets.lastOpenedDate ?? .distantPast,
                    $1.facets.lastOpenedDate ?? .distantPast,
                )
            case .dateAdded: compare($0.facets.addedDate, $1.facets.addedDate)
            case .dateModified: compare($0.modifiedDate, $1.modifiedDate)
            case .dateCreated: compare($0.facets.createdDate, $1.facets.createdDate)
            case .size: compare($0.size, $1.size)
            case .tags: ($0.facets.tags?.first?.name ?? "")
                .localizedCaseInsensitiveCompare($1.facets.tags?.first?.name ?? "")
            }
            return order == .ascending ? result != .orderedDescending : result == .orderedDescending
        }
    }

    private func group(_ items: [EntryModel], key: GroupKey, now _: Date) -> [GroupedItems] {
        guard key != .none else { return [GroupedItems(groupName: "", items: items)] }
        if key == .name { return [GroupedItems(groupName: "", items: items)] }
        let grouped = Dictionary(grouping: items) { item in
            switch key {
            case .none, .name: ""
            case .kind:
                item
                    .isFolder ? "Folders" :
                    (item.fileExtension.lowercased() == CollectionConstants
                        .fileExtension ? "Collections" : (item.facets.kind.isEmpty ? "Other" : item.facets.kind))
            case .application:
                item.isFolder ? "Other" : (item.facets.creatorApplication ?? "Other")
            case .dateLastOpened:
                item.facets.lastOpenedDate.map { Self.dateGroupName(for: $0) } ?? "Earlier"
            case .dateAdded:
                Self.dateGroupName(for: item.facets.addedDate)
            case .dateModified:
                Self.dateGroupName(for: item.modifiedDate)
            case .dateCreated:
                Self.dateGroupName(for: item.facets.createdDate)
            case .size:
                Self.sizeGroupName(for: item)
            case .tags:
                item.facets.tags?.first?.name ?? "No Tags"
            }
        }
        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { name in
            GroupedItems(
                groupName: name,
                items: grouped[name] ?? [],
                colorCode: key == .tags ? grouped[name]?
                    .compactMap { $0.facets.tags?.first(where: { $0.name == name })?.colorCode }.first : nil,
            )
        }
    }

    private func compare(_ lhs: Date, _ rhs: Date) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }

    private func compare(_ lhs: Int64, _ rhs: Int64) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }

    private static func dateGroupName(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func sizeGroupName(for item: EntryModel) -> String {
        if item.isFolder { return "---" }
        switch item.size {
        case ..<1: return "Zero bytes"
        case ..<100_000: return "Less than 100 KB"
        case ..<1_000_000: return "100 KB - 1 MB"
        case ..<100_000_000: return "1 MB - 100 MB"
        case ..<1_000_000_000: return "100 MB - 1 GB"
        default: return "More than 1 GB"
        }
    }
}

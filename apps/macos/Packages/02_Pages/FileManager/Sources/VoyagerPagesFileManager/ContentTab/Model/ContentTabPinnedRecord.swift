import Foundation

public struct ContentTabPinnedRecord: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let page: ContentTabPage
    public let anchor: ContentTabPageAnchor
    public let title: String?
    public let iconName: String?
    public let pinnedAt: Date

    public init(
        id: String,
        page: ContentTabPage,
        anchor: ContentTabPageAnchor,
        title: String?,
        iconName: String?,
        pinnedAt: Date,
    ) {
        self.id = id
        self.page = page
        self.anchor = anchor
        self.title = title
        self.iconName = iconName
        self.pinnedAt = pinnedAt
    }
}

public extension ContentTabPinnedRecord {
    var isPageAnchorCompatible: Bool {
        Self.isPageAnchorCompatible(page: page, anchor: anchor)
    }
}

extension ContentTabPinnedRecord {
    var isSupportedPinnedContentTab: Bool {
        switch (page, anchor) {
        case (.directory, .directory),
             (.collection, .collectionFile):
            true
        default:
            false
        }
    }

    static func isPageAnchorCompatible(
        page: ContentTabPage,
        anchor: ContentTabPageAnchor,
    ) -> Bool {
        switch (page, anchor) {
        case (.home, .homeDefault):
            true
        case (.directory, .directory):
            true
        case (.collection, .collectionFile):
            true
        case (.collection, .virtualCollection):
            false
        case (.aiChat, .aiChat):
            false
        default:
            false
        }
    }
}

public struct ContentTabPinnedRecordStore: Equatable, Sendable, Codable {
    public var schemaVersion: Int
    public var records: [ContentTabPinnedRecord]
    public var topNavigationOrder: FileManagerTopNavigationOrder

    public init(
        schemaVersion: Int = 2,
        records: [ContentTabPinnedRecord] = [],
        topNavigationOrder: FileManagerTopNavigationOrder = .init(),
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
        self.topNavigationOrder = topNavigationOrder
    }
}

public enum ContentTabPinnedRecordStoreCorruptionReason: Equatable, Sendable {
    case invalidPayload
}

public enum ContentTabPinnedRecordStoreLoadOutcome: Equatable, Sendable {
    case missing
    case migratedV1(ContentTabPinnedRecordStore)
    case migratedLegacyV2(ContentTabPinnedRecordStore)
    case currentV2(ContentTabPinnedRecordStore)
    case corruptUnavailable(
        originalData: Data,
        reason: ContentTabPinnedRecordStoreCorruptionReason,
    )
    case futureSchemaUnavailable(schemaVersion: Int, originalData: Data)

    public var writableStore: ContentTabPinnedRecordStore? {
        switch self {
        case .missing:
            ContentTabPinnedRecordStore()
        case let .migratedV1(store), let .migratedLegacyV2(store), let .currentV2(store):
            store
        case .corruptUnavailable, .futureSchemaUnavailable:
            nil
        }
    }
}

public enum ContentTabPinnedRecordStoreLoadError: Error, Equatable, Sendable {
    case corruptUnavailable
    case futureSchemaUnavailable(Int)
}

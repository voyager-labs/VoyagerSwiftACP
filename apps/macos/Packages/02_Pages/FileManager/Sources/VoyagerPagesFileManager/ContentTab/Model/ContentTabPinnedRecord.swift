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

    public init(schemaVersion: Int = 1, records: [ContentTabPinnedRecord] = []) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}

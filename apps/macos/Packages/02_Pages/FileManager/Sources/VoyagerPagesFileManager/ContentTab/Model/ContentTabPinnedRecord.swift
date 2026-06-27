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
    static func identity(for anchor: ContentTabPageAnchor) -> String {
        switch anchor {
        case .homeDefault:
            "home"
        case let .directory(path):
            "directory:\(path)"
        case let .collectionFile(url):
            "collection:\(url.absoluteString)"
        case let .virtualCollection(id):
            "virtualCollection:\(id)"
        case let .aiChat(sessionID):
            "aiChat:\(sessionID)"
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

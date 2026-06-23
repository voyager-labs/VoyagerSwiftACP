import ComposableArchitecture
import Foundation
import IdentifiedCollections

public struct ContentTabID: Hashable, Sendable, Codable {
    public let rawValue: String

    public init() {
        rawValue = UUID().uuidString
    }
}

public enum ContentTabPage: Equatable, Sendable, Codable {
    case home
    case directory
    case collection
    case aiChat
}

public enum ContentTabPageAnchor: Equatable, Sendable, Codable {
    case homeDefault
    case directory(path: String)
    case collectionFile(url: URL)
    case virtualCollection(id: String)
    case aiChat(sessionID: String)
}

public struct ContentTabItem: Equatable, Sendable, Identifiable {
    public let id: ContentTabID
    public var page: ContentTabPage
    public var anchor: ContentTabPageAnchor
    public var isPinned: Bool
    public var title: String?
    public var iconName: String?
}

public struct ClosedContentTabSnapshot: Equatable, Sendable, Codable {
    public var page: ContentTabPage
    public var anchor: ContentTabPageAnchor
    public var wasPinned: Bool
    public var closedAt: Date
}

@ObservableState
public struct ContentTabState: Equatable {
    public var tabs: IdentifiedArrayOf<ContentTabItem> = []
    public var activeTabID: ContentTabID?
    public var recentlyClosed: ClosedContentTabSnapshot?
}

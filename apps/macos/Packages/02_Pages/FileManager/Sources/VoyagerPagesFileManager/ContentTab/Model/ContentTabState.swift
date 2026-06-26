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
    public var previousActiveTabID: ContentTabID?
    public var recentlyClosed: ClosedContentTabSnapshot?

    public init(
        tabs: IdentifiedArrayOf<ContentTabItem> = [],
        activeTabID: ContentTabID? = nil,
        previousActiveTabID: ContentTabID? = nil,
        recentlyClosed: ClosedContentTabSnapshot? = nil,
    ) {
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.previousActiveTabID = previousActiveTabID
        self.recentlyClosed = recentlyClosed
    }
}

public extension ContentTabState {
    static func withHomeTab() -> ContentTabState {
        let id = ContentTabID()
        return ContentTabState(
            tabs: [ContentTabItem(
                id: id,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )],
            activeTabID: id,
            previousActiveTabID: nil,
            recentlyClosed: nil,
        )
    }

    static func bootstrapping(
        restoredTabs: IdentifiedArrayOf<ContentTabItem> = [],
        activeTabID: ContentTabID? = nil,
    ) -> ContentTabState {
        guard let first = restoredTabs.first else { return .withHomeTab() }

        let active: ContentTabID = if let activeTabID, restoredTabs[id: activeTabID] != nil {
            activeTabID
        } else {
            first.id
        }

        return ContentTabState(
            tabs: restoredTabs,
            activeTabID: active,
            previousActiveTabID: nil,
            recentlyClosed: nil,
        )
    }
}

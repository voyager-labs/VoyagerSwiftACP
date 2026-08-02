import Foundation

public enum ContentTabProjection {}

public extension ContentTabProjection {
    struct ContentTabSidebarItem: Equatable, Sendable {
        public let id: ContentTabID
        public let title: String?
        public let iconName: String?
        public let targetURL: URL?
        public let tagColorCode: Int?
        public let pageType: ContentTabPage
        public let isActive: Bool
        public let isPinned: Bool
    }
}

extension ContentTabProjection {
    static func tabID(atDisplayPosition position: Int, in state: ContentTabState) -> ContentTabID? {
        guard (1 ... 9).contains(position) else { return nil }
        let displayedTabIDs = state.selectionOrderedTabIDs
        let index = position - 1
        guard displayedTabIDs.indices.contains(index) else { return nil }
        return displayedTabIDs[index]
    }
}

public extension ContentTabProjection {
    static func sidebarItems(from state: ContentTabState) -> [ContentTabSidebarItem] {
        state.tabs.map { tab in
            ContentTabSidebarItem(
                id: tab.id,
                title: tab.title,
                iconName: tab.iconName,
                targetURL: targetURL(for: tab.anchor),
                tagColorCode: nil,
                pageType: tab.page,
                isActive: state.activeTabID == tab.id,
                isPinned: tab.isPinned,
            )
        }
    }

    private static func targetURL(for anchor: ContentTabPageAnchor) -> URL? {
        switch anchor {
        case let .directory(path):
            URL(fileURLWithPath: path)
        case let .collectionFile(url):
            url
        case .homeDefault, .virtualCollection, .aiChat:
            nil
        }
    }

    static func activePageAnchor(from state: ContentTabState) -> ContentTabPageAnchor? {
        activeTab(from: state)?.anchor
    }

    static func activeTab(from state: ContentTabState) -> ContentTabItem? {
        guard let activeID = state.activeTabID else { return nil }
        return state.tabs[id: activeID]
    }

    static func restoreCandidate(from state: ContentTabState) -> ClosedContentTabSnapshot? {
        state.recentlyClosed
    }
}

import Foundation

public enum ContentTabProjection {}

public extension ContentTabProjection {
    struct ContentTabSidebarItem: Equatable, Sendable {
        public let id: ContentTabID
        public let title: String?
        public let iconName: String?
        public let tagColorCode: Int?
        public let pageType: ContentTabPage
        public let isActive: Bool
        public let isPinned: Bool
    }
}

public extension ContentTabProjection {
    static func sidebarItems(from state: ContentTabState) -> [ContentTabSidebarItem] {
        state.tabs.map { tab in
            ContentTabSidebarItem(
                id: tab.id,
                title: tab.title,
                iconName: tab.iconName,
                tagColorCode: nil,
                pageType: tab.page,
                isActive: state.activeTabID == tab.id,
                isPinned: tab.isPinned,
            )
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

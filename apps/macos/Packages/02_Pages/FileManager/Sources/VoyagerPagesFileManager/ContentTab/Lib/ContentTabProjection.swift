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
        let canReturnToPinnedLocation: Bool

        init(
            id: ContentTabID,
            title: String?,
            iconName: String?,
            targetURL: URL?,
            tagColorCode: Int?,
            pageType: ContentTabPage,
            isActive: Bool,
            isPinned: Bool,
            canReturnToPinnedLocation: Bool = false,
        ) {
            self.id = id
            self.title = title
            self.iconName = iconName
            self.targetURL = targetURL
            self.tagColorCode = tagColorCode
            self.pageType = pageType
            self.isActive = isActive
            self.isPinned = isPinned
            self.canReturnToPinnedLocation = canReturnToPinnedLocation
        }
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
            let pinnedRecord = state.pinnedRecords[tab.id]
            return ContentTabSidebarItem(
                id: tab.id,
                title: tab.title,
                iconName: tab.iconName,
                targetURL: targetURL(for: tab.anchor),
                tagColorCode: nil,
                pageType: tab.page,
                isActive: state.activeTabID == tab.id,
                isPinned: tab.isPinned,
                canReturnToPinnedLocation: tab.isPinned
                    && pinnedRecord?.isSupportedPinnedContentTab == true
                    && pinnedRecord?.anchor != tab.anchor,
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

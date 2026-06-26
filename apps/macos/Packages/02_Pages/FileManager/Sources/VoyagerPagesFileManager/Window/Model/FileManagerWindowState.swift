import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

@ObservableState
public struct FileManagerWindowState: Equatable {
    public var content: FileManagerContentFeature.State
    public var tabContentStates: [ContentTabID: FileManagerContentFeature.State]
    public var sidebar: FileManagerSidebarFeature.State
    public var inspector: FileManagerInspectorFeature.State
    public var contentTabs: ContentTabState
    public var recentlyClosedNavigationRoute: ContentPageNavigationRoute?

    public init() {
        content = .init()
        sidebar = .init()
        inspector = .init()
        contentTabs = .withHomeTab()
        tabContentStates = [:]
        recentlyClosedNavigationRoute = nil
        if let activeTabID = contentTabs.activeTabID {
            tabContentStates[activeTabID] = content
        }
        syncContentTabSidebarItems()
    }

    public static func makeInitial(path: String?) -> Self {
        var state = Self()

        if let path {
            state.content.navigation.seedInitialFolderPath(path)
            state.syncActiveTabAnchorForInitialPath(path)
        } else {
            let activeAnchor = state.contentTabs.activeTabID
                .flatMap { state.contentTabs.tabs[id: $0]?.anchor }
            state.content = FileManagerContentFeature.State.initialContent(
                for: activeAnchor,
                inheritingWindowContextFrom: state.content,
            )
        }

        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()
        return state
    }

    public static func makeInitial(
        path: String?,
        contentTabs: ContentTabState?,
    ) -> Self {
        var state = Self()
        state.contentTabs = contentTabs.map { ContentTabState.bootstrapping(
            restoredTabs: $0.tabs,
            activeTabID: $0.activeTabID,
        )
        } ?? .withHomeTab()

        if let path {
            state.content.navigation.seedInitialFolderPath(path)
            state.syncActiveTabAnchorForInitialPath(path)
        } else {
            let activeAnchor = state.contentTabs.activeTabID
                .flatMap { state.contentTabs.tabs[id: $0]?.anchor }
            state.content = FileManagerContentFeature.State.initialContent(
                for: activeAnchor,
                inheritingWindowContextFrom: state.content,
            )
        }

        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()
        return state
    }
}

public extension FileManagerWindowState {
    func appPreferencesPreservingSidebarState(from preferences: AppPreferencesState) -> AppPreferencesState {
        var result = preferences
        result.sidebarVisible = sidebar.sidebarVisible
        result.sidebarWidth = sidebar.sidebarWidth
        return result
    }
}

extension FileManagerWindowState {
    var activeTabContentStateMissing: Bool {
        guard let activeTabID = contentTabs.activeTabID else { return false }
        return tabContentStates[activeTabID] == nil
    }

    mutating func syncActiveTabAnchorForInitialPath(_ path: String) {
        guard let activeTabID = contentTabs.activeTabID else { return }
        contentTabs.tabs[id: activeTabID]?.anchor = .directory(path: path)
        contentTabs.tabs[id: activeTabID]?.page = .directory
        let title = URL(fileURLWithPath: path).lastPathComponent
        contentTabs.tabs[id: activeTabID]?.title = title.isEmpty ? path : title
        contentTabs.tabs[id: activeTabID]?.iconName = "folder"
    }

    mutating func syncActiveTabContentState() {
        guard let activeTabID = contentTabs.activeTabID else { return }
        tabContentStates[activeTabID] = content
    }

    mutating func saveCurrentContentStateForPreviousActiveTab() {
        guard let previousActiveTabID = contentTabs.previousActiveTabID else { return }
        tabContentStates[previousActiveTabID] = content
    }

    mutating func restoreContentStateForActiveTab() {
        guard let activeTabID = contentTabs.activeTabID else { return }
        if let savedContent = tabContentStates[activeTabID] {
            content = savedContent
        } else {
            let activeAnchor = contentTabs.tabs[id: activeTabID]?.anchor
            content = FileManagerContentFeature.State.initialContent(
                for: activeAnchor,
                inheritingWindowContextFrom: content,
            )
            tabContentStates[activeTabID] = content
        }
    }

    mutating func removeContentState(for tabID: ContentTabID) {
        tabContentStates[tabID] = nil
    }

    mutating func syncContentTabSidebarItems() {
        sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: contentTabs).map { item in
            enrichedContentTabSidebarItem(item)
        }
    }

    private func enrichedContentTabSidebarItem(
        _ item: ContentTabProjection.ContentTabSidebarItem,
    ) -> ContentTabProjection.ContentTabSidebarItem {
        guard let anchor = contentTabs.tabs[id: item.id]?.anchor else { return item }

        switch anchor {
        case let .directory(path):
            guard let location = locationItem(forPath: path) else { return item }
            return item.withTitle(location.name, iconName: location.iconName, targetURL: location.url)

        case let .virtualCollection(id):
            if let location = sidebar.locations.first(where: { $0.name == id }) {
                return item.withTitle(location.name, iconName: location.iconName, targetURL: location.url)
            }
            if let tag = sidebar.tags.first(where: { $0.name == id }) {
                return item.withTagColorCode(tag.colorCode)
            }
            return item

        case .homeDefault,
             .collectionFile,
             .aiChat:
            return item
        }
    }

    private func locationItem(forPath path: String) -> SidebarItems.LocationItem? {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return sidebar.locations.first { location in
            guard location.url.isFileURL else { return false }
            return location.url.standardizedFileURL.path == standardizedPath
        }
    }
}

private extension ContentTabProjection.ContentTabSidebarItem {
    func withTitle(_ title: String?, iconName: String?, targetURL: URL? = nil) -> Self {
        Self(
            id: id,
            title: title,
            iconName: iconName,
            targetURL: targetURL,
            tagColorCode: tagColorCode,
            pageType: pageType,
            isActive: isActive,
            isPinned: isPinned,
        )
    }

    func withTagColorCode(_ tagColorCode: Int) -> Self {
        Self(
            id: id,
            title: title,
            iconName: iconName,
            targetURL: targetURL,
            tagColorCode: tagColorCode,
            pageType: pageType,
            isActive: isActive,
            isPinned: isPinned,
        )
    }
}

extension FileManagerContentFeature.State {
    static func initialContent(
        for anchor: ContentTabPageAnchor?,
        inheritingWindowContextFrom source: Self? = nil,
    ) -> Self {
        var content = Self()

        if let source {
            content.applyWindowContext(from: source)
        }

        switch anchor {
        case let .directory(path):
            content.navigation.seedInitialFolderPath(path)
        case let .collectionFile(url):
            content.navigation.navigationState = .collection(.init(
                kind: .file(url: url, name: url.deletingPathExtension().lastPathComponent),
                context: CollectionContext(query: "", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ))
        case let .virtualCollection(id):
            content.navigation.navigationState = .tags(id)
        case .homeDefault,
             .aiChat,
             .none:
            break
        }

        return content
    }

    mutating func applyWindowContext(from source: Self) {
        entryViewLayout.mode = source.entryViewLayout.mode
        entryViewLayout.listIconSize = source.entryViewLayout.listIconSize
        entryViewLayout.gridIconSize = source.entryViewLayout.gridIconSize
        entryViewLayout.listTextSize = source.entryViewLayout.listTextSize
        entryViewLayout.gridTextSize = source.entryViewLayout.gridTextSize
        entryViewLayout.showHiddenFiles = source.entryViewLayout.showHiddenFiles
        entryViewLayout.entryArrangements.sortKey = source.entryViewLayout.entryArrangements.sortKey
        entryViewLayout.entryArrangements.sortOrder = source.entryViewLayout.entryArrangements.sortOrder
        entryViewLayout.entryArrangements.hasUserSetSortOrder = source.entryViewLayout.entryArrangements
            .hasUserSetSortOrder
        entryViewLayout.entryArrangements.groupKey = source.entryViewLayout.entryArrangements.groupKey
        entryViewLayout.entryOperations.windowID = source.entryViewLayout.entryOperations.windowID
        composer.cancellationOwnerID = source.composer.cancellationOwnerID
    }
}

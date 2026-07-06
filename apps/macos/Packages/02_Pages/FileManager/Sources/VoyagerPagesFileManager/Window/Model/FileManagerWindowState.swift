import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

@ObservableState
public struct FileManagerWindowState: Equatable {
    public var content: FileManagerContentFeature.State
    public var tabContentStates: [ContentTabID: FileManagerContentFeature.State]
    public var tabInspectorStates: [ContentTabID: FileManagerInspectorFeature.State]
    public var backgroundAiChatStates: [AiChatSessionID: FileManagerContentFeature.State]
    public var backgroundInspectorAiChatStates: [AiChatSessionID: FileManagerInspectorFeature.State]
    public var sidebar: FileManagerSidebarFeature.State
    public var inspector: FileManagerInspectorFeature.State
    public var contentTabs: ContentTabState
    public var recentlyClosedNavigationRoute: ContentPageNavigationRoute?
    public var pendingContentTabClose: PendingContentTabClose?

    public init() {
        content = .init()
        sidebar = .init()
        inspector = .init()
        contentTabs = .withHomeTab()
        tabContentStates = [:]
        tabInspectorStates = [:]
        backgroundAiChatStates = [:]
        backgroundInspectorAiChatStates = [:]
        recentlyClosedNavigationRoute = nil
        pendingContentTabClose = nil
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
        state.restoreInspectorStateForActiveTab()
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
            pinnedRecords: $0.pinnedRecords,
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
        state.restoreInspectorStateForActiveTab()
        state.syncContentTabSidebarItems()
        return state
    }
}

public struct PendingContentTabClose: Equatable {
    public let tabID: ContentTabID
    public let previousActiveTabID: ContentTabID?
    public let previousActiveContent: FileManagerContentFeature.State?
    public let targetContent: FileManagerContentFeature.State?
    public let previousActiveInspector: FileManagerInspectorFeature.State?
    public let targetInspector: FileManagerInspectorFeature.State?
    public var didReceiveWriteBackNavigationState: Bool
    public var didReceiveWriteBackComposerSync: Bool

    public init(
        tabID: ContentTabID,
        previousActiveTabID: ContentTabID? = nil,
        previousActiveContent: FileManagerContentFeature.State? = nil,
        targetContent: FileManagerContentFeature.State? = nil,
        previousActiveInspector: FileManagerInspectorFeature.State? = nil,
        targetInspector: FileManagerInspectorFeature.State? = nil,
        didReceiveWriteBackNavigationState: Bool = false,
        didReceiveWriteBackComposerSync: Bool = false,
    ) {
        self.tabID = tabID
        self.previousActiveTabID = previousActiveTabID
        self.previousActiveContent = previousActiveContent
        self.targetContent = targetContent
        self.previousActiveInspector = previousActiveInspector
        self.targetInspector = targetInspector
        self.didReceiveWriteBackNavigationState = didReceiveWriteBackNavigationState
        self.didReceiveWriteBackComposerSync = didReceiveWriteBackComposerSync
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
    var activeTabInspectorStateMissing: Bool {
        guard let activeTabID = contentTabs.activeTabID,
              supportsInspector(tabID: activeTabID)
        else { return false }
        return tabInspectorStates[activeTabID] == nil
    }

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

    mutating func syncActiveTabInspectorState() {
        guard let activeTabID = contentTabs.activeTabID else { return }
        guard supportsInspector(tabID: activeTabID) else {
            tabInspectorStates[activeTabID] = nil
            return
        }
        tabInspectorStates[activeTabID] = inspector.tabSnapshot()
    }

    mutating func saveCurrentInspectorStateForPreviousActiveTab() {
        guard let previousActiveTabID = contentTabs.previousActiveTabID else { return }
        guard supportsInspector(tabID: previousActiveTabID) else {
            tabInspectorStates[previousActiveTabID] = nil
            return
        }
        tabInspectorStates[previousActiveTabID] = inspector.tabSnapshot()
    }

    mutating func restoreInspectorStateForActiveTab() {
        guard let activeTabID = contentTabs.activeTabID else {
            inspector = .init()
            return
        }
        guard supportsInspector(tabID: activeTabID) else {
            inspector = .init()
            tabInspectorStates[activeTabID] = nil
            return
        }
        if let savedInspector = tabInspectorStates[activeTabID] {
            inspector = savedInspector.tabSnapshot()
        } else {
            inspector = .init()
            tabInspectorStates[activeTabID] = inspector.tabSnapshot()
        }
    }

    mutating func removeInspectorState(for tabID: ContentTabID) {
        tabInspectorStates[tabID] = nil
    }

    mutating func addBackgroundInspectorAiChatState(for tabID: ContentTabID) {
        let inspectorState = if contentTabs.previousActiveTabID == tabID || contentTabs.activeTabID == tabID {
            inspector
        } else {
            tabInspectorStates[tabID]
        }

        guard let inspectorState else { return }
        addBackgroundInspectorAiChatState(state: inspectorState)
    }

    mutating func addBackgroundInspectorAiChatState(state inspectorState: FileManagerInspectorFeature.State) {
        guard inspectorState.shouldPreserveAiChatInBackground else { return }
        guard let sessionID = inspectorState.aiChat.sessionID ?? inspectorState.aiChat.executionPhase.lock?.context
            .sessionID
        else {
            return
        }
        backgroundInspectorAiChatStates[sessionID] = inspectorState.tabSnapshot()
    }

    @discardableResult
    mutating func removeBackgroundInspectorAiChatState(
        sessionID: AiChatSessionID,
    ) -> FileManagerInspectorFeature.State? {
        backgroundInspectorAiChatStates.removeValue(forKey: sessionID)
    }

    func backgroundInspectorAiChatState(for sessionID: AiChatSessionID) -> FileManagerInspectorFeature.State? {
        backgroundInspectorAiChatStates[sessionID]
    }

    func inspectorState(for tabID: ContentTabID) -> FileManagerInspectorFeature.State? {
        if contentTabs.activeTabID == tabID {
            return inspector
        }
        return tabInspectorStates[tabID]
    }

    func supportsInspector(tabID: ContentTabID) -> Bool {
        guard let anchor = contentTabs.tabs[id: tabID]?.anchor else { return false }
        return anchor.supportsInspector
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
        sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: contentTabs)
    }

    mutating func applyPinnedContentTabs(_ restoredPinnedState: ContentTabState) {
        let recentlyClosed = contentTabs.recentlyClosed
        let restoredPinnedTabs = restoredPinnedState.tabs.filter(\.isPinned)
        let restoredTabIDs = Set(restoredPinnedTabs.map(\.id))
        let currentPinnedTabs = contentTabs.tabs.filter(\.isPinned)
        let pendingPinnedTabs = currentPinnedTabs.filter {
            contentTabs.pendingPinnedRecordIDs.contains($0.id) && !restoredTabIDs.contains($0.id)
        }
        let mergedPinnedTabs = restoredPinnedTabs + pendingPinnedTabs
        let mergedPinnedIDs = Set(mergedPinnedTabs.map(\.id))
        let currentUnpinnedTabs = contentTabs.tabs.filter { !$0.isPinned && !mergedPinnedIDs.contains($0.id) }
        let currentPinnedIDs = Set(currentPinnedTabs.map(\.id))
        let previousPinnedAnchors = Dictionary(uniqueKeysWithValues: currentPinnedTabs.map { ($0.id, $0.anchor) })
        let activeTabIDBeforeSync = contentTabs.activeTabID

        let pendingPinnedIDs = Set(pendingPinnedTabs.map(\.id))
        let pendingPinnedRecords = contentTabs.pinnedRecords.filter { pendingPinnedIDs.contains($0.key) }

        contentTabs.tabs = IdentifiedArrayOf(uniqueElements: mergedPinnedTabs + currentUnpinnedTabs)
        contentTabs.pinnedRecords = restoredPinnedState.pinnedRecords
            .merging(pendingPinnedRecords) { restored, _ in restored }
        contentTabs.pendingPinnedRecordIDs = pendingPinnedIDs
        contentTabs.previousActiveTabID = nil

        for removedID in currentPinnedIDs.subtracting(restoredTabIDs) where contentTabs.tabs[id: removedID] == nil {
            tabContentStates[removedID] = nil
            tabInspectorStates[removedID] = nil
        }
        let changedPinnedTabIDs = Set(
            restoredPinnedTabs.compactMap { tab in
                previousPinnedAnchors[tab.id].map { $0 != tab.anchor } == true ? tab.id : nil
            },
        )
        for changedID in changedPinnedTabIDs {
            tabContentStates[changedID] = nil
            tabInspectorStates[changedID] = nil
        }

        if contentTabs.tabs.isEmpty {
            contentTabs = .withHomeTab()
            restoreContentStateForActiveTab()
            restoreInspectorStateForActiveTab()
        } else if let activeTabID = contentTabs.activeTabID,
                  let activeTab = contentTabs.tabs[id: activeTabID]
        {
            let activePinnedAnchorDidChange = activeTab.isPinned
                && activeTabID == activeTabIDBeforeSync
                && changedPinnedTabIDs.contains(activeTabID)
            if activePinnedAnchorDidChange {
                tabContentStates[activeTabID] = nil
                tabInspectorStates[activeTabID] = nil
                restoreContentStateForActiveTab()
                restoreInspectorStateForActiveTab()
            }
        } else {
            contentTabs.activeTabID = mergedPinnedTabs.first?.id ?? currentUnpinnedTabs.first?.id
            restoreContentStateForActiveTab()
            restoreInspectorStateForActiveTab()
        }

        contentTabs.recentlyClosed = recentlyClosed
        syncContentTabSidebarItems()
    }

    mutating func addBackgroundAiChatState(sessionID: AiChatSessionID, state: FileManagerContentFeature.State) {
        let isCompleted = if case .completed = state.aiChat.executionPhase {
            true
        } else {
            false
        }
        guard state.aiChat.executionPhase.isProcessing
            || isCompleted
            || state.aiChat.pendingRequestStart != nil
        else { return }
        backgroundAiChatStates[sessionID] = state
    }

    @discardableResult
    mutating func removeBackgroundAiChatState(sessionID: AiChatSessionID) -> FileManagerContentFeature.State? {
        backgroundAiChatStates.removeValue(forKey: sessionID)
    }

    func backgroundAiChatState(for sessionID: AiChatSessionID) -> FileManagerContentFeature.State? {
        backgroundAiChatStates[sessionID]
    }

    func canPinContentTab(_ tabID: ContentTabID) -> Bool {
        let tab = contentTabs.tabs[id: tabID]
        if let tab {
            let pinnedRecord = ContentTabPinnedRecord(
                id: tab.id.rawValue,
                page: tab.page,
                anchor: tab.anchor,
                title: tab.title,
                iconName: tab.iconName,
                pinnedAt: .distantPast,
            )
            guard pinnedRecord.isPageAnchorCompatible else { return false }
        }

        let tabPage = tab?.page
        let contentState = contentTabs.activeTabID == tabID ? content : tabContentStates[tabID]

        guard let contentState else { return tabPage != .collection }

        let isShowingCollectionNavigation = if case .collection = contentState.navigation.navigationState {
            true
        } else {
            false
        }

        guard tabPage == .collection || contentState.isCollectionMode || isShowingCollectionNavigation else {
            return true
        }

        if case let .collection(navigation) = contentState.navigation.navigationState,
           case .temporary = navigation.kind
        {
            return false
        }
        guard contentState.isCollectionMode else { return true }
        guard contentState.collection.collectionSession.document?.url != nil,
              contentState.collection.collectionSession.metadata.baseline != nil
        else {
            return false
        }
        return contentState.openedCollectionURLExists
    }
}

extension FileManagerInspectorFeature.State {
    var shouldPreserveAiChatInBackground: Bool {
        if aiChat.executionPhase.isProcessing || aiChat.pendingRequestStart != nil { return true }
        if case .completed = aiChat.executionPhase { return true }
        return false
    }

    func tabSnapshot() -> Self {
        var snapshot = self
        snapshot.inspectorPaneExists = false
        return snapshot
    }
}

private extension ContentTabPageAnchor {
    var supportsInspector: Bool {
        switch self {
        case .directory,
             .collectionFile,
             .virtualCollection:
            true
        case .homeDefault,
             .aiChat:
            false
        }
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
        case let .aiChat(sessionID):
            content.navigation.navigationState = .aiChat(sessionID)
            content.aiChat.mode = .chat
        case .homeDefault,
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

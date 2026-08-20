import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

extension FileManagerWindowState {
    var windowID: UUID? {
        get {
            content.entryViewLayout.entryOperations.windowID
        }
        set {
            content.entryViewLayout.entryOperations.windowID = newValue
            content.composer.cancellationOwnerID = newValue
            for tabID in tabContentStates.keys {
                tabContentStates[tabID]?.entryViewLayout.entryOperations.windowID = newValue
                tabContentStates[tabID]?.composer.cancellationOwnerID = newValue
            }
            sidebarEntryDropOperations.windowID = newValue
        }
    }

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
        for sessionID in inspectorState.aiChat.lifecycleSessionIDsToPreserve {
            var mergedInspectorState = inspectorState.tabSnapshot()
            if let existingInspectorState = backgroundInspectorAiChatStates[sessionID] {
                mergedInspectorState.aiChat.mergeBackgroundLifecycleOwners(from: existingInspectorState.aiChat)
            }
            backgroundInspectorAiChatStates[sessionID] = mergedInspectorState
        }
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
        if let request = pendingCollectionOpenRequest {
            content.navigation.backHistory = request.prePrepareBackHistory
            content.navigation.forwardHistory = request.prePrepareForwardHistory
        }
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

    mutating func addBackgroundAiChatState(for tabID: ContentTabID) {
        let contentState = if contentTabs.previousActiveTabID == tabID || contentTabs.activeTabID == tabID {
            content
        } else {
            tabContentStates[tabID]
        }

        guard let contentState else { return }
        for sessionID in contentState.aiChat.lifecycleSessionIDsToPreserve {
            addBackgroundAiChatState(sessionID: sessionID, state: contentState)
        }
    }

    mutating func syncContentTabSidebarItems() {
        sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: contentTabs)
        syncSidebarTopNavigationItems()
    }

    mutating func syncSidebarTopNavigationItems() {
        var synchronizedSidebar = sidebar
        var synchronizedOrder = optimisticTopNavigationOrder
        FileManagerSidebarSync.synchronizeTopNavigation(
            sidebar: &synchronizedSidebar,
            optimisticOrder: &synchronizedOrder,
            dormantContentTabSlots: dormantContentTabSlots,
        )
        sidebar = synchronizedSidebar
        optimisticTopNavigationOrder = synchronizedOrder
        sidebar.contentTabSelectionOrderedIDs = contentTabSelectionOrderedIDs
    }

    var contentTabSelectionOrderedIDs: [ContentTabID] {
        let displayedPinnedIDs = sidebar.topNavigationItems.compactMap { item -> ContentTabID? in
            guard case let .contentTab(contentTab) = item else { return nil }
            return contentTab.id
        }
        let displayedPinnedIDSet = Set(displayedPinnedIDs)
        let remainingPinnedIDs = contentTabs.tabs.compactMap { tab in
            tab.isPinned && !displayedPinnedIDSet.contains(tab.id) ? tab.id : nil
        }
        let unpinnedIDs = contentTabs.tabs.compactMap { tab in
            tab.isPinned ? nil : tab.id
        }
        return displayedPinnedIDs + remainingPinnedIDs + unpinnedIDs
    }

    mutating func updateActiveAiChatTabTitle(_ title: String?) {
        guard let activeTabID = contentTabs.activeTabID,
              case .aiChat = contentTabs.tabs[id: activeTabID]?.anchor
        else { return }
        let resolvedTitle = aiChatTabTitle(title)
        contentTabs.tabs[id: activeTabID]?.title = resolvedTitle
        syncContentTabSidebarItems()
    }

    mutating func refreshActiveAiChatTabTitleFromSessionList(onlyIfUsingFallback: Bool = false) {
        guard let activeTabID = contentTabs.activeTabID,
              !onlyIfUsingFallback || contentTabs.tabs[id: activeTabID]?.title == "AI Chat",
              case let .aiChat(sessionIDString) = contentTabs.tabs[id: activeTabID]?.anchor,
              let sessionUUID = UUID(uuidString: sessionIDString),
              let summary = content.aiChat.sessionList.allRows.first(where: {
                  $0.sessionID.rawValue == sessionUUID
              })
        else { return }
        let resolvedTitle = aiChatTabTitle(summary.title)
        contentTabs.tabs[id: activeTabID]?.title = resolvedTitle
    }

    mutating func updateAiChatTabTitle(sessionID: AiChatSessionID, title: String?) {
        let sessionIDString = sessionID.rawValue.uuidString
        let resolvedTitle = aiChatTabTitle(title)
        for tabID in contentTabs.tabs.ids {
            guard contentTabs.tabs[id: tabID]?.anchor == .aiChat(sessionID: sessionIDString) else { continue }
            contentTabs.tabs[id: tabID]?.title = resolvedTitle
        }
        syncContentTabSidebarItems()
    }

    mutating func refreshAiChatTabTitleFromCanonicalSummary(sessionID: AiChatSessionID) {
        guard let summary = canonicalAiChatSessionSummary(sessionID: sessionID) else { return }
        updateAiChatTabTitle(sessionID: sessionID, title: summary.title)
    }

    private func canonicalAiChatSessionSummary(sessionID: AiChatSessionID) -> AiChatSessionSummary? {
        var canonicalSummary: AiChatSessionSummary?

        func consider(_ aiChat: AiChatFeature.State) {
            guard let candidate = aiChat.sessionList.allRows.first(where: { $0.sessionID == sessionID }) else { return }
            guard let currentSummary = canonicalSummary else {
                canonicalSummary = candidate
                return
            }
            if candidate.isNewer(than: currentSummary) {
                canonicalSummary = candidate
            }
        }

        consider(content.aiChat)
        for contentState in tabContentStates.values {
            consider(contentState.aiChat)
        }
        consider(inspector.aiChat)
        for inspectorState in tabInspectorStates.values {
            consider(inspectorState.aiChat)
        }
        for contentState in backgroundAiChatStates.values {
            consider(contentState.aiChat)
        }
        for inspectorState in backgroundInspectorAiChatStates.values {
            consider(inspectorState.aiChat)
        }
        return canonicalSummary
    }

    private func aiChatTabTitle(_ title: String?) -> String {
        guard let normalized = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty
        else { return "AI Chat" }
        return normalized
    }

    mutating func syncFixedLocationItems(
        with locationsClient: FileManagerLocationsClient,
        entryLoadingClient: EntryLoadingClient,
        hiddenLocationIDs: Set<FileManagerFixedLocationItem.ID> = [],
    ) {
        let items = FileManagerHomeDashboardProjection.makeFixedLocations(
            from: locationsClient.loadLocations(entryLoadingClient),
        )
        applyFixedLocationItems(items, hiddenLocationIDs: hiddenLocationIDs)
    }

    mutating func applyFixedLocationItems(
        _ items: [FileManagerFixedLocationItem],
        hiddenLocationIDs: Set<FileManagerFixedLocationItem.ID> = [],
    ) {
        sidebar.setFixedLocationItems(items, hiddenIDs: hiddenLocationIDs)
        lastConfirmedTopNavigationOrder = FileManagerTopNavigationOrderPolicy.reconcilingDiscoveredLocations(
            in: lastConfirmedTopNavigationOrder,
            discoveredLocationIDs: items.map(\.id),
        )
        syncSidebarTopNavigationItems()
        guard activeTabAnchor == .homeDefault else { return }
        content.homeLocationItems = items
        syncActiveTabContentState()
    }

    mutating func applyBootstrap(_ bootstrap: FileManagerWindowBootstrap) {
        applyPinnedContentTabs(bootstrap.authoritativePinnedContentTabs, mode: .authoritative)
        switch bootstrap.arrangementAvailability {
        case .available:
            lastConfirmedTopNavigationOrder = bootstrap.committedTopNavigationOrder
            lastConfirmedTopNavigationCommitRevision = nil
            topNavigationArrangementAvailability = .available
            topNavigationArrangementPresentation = nil
        case let .unavailable(failure):
            topNavigationArrangementAvailability = .unavailable(failure)
            topNavigationArrangementPresentation = .loadUnavailable
        }
        applyFixedLocationItems(
            bootstrap.fixedLocationItems,
            hiddenLocationIDs: sidebar.hiddenFixedLocationItemIDs,
        )
        replayTopNavigationOverlays()
    }

    // MARK: - Home Dashboard Projection

    mutating func applyHomeFavoriteItems(_ items: [FileManagerHomeFavoriteItem]) {
        homeFavoriteItems = items
        syncHomeFavoriteItems()
    }

    mutating func syncHomeFavoriteItems() {
        guard activeTabAnchor == .homeDefault else { return }
        content.homeFavoriteItems = homeFavoriteItems
        syncActiveTabContentState()
    }

    mutating func syncHomeLocationItems() {
        guard activeTabAnchor == .homeDefault else { return }
        content.homeLocationItems = sidebar.allFixedLocationItems
        syncActiveTabContentState()
    }

    private var activeTabAnchor: ContentTabPageAnchor? {
        contentTabs.activeTabID.flatMap { contentTabs.tabs[id: $0]?.anchor }
    }

    mutating func applyPinnedContentTabs(
        _ restoredPinnedState: ContentTabState,
        mode: PinnedContentTabsApplicationMode = .preservingRuntime,
        runtimePreservingTabIDs: Set<ContentTabID> = [],
    ) {
        let recentlyClosed = contentTabs.recentlyClosed
        let plan = makePinnedContentTabsPlan(
            restoredPinnedState: restoredPinnedState,
            mode: mode,
            runtimePreservingTabIDs: runtimePreservingTabIDs,
        )

        contentTabs.tabs = IdentifiedArrayOf(uniqueElements: plan.mergedPinnedTabs + plan.currentUnpinnedTabs)
        contentTabs.pinnedRecords = plan.synchronizedPinnedRecords
            .merging(plan.pendingPinnedRecords) { _, pending in pending }
        contentTabs.pendingPinnedRecordIDs = plan.retainedPendingPinnedIDs
        contentTabs.previousActiveTabID = nil

        installSemanticOwners(forNewPinnedTabIDs: plan.newlyInsertedPinnedIDs)

        for removedID in plan.removedPinnedIDs where contentTabs.tabs[id: removedID] == nil {
            tabContentStates[removedID] = nil
            tabInspectorStates[removedID] = nil
        }
        for changedID in plan.changedPinnedTabIDs {
            tabContentStates[changedID] = nil
            tabInspectorStates[changedID] = nil
        }

        reactivateTabAfterPinnedSync(plan: plan)

        contentTabs.recentlyClosed = recentlyClosed
        contentTabs.reconcileSelection()
        syncContentTabSidebarItems()
    }

    private mutating func makePinnedContentTabsPlan(
        restoredPinnedState: ContentTabState,
        mode: PinnedContentTabsApplicationMode,
        runtimePreservingTabIDs: Set<ContentTabID>,
    ) -> PinnedContentTabsPlan {
        let existingTabIDs = Set(contentTabs.tabs.ids)
        let allRestoredPinnedTabs = restoredPinnedState.tabs.filter(\.isPinned)
        let restoredTabIDs = Set(allRestoredPinnedTabs.map(\.id))
        suppressedPinnedTabIDs.formIntersection(restoredTabIDs)
        let restoredPinnedTabs = Array(allRestoredPinnedTabs.filter { !suppressedPinnedTabIDs.contains($0.id) })
        let currentPinnedTabs = Array(contentTabs.tabs.filter(\.isPinned))
        let currentPinnedTabsByID = Dictionary(uniqueKeysWithValues: currentPinnedTabs.map { ($0.id, $0) })
        let previousPinnedAnchors = Dictionary(uniqueKeysWithValues: currentPinnedTabs.map { ($0.id, $0.anchor) })
        let activeTabIDBeforeSync = contentTabs.activeTabID
        let pendingPinnedIDs = contentTabs.pendingPinnedRecordIDs
        let synchronizedPinnedTabs = synchronizedPinnedTabs(
            PinnedSyncContext(
                restoredPinnedTabs: restoredPinnedTabs,
                pendingPinnedIDs: pendingPinnedIDs,
                currentPinnedTabsByID: currentPinnedTabsByID,
                activeTabIDBeforeSync: activeTabIDBeforeSync,
                mode: mode,
                runtimePreservingTabIDs: runtimePreservingTabIDs,
            ),
        )
        let pendingPinnedTabs = currentPinnedTabs.filter { pendingPinnedIDs.contains($0.id) }
        let mergedPinnedTabs = synchronizedPinnedTabs + pendingPinnedTabs
        let mergedPinnedIDs = Set(mergedPinnedTabs.map(\.id))
        let newlyInsertedPinnedIDs = mergedPinnedIDs.subtracting(existingTabIDs)
        let currentUnpinnedTabs = Array(contentTabs.tabs.filter { !$0.isPinned && !mergedPinnedIDs.contains($0.id) })
        let currentPinnedIDs = Set(currentPinnedTabs.map(\.id))
        let retainedPendingPinnedIDs = pendingPinnedIDs.intersection(contentTabs.tabs.ids)
        let pendingPinnedRecords = contentTabs.pinnedRecords.filter { retainedPendingPinnedIDs.contains($0.key) }
        let synchronizedPinnedRecords = restoredPinnedState.pinnedRecords.filter {
            !retainedPendingPinnedIDs.contains($0.key)
        }
        let changedPinnedTabIDs = changedPinnedTabIDs(
            restoredPinnedTabs: restoredPinnedTabs,
            mode: mode,
            runtimePreservingTabIDs: runtimePreservingTabIDs,
            previousPinnedAnchors: previousPinnedAnchors,
        )
        return PinnedContentTabsPlan(
            mergedPinnedTabs: mergedPinnedTabs,
            currentUnpinnedTabs: currentUnpinnedTabs,
            newlyInsertedPinnedIDs: newlyInsertedPinnedIDs,
            removedPinnedIDs: currentPinnedIDs.subtracting(restoredTabIDs),
            synchronizedPinnedRecords: synchronizedPinnedRecords,
            pendingPinnedRecords: pendingPinnedRecords,
            retainedPendingPinnedIDs: retainedPendingPinnedIDs,
            changedPinnedTabIDs: changedPinnedTabIDs,
            activeTabIDBeforeSync: activeTabIDBeforeSync,
        )
    }

    private func changedPinnedTabIDs(
        restoredPinnedTabs: [ContentTabItem],
        mode: PinnedContentTabsApplicationMode,
        runtimePreservingTabIDs: Set<ContentTabID>,
        previousPinnedAnchors: [ContentTabID: ContentTabPageAnchor],
    ) -> Set<ContentTabID> {
        guard mode == .authoritative else { return [] }
        return Set(restoredPinnedTabs.compactMap { tab -> ContentTabID? in
            guard !runtimePreservingTabIDs.contains(tab.id),
                  previousPinnedAnchors[tab.id].map({ $0 != tab.anchor }) == true
            else { return nil }
            return tab.id
        })
    }

    private func synchronizedPinnedTabs(_ context: PinnedSyncContext) -> [ContentTabItem] {
        context.restoredPinnedTabs
            .filter { !context.pendingPinnedIDs.contains($0.id) }
            .map { restoredTab in
                let hasRuntimeState = tabContentStates[restoredTab.id] != nil
                    || tabInspectorStates[restoredTab.id] != nil
                let preservesRuntime = context.mode == .preservingRuntime
                    || context.runtimePreservingTabIDs.contains(restoredTab.id)
                guard preservesRuntime,
                      context.runtimePreservingTabIDs.contains(restoredTab.id)
                      || restoredTab.id != context.activeTabIDBeforeSync
                      || hasRuntimeState,
                      let currentTab = context.currentPinnedTabsByID[restoredTab.id]
                else { return restoredTab }
                return currentTab
            }
    }

    private mutating func reactivateTabAfterPinnedSync(plan: PinnedContentTabsPlan) {
        if contentTabs.tabs.isEmpty {
            contentTabs = .withHomeTab()
            restoreContentStateForActiveTab()
            restoreInspectorStateForActiveTab()
        } else if let activeTabID = contentTabs.activeTabID,
                  contentTabs.tabs[id: activeTabID] != nil
        {
            if activeTabID == plan.activeTabIDBeforeSync, plan.changedPinnedTabIDs.contains(activeTabID) {
                restoreContentStateForActiveTab()
                restoreInspectorStateForActiveTab()
            }
        } else {
            contentTabs.activeTabID = plan.mergedPinnedTabs.first?.id ?? plan.currentUnpinnedTabs.first?.id
            restoreContentStateForActiveTab()
            restoreInspectorStateForActiveTab()
        }
    }

    private mutating func installSemanticOwners(forNewPinnedTabIDs tabIDs: Set<ContentTabID>) {
        for tabID in tabIDs {
            let anchor = contentTabs.tabs[id: tabID]?.anchor
            if tabContentStates[tabID] == nil {
                tabContentStates[tabID] = FileManagerContentFeature.State.initialContent(
                    for: anchor,
                    inheritingWindowContextFrom: content,
                )
            }
            if supportsInspector(tabID: tabID) {
                if tabInspectorStates[tabID] == nil {
                    tabInspectorStates[tabID] = FileManagerInspectorFeature.State().tabSnapshot()
                }
            } else {
                tabInspectorStates[tabID] = nil
            }
        }
    }

    mutating func addBackgroundAiChatState(sessionID: AiChatSessionID, state: FileManagerContentFeature.State) {
        let shouldPreserveOwner = switch state.aiChat.executionPhase {
        case .completed,
             .persistenceRecovery:
            true
        default:
            false
        }
        let hasBackgroundExecutionPhase = state.aiChat.backgroundExecutionPhases.values.contains {
            $0.lock?.context.sessionID == sessionID
        }
        let hasBackgroundPendingRequestStart = state.aiChat.backgroundPendingRequestStarts.values.contains {
            $0.sessionID == sessionID
        }
        guard state.aiChat.executionPhase.isProcessing
            || shouldPreserveOwner
            || state.aiChat.pendingRequestStart != nil
            || hasBackgroundPendingRequestStart
            || hasBackgroundExecutionPhase
        else { return }
        var mergedState = state
        if let existingState = backgroundAiChatStates[sessionID] {
            mergedState.aiChat.mergeBackgroundLifecycleOwners(from: existingState.aiChat)
        }
        backgroundAiChatStates[sessionID] = mergedState
    }

    @discardableResult
    mutating func removeBackgroundAiChatState(sessionID: AiChatSessionID) -> FileManagerContentFeature.State? {
        backgroundAiChatStates.removeValue(forKey: sessionID)
    }

    func backgroundAiChatState(for sessionID: AiChatSessionID) -> FileManagerContentFeature.State? {
        backgroundAiChatStates[sessionID]
    }

    func canPinContentTab(_ tabID: ContentTabID) -> Bool {
        guard let tab = contentTabs.tabs[id: tabID] else { return false }

        let contentState = contentTabs.activeTabID == tabID ? content : tabContentStates[tabID]
        switch tab.page {
        case .home, .aiChat:
            return false
        case .directory:
            guard let contentState else { return true }
            let isShowingCollectionNavigation = if case .collection = contentState.navigation.navigationState {
                true
            } else {
                false
            }
            return !contentState.isCollectionMode && !isShowingCollectionNavigation
        case .collection:
            guard case .collectionFile = tab.anchor,
                  let contentState,
                  contentState.isCollectionMode,
                  contentState.collection.collectionSession.document?.url != nil,
                  contentState.collection.collectionSession.metadata.baseline != nil
            else {
                return false
            }
            if case let .collection(navigation) = contentState.navigation.navigationState,
               case .temporary = navigation.kind
            {
                return false
            }
            return contentState.openedCollectionURLExists
        }
    }
}

extension FileManagerInspectorFeature.State {
    var shouldPreserveAiChatInBackground: Bool {
        !aiChat.lifecycleSessionIDsToPreserve.isEmpty
    }

    func tabSnapshot() -> Self {
        var snapshot = self
        snapshot.inspectorPaneExists = false
        return snapshot
    }
}

private extension AiChatFeature.State {
    mutating func mergeBackgroundLifecycleOwners(from existingState: Self) {
        mergeBackgroundPendingRequestStart(existingState.pendingRequestStart)
        for pendingRequestStart in existingState.backgroundPendingRequestStarts.values {
            mergeBackgroundPendingRequestStart(pendingRequestStart)
        }
        mergeBackgroundLifecycleOwner(existingState.executionPhase)
        for phase in existingState.backgroundExecutionPhases.values {
            mergeBackgroundLifecycleOwner(phase)
        }
    }

    mutating func mergeBackgroundPendingRequestStart(_ pendingRequestStart: AiChatPendingRequestStart?) {
        guard let pendingRequestStart else { return }
        if self.pendingRequestStart?.resolutionID == pendingRequestStart.resolutionID { return }
        backgroundPendingRequestStarts[pendingRequestStart.resolutionID] = pendingRequestStart
    }

    mutating func mergeBackgroundLifecycleOwner(_ phase: AiChatExecutionPhase) {
        guard let lock = phase.lock else { return }
        if executionPhase.lock?.requestID == lock.requestID { return }
        backgroundExecutionPhases[lock.requestID] = phase
    }
}

extension AiChatFeature.State {
    var lifecycleSessionIDsToPreserve: [AiChatSessionID] {
        var sessionIDs: [AiChatSessionID] = []
        let shouldPreserveOwner = switch executionPhase {
        case let .completed(lock):
            lock.finalSnapshot != nil
        case .persistenceRecovery:
            true
        default:
            false
        }
        if executionPhase.isProcessing || shouldPreserveOwner,
           let ownerSessionID = executionPhase.lock?.context.sessionID
        {
            sessionIDs.append(ownerSessionID)
        }
        if let pendingSessionID = pendingRequestStart?.sessionID {
            sessionIDs.append(pendingSessionID)
        }
        for pendingRequestStart in backgroundPendingRequestStarts.values {
            sessionIDs.append(pendingRequestStart.sessionID)
        }
        for phase in backgroundExecutionPhases.values where phase.isProcessing {
            if let sessionID = phase.lock?.context.sessionID {
                sessionIDs.append(sessionID)
            }
        }
        return Array(Set(sessionIDs))
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

    mutating func applyWindowContext(windowID: UUID) {
        entryViewLayout.entryOperations.windowID = windowID
        composer.cancellationOwnerID = windowID
    }

    mutating func applyWindowContext(from source: Self) {
        entryViewLayout.mode = source.entryViewLayout.mode
        entryViewLayout.listIconSize = source.entryViewLayout.listIconSize
        entryViewLayout.gridIconSize = source.entryViewLayout.gridIconSize
        entryViewLayout.listTextSize = source.entryViewLayout.listTextSize
        entryViewLayout.gridTextSize = source.entryViewLayout.gridTextSize
        entryViewLayout.showHiddenFiles = source.entryViewLayout.showHiddenFiles
        entryViewLayout.entryOperations.windowID = source.entryViewLayout.entryOperations.windowID
        entryViewLayout.entryArrangements.sortKey = source.entryViewLayout.entryArrangements.sortKey
        entryViewLayout.entryArrangements.sortOrder = source.entryViewLayout.entryArrangements.sortOrder
        entryViewLayout.entryArrangements.hasUserSetSortOrder = source.entryViewLayout.entryArrangements
            .hasUserSetSortOrder
        entryViewLayout.entryArrangements.groupKey = source.entryViewLayout.entryArrangements.groupKey
        composer.cancellationOwnerID = source.composer.cancellationOwnerID
    }
}

private struct PinnedContentTabsPlan {
    var mergedPinnedTabs: [ContentTabItem]
    var currentUnpinnedTabs: [ContentTabItem]
    var newlyInsertedPinnedIDs: Set<ContentTabID>
    var removedPinnedIDs: Set<ContentTabID>
    var synchronizedPinnedRecords: [ContentTabID: ContentTabPinnedRecord]
    var pendingPinnedRecords: [ContentTabID: ContentTabPinnedRecord]
    var retainedPendingPinnedIDs: Set<ContentTabID>
    var changedPinnedTabIDs: Set<ContentTabID>
    var activeTabIDBeforeSync: ContentTabID?
}

private struct PinnedSyncContext {
    var restoredPinnedTabs: [ContentTabItem]
    var pendingPinnedIDs: Set<ContentTabID>
    var currentPinnedTabsByID: [ContentTabID: ContentTabItem]
    var activeTabIDBeforeSync: ContentTabID?
    var mode: PinnedContentTabsApplicationMode
    var runtimePreservingTabIDs: Set<ContentTabID>
}

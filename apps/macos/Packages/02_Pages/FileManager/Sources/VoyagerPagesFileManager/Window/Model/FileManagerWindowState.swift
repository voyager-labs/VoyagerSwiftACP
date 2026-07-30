import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

@ObservableState
struct ContentTabRowInteractionSurface: Equatable {
    let currentTabIDs: [ContentTabID]
    let validSelectedTabIDs: Set<ContentTabID>
    let isCloseEnabled: Bool
    let isPinMutationEnabled: Bool

    init(state: FileManagerWindowState) {
        let currentTabIDs = Array(state.contentTabs.tabs.ids)
        self.init(
            currentTabIDs: currentTabIDs,
            validSelectedTabIDs: Set(currentTabIDs).intersection(state.contentTabs.selectedTabIDs),
            isCloseEnabled: state.canStartSelectedContentTabClose,
            isPinMutationEnabled: state.canStartSelectedContentTabPinMutation,
        )
    }

    init(
        currentTabIDs: [ContentTabID],
        validSelectedTabIDs: Set<ContentTabID>,
        isCloseEnabled: Bool,
        isPinMutationEnabled: Bool,
    ) {
        self.currentTabIDs = currentTabIDs
        self.validSelectedTabIDs = validSelectedTabIDs
        self.isCloseEnabled = isCloseEnabled
        self.isPinMutationEnabled = isPinMutationEnabled
    }
}

public enum FileManagerUndoRedoPhase: Equatable, Sendable {
    case idle
    case invoking(requestID: UUID, direction: EntryActionDirection)
    case replaying(requestID: UUID, direction: EntryActionDirection)
    case refreshing(requestID: UUID)
    case recovering(requestID: UUID, direction: EntryActionDirection, ownerID: UUID)
    case tearingDownTab(requestID: UUID, ownerID: UUID)
    case desynchronized
}

enum FileManagerFixedLocationsLoadPhase: Equatable {
    case idle
    case loading(UUID)
    case loaded
}

enum FileManagerAiChatInspectorDestination: Equatable {
    case newChat
    case chatHistory
}

struct FileManagerPendingAiChatInspectorOpen: Equatable {
    var requestID: UUID
    var tabID: ContentTabID
    var destination: FileManagerAiChatInspectorDestination
}

struct FileManagerPendingAiChatNewChat: Equatable {
    var requestID: UUID
    var tabID: ContentTabID
    var target: FileManagerAiChatNewChatTarget
    var windowLast: AiChatNewChatSelectionCandidate?
    var persistedDefault: AiChatPersistedSelectionCandidate?
    var didLoadPersistedDefault: Bool
    var requiresCatalogRefresh: Bool
    var didObserveCatalogRefresh: Bool
    var expectedModelListRequestID: UUID?
}

struct FileManagerAiChatSelection: Equatable {
    var modelHandle: AiModelHandle
    var thinking: AiThinkingSelection?
}

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
    public var pendingSelectedContentTabClose: PendingSelectedContentTabClose?
    public var pendingSelectedContentTabPinMutation: PendingSelectedContentTabPinMutation?
    public var deferredPinnedContentTabs: ContentTabState?
    public var deferredPinnedContentTabsMode: PinnedContentTabsApplicationMode?
    var pendingRuntimePreservationRecords: [ContentTabID: ContentTabPinnedRecord] = [:]
    public var pendingContentTabTeardown: PendingContentTabTeardown?
    public var isClosing: Bool
    public var pendingDirectoryReloadTabIDs: Set<ContentTabID>
    public var undoManagerAvailability: UndoManagerAvailability
    public var undoRedoPhase: FileManagerUndoRedoPhase
    public var sidebarEntryDropOperations: EntryOperationsState
    public var pendingCollectionOpenRequest: ContentPageCollectionOpenRequest?
    var lastExplicitAiChatSelection: FileManagerAiChatSelection?
    var pendingAiChatInspectorOpen: FileManagerPendingAiChatInspectorOpen?
    var pendingAiChatNewChat: FileManagerPendingAiChatNewChat?
    var fixedLocationsLoadPhase: FileManagerFixedLocationsLoadPhase = .idle
    var homeFavoriteItems: [FileManagerHomeFavoriteItem] = []

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
        pendingSelectedContentTabClose = nil
        pendingSelectedContentTabPinMutation = nil
        deferredPinnedContentTabs = nil
        deferredPinnedContentTabsMode = nil
        pendingContentTabTeardown = nil
        isClosing = false
        pendingDirectoryReloadTabIDs = []
        undoManagerAvailability = .init()
        undoRedoPhase = .idle
        sidebarEntryDropOperations = .init()
        pendingCollectionOpenRequest = nil
        lastExplicitAiChatSelection = nil
        pendingAiChatInspectorOpen = nil
        pendingAiChatNewChat = nil
        if let activeTabID = contentTabs.activeTabID {
            tabContentStates[activeTabID] = content
        }
        syncContentTabSidebarItems()
    }

    public static func makeInitial(path: String?, selectEntryID: String? = nil) -> Self {
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
        state.content.pendingSelectEntryID = selectEntryID

        state.syncActiveTabContentState()
        state.restoreInspectorStateForActiveTab()
        state.syncContentTabSidebarItems()
        return state
    }

    public static func makeInitial(
        path: String?,
        contentTabs: ContentTabState?,
        selectEntryID: String? = nil,
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

        state.content.pendingSelectEntryID = selectEntryID

        state.syncActiveTabContentState()
        state.restoreInspectorStateForActiveTab()
        state.syncContentTabSidebarItems()
        return state
    }

    public static func makeExternalInitial(
        reservations: [ExternalContentTabReservation],
        windowID: UUID? = nil,
    ) -> Self? {
        guard canReserveExternalContentTabs(
            reservations,
            existingIDs: [],
            existingCount: 0,
        ) else { return nil }

        var windowContext = FileManagerContentFeature.State()
        if let windowID {
            windowContext.applyWindowContext(windowID: windowID)
        }
        let snapshots = externalSnapshots(
            for: reservations,
            inheritingWindowContextFrom: windowContext,
        )
        guard let activeReservation = reservations.last,
              let activeContent = snapshots.content[activeReservation.id]
        else { return nil }

        var tabs = ContentTabState().tabs
        for reservation in reservations {
            tabs.append(ContentTabItem.makeExternalReservation(
                id: reservation.id,
                anchor: reservation.anchor,
            ))
        }
        let previousActiveTabID = reservations.dropLast().last?.id
        var state = Self(
            externalContent: activeContent,
            externalContentStates: snapshots.content,
            externalInspectorStates: snapshots.inspector,
            externalContentTabs: ContentTabState(
                tabs: tabs,
                activeTabID: activeReservation.id,
                previousActiveTabID: previousActiveTabID,
            ),
            externalInspector: snapshots.inspector[activeReservation.id] ?? .init(),
            windowID: windowID,
        )
        state.syncContentTabSidebarItems()
        return state
    }

    private init(
        externalContent: FileManagerContentFeature.State,
        externalContentStates: [ContentTabID: FileManagerContentFeature.State],
        externalInspectorStates: [ContentTabID: FileManagerInspectorFeature.State],
        externalContentTabs: ContentTabState,
        externalInspector: FileManagerInspectorFeature.State,
        windowID initialWindowID: UUID?,
    ) {
        content = externalContent
        tabContentStates = externalContentStates
        tabInspectorStates = externalInspectorStates
        backgroundAiChatStates = [:]
        backgroundInspectorAiChatStates = [:]
        sidebar = .init()
        inspector = externalInspector
        contentTabs = externalContentTabs
        recentlyClosedNavigationRoute = nil
        pendingContentTabClose = nil
        pendingSelectedContentTabClose = nil
        pendingSelectedContentTabPinMutation = nil
        deferredPinnedContentTabs = nil
        deferredPinnedContentTabsMode = nil
        pendingContentTabTeardown = nil
        isClosing = false
        pendingDirectoryReloadTabIDs = []
        undoManagerAvailability = .init()
        undoRedoPhase = .idle
        var sidebarEntryDropOperations = EntryOperationsState()
        sidebarEntryDropOperations.windowID = initialWindowID
        self.sidebarEntryDropOperations = sidebarEntryDropOperations
        pendingCollectionOpenRequest = nil
        lastExplicitAiChatSelection = nil
        pendingAiChatInspectorOpen = nil
        pendingAiChatNewChat = nil
        fixedLocationsLoadPhase = .idle
        homeFavoriteItems = []
    }
}

public struct PendingContentTabTeardown: Equatable, Sendable {
    public let requestID: UUID
    public let tabID: ContentTabID
    public let ownerID: UUID

    public init(requestID: UUID, tabID: ContentTabID, ownerID: UUID) {
        self.requestID = requestID
        self.tabID = tabID
        self.ownerID = ownerID
    }
}

public struct PendingSelectedContentTabPinMutation: Equatable {
    public let operationID: UUID
    public let target: SelectedContentTabPinMutationTargetState
    public let orderedTargetIDs: [ContentTabID]
    public var cursor: Int
    public var currentTabID: ContentTabID?
    public var currentItemRollbackSnapshot: ContentTabPinnedRecordRollbackSnapshot?
    public var successCount: Int
    public var failureCount: Int
    public var remainingCount: Int

    public var totalCount: Int {
        orderedTargetIDs.count
    }

    public init(
        operationID: UUID,
        target: SelectedContentTabPinMutationTargetState,
        orderedTargetIDs: [ContentTabID],
        cursor: Int = 0,
        currentTabID: ContentTabID? = nil,
        currentItemRollbackSnapshot: ContentTabPinnedRecordRollbackSnapshot? = nil,
        successCount: Int = 0,
        failureCount: Int = 0,
        remainingCount: Int = 0,
    ) {
        self.operationID = operationID
        self.target = target
        self.orderedTargetIDs = orderedTargetIDs
        self.cursor = cursor
        self.currentTabID = currentTabID
        self.currentItemRollbackSnapshot = currentItemRollbackSnapshot
        self.successCount = successCount
        self.failureCount = failureCount
        self.remainingCount = remainingCount
    }
}

public struct PendingSelectedContentTabClose: Equatable, Sendable {
    public let operationID: UUID
    public let orderedTargetIDs: [ContentTabID]
    public var cursor: Int
    public var currentTabID: ContentTabID?
    public let originalActiveTabID: ContentTabID?
    public let preferredFallbackIDs: [ContentTabID]

    public init(
        operationID: UUID,
        orderedTargetIDs: [ContentTabID],
        cursor: Int,
        currentTabID: ContentTabID?,
        originalActiveTabID: ContentTabID?,
        preferredFallbackIDs: [ContentTabID],
    ) {
        self.operationID = operationID
        self.orderedTargetIDs = orderedTargetIDs
        self.cursor = cursor
        self.currentTabID = currentTabID
        self.originalActiveTabID = originalActiveTabID
        self.preferredFallbackIDs = preferredFallbackIDs
    }

    public init(
        operationID: UUID,
        orderedTargetIDs: [ContentTabID],
        originalActiveTabID: ContentTabID?,
        preferredFallbackIDs: [ContentTabID],
    ) {
        self.init(
            operationID: operationID,
            orderedTargetIDs: orderedTargetIDs,
            cursor: 0,
            currentTabID: nil,
            originalActiveTabID: originalActiveTabID,
            preferredFallbackIDs: preferredFallbackIDs,
        )
    }

    public init(
        operationID: UUID,
        orderedTargetIDs: [ContentTabID],
        cursor: Int,
        originalActiveTabID: ContentTabID?,
        preferredFallbackIDs: [ContentTabID],
    ) {
        self.init(
            operationID: operationID,
            orderedTargetIDs: orderedTargetIDs,
            cursor: cursor,
            currentTabID: nil,
            originalActiveTabID: originalActiveTabID,
            preferredFallbackIDs: preferredFallbackIDs,
        )
    }

    public init(
        operationID: UUID,
        orderedTargetIDs: [ContentTabID],
        currentTabID: ContentTabID?,
        originalActiveTabID: ContentTabID?,
        preferredFallbackIDs: [ContentTabID],
    ) {
        self.init(
            operationID: operationID,
            orderedTargetIDs: orderedTargetIDs,
            cursor: 0,
            currentTabID: currentTabID,
            originalActiveTabID: originalActiveTabID,
            preferredFallbackIDs: preferredFallbackIDs,
        )
    }
}

public struct PendingContentTabClose: Equatable {
    public let tabID: ContentTabID
    public let previousActiveTabID: ContentTabID?
    public let originalPreviousActiveTabID: ContentTabID?
    public let previousActiveContent: FileManagerContentFeature.State?
    public let targetContent: FileManagerContentFeature.State?
    public let previousActiveInspector: FileManagerInspectorFeature.State?
    public let targetInspector: FileManagerInspectorFeature.State?
    public let batchOperationID: UUID?
    public var didReceiveWriteBackNavigationState: Bool
    public var didReceiveWriteBackComposerSync: Bool
    public var requiresWriteBackFailureTerminal: Bool
    public var didReceiveSaveCompletedFailure: Bool
    public var didReceiveWriteBackFailure: Bool
    public var didReceiveSaveFeedbackFailure: Bool
    public var didReceiveSaveBlockedFeedback: Bool

    public init(
        tabID: ContentTabID,
        previousActiveTabID: ContentTabID? = nil,
        originalPreviousActiveTabID: ContentTabID? = nil,
        previousActiveContent: FileManagerContentFeature.State? = nil,
        targetContent: FileManagerContentFeature.State? = nil,
        previousActiveInspector: FileManagerInspectorFeature.State? = nil,
        targetInspector: FileManagerInspectorFeature.State? = nil,
        batchOperationID: UUID? = nil,
        didReceiveWriteBackNavigationState: Bool = false,
        didReceiveWriteBackComposerSync: Bool = false,
        requiresWriteBackFailureTerminal: Bool = true,
        didReceiveSaveCompletedFailure: Bool = false,
        didReceiveWriteBackFailure: Bool = false,
        didReceiveSaveFeedbackFailure: Bool = false,
        didReceiveSaveBlockedFeedback: Bool = false,
    ) {
        self.tabID = tabID
        self.previousActiveTabID = previousActiveTabID
        self.originalPreviousActiveTabID = originalPreviousActiveTabID
        self.previousActiveContent = previousActiveContent
        self.targetContent = targetContent
        self.previousActiveInspector = previousActiveInspector
        self.targetInspector = targetInspector
        self.batchOperationID = batchOperationID
        self.didReceiveWriteBackNavigationState = didReceiveWriteBackNavigationState
        self.didReceiveWriteBackComposerSync = didReceiveWriteBackComposerSync
        self.requiresWriteBackFailureTerminal = requiresWriteBackFailureTerminal
        self.didReceiveSaveCompletedFailure = didReceiveSaveCompletedFailure
        self.didReceiveWriteBackFailure = didReceiveWriteBackFailure
        self.didReceiveSaveFeedbackFailure = didReceiveSaveFeedbackFailure
        self.didReceiveSaveBlockedFeedback = didReceiveSaveBlockedFeedback
    }
}

private func isSelectedContentTabCloseBusy(_ content: FileManagerContentFeature.State) -> Bool {
    content.collection.isSaving
        || content.collection.collectionSession.phase.isOpening
        || content.collection.collectionSession.phase.isInflightRefresh
        || content.collection.collectionSession.phase.isInflightWriteBack
}

public extension FileManagerWindowState {
    internal var canStartSelectedContentTabClose: Bool {
        let selectedInactiveContentIsBusy = contentTabs.orderedValidSelectedTabIDs.contains { tabID in
            tabID != contentTabs.activeTabID
                && tabContentStates[tabID].map(isSelectedContentTabCloseBusy) == true
        }
        guard !isClosing,
              pendingSelectedContentTabClose == nil,
              pendingSelectedContentTabPinMutation == nil,
              pendingContentTabClose == nil,
              pendingContentTabTeardown == nil,
              !isSelectedContentTabCloseBusy(content),
              !selectedInactiveContentIsBusy,
              contentTabs.pendingPinnedRecordIDs.isEmpty
        else { return false }

        switch undoRedoPhase {
        case .idle, .desynchronized:
            return true
        case .invoking, .replaying, .refreshing, .recovering, .tearingDownTab:
            return false
        }
    }

    internal var canStartSelectedContentTabPinMutation: Bool {
        guard !isClosing,
              pendingSelectedContentTabPinMutation == nil,
              pendingSelectedContentTabClose == nil,
              pendingContentTabClose == nil,
              pendingContentTabTeardown == nil,
              contentTabs.pendingPinnedRecordIDs.isEmpty,
              !isSelectedContentTabCloseBusy(content),
              !contentTabs.orderedValidSelectedTabIDs.contains(where: { tabID in
                  tabID != contentTabs.activeTabID
                      && tabContentStates[tabID].map(isSelectedContentTabCloseBusy) == true
              })
        else { return false }

        switch undoRedoPhase {
        case .idle, .desynchronized:
            return true
        case .invoking, .replaying, .refreshing, .recovering, .tearingDownTab:
            return false
        }
    }

    internal var contentTabRowInteractionSurface: ContentTabRowInteractionSurface {
        ContentTabRowInteractionSurface(state: self)
    }

    func appPreferencesPreservingSidebarState(from preferences: AppPreferencesState) -> AppPreferencesState {
        var result = preferences
        result.sidebarVisible = sidebar.sidebarVisible
        result.sidebarWidth = sidebar.sidebarWidth
        return result
    }
}

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
        content.homeLocationItems = items
    }

    // MARK: - Home Dashboard Projection

    mutating func applyHomeFavoriteItems(_ items: [FileManagerHomeFavoriteItem]) {
        homeFavoriteItems = items
        syncHomeFavoriteItems()
    }

    mutating func syncHomeFavoriteItems() {
        content.homeFavoriteItems = homeFavoriteItems
    }

    mutating func syncHomeLocationItems() {
        content.homeLocationItems = sidebar.allFixedLocationItems
    }

    mutating func applyPinnedContentTabs(
        _ restoredPinnedState: ContentTabState,
        mode: PinnedContentTabsApplicationMode = .preservingRuntime,
        runtimePreservingTabIDs: Set<ContentTabID> = [],
    ) {
        let recentlyClosed = contentTabs.recentlyClosed
        let restoredPinnedTabs = restoredPinnedState.tabs.filter(\.isPinned)
        let restoredTabIDs = Set(restoredPinnedTabs.map(\.id))
        let currentPinnedTabs = contentTabs.tabs.filter(\.isPinned)
        let currentPinnedTabsByID = Dictionary(uniqueKeysWithValues: currentPinnedTabs.map { ($0.id, $0) })
        let previousPinnedAnchors = Dictionary(uniqueKeysWithValues: currentPinnedTabs.map { ($0.id, $0.anchor) })
        let activeTabIDBeforeSync = contentTabs.activeTabID
        let pendingPinnedIDs = contentTabs.pendingPinnedRecordIDs
        let synchronizedPinnedTabs = restoredPinnedTabs
            .filter { !pendingPinnedIDs.contains($0.id) }
            .map { restoredTab in
                let hasRuntimeState = tabContentStates[restoredTab.id] != nil
                    || tabInspectorStates[restoredTab.id] != nil
                let preservesRuntime = mode == .preservingRuntime
                    || runtimePreservingTabIDs.contains(restoredTab.id)
                guard preservesRuntime,
                      runtimePreservingTabIDs.contains(restoredTab.id)
                      || restoredTab.id != activeTabIDBeforeSync
                      || hasRuntimeState,
                      let currentTab = currentPinnedTabsByID[restoredTab.id]
                else { return restoredTab }
                return currentTab
            }
        let pendingPinnedTabs = currentPinnedTabs.filter { pendingPinnedIDs.contains($0.id) }
        let mergedPinnedTabs = synchronizedPinnedTabs + pendingPinnedTabs
        let mergedPinnedIDs = Set(mergedPinnedTabs.map(\.id))
        let currentUnpinnedTabs = contentTabs.tabs.filter { !$0.isPinned && !mergedPinnedIDs.contains($0.id) }
        let currentPinnedIDs = Set(currentPinnedTabs.map(\.id))

        let currentTabIDs = Set(contentTabs.tabs.ids)
        let retainedPendingPinnedIDs = pendingPinnedIDs.intersection(currentTabIDs)
        let pendingPinnedRecords = contentTabs.pinnedRecords.filter { retainedPendingPinnedIDs.contains($0.key) }
        let synchronizedPinnedRecords = restoredPinnedState.pinnedRecords.filter {
            !retainedPendingPinnedIDs.contains($0.key)
        }

        contentTabs.tabs = IdentifiedArrayOf(uniqueElements: mergedPinnedTabs + currentUnpinnedTabs)
        contentTabs.pinnedRecords = synchronizedPinnedRecords
            .merging(pendingPinnedRecords) { _, pending in pending }
        contentTabs.pendingPinnedRecordIDs = retainedPendingPinnedIDs
        contentTabs.previousActiveTabID = nil

        for removedID in currentPinnedIDs.subtracting(restoredTabIDs) where contentTabs.tabs[id: removedID] == nil {
            tabContentStates[removedID] = nil
            tabInspectorStates[removedID] = nil
        }
        let changedPinnedTabIDs: Set<ContentTabID> = mode == .authoritative
            ? Set(restoredPinnedTabs.compactMap { tab -> ContentTabID? in
                guard !runtimePreservingTabIDs.contains(tab.id),
                      previousPinnedAnchors[tab.id].map({ $0 != tab.anchor }) == true
                else { return nil }
                return tab.id
            })
            : []
        for changedID in changedPinnedTabIDs {
            tabContentStates[changedID] = nil
            tabInspectorStates[changedID] = nil
        }

        if contentTabs.tabs.isEmpty {
            contentTabs = .withHomeTab()
            restoreContentStateForActiveTab()
            restoreInspectorStateForActiveTab()
        } else if let activeTabID = contentTabs.activeTabID,
                  contentTabs.tabs[id: activeTabID] != nil
        {
            if activeTabID == activeTabIDBeforeSync, changedPinnedTabIDs.contains(activeTabID) {
                restoreContentStateForActiveTab()
                restoreInspectorStateForActiveTab()
            }
        } else {
            contentTabs.activeTabID = mergedPinnedTabs.first?.id ?? currentUnpinnedTabs.first?.id
            restoreContentStateForActiveTab()
            restoreInspectorStateForActiveTab()
        }

        contentTabs.recentlyClosed = recentlyClosed
        contentTabs.reconcileSelection()
        syncContentTabSidebarItems()
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

private extension AiChatExecutionPhase {
    var shouldPreserveLifecycleOwner: Bool {
        switch self {
        case let .completed(lock):
            lock.finalSnapshot != nil
        case .persistenceRecovery:
            true
        default:
            false
        }
    }
}

private extension AiChatFeature.State {
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
        for phase in backgroundExecutionPhases.values where phase.isProcessing || phase.shouldPreserveLifecycleOwner {
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
        entryViewLayout.entryArrangements.sortKey = source.entryViewLayout.entryArrangements.sortKey
        entryViewLayout.entryArrangements.sortOrder = source.entryViewLayout.entryArrangements.sortOrder
        entryViewLayout.entryArrangements.hasUserSetSortOrder = source.entryViewLayout.entryArrangements
            .hasUserSetSortOrder
        entryViewLayout.entryArrangements.groupKey = source.entryViewLayout.entryArrangements.groupKey
        entryViewLayout.entryOperations.windowID = source.entryViewLayout.entryOperations.windowID
        composer.cancellationOwnerID = source.composer.cancellationOwnerID
    }
}

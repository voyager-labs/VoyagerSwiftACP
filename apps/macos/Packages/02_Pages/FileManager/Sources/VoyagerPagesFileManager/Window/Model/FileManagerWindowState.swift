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
    case reopenChat
}

struct FileManagerPendingAiChatInspectorOpen: Equatable {
    var requestID: UUID
    var tabID: ContentTabID
    var destination: FileManagerAiChatInspectorDestination
    var resumeSessionID: AiChatSessionID?
    var resumeProvenance: AiChatNewChatPreparationProvenance?
    var preservesLiveRuntime: Bool
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

public struct FileManagerTopNavigationOperationToken: Equatable, Hashable, Sendable {
    public let value: UUID

    public init(value: UUID) {
        self.value = value
    }
}

public enum FileManagerTopNavigationIntent: Equatable, Sendable {
    case move(
        source: FileManagerTopNavigationItemID,
        destination: FileManagerTopNavigationMoveDestination,
    )
    case movePinnedGroup(
        orderedIDs: [ContentTabID],
        destination: FileManagerTopNavigationMoveDestination,
    )
    case pin(ContentTabID, placement: ContentTabPlacement? = nil)
    case unpin(ContentTabID)
    case close(ContentTabID)
    case update(ContentTabID)
}

extension FileManagerTopNavigationIntent {
    var isContentTabMoveMetricEligible: Bool {
        switch self {
        case .move, .movePinnedGroup:
            true
        case .pin, .unpin, .close, .update:
            false
        }
    }
}

/// direct pin/unpin 터미널을 탭별로 상관하기 위한 메트릭 키.
public struct ProductContentTabPinMutationMetric: Equatable, Sendable {
    public let operationID: UUID
    public let identity: ContentTabInteractionIdentity

    public init(operationID: UUID, identity: ContentTabInteractionIdentity) {
        self.operationID = operationID
        self.identity = identity
    }
}

public struct FileManagerPendingTopNavigationIntent: Equatable, Sendable {
    public let token: FileManagerTopNavigationOperationToken
    public let intent: FileManagerTopNavigationIntent
    public var persistenceContext: ContentTabPinnedRecordTerminalContext?

    public init(
        token: FileManagerTopNavigationOperationToken,
        intent: FileManagerTopNavigationIntent,
        persistenceContext: ContentTabPinnedRecordTerminalContext? = nil,
    ) {
        self.token = token
        self.intent = intent
        self.persistenceContext = persistenceContext
    }
}

public enum FileManagerTopNavigationArrangementLoadFailure: Equatable, Sendable {
    case corrupt
    case unsupportedSchema(Int)
}

public enum FileManagerTopNavigationArrangementAvailability: Equatable, Sendable {
    case available
    case unavailable(FileManagerTopNavigationArrangementLoadFailure)
}

public enum FileManagerTopNavigationArrangementPresentation: Equatable, Sendable {
    case saveRollback
    case loadUnavailable
}

public extension FileManagerTopNavigationArrangementPresentation {
    init?(failure: FileManagerTopNavigationIntentFailure) {
        switch failure {
        case .save:
            self = .saveRollback
        case .storeUnavailable:
            self = .loadUnavailable
        case .cancelled, .superseded:
            return nil
        }
    }

    var message: String {
        switch self {
        case .saveRollback:
            "Couldn’t save the sidebar order. Your previous order was restored."
        case .loadUnavailable:
            "Couldn’t load the saved sidebar arrangement. A default order is shown; the saved data was not changed."
        }
    }
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
    public var lastConfirmedTopNavigationOrder: FileManagerTopNavigationOrder
    public var lastConfirmedTopNavigationCommitRevision: UInt64?
    public var optimisticTopNavigationOrder: FileManagerTopNavigationOrder
    public var dormantContentTabSlots: [FileManagerTopNavigationOrderPolicy.DormantContentTabSlot]
    public var pendingTopNavigationIntents: [FileManagerPendingTopNavigationIntent]
    public var topNavigationArrangementAvailability: FileManagerTopNavigationArrangementAvailability
    public var topNavigationArrangementPresentation: FileManagerTopNavigationArrangementPresentation? {
        get { sidebar.topNavigationArrangementPresentation }
        set { sidebar.topNavigationArrangementPresentation = newValue }
    }

    public var suppressedPinnedTabIDs: Set<ContentTabID> = []

    public var recentlyClosedNavigationRoute: ContentPageNavigationRoute?
    public var pendingContentTabClose: PendingContentTabClose?
    public var pendingSelectedContentTabClose: PendingSelectedContentTabClose?
    public var pendingSelectedContentTabPinMutation: PendingSelectedContentTabPinMutation?
    var productContentTabMoveOperationIDs: [FileManagerTopNavigationOperationToken: UUID] = [:]
    var productContentTabPinMutationMetrics: [ContentTabID: ProductContentTabPinMutationMetric] = [:]
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
    public var pendingContentTabMove: FileManagerWindowContentTabMovePending?
    public var contentTabMoveParticipantRequestID: UUID?
    public var contentTabMoveFailurePresentation: ContentTabMoveFailurePresentation?
    public var contentTabSwitcherPresentation: FileManagerContentTabSwitcherPresentation?
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
        lastConfirmedTopNavigationOrder = .init()
        lastConfirmedTopNavigationCommitRevision = nil
        optimisticTopNavigationOrder = .init()
        dormantContentTabSlots = []
        pendingTopNavigationIntents = []
        topNavigationArrangementAvailability = .available
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
        pendingContentTabMove = nil
        contentTabMoveParticipantRequestID = nil
        contentTabMoveFailurePresentation = nil
        contentTabSwitcherPresentation = nil
        lastExplicitAiChatSelection = nil
        pendingAiChatInspectorOpen = nil
        pendingAiChatNewChat = nil
        if let activeTabID = contentTabs.activeTabID {
            tabContentStates[activeTabID] = content
        }
        syncContentTabSidebarItems()
    }

    public static func makeInitial(
        path: String?,
        selectEntryID: String? = nil,
        windowID: UUID? = nil,
    ) -> Self {
        var state = Self()
        if let windowID {
            state.content.applyWindowContext(windowID: windowID)
        }
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
        windowID: UUID? = nil,
    ) -> Self {
        var state = Self()
        if let windowID {
            state.content.applyWindowContext(windowID: windowID)
        }
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
                recentlyUsedTabIDs: reservations.reversed().map(\.id),
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
        lastConfirmedTopNavigationOrder = .init()
        lastConfirmedTopNavigationCommitRevision = nil
        optimisticTopNavigationOrder = .init()
        dormantContentTabSlots = []
        pendingTopNavigationIntents = []
        topNavigationArrangementAvailability = .available
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
        pendingContentTabMove = nil
        contentTabMoveFailurePresentation = nil
        contentTabSwitcherPresentation = nil
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

public enum SelectedContentTabPinMutationOrigin: Equatable, Sendable {
    case menu
    case drag
}

public struct PendingSelectedContentTabPinMutation: Equatable {
    public let operationID: UUID
    public let target: SelectedContentTabPinMutationTargetState
    public let orderedTargetIDs: [ContentTabID]
    public let origin: SelectedContentTabPinMutationOrigin
    public let dragOperationID: UUID?
    public let sourceWindowID: UUID?
    public let sourceDomain: ContentTabDomain?
    public let targetDomain: ContentTabDomain?
    public let initialPlacement: ContentTabPlacement?
    public var cursor: Int
    public var currentTabID: ContentTabID?
    public var currentItemRollbackSnapshot: ContentTabPinnedRecordRollbackSnapshot?
    public var lastSuccessfullyPlacedID: ContentTabID?
    public var currentPersistenceContext: ContentTabPinnedRecordTerminalContext?
    public var currentTopNavigationToken: FileManagerTopNavigationOperationToken?
    public var successCount: Int
    public var failureCount: Int
    public var remainingCount: Int

    public var totalCount: Int {
        orderedTargetIDs.count
    }

    public var currentPlacement: ContentTabPlacement? {
        guard origin == .drag else { return nil }
        return lastSuccessfullyPlacedID.map(ContentTabPlacement.after) ?? initialPlacement
    }

    public init(
        operationID: UUID,
        target: SelectedContentTabPinMutationTargetState,
        orderedTargetIDs: [ContentTabID],
        origin: SelectedContentTabPinMutationOrigin = .menu,
        dragOperationID: UUID? = nil,
        sourceWindowID: UUID? = nil,
        sourceDomain: ContentTabDomain? = nil,
        targetDomain: ContentTabDomain? = nil,
        initialPlacement: ContentTabPlacement? = nil,
        cursor: Int = 0,
        currentTabID: ContentTabID? = nil,
        currentItemRollbackSnapshot: ContentTabPinnedRecordRollbackSnapshot? = nil,
        lastSuccessfullyPlacedID: ContentTabID? = nil,
        currentPersistenceContext: ContentTabPinnedRecordTerminalContext? = nil,
        currentTopNavigationToken: FileManagerTopNavigationOperationToken? = nil,
        successCount: Int = 0,
        failureCount: Int = 0,
        remainingCount: Int = 0,
    ) {
        self.operationID = operationID
        self.target = target
        self.orderedTargetIDs = orderedTargetIDs
        self.origin = origin
        self.dragOperationID = dragOperationID
        self.sourceWindowID = sourceWindowID
        self.sourceDomain = sourceDomain
        self.targetDomain = targetDomain
        self.initialPlacement = initialPlacement
        self.cursor = cursor
        self.currentTabID = currentTabID
        self.currentItemRollbackSnapshot = currentItemRollbackSnapshot
        self.lastSuccessfullyPlacedID = lastSuccessfullyPlacedID
        self.currentPersistenceContext = currentPersistenceContext
        self.currentTopNavigationToken = currentTopNavigationToken
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
    public var aggregateResult: ContentTabActionResult?

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
        aggregateResult = nil
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
              contentTabMoveParticipantRequestID == nil,
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
              contentTabMoveParticipantRequestID == nil,
              pendingSelectedContentTabPinMutation == nil,
              pendingSelectedContentTabClose == nil,
              pendingContentTabClose == nil,
              pendingContentTabTeardown == nil,
              pendingContentTabMove == nil,
              pendingTopNavigationIntents.isEmpty,
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

    mutating func replayTopNavigationOverlays() {
        var order = lastConfirmedTopNavigationOrder
        for pending in pendingTopNavigationIntents {
            order = Self.applying(pending.intent, to: order, dormantSlots: dormantContentTabSlots)
        }
        optimisticTopNavigationOrder = order
        syncSidebarTopNavigationItems()
    }

    private static func applying(
        _ intent: FileManagerTopNavigationIntent,
        to order: FileManagerTopNavigationOrder,
        dormantSlots: [FileManagerTopNavigationOrderPolicy.DormantContentTabSlot],
    ) -> FileManagerTopNavigationOrder {
        switch intent {
        case let .move(source, destination):
            FileManagerTopNavigationOrderPolicy.moving(source, to: destination, in: order)

        case let .movePinnedGroup(orderedIDs, destination):
            FileManagerTopNavigationOrderPolicy.movingPinnedContentTabs(
                orderedIDs,
                to: destination,
                in: order,
            )

        case let .pin(id, placement):
            if let placement,
               let placedOrder = FileManagerTopNavigationOrderPolicy.insertingContentTab(
                   id,
                   at: placement,
                   in: order,
               )
            {
                placedOrder
            } else {
                FileManagerTopNavigationOrderPolicy.insertingPinnedItem(
                    id,
                    into: order,
                    dormantSlot: dormantSlots.first { $0.id == id },
                )
            }

        case let .unpin(id), let .close(id):
            FileManagerTopNavigationOrder(items: order.items.filter { $0 != .contentTab(id) })

        case .update:
            order
        }
    }

    func appPreferencesPreservingSidebarState(from preferences: AppPreferencesState) -> AppPreferencesState {
        var result = preferences
        result.sidebarVisible = sidebar.sidebarVisible
        result.sidebarWidth = sidebar.sidebarWidth
        return result
    }
}

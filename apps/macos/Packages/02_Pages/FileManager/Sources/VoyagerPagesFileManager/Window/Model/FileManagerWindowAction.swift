import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

public enum SelectedContentTabPinMutationTargetState: Equatable, Sendable {
    case pinned
    case unpinned
}

public enum SelectedContentTabPinMutationOutcome: Equatable, Sendable {
    case success
    case failure
    case remaining
}

public struct SelectedContentTabPinMutationResult: Equatable, Sendable {
    public let operationID: UUID
    public let target: SelectedContentTabPinMutationTargetState
    public let totalCount: Int
    public let successCount: Int
    public let failureCount: Int
    public let remainingCount: Int
    /// 배치를 시작한 입력 표면. 터미널 메트릭 source_surface의 원천이다.
    public let origin: SelectedContentTabPinMutationOrigin

    public init(
        operationID: UUID,
        target: SelectedContentTabPinMutationTargetState,
        totalCount: Int,
        successCount: Int,
        failureCount: Int,
        remainingCount: Int,
        origin: SelectedContentTabPinMutationOrigin = .menu,
    ) {
        self.operationID = operationID
        self.target = target
        self.totalCount = totalCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.remainingCount = remainingCount
        self.origin = origin
    }
}

public enum FileManagerPinnedRecordPersistenceSource: Equatable, Sendable {
    case contentTab
    case selectedPin(operationID: UUID)
    case selectedClose(operationID: UUID)
}

public enum FileManagerPinnedRecordPersistenceOwnership: Equatable, Sendable {
    case local
    case windowManager
}

extension FileManagerPinnedRecordPersistenceOwnership: DependencyKey {
    public static let liveValue: Self = .local
    public static let testValue: Self = .local
    public static let previewValue: Self = .local
}

public extension DependencyValues {
    var fileManagerPinnedRecordOwner: FileManagerPinnedRecordPersistenceOwnership {
        get { self[FileManagerPinnedRecordPersistenceOwnership.self] }
        set { self[FileManagerPinnedRecordPersistenceOwnership.self] = newValue }
    }
}

public enum SelectedContentTabCloseOutcome: Equatable, Sendable {
    case removed
    case unpinned
    case cancelled
    case failed
    case missing
}

public enum PinnedContentTabsApplicationMode: Equatable, Sendable {
    case preservingRuntime
    case authoritative
}

public struct FileManagerContentNewChatSeedApplication: Equatable, Sendable {
    let tabID: ContentTabID
    let expectedAnchor: ContentTabPageAnchor
    let sessionID: AiChatSessionID?
    let provenance: AiChatNewChatPreparationProvenance
    let seed: AiChatNewChatSelectionSeed?
}

public struct FileManagerInspectorNewChatSeedApplication: Equatable, Sendable {
    let tabID: ContentTabID
    let snapshot: AiChatCurrentContextSnapshot
    let provenance: AiChatNewChatPreparationProvenance
    let applicationProvenance: AiChatNewChatPreparationProvenance
    let seed: AiChatNewChatSelectionSeed?
}

public enum FileManagerTopNavigationIntentFailure: Equatable, Sendable {
    case cancelled
    case superseded
    case save
    case storeUnavailable(FileManagerTopNavigationArrangementLoadFailure)
}

public enum FileManagerTopNavigationIntentTerminal: Equatable, Sendable {
    case committed(FileManagerTopNavigationCommit)
    case failed(FileManagerTopNavigationIntentFailure)
}

public struct FileManagerWindowBootstrap: Equatable, Sendable {
    public let arrangementAvailability: FileManagerTopNavigationArrangementAvailability
    public let committedTopNavigationOrder: FileManagerTopNavigationOrder
    public let authoritativePinnedContentTabs: ContentTabState
    public let fixedLocationItems: [FileManagerFixedLocationItem]

    public init(
        arrangementAvailability: FileManagerTopNavigationArrangementAvailability,
        committedTopNavigationOrder: FileManagerTopNavigationOrder,
        authoritativePinnedContentTabs: ContentTabState,
        fixedLocationItems: [FileManagerFixedLocationItem],
    ) {
        self.arrangementAvailability = arrangementAvailability
        self.committedTopNavigationOrder = committedTopNavigationOrder
        self.authoritativePinnedContentTabs = authoritativePinnedContentTabs
        self.fixedLocationItems = fixedLocationItems
    }
}

@CasePathable
public enum FileManagerWindowAction: CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)

    case `internal`(Internal)
    case request(WindowCommand)
    case content(FileManagerContentFeature.Action)
    case tabContent(tabID: ContentTabID, action: FileManagerContentFeature.Action)
    case backgroundAiChat(AiChatAction)
    case backgroundAiChatSnapshotPersisted(AiChatSessionSnapshot)
    case backgroundInspectorAiChat(AiChatAction)
    case backgroundInspectorSnapshotPersisted(AiChatSessionSnapshot)
    case sidebar(FileManagerSidebarFeature.Action)
    case inspector(FileManagerInspectorFeature.Action)
    case navigation(ContentPageNavigationFeature.Action)
    case contentTabs(ContentTabAction)
    case applyBootstrap(FileManagerWindowBootstrap)
    case applyAppPreferences(AppPreferencesState)
    case applyPinnedContentTabs(ContentTabState)
    case applyAuthoritativePinnedContentTabs(ContentTabState)
    case topNavigationMoveRequested(
        source: FileManagerTopNavigationItemID,
        destination: FileManagerTopNavigationMoveDestination,
    )
    case applyExternalCommittedTopNavigationOrder(
        FileManagerTopNavigationOrder,
        revision: UInt64? = nil,
    )
    case applyCommittedTopNavigationSnapshot(
        order: FileManagerTopNavigationOrder,
        revision: UInt64,
        authoritativePinnedContentTabs: ContentTabState?,
    )
    case applyFixedLocationItems([FileManagerFixedLocationItem])
    case applyUnavailableTopNavigationArrangement(FileManagerTopNavigationArrangementLoadFailure)
    case applyPinnedContentTabRuntimeNavigation(
        tabID: ContentTabID,
        navigationState: ContentPageNavigationRoute,
        pendingSelectEntryID: String? = nil,
    )
    case selectContentTab(ContentTabID)
    case returnContentTabToPinnedLocation(
        ContentTabID,
        pendingSelectEntryID: String? = nil,
        activateIfNeeded: Bool = true,
    )
    case applyHiddenFixedLocationIDs(Set<FileManagerFixedLocationItem.ID>)
    case aiConnectionsFileUpdated(AIConnectionsFile)
    case reserveExternalContentTabs([ExternalContentTabReservation])
    case activateExternalContentTabUndoScopes([ContentTabID])
    case cancelPendingPinnedCollectionReturn(ContentTabID)
    case resyncActiveCollectionNavigation

    case requestSelectedContentTabPinMutation(target: SelectedContentTabPinMutationTargetState)
    case requestContentTabDomainTransition(ContentTabDomainTransitionRequest)
    case processNextSelectedContentTabPinMutation(operationID: UUID)
    case performSelectedContentTabPinMutation(
        operationID: UUID,
        tabID: ContentTabID,
        action: ContentTabAction,
    )
    case selectedPinMutationItemCompleted(
        operationID: UUID,
        tabID: ContentTabID,
        outcome: SelectedContentTabPinMutationOutcome,
    )
    case selectedPinMutationBatchCompleted(SelectedContentTabPinMutationResult)

    case requestCloseSelectedContentTabs
    case requestCloseSelectedTabs(ContentTabActionSource)
    case performSelectedContentTabCloseMutation(
        operationID: UUID,
        tabID: ContentTabID,
        action: ContentTabAction,
    )
    case performBatchCloseContentAction(
        operationID: UUID,
        tabID: ContentTabID,
        action: FileManagerContentAction,
    )
    case performBatchCloseNavigationAction(
        operationID: UUID,
        tabID: ContentTabID,
        action: ContentPageNavigationFeature.Action,
    )
    case processNextSelectedContentTabClose(operationID: UUID)
    case selectedContentTabCloseItemCompleted(
        operationID: UUID,
        tabID: ContentTabID,
        outcome: SelectedContentTabCloseOutcome,
    )
    case closeContentTabRequested(ContentTabID)
    case closeContentTabRequestedWithSource(ContentTabID, ContentTabActionSource)
    case contentTabActionRequested(ContentTabAction, source: ContentTabActionSource)
    case contentTabCloseAlertResponse(CollectionNavigationChoice)
    case selectedContentTabCloseAlertResponse(
        operationID: UUID,
        tabID: ContentTabID,
        choice: CollectionNavigationChoice,
    )

    case onAppear
    case onDisappear

    case contentTabMoveSucceeded(request: ContentTabMoveRequest)
    case contentTabMoveRejected(
        request: ContentTabMoveRequest,
        category: ContentTabMoveFailurePresentation.Category,
    )

    @CasePathable
    public enum View: Sendable {
        case activateContentTabSwitcherCandidate(ContentTabID)
        case dismissContentTabMoveFailure(requestID: UUID)
        case dismissContentTabSwitcher
    }

    @CasePathable
    public enum Internal: Sendable {
        case fixedLocationsLoaded(
            requestID: UUID,
            items: [FileManagerFixedLocationItem],
        )
        case entryActionCompleted(
            tabID: ContentTabID,
            record: EntryActionRecord,
            undoManagerGeneration: UInt64?,
        )
        case homeFavoritesLoaded([FileManagerHomeFavoriteItem])
        case topNavigationIntentCompleted(
            token: FileManagerTopNavigationOperationToken,
            terminal: FileManagerTopNavigationIntentTerminal,
        )
        case pinnedRecordPersistenceCompleted(
            token: FileManagerTopNavigationOperationToken,
            source: FileManagerPinnedRecordPersistenceSource,
            request: ContentTabPinnedRecordPersistenceRequest,
            terminal: FileManagerTopNavigationIntentTerminal,
        )
        case aiChatTabTitleUpdated(sessionID: AiChatSessionID, title: String?)
        case duplicateContentTabReduced(
            sourceID: ContentTabID,
            duplicateID: ContentTabID,
            duplicateIDWasPreexisting: Bool,
        )
        case duplicateSelectedContentTabsReduced(
            requests: [ContentTabDuplicateRequest],
            preexistingTabIDs: Set<ContentTabID>,
        )
        case routeContent(tabID: ContentTabID, action: FileManagerContentAction)
        case sidebarEntryDrop(EntryOperationsAction)
        case undoManagerWindowIDChanged(UUID)
        case undoManagerEventReceived(UndoManagerEvent)
        case undoManagerAvailabilityChanged(UndoManagerAvailability)
        case undoManagerReplayAvailabilityChanged(
            requestID: UUID,
            availability: UndoManagerAvailability,
        )
        case undoManagerInvocationFinished(
            requestID: UUID,
            direction: EntryActionDirection,
            result: UndoManagerInvocationResult,
        )
        case undoManagerOwnerInvalidationFinished(
            requestID: UUID,
            ownerID: UUID,
            result: UndoManagerInvalidationResult,
        )
        case aiChatNewChatInspectorOpenLoaded(
            requestID: UUID,
            setup: AiChatSetupState,
            connectionsFile: AIConnectionsFile,
        )
        case aiChatHistoryInspectorOpenLoaded(
            requestID: UUID,
            setup: AiChatSetupState,
            connectionsFile: AIConnectionsFile,
        )
        case aiChatReopenInspectorOpenLoaded(
            requestID: UUID,
            setup: AiChatSetupState,
            connectionsFile: AIConnectionsFile,
        )
        case aiChatNewChatDefaultsLoaded(
            requestID: UUID,
            candidate: AiChatPersistedSelectionCandidate?,
        )
        case homeAiChatNewChatSeedRequested(sessionID: AiChatSessionID)
        case applyContentNewChatSeed(FileManagerContentNewChatSeedApplication)
        case applyInspectorNewChatSeed(FileManagerInspectorNewChatSeedApplication)
        case defaultStartPageResolved(StartPage)
    }

    @CasePathable
    public enum WindowCommand: Sendable {
        case newFolder
        case openSelectedItem
        case quickLookSelectedItem
        case getInfo
        case saveCollection
        case saveCollectionAs
        case goBack
        case goForward
        case goToEnclosingDirectory
        case toggleSidebar
        case toggleShowHiddenFiles
        case setViewLayout(EntryViewLayoutState.Mode)
        case setGroupKey(GroupKey)
        case setSortKey(SortKey)
        case setSortOrder(VoyagerShared.SortOrder)
        case requestUndo
        case requestRedo
        case find
        case toggleComposer
        case reopenChat
        case newChat
        case showChatHistory
        case cut
        case copy
        case paste
        case duplicate
        case makeAlias
        case selectAll
        case copyAbsolutePaths
        case copyURLs
        case openNewContentTab
        case selectContentTab(position: Int)
        case selectMostRecentlyUsedContentTab
        case activateContentTabSwitcherSelection
        case moveContentTabSwitcherFocus(direction: ContentTabSwitcherFocusDirection)
        case presentContentTabSwitcher(source: FileManagerContentTabSwitcherPresentation.Source)
        case dismissContentTabSwitcher
        case closeActiveContentTab
        case closeSelectedContentTabs
        case toggleActiveContentTabPin
        case restoreLastClosedContentTab
        case duplicateContentTab(ContentTabID)
        case duplicateActiveContentTab
        case duplicateSelectedContentTabs
        case contentTabAction(ContentTabProductActionRequest, source: ContentTabActionSource)
    }

    @CasePathable
    public enum Delegate: Sendable {
        case persistTopNavigationMove(
            token: FileManagerTopNavigationOperationToken,
            source: FileManagerTopNavigationItemID,
            destination: FileManagerTopNavigationMoveDestination,
            discoveredLocationIDs: [String],
        )
        case persistTopNavigationPinnedGroupMove(
            token: FileManagerTopNavigationOperationToken,
            orderedIDs: [ContentTabID],
            destination: FileManagerTopNavigationMoveDestination,
            discoveredLocationIDs: [String],
        )
        case persistPinnedRecordMutation(
            token: FileManagerTopNavigationOperationToken,
            source: FileManagerPinnedRecordPersistenceSource,
            request: ContentTabPinnedRecordPersistenceRequest,
            discoveredLocationIDs: [String],
        )
        case closeWindow
        case openPathInNewWindow(String)
        case openAISettings
        case requestAttachmentPicker(AiChatSessionID)
        case fixedLocationVisibilityChanged(Set<FileManagerFixedLocationItem.ID>)
        case requestContentTabMove(ContentTabMoveRequest)
        case receiveContentTabDrag(ContentTabDragPayload)
        /// 외부 창 explicit domain 경계 drop 의도를 window manager로 전달한다.
        case receiveContentTabExplicitDomainDrag(
            payload: ContentTabDragPayload,
            targetDomain: ContentTabDomain,
            placement: ContentTabPlacement,
        )
        case pinnedContentTabRuntimeNavigationChanged(
            tabID: ContentTabID,
            navigationState: ContentPageNavigationRoute,
        )
        /// pinned tab의 durable route 복귀가 실제 navigation commit 없이 실패했음을 window manager에 알린다.
        case pinnedContentTabRuntimeNavigationFailed(tabID: ContentTabID)
    }
}

public enum ContentTabProductActionRequest: Equatable, Sendable {
    case closeActive
    case closeSelected
    case restoreLastClosed
    case duplicate(ContentTabID)
    case duplicateActive
    case duplicateSelected
}

public extension FileManagerWindowAction.WindowCommand {
    static var moveNextContentTabSwitcher: Self {
        .moveContentTabSwitcherFocus(direction: .next)
    }

    static var movePreviousContentTabSwitcher: Self {
        .moveContentTabSwitcherFocus(direction: .previous)
    }
}

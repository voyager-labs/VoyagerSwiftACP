import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
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

    public init(
        operationID: UUID,
        target: SelectedContentTabPinMutationTargetState,
        totalCount: Int,
        successCount: Int,
        failureCount: Int,
        remainingCount: Int,
    ) {
        self.operationID = operationID
        self.target = target
        self.totalCount = totalCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.remainingCount = remainingCount
    }
}

public enum SelectedContentTabCloseOutcome: Equatable, Sendable {
    case removed
    case unpinned
    case cancelled
    case failed
    case missing
}

public enum FileManagerPinnedRecordPersistenceRoute: Equatable, Sendable {
    case single
    case selectedPin(operationID: UUID)
    case selectedClose(operationID: UUID)
}

public struct FileManagerPinnedRecordPersistenceRequest: Equatable, Sendable {
    public let request: ContentTabPinnedRecordPersistenceRequest
    public let route: FileManagerPinnedRecordPersistenceRoute

    public init(
        request: ContentTabPinnedRecordPersistenceRequest,
        route: FileManagerPinnedRecordPersistenceRoute,
    ) {
        self.request = request
        self.route = route
    }
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

@CasePathable
public enum FileManagerWindowAction: CasePathable, Sendable {
    case delegate(Delegate)

    case `internal`(Internal)
    case request(WindowCommand)
    case content(FileManagerContentFeature.Action)
    case tabContent(tabID: ContentTabID, action: FileManagerContentFeature.Action)
    case backgroundAiChat(AiChatAction)
    case backgroundAiChatSnapshotPersisted(AiChatSessionSnapshot)
    case backgroundInspectorAiChat(AiChatAction)
    case backgroundInspectorAiChatSnapshotPersisted(AiChatSessionSnapshot)
    case sidebar(FileManagerSidebarFeature.Action)
    case inspector(FileManagerInspectorFeature.Action)
    case navigation(ContentPageNavigationFeature.Action)
    case contentTabs(ContentTabAction)
    case applyAppPreferences(AppPreferencesState)
    case applyPinnedContentTabs(ContentTabState)
    case applyAuthoritativePinnedContentTabs(ContentTabState)
    case applyPinnedContentTabRuntimeNavigation(
        tabID: ContentTabID,
        navigationState: ContentPageNavigationRoute,
    )
    case applyHiddenFixedLocationIDs(Set<FileManagerFixedLocationItem.ID>)
    case aiConnectionsFileUpdated(AIConnectionsFile)
    case reserveExternalContentTabs([ExternalContentTabReservation])
    case activateExternalContentTabUndoScopes([ContentTabID])
    case resyncActiveCollectionNavigation

    case requestSelectedContentTabPinMutation(target: SelectedContentTabPinMutationTargetState)
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
    case contentTabCloseAlertResponse(CollectionNavigationChoice)
    case selectedContentTabCloseAlertResponse(
        operationID: UUID,
        tabID: ContentTabID,
        choice: CollectionNavigationChoice,
    )

    case onAppear
    case onDisappear

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
        case aiChatNewChatDefaultsLoaded(
            requestID: UUID,
            candidate: AiChatPersistedSelectionCandidate?,
        )
        case homeAiChatNewChatSeedRequested(sessionID: AiChatSessionID)
        case applyContentNewChatSeed(FileManagerContentNewChatSeedApplication)
        case applyInspectorNewChatSeed(FileManagerInspectorNewChatSeedApplication)
    }

    @CasePathable
    public enum WindowCommand: Sendable {
        case newFolder
        case openSelectedItem
        case quickLookSelectedItem
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
        case toggleComposer
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
        case closeActiveContentTab
        case closeSelectedContentTabs
        case toggleActiveContentTabPin
        case restoreLastClosedContentTab
        case duplicateContentTab(ContentTabID)
        case duplicateActiveContentTab
        case duplicateSelectedContentTabs
    }

    @CasePathable
    public enum Delegate: Sendable {
        case closeWindow
        case openPathInNewWindow(String)
        case openAISettings
        case requestAttachmentPicker
        case fixedLocationVisibilityChanged(Set<FileManagerFixedLocationItem.ID>)
        case pinnedContentTabRuntimeNavigationChanged(
            tabID: ContentTabID,
            navigationState: ContentPageNavigationRoute,
        )
        case pinnedRecordPersistenceRequested(FileManagerPinnedRecordPersistenceRequest)
    }
}

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

@CasePathable
public enum FileManagerWindowAction: CasePathable, Sendable {
    case delegate(Delegate)

    case `internal`(Internal)
    case request(WindowCommand)
    case content(FileManagerContentFeature.Action)
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
    case applyHiddenFixedLocationIDs(Set<FileManagerFixedLocationItem.ID>)
    case aiConnectionsFileUpdated(AIConnectionsFile)
    case reserveExternalContentTabs([ExternalContentTabReservation])
    case resyncActiveCollectionNavigation

    case closeContentTabRequested(ContentTabID)
    case contentTabCloseAlertResponse(CollectionNavigationChoice)

    case onAppear
    case onDisappear

    @CasePathable
    public enum Internal: Sendable {
        case fixedLocationsLoaded(
            requestID: UUID,
            items: [FileManagerFixedLocationItem],
        )
        case homeFavoritesLoaded([FileManagerHomeFavoriteItem])
        case aiChatTabTitleUpdated(sessionID: AiChatSessionID, title: String?)
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
        case openContextualAiChat
        case presentContextualAiChat
        case cut
        case copy
        case paste
        case duplicate
        case makeAlias
        case selectAll
        case copyAbsolutePaths
        case copyURLs
        case openNewContentTab
        case closeActiveContentTab
        case toggleActiveContentTabPin
        case restoreLastClosedContentTab
        case duplicateContentTab(ContentTabID)
        case duplicateActiveContentTab
    }

    @CasePathable
    public enum Delegate: Sendable {
        case closeWindow
        case openPathInNewWindow(String)
        case openAISettings
        case requestAttachmentPicker
        case fixedLocationVisibilityChanged(Set<FileManagerFixedLocationItem.ID>)
    }
}

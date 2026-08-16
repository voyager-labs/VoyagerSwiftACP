import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@CasePathable
public enum FileManagerContentAction: ViewAction, CasePathable, Sendable {
    case view(View)
    case `internal`(Internal)
    case delegate(Delegate)

    case entryViewLayout(EntryViewLayoutFeature.Action)
    case composer(ComposerFeature.Action)
    case collection(CollectionFeature.Action)
    case aiChat(AiChatFeature.Action)
    case externalFileSystemChanged(
        [FileChangeGatewayEvent],
        deliveryChainToken: String? = nil,
    )

    @CasePathable
    public enum View: Sendable {
        case handleKeyCommand(KeyCommand)
        case changeLayout(EntryViewLayoutState.Mode)
        case selectAllEntries
        case newChatTapped
        case aiChatNewChatTapped
        case showChatHistoryTapped
        case refreshStaleCollection
        case toggleShowHiddenFilesAndReload
        case discardCollectionChanges
        case homeSelectionTapped(FileManagerHomeSelection)
        case homeAppeared
    }

    @CasePathable
    public enum Internal: Sendable {
        case applyNavigationState(ContentPageNavigationRoute)
        case performPendingNavigation(ContentPageNavigationPending)
        case requestNavigation(ContentPageNavigationAction)
        case saveScrollOffset(CGPoint, forPath: String)
        case startObservingSystemNotifications
        case stopObservingSystemNotifications
        case systemAppDidBecomeActive
        case clearCollectionMode
        case exitCollectionMode
        case resetComposer
        case resetComposerAfterDirectoryNavigation
        case setAutomaticRefreshFeedbackSuppressed(Bool)
        case reloadDirectoryListing
        case homeDirectoryPickerFinished(FileManagerHomePickerResult<String>)
        case homeCollectionPickerFinished(FileManagerHomePickerResult<URL>)
        case homeAiChatSessionCreated(FileManagerHomePickerResult<String>)
        case homeDirectoryItemCountsLoaded([FileManagerHomeDirectory: Int])
        case homeChatHistoryLoaded([FileManagerHomeChatHistoryItem])
        case homeChatHistoryLoadFailed
    }

    @CasePathable
    public enum Delegate: Sendable {
        case collectionChangesDiscarded
        case composerCollectionSearchSucceeded
        case composerCollectionSearchFailed
        case openPathInNewWindow(String)
        case openInNewTab([String])
        case closeWindow
        case newChatRequested
        case durableNewChatRequested
        case showChatHistoryRequested
        case openAISettings
        case requestDuplicate
        case requestUndoRedo(EntryActionDirection)
        case currentContextChanged(AiChatCurrentContextSnapshot)
        case homePageAnchorSelected(ContentTabPageAnchor)
        case homeChatHistorySessionSelected(AiChatSessionID)
        case aiChatSessionCreated(AiChatSessionID)
        case aiChatSessionRestored(sessionID: AiChatSessionID, title: String)
    }
}

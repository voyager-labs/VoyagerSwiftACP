import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
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
    case externalFileSystemChanged([String])

    @CasePathable
    public enum View: Sendable {
        case handleKeyCommand(KeyCommand)
        case changeLayout(EntryViewLayoutState.Mode)
        case selectAllEntries
        case openContextualAiChatTapped
        case refreshStaleCollection
        case toggleShowHiddenFilesAndReload
        case discardCollectionChanges
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
    }

    @CasePathable
    public enum Delegate: Sendable {
        case collectionChangesDiscarded
        case composerCollectionSearchSucceeded
        case composerCollectionSearchFailed
        case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
        case dropItemsToTag(providers: [NSItemProvider], tagName: String)
        case openPathInNewWindow(String)
        case openPathInNewTab(String)
        case closeWindow
        case openContextualAiChat
        case currentContextChanged(AiChatCurrentContextSnapshot)
    }
}

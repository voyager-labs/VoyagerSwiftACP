import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
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
    enum View: Sendable {
        case handleKeyCommand(KeyCommand)
        case changeLayout(EntryViewLayoutState.Mode)
        case selectAllEntries
        case refreshStaleCollection
        case toggleShowHiddenFilesAndReload
        case discardCollectionChanges
    }

    @CasePathable
    enum Internal: Sendable {
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
    }

    @CasePathable
    enum Delegate: Sendable {
        case collectionChangesDiscarded
        case composerCollectionSearchSucceeded
        case composerCollectionSearchFailed
        case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
        case dropItemsToTag(providers: [NSItemProvider], tagName: String)
        case openPathInNewWindow(String)
        case openPathInNewTab(String)
        case closeWindow
    }
}

import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

@CasePathable
enum FileManagerContentAction: ViewAction, CasePathable, Sendable {
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
        case syncComposerCollectionState
    }

    @CasePathable
    enum Delegate: Sendable {
        case discardCollectionChanges
        case composerCollectionSearchSucceeded
        case composerCollectionSearchFailed
        case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
        case dropItemsToTag(providers: [NSItemProvider], tagName: String)
        case openPathInNewWindow(String)
        case openPathInNewTab(String)
        case closeWindow
    }
}

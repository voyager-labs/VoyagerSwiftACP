import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

import VoyagerEntitiesEntry
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
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
        case refreshStaleCollection
        case toggleShowHiddenFilesAndReload
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
        case syncComposerCollectionState
    }

    @CasePathable
    public enum Delegate: @unchecked Sendable {
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

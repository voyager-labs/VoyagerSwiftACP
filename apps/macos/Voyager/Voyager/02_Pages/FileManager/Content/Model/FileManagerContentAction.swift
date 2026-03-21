import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

@CasePathable
enum FileManagerContentAction: ViewAction, CasePathable, Sendable {
    case view(View)
    case `internal`(Internal)
    case delegate(Delegate)
    case entryArrangements(EntryArrangementsAction)
    case entryViewLayout(EntryViewLayoutAction)
    case entryOperations(EntryOperationsFeature.Action)
    case composer(ComposerFeature.Action)

    @CasePathable
    enum View: Sendable {
        case handleKeyCommand(KeyCommand)
        case changeLayout(EntryViewLayoutState.Mode)
        case selectAllEntries
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

import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

@CasePathable
enum FileManagerContentAction: CasePathable, Sendable {
    case entryArrangements(EntryArrangementsAction)
    case entries(EntryCommandAction)
    case entryViewLayout(EntryViewLayoutAction)
    case entryOperations(EntryOperationsFeature.Action)
    case composer(ComposerFeature.Action)

    case delegate(FileManagerContentDelegateAction)
    case collectionDraft(FileManagerContentCollectionDraftAction)

    case handleKeyCommand(KeyCommand)

    case changeLayout(EntryViewLayoutState.Mode)
    case applyNavigationState(ContentPageNavigationRoute)
    case performPendingNavigation(ContentPageNavigationPending)
    case requestNavigation(ContentPageNavigationAction)
    case selectAllEntries
    case toggleShowHiddenFilesAndReload

    case saveScrollOffset(CGPoint, forPath: String)

    case discardCollectionChanges
    case composerCollectionSearchSucceeded
    case composerCollectionSearchFailed

    // NOTE: 이거 두 개는 ContentPane에 있어야 하는건가?
    case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
    case dropItemsToTag(providers: [NSItemProvider], tagName: String)

    case openPathInNewWindow(String)
    case openPathInNewTab(String)
    case closeWindow

    // System lifecycle
    case startObservingSystemNotifications
    case stopObservingSystemNotifications
    case systemAppDidBecomeActive
}

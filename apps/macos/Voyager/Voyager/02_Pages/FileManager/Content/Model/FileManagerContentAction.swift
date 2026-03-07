import AppKit
import Foundation
import SwiftUI

import ComposableArchitecture

@CasePathable
enum FileManagerContentAction: CasePathable, Sendable {
    case entryArrangements(EntryArrangementsAction)
    case entries(EntryCommandAction)
    case entryViewLayout(EntryViewLayoutAction)
    case entryOperations(EntryOperationsFeature.Action)
    case composer(ComposerFeature.Action)

    case handleKeyCommand(KeyCommand)

    case changeLayout(ContentViewLayout)

    case saveScrollOffset(CGPoint, forPath: String)

    // NOTE: 이거 두 개는 ContentPane에 있어야 하는건가?
    case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
    case dropItemsToTag(providers: [NSItemProvider], tagName: String)

    case performPendingNavigation(ContentPageNavigationPending)
    case requestNavigation(ContentPageNavigationAction)
    case discardCollectionChanges
    case composerCollectionSearchSucceeded
    case composerCollectionSearchFailed

    case openPathInNewWindow(String)
    case openPathInNewTab(String)

    case closeWindow
}

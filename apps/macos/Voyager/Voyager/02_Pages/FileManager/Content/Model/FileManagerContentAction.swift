import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

@CasePathable
enum FileManagerContentAction: CasePathable, Sendable {
    case entryArrangements(EntryArrangementsAction)
    case entries(EntryFeature.Action)
    case entryOperations(EntryOperationsFeature.Action)
    case composer(ComposerFeature.Action)

    case handleKeyCommand(KeyCommand)

    case changeLayout(ContentViewLayout)

    case saveScrollOffset(CGPoint, forPath: String)

    // NOTE: 이거 두 개는 ContentPane에 있어야 하는건가?
    case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
    case dropItemsToTag(providers: [NSItemProvider], tagName: String)

    case performPendingNavigation(ContentPendingNavigation)
    // TODO(Collection): Collection으로 이동
    case discardCollectionChanges

    case openPathInNewWindow(String)

    // TODO(EntryOperations): EntryOperations로 이동
    case emptyTrashCompleted

    // TODO(Window): Window로 이동
    case closeWindow
}

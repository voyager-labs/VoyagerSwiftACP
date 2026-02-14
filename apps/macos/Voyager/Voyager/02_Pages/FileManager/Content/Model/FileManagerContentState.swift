import ComposableArchitecture
import Foundation
import SwiftUI

@ObservableState
struct FileManagerContentState: Equatable {
    struct EntryThumbnailState: Equatable {
        var thumbnailsReady: Set<String> = []
        var thumbnailRequestsInFlight: Set<String> = []
        var thumbnailRequestsFailed: Set<String> = []
    }

    var navigation: FileManagerContentNavigationFeature.State = .init()
    var entries: EntryFeature.State = .init()
    var entryArrangements: EntryArrangementsState = .init()
    var entryOperations: EntryOperationsFeature.State = .init()
    var entryThumbnails: EntryThumbnailState = .init()
    var composer: ComposerFeature.State = .init()

    var viewLayout: ContentViewLayout = .list
    var listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize
    var gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize
    var listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize
    var gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize

    // 컴포저 관련 //
    var pendingSearchQuery: String?
    var collectionContext: CollectionContext?

    var resetComposerOnNextDirectoryNavigation: Bool = false

    // 콜렉션 관련 //
    var collectionSession: CollectionDocumentSessionState = .init()

    mutating func resetComposer() {
        composer = .init()
        syncComposerCollectionState()
    }

    mutating func syncComposerCollectionState() {
        composer.collectionContext = collectionContext
        composer.openedCollectionURL = collectionSession.openedURL
    }

    var canSaveCollection: Bool {
        guard entries.isCollectionMode, collectionContext != nil else { return false }
        if collectionSession.baseline == nil {
            return true
        }
        return isOpenedCollectionDirty
    }

    var isOpenedCollectionDirty: Bool {
        guard let baseline = collectionSession.baseline, let context = collectionContext else { return false }
        if baseline.context != context { return true }
        return false
    }

    // 엔트리 관련 //
    var canOpenSelectedItem: Bool {
        hasSelectableEntries
    }

    var canQuickLookSelectedItem: Bool {
        hasSelectableEntries
    }

    var hasSelectedItems: Bool {
        !entries.selectedIds.isEmpty
    }

    var hasClipboardItems: Bool {
        !entryOperations.clipboardItems.isEmpty
    }

    private var hasSelectableEntries: Bool {
        guard !entries.selectedIds.isEmpty else { return false }
        return entries.displayItems.contains { entries.selectedIds.contains($0.id) }
    }
}

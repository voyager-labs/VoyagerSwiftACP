import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerShared

@ObservableState
struct FileManagerContentState: Equatable {
    struct EntryThumbnailState: Equatable {
        var thumbnailRequestsInFlight: Set<String> = []
        var thumbnailRenderVersion: Int = 0
        var thumbnailsReady: Set<String> = []
        var thumbnailRequestsFailed: Set<String> = []
    }

    var navigation: ContentPageNavigationFeature.State = .init()
    var entryViewLayout: EntryViewLayoutState = .init()
    var entryThumbnails: EntryThumbnailState = .init()
    var composer: ComposerFeature.State = .init()

    var viewLayout: ContentViewLayout = .list
    var listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize
    var gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize
    var listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize
    var gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize

    // 컴포저 관련 //
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
        composer.isCollectionMode = entryViewLayout.entryOperations.loadingContext.isCollectionMode
    }

    var canSaveCollection: Bool {
        guard entryViewLayout.entryOperations.loadingContext.isCollectionMode,
              collectionContext != nil else { return false }
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
        !entryViewLayout.selectedIds.isEmpty
    }

    var hasClipboardItems: Bool {
        !entryViewLayout.entryOperations.clipboardItems.isEmpty
    }

    private var hasSelectableEntries: Bool {
        guard !entryViewLayout.selectedIds.isEmpty else { return false }
        return entryViewLayout.entryOperations.displayItems.contains { entryViewLayout.selectedIds.contains($0.id) }
    }
}

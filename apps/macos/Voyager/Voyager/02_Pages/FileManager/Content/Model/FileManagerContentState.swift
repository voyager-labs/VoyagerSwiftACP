import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerShared

@ObservableState
struct FileManagerContentState: Equatable {
    var navigation: ContentPageNavigationFeature.State = .init()
    var entryViewLayout: EntryViewLayoutFeature.State = .init()
    var entryArrangements: EntryArrangementsFeature.State = .init()
    var entryOperations: EntryOperationsFeature.State = .init()
    var composer: ComposerFeature.State = .init()

    var listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize
    var gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize
    var listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize
    var gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize

    // 컴포저 관련
    var collectionContext: CollectionContext?

    var resetComposerOnNextDirectoryNavigation: Bool = false

    // 콜렉션 관련
    var collectionSession: CollectionDocumentSessionState = .init()

    mutating func resetComposer() {
        composer = .init()
        syncComposerCollectionState()
    }

    mutating func syncComposerCollectionState() {
        composer.collectionContext = collectionContext
        composer.openedCollectionURL = collectionSession.openedURL
        composer.isCollectionMode = entryOperations.loadingContext.isCollectionMode
    }

    var canSaveCollection: Bool {
        guard entryOperations.loadingContext.isCollectionMode, collectionContext != nil else { return false }
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

    var selectedEntries: [EntryModel] {
        let selectedIds = entryViewLayout.selectedIds
        return selectedIds.compactMap { id in
            entryOperations.displayItems[id: id]
        }
    }

    mutating func restoreCollectionDraftFromBaseline() {
        if let baseline = collectionSession.baseline {
            collectionContext = baseline.context
            syncComposerCollectionState()
        }
    }
}

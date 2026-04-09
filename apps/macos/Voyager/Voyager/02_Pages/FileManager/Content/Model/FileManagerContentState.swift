import ComposableArchitecture
import Foundation
import VoyagerShared

import VoyagerFeaturesEntryOperations

@ObservableState
struct FileManagerContentState: Equatable {
    var navigation: ContentPageNavigationFeature.State = .init()
    var entryViewLayout: EntryViewLayoutFeature.State = .init()
    var composer: ComposerFeature.State = .init()

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
        composer.isCollectionMode = entryViewLayout.entryOperations.isCollectionMode
    }

    var canSaveCollection: Bool {
        guard entryViewLayout.entryOperations.isCollectionMode, collectionContext != nil else {
            return false
        }
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
}

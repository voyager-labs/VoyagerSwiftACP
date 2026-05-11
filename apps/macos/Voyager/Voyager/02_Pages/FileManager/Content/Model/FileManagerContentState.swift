import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

@ObservableState
struct FileManagerContentState: Equatable {
    var navigation: ContentPageNavigationFeature.State = .init()
    var entryViewLayout: EntryViewLayoutFeature.State = .init()
    var composer: ComposerFeature.State = .init()
    var collection: CollectionFeature.State = .init()

    // Suppresses Swift 6 InferIsolatedConformances @MainActor-isolated Equatable synthesis.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.navigation == rhs.navigation
                && lhs.entryViewLayout == rhs.entryViewLayout
                && lhs.composer == rhs.composer
                && lhs.collection == rhs.collection
                && lhs.resetComposerOnNextDirectoryNavigation == rhs.resetComposerOnNextDirectoryNavigation
        }
    }

    // 컴포저 관련
    var collectionContext: CollectionContext? {
        get { collection.collectionContext }
        set { collection.collectionContext = newValue }
    }

    var resetComposerOnNextDirectoryNavigation: Bool = false

    // 콜렉션 관련
    var collectionSession: CollectionDocumentSessionState {
        get { collection.collectionSession }
        set { collection.collectionSession = newValue }
    }

    var isCollectionMode: Bool {
        entryViewLayout.isCollectionMode
    }

    mutating func resetComposer() {
        composer = .init()
        syncComposerCollectionState()
    }

    mutating func syncComposerCollectionState() {
        composer.collectionContext = collectionContext
        composer.openedCollectionURL = collectionSession.document?.url
        composer.openedCollectionCompatibility = collectionSession.document?.compatibility
        composer.isCollectionMode = isCollectionMode
    }

    var canSaveCollection: Bool {
        guard isCollectionMode, collectionContext != nil else {
            return false
        }
        if collectionSession.metadata.baseline == nil {
            return true
        }
        return isOpenedCollectionDirty
    }

    var isOpenedCollectionDirty: Bool {
        guard let baseline = collectionSession.metadata.baseline, let context = collectionContext else { return false }
        if baseline.context != context { return true }
        return false
    }

    var isOpenedCollectionStale: Bool {
        isCollectionMode && collectionSession.phase.isStale
    }

    var refreshBlockingReason: CollectionSessionRefreshBlockingReason? {
        collection.refreshBlockingReason(
            isCollectionMode: isCollectionMode,
            isDirty: isOpenedCollectionDirty,
            isSearching: composer.isCollectionSearching,
        )
    }
}

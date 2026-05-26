import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

@ObservableState
public struct FileManagerContentState: Equatable, @unchecked Sendable {
    var navigation: ContentPageNavigationFeature.State = .init()
    var entryViewLayout: EntryViewLayoutFeature.State = .init()
    var composer: ComposerFeature.State = .init()
    var collection: CollectionFeature.State = .init()

    // @ObservableState 하위 상태는 MainActor 격리로 비교해야 하므로 Equatable 비교를 MainActor에서 수행한다.
    public nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.navigation == rhs.navigation
                && lhs.entryViewLayout == rhs.entryViewLayout
                && lhs.composer == rhs.composer
                && lhs.collection == rhs.collection
                && lhs.resetComposerOnNextDirectoryNavigation == rhs.resetComposerOnNextDirectoryNavigation
        }
    }

    // 컴포저 관련
    var resetComposerOnNextDirectoryNavigation: Bool = false

    var isCollectionMode: Bool {
        entryViewLayout.isCollectionMode
    }

    mutating func syncComposerCollectionState() {
        composer.collectionContext = collection.collectionContext
        composer.openedCollectionURL = collection.collectionSession.document?.url
        composer.openedCollectionCompatibility = collection.collectionSession.document?.compatibility
        composer.isCollectionMode = isCollectionMode
    }

    mutating func resetComposer() {
        composer = .init()
        syncComposerCollectionState()
    }

    var canSaveCollection: Bool {
        collection.canSave(isCollectionMode: isCollectionMode)
    }

    var isOpenedCollectionDirty: Bool {
        collection.isDirty
    }
}

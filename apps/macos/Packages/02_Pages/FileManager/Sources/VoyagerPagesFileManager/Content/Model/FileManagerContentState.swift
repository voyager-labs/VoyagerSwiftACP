import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

@ObservableState
public struct FileManagerContentState: Equatable {
    public var navigation: ContentPageNavigationFeature.State = .init()
    public var entryViewLayout: EntryViewLayoutFeature.State = .init()
    public var composer: ComposerFeature.State = .init()
    public var collection: CollectionFeature.State = .init()

    /// 컴포저 관련
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

    public var canSaveCollection: Bool {
        collection.canSave(isCollectionMode: isCollectionMode)
    }

    var isOpenedCollectionDirty: Bool {
        collection.isDirty
    }
}

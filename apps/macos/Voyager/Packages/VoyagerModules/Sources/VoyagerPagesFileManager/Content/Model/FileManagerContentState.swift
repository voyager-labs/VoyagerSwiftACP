import ComposableArchitecture
import Foundation
import VoyagerShared

import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

@ObservableState
public struct FileManagerContentState: Equatable {
    public var navigation: ContentPageNavigationFeature.State = .init()
    public var entryViewLayout: EntryViewLayoutFeature.State = .init()
    public var composer: ComposerFeature.State = .init()

    // 컴포저 관련
    public var collectionContext: CollectionContext?

    public var resetComposerOnNextDirectoryNavigation: Bool = false

    // 콜렉션 관련
    public var collectionSession: CollectionDocumentSessionState = .init()

    public var isCollectionMode: Bool {
        entryViewLayout.isCollectionMode
    }

    public mutating func resetComposer() {
        composer = .init()
        syncComposerCollectionState()
    }

    public mutating func syncComposerCollectionState() {
        composer.collectionContext = collectionContext
        composer.openedCollectionURL = collectionSession.openedURL
        composer.isCollectionMode = isCollectionMode
    }

    public var canSaveCollection: Bool {
        guard isCollectionMode, collectionContext != nil else {
            return false
        }
        if collectionSession.baseline == nil {
            return true
        }
        return isOpenedCollectionDirty
    }

    public var isOpenedCollectionDirty: Bool {
        guard let baseline = collectionSession.baseline, let context = collectionContext else { return false }
        if baseline.context != context { return true }
        return false
    }
}

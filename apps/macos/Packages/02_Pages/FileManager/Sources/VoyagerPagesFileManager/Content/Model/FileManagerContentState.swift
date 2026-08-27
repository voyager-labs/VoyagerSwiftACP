import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@ObservableState
public struct FileManagerContentState: Equatable {
    public var navigation: ContentPageNavigationFeature.State = .init()
    public var entryViewLayout: EntryViewLayoutFeature.State = .init()
    public var composer: ComposerFeature.State = .init()
    public var collection: CollectionFeature.State = .init()
    public var aiChat: AiChatFeature.State = .init()
    /// 외부에서 오픈 요청된 파일의 선택 focus ID (itemsLoaded 후 소비됨)
    public var pendingSelectEntryID: String?

    var productBrowsingOperationID: UUID?
    var productBrowsingIdentity: ContentPageNavigationInteractionIdentity?
    var productBrowsingSource: ContentBrowsingSource?
    var productBrowsingContent: ContentBrowsingKind?
    var pendingProductBrowsingSource: ContentBrowsingSource?
    var recordedEntryCommandIDs: Set<UUID> = []

    var homeFavoriteItems: [FileManagerHomeFavoriteItem] = []
    var homeLocationItems: [FileManagerFixedLocationItem] = []
    var homeDirectoryItemCounts: [FileManagerHomeDirectory: Int] = [:]
    var homeChatHistoryItems: [FileManagerHomeChatHistoryItem] = []
    var homeChatHistoryLoadFailed: Bool = false

    /// 컴포저 관련
    var resetComposerOnNextDirectoryNavigation: Bool = false
    var suppressAutomaticRefreshFeedback: Bool = false

    var isCollectionMode: Bool {
        entryViewLayout.isCollectionMode
    }

    var isOrdinaryDirectoryLoading: Bool {
        !composer.isCollectionSearching
            && !entryViewLayout.isCollectionContentLoading
            && entryViewLayout.entryOperations.isLoading
            && !isCollectionMode
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

    mutating func resetComposerAndClearCollectionMode() {
        entryViewLayout.clearCollectionPresentation()
        collection.resetSession()
        navigation.pendingNavigation = nil
        resetComposer()
    }

    var openedCollectionURL: URL? {
        if let url = collection.collectionSession.document?.url {
            return url
        }
        if case let .collection(navigation) = navigation.navigationState,
           case let .file(url, _) = navigation.kind
        {
            return url
        }
        return nil
    }

    var openedCollectionURLExists: Bool {
        openedCollectionURL != nil
    }

    var hasUnsavedCollectionChanges: Bool {
        collection.canSave(isCollectionMode: isCollectionMode)
    }

    public var canSaveCollection: Bool {
        !entryViewLayout.isCollectionContentLoading
            && hasUnsavedCollectionChanges
    }

    var isOpenedCollectionDirty: Bool {
        collection.isDirty
    }
}

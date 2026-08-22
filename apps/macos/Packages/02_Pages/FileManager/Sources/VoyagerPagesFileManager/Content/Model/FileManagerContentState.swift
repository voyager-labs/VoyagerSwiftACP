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

    /// 성공한 rename/move 명령의 consume-once 경로 전이.
    /// 동일 identity 변경을 알리는 외부 파일시스템 이벤트가 명령 완료 시 예약된 refresh를
    /// 중복 예약하는지 판정하는 데만 쓰인다. 벽시계 만료는 없으며 소비·대체·불일치로만 사라진다.
    var pendingIdentityTransition: EntryIdentityTransition?

    /// 하나의 성공한 명령이 만드는 단발성 경로 전이 (package-local).
    struct EntryIdentityTransition: Equatable {
        /// 전이의 원인이 된 EntryActionRecord 식별자
        let recordID: UUID
        /// 표준화된 이전 경로
        let beforePath: String
        /// 표준화된 이후 경로
        let afterPath: String
        /// 생성 시점의 표준화된 현재 폴더 경로
        let rootPath: String
        /// 생성 시점의 로딩 세대 (세대 불일치 시 만료)
        let refreshGeneration: Int
        /// 비종료 대체 projection이 reconcile로 before-path 선택을 지우기 직전에
        /// 한 action cycle 동안만 설정되는 transient 표시. 다음 reconcile에서
        /// before-path를 복원하고 즉시 해제된다(사용자 deselect와 구분).
        var preserveSelectionForReplacementBatch: Bool = false
        /// 보존 복원 시 정확히 재선택할 원본 lexical 선택 ID.
        /// 경로 비교는 canonical 기준으로 하되 재선택 ID는 lexical 표기를 유지한다
        /// (symlink 등 lexical 표기가 canonical과 다른 경로의 선택 손실 방지).
        var preservedLexicalBeforeID: String?
    }

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

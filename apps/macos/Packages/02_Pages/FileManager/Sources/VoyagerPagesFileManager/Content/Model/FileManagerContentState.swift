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
    public var pendingSelectEntryDestinationPath: String?
    /// 네비게이션 기원 pending selection이 바인딩된 목적지 로딩 세대. nil이면 미바인딩(외부 기원 또는 로드 전) 상태다.
    var pendingSelectEntryLoadGeneration: Int?

    /// 성공한 rename/move 명령의 consume-once 경로 전이.
    /// 동일 identity 변경을 알리는 외부 파일시스템 이벤트가 명령 완료 시 예약된 refresh를
    /// 중복 예약하는지 판정하는 데만 쓰인다. 벽시계 만료는 없으며 소비·대체·불일치로만 사라진다.
    var pendingIdentityTransition: EntryIdentityTransition?

    /// An overlapping external delivery that cannot be proven to be the command echo.
    /// Keep its invalidation scope until the identity transition settles instead of dropping
    /// the event; one trailing refresh then converges the page with the filesystem.
    struct PendingExternalRefresh: Equatable {
        let rootPath: String
        var affectedPaths: [String]
        var removedPrefixes: [String]
        var requiresCoarseHierarchyReload: Bool
    }

    var pendingExternalRefresh: PendingExternalRefresh?

    /// 하나의 성공한 명령이 만드는 단발성 경로 전이 (package-local).
    enum EntryIdentityTransitionProjectionOwner: Equatable {
        case root(generation: Int)
        case folder(id: String, generation: Int)
    }

    /// 다중 선택 이동에서 primary 외의 before→after 쌍.
    struct EntryMovePair: Equatable {
        /// canonical화된 이전·이후 경로(선택 매칭의 before 비교에 사용).
        let beforePath: String
        let afterPath: String
        /// symlink 해석 전 lexical 이전 경로. 행 identity 매칭에 사용한다.
        var beforeLexicalPath: String = ""
        /// symlink 해석 전 lexical 이후 경로. 행 identity 매칭에 사용한다.
        var afterLexicalPath: String = ""
        /// 이동 source의 projection 소유자. destination과 같으면 nil.
        var sourceOwner: EntryIdentityTransitionProjectionOwner?
        /// after 행을 투영하는 destination 소유자. primary와 같으면 nil.
        var destinationOwner: EntryIdentityTransitionProjectionOwner?
        /// destination batch에서 선택 이동이 완료됐는지 여부.
        var migrated = false
    }

    struct EntryIdentityTransition: Equatable {
        /// 전이의 원인이 된 EntryActionRecord 식별자
        let recordID: UUID
        /// 표준화된 이전 경로
        let beforePath: String
        /// 표준화된 이후 경로 (상관관계·동등성 판정용)
        let afterPath: String
        /// symlink 해석 전 lexical 이후 경로. 화면 row identity 매칭에 사용하며
        /// 대상 폴더에 target 실체가 함께 있어도 renamed symlink 행을 가리킨다.
        var afterLexicalPath: String = ""
        /// 생성 시점의 표준화된 현재 폴더 경로
        let rootPath: String
        /// 생성 시점의 로딩 세대 (세대 불일치 시 만료)
        let refreshGeneration: Int
        /// after-path를 실제로 투영하는 root 또는 expanded folder 세대
        var projectionOwner: EntryIdentityTransitionProjectionOwner
        /// before-path가 사라지는 원본 projection 소유자(교차 폴더 이동의 소스).
        /// migration 소유자와 동일하면 nil이며, 소스 배치가 먼저 도착할 때
        /// 선택 보존 트리거를 판정하는 데만 쓰인다.
        var preservationOwner: EntryIdentityTransitionProjectionOwner?
        /// 비종료 대체 projection이 reconcile로 before-path 선택을 지우기 직전에
        /// 한 action cycle 동안만 설정되는 transient 표시. 다음 reconcile에서
        /// before-path를 복원하고 즉시 해제된다(사용자 deselect와 구분).
        var preserveSelectionForReplacementBatch: Bool = false
        /// 보존 복원 시 정확히 재선택할 원본 lexical 선택 ID.
        /// 경로 비교는 canonical 기준으로 하되 재선택 ID는 lexical 표기를 유지한다
        /// (symlink 등 lexical 표기가 canonical과 다른 경로의 선택 손실 방지).
        var preservedLexicalBeforeID: String?
        /// canonical 비교가 symlink와 target을 묶지 않도록 보존하는 raw lexical before 경로.
        var beforeLexicalPath: String = ""
        /// primary destination batch에서 primary 선택 이동이 완료됐는지 여부.
        var primaryMigrated = false
        /// 같은 record로 함께 이동한 나머지 선택 항목의 before→after 쌍.
        var additionalMoves: [EntryMovePair] = []

        init(
            recordID: UUID,
            beforePath: String,
            afterPath: String,
            rootPath: String,
            refreshGeneration: Int,
            projectionOwner: EntryIdentityTransitionProjectionOwner? = nil,
            preservationOwner: EntryIdentityTransitionProjectionOwner? = nil,
            afterLexicalPath: String = "",
            beforeLexicalPath: String = "",
            additionalMoves: [EntryMovePair] = [],
        ) {
            self.recordID = recordID
            self.beforePath = beforePath
            self.afterPath = afterPath
            self.rootPath = rootPath
            self.refreshGeneration = refreshGeneration
            self.projectionOwner = projectionOwner ?? .root(generation: refreshGeneration)
            self.preservationOwner = preservationOwner
            self.afterLexicalPath = afterLexicalPath
            self.beforeLexicalPath = beforeLexicalPath
            self.additionalMoves = additionalMoves
        }
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

    mutating func setPendingEntrySelection(entryID: String?, destinationPath: String?, generation: Int? = nil) {
        pendingSelectEntryID = entryID
        pendingSelectEntryDestinationPath = destinationPath
        pendingSelectEntryLoadGeneration = generation
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

    @discardableResult
    mutating func consumeExternalPendingSelectionIfAlreadyLoaded() -> Bool {
        guard pendingSelectEntryID != nil else { return false }
        let entries = isCollectionMode
            ? Array(entryViewLayout.collectionItems)
            : Array(entryViewLayout.entryOperations.items)
        guard !entries.isEmpty else { return false }
        return FileManagerContentEntryOpsCoordinator.applyPendingSelectionForLoadedEntries(
            entries: entries,
            state: &self,
        )
    }
}

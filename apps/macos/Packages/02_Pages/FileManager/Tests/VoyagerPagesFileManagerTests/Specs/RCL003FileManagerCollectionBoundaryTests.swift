@_spi(Internals) import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class RCL003FileManagerCollectionBoundaryTests: XCTestCase {
    // MARK: - RCL-003-indicate_collection_results_staleness

    /// RCL-003-indicate_collection_results_staleness: stale collection은 toolbar staleness affordance로 노출됨
    /// Collection package의 stale phase가 FileManager toolbar view-state로 변환되는지 검증한다.
    /// - 검증 내용: stale indicator, refresh affordance, refresh enabled 상태 확인
    /// - 사전 조건: collection mode이며 opened collection이 stale이고 refresh blocker가 없음
    /// - 기대 결과: stale indicator와 refresh affordance가 표시되고 refresh가 활성화됨
    func testIndicateCollectionResultsStaleness_withStaleOpenedCollection_showsRefreshAffordance() {
        let viewState = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            refreshBlockingReason: nil,
        )

        XCTAssertFalse(viewState.showsUnsavedIndicator)
        XCTAssertTrue(viewState.showsStaleIndicator)
        XCTAssertTrue(viewState.showsRefreshAffordance)
        XCTAssertTrue(viewState.isRefreshEnabled)
        XCTAssertNil(viewState.refreshBlockingReason)
    }

    /// RCL-003-indicate_collection_results_staleness: dirty collection은 unsaved indicator만 노출됨
    /// dirty collection 상태가 stale refresh affordance와 섞이지 않고 저장 필요 상태로만 표시되는지 검증한다.
    /// - 검증 내용: unsaved/stale indicator, refresh affordance, blocking reason 확인
    /// - 사전 조건: collection mode이며 opened collection이 dirty이고 stale은 아님
    /// - 기대 결과: unsaved indicator만 표시되고 refresh는 비활성화됨
    func testIndicateCollectionResultsStaleness_withDirtyCollection_showsUnsavedIndicatorOnly() {
        let viewState = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: false,
            refreshBlockingReason: .notStale,
        )

        XCTAssertTrue(viewState.showsUnsavedIndicator)
        XCTAssertFalse(viewState.showsStaleIndicator)
        XCTAssertFalse(viewState.showsRefreshAffordance)
        XCTAssertFalse(viewState.isRefreshEnabled)
        XCTAssertEqual(viewState.refreshBlockingReason, .notStale)
    }

    /// RCL-003-indicate_collection_results_staleness: dirty stale collection은 두 indicator를 보이되 refresh는 막힘
    /// dirty와 stale 상태가 공존할 때 사용자가 현재 결과는 stale임을 보되 write-back 충돌 refresh는 막히는지 검증한다.
    /// - 검증 내용: unsaved/stale indicator 동시 표시와 dirtyCollection 차단 확인
    /// - 사전 조건: collection mode이며 opened collection이 dirty이면서 stale임
    /// - 기대 결과: 두 indicator가 표시되고 refresh affordance는 비활성화됨
    func testIndicateCollectionResultsStaleness_withDirtyAndStaleCollection_disablesRefresh() {
        let viewState = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
            refreshBlockingReason: .dirtyCollection,
        )

        XCTAssertTrue(viewState.showsUnsavedIndicator)
        XCTAssertTrue(viewState.showsStaleIndicator)
        XCTAssertFalse(viewState.showsRefreshAffordance)
        XCTAssertFalse(viewState.isRefreshEnabled)
        XCTAssertEqual(viewState.refreshBlockingReason, .dirtyCollection)
    }

    /// RCL-003-indicate_collection_results_staleness: refresh 전제 조건이 없으면 stale affordance를 숨김
    /// baseline/document 등 refresh 전제가 빠진 stale collection이 refresh 가능 상태로 보이지 않는지 검증한다.
    /// - 검증 내용: stale indicator는 유지하되 refresh affordance와 enabled 상태 차단 확인
    /// - 사전 조건: opened collection은 stale이나 refreshBlockingReason이 missingBaseline임
    /// - 기대 결과: stale indicator만 표시되고 refresh action은 비활성화됨
    func testIndicateCollectionResultsStaleness_withMissingPrerequisites_disablesRefreshAffordance() {
        let viewState = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            refreshBlockingReason: .missingBaseline,
        )

        XCTAssertTrue(viewState.showsStaleIndicator)
        XCTAssertFalse(viewState.showsRefreshAffordance)
        XCTAssertFalse(viewState.isRefreshEnabled)
        XCTAssertEqual(viewState.refreshBlockingReason, .missingBaseline)
    }

    /// RCL-003-indicate_collection_results_staleness: collection mode가 아니면 indicator를 표시하지 않음
    /// non-collection route의 dirty/stale-like input이 toolbar collection indicator로 새지 않는지 검증한다.
    /// - 검증 내용: 모든 collection indicator와 refresh affordance 비활성화 확인
    /// - 사전 조건: collection mode가 아닌 상태에서 dirty/stale 값이 들어옴
    /// - 기대 결과: collection 전용 indicator가 모두 숨겨짐
    func testIndicateCollectionResultsStaleness_outsideCollectionMode_hidesIndicators() {
        let viewState = ToolbarCollectionStatusViewState(
            isCollectionMode: false,
            openedCollectionURLExists: false,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
            refreshBlockingReason: .notInCollectionMode,
        )

        XCTAssertFalse(viewState.showsUnsavedIndicator)
        XCTAssertFalse(viewState.showsStaleIndicator)
        XCTAssertFalse(viewState.showsRefreshAffordance)
        XCTAssertFalse(viewState.isRefreshEnabled)
        XCTAssertEqual(viewState.refreshBlockingReason, .notInCollectionMode)
    }

    /// RCL-003-indicate_collection_results_staleness: toolbar refresh button은 hover와 refresh affordance를 모두 요구함
    /// stale collection refresh button이 title hover와 refresh 가능 상태 둘 다 만족할 때만 표시되는지 검증한다.
    /// - 검증 내용: hover false/true별 표시 여부와 enabled 상태 확인
    /// - 사전 조건: stale opened collection이고 refreshBlockingReason이 없음
    /// - 기대 결과: hover 중일 때만 refresh button이 보이고 enabled 상태가 유지됨
    func testIndicateCollectionResultsStaleness_refreshButtonRequiresHoverAndAffordance() {
        let status = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            refreshBlockingReason: nil,
        )

        XCTAssertFalse(showsToolbarRefreshButton(status, isTitleAreaHovered: false))
        XCTAssertTrue(showsToolbarRefreshButton(status, isTitleAreaHovered: true))
        XCTAssertTrue(isToolbarRefreshButtonEnabled(status))
    }

    /// RCL-003-indicate_collection_results_staleness: refresh button은 stale collection 밖에서 숨겨짐
    /// non-collection 또는 refresh 차단 상태가 toolbar refresh affordance로 노출되지 않는지 검증한다.
    /// - 검증 내용: collection 외부와 dirty stale 상태의 button 표시/활성화 차단 확인
    /// - 사전 조건: collection mode가 아니거나 dirtyCollection 차단 사유가 있음
    /// - 기대 결과: refresh button은 hover 여부와 무관하게 숨겨지고 비활성화됨
    func testIndicateCollectionResultsStaleness_refreshButtonHiddenWhenNotResolvable() {
        let nonCollectionStatus = ToolbarCollectionStatusViewState(
            isCollectionMode: false,
            openedCollectionURLExists: false,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            refreshBlockingReason: .notInCollectionMode,
        )
        let dirtyStatus = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
            refreshBlockingReason: .dirtyCollection,
        )

        XCTAssertFalse(showsToolbarRefreshButton(nonCollectionStatus, isTitleAreaHovered: false))
        XCTAssertFalse(showsToolbarRefreshButton(nonCollectionStatus, isTitleAreaHovered: true))
        XCTAssertFalse(isToolbarRefreshButtonEnabled(nonCollectionStatus))
        XCTAssertFalse(showsToolbarRefreshButton(dirtyStatus, isTitleAreaHovered: false))
        XCTAssertFalse(showsToolbarRefreshButton(dirtyStatus, isTitleAreaHovered: true))
        XCTAssertFalse(isToolbarRefreshButtonEnabled(dirtyStatus))
    }

    /// Collection 탭 전환 직후에는 파일 로드 완료 전에도 탭 앵커로 Collection 아이콘을 표시한다.
    func testCollectionTitleIcon_collectionAnchorShowsBeforeCollectionLoadCompletes() {
        let collectionAnchor = ContentTabPageAnchor.collectionFile(
            url: URL(fileURLWithPath: "/VoyagerFixtures/Recents.voycoll"),
        )

        XCTAssertTrue(showsCollectionTitleIcon(
            isCollectionMode: false,
            isOpeningCollectionFile: false,
            openedCollectionName: nil,
            activePageAnchor: collectionAnchor,
        ))
    }

    /// 일반 폴더 탭은 Collection 세션 상태가 없을 때 기존 폴더 아이콘을 유지한다.
    func testCollectionTitleIcon_directoryAnchorKeepsFolderIcon() {
        XCTAssertFalse(showsCollectionTitleIcon(
            isCollectionMode: false,
            isOpeningCollectionFile: false,
            openedCollectionName: nil,
            activePageAnchor: .directory(path: "/VoyagerFixtures/Documents"),
        ))
    }

    // MARK: - RCL-003-mark_open_collection_as_stale_on_external_change

    /// RCL-003-mark_open_collection_as_stale_on_external_change: 외부 파일 변경은 collection stale reducer로 라우팅됨
    /// FileManager content sync 계층이 열린 collection scope에 포함된 경로 변경을 Collection reducer로 전달하는지 검증한다.
    /// - 검증 내용: externalFileSystemChanged 수신 후 collection.externalPathsChanged action 전달 확인
    /// - 사전 조건: opened collection이 `/VoyagerFixtures/Documents` scope를 가지고 ready 상태임
    /// - 기대 결과: 관련 파일 변경 path가 collection stale 판단 action으로 전달됨
    func testMarkOpenCollectionAsStaleOnExternalChange_withScopedPath_routesToCollectionExternalPathsChanged() async {
        let changedPath = "/VoyagerFixtures/Documents/report.md"
        let store = TestStore(initialState: makeReadyContentState()) {
            FileManagerContentSyncReducer()
        }

        await store.send(.externalFileSystemChanged([changedPath]))
        await store.receive { action in
            guard case let .collection(.externalPathsChanged(paths)) = action else {
                return false
            }
            return paths == [changedPath]
        }
        await store.finish()
    }

    // MARK: - RCL-003-refresh_stale_collection_results_on_reopen

    /// RCL-003-refresh_stale_collection_results_on_reopen: stale collection refresh request는 검색 경로로 라우팅됨
    /// FileManager의 refresh action이 Collection refresh와 Composer query 실행으로 이어지는지 검증한다.
    /// - 검증 내용: refreshRequested, setText, submit 액션 순서 확인
    /// - 사전 조건: opened collection이 stale이고 baseline/context/document가 모두 있음
    /// - 기대 결과: stale refresh 시작 후 collection query로 Composer 검색 submit이 요청됨
    func testRefreshStaleCollectionResultsOnReopen_withQuery_routesToComposerSubmit() async {
        let store = TestStore(initialState: makeStaleContentState(query: "report")) {
            FileManagerContentComposerReducer()
        }
        // 이 suite는 FileManager 라우팅 계층을 검증하므로 child reducer의 내부 transient action은 제외한다.
        store.exhaustivity = .off

        await store.send(.view(.refreshStaleCollection))
        await store.receive(\.collection.refreshRequested)
        await store.receive(\.composer.view.setText)
        await store.receive(\.composer.view.submit)
        await store.finish()
    }

    // MARK: - RCL-003-update_collection_results_on_filter_change

    /// RCL-003-update_collection_results_on_filter_change: 빈 query refresh는 현재 filter 실행으로 라우팅됨
    /// query가 없는 collection refresh가 Composer applyFilters로 이어지는지 검증한다.
    /// - 검증 내용: refreshRequested 후 applyFilters 액션 수신 확인
    /// - 사전 조건: opened collection이 stale이며 query는 비어 있고 scope/filter context가 있음
    /// - 기대 결과: live query submit 없이 현재 filter 실행이 요청됨
    func testUpdateCollectionResultsOnFilterChange_withEmptyQuery_routesToApplyFilters() async {
        let store = TestStore(initialState: makeStaleContentState(query: "")) {
            FileManagerContentComposerReducer()
        }
        // 이 suite는 FileManager 라우팅 계층을 검증하므로 child reducer의 내부 loading action은 제외한다.
        store.exhaustivity = .off

        await store.send(.view(.refreshStaleCollection))
        await store.receive(\.collection.refreshRequested)
        await store.receive(\.composer.view.applyFilters)
        await store.finish()
    }

    /// Definition-only Collection 재열기 검색은 snapshot refresh로 오인하지 않아야 한다.
    /// - 검증 내용: 일반 filters response 이후 refresh feedback과 write-back 상태가 생성되지 않음
    /// - 사전 조건: canonical built-in과 동일한 definition-only compatibility로 열린 ready Collection
    /// - 기대 결과: 검색 결과는 수락되지만 저장 실패 feedback 없이 ready 상태를 유지함
    func testReopenDefinitionOnlyCollection_withFiltersResponse_doesNotPresentWriteBackFeedback() async {
        let requestID = UUID()
        var state = makeReadyContentState()
        state.collection.collectionSession.document?.compatibility = makeDefinitionOnlyCompatibility()
        state.composer.activeFiltersRequestID = requestID
        state.composer.isLoadingFilters = true
        state.composer.isFilteringInFlight = true
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.registryClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.composer(.filtersResponse(
            requestID,
            .success(SearchResponsePayload(itemCount: 0)),
        )))
        await store.finish()

        XCTAssertNil(store.state.composer.transientFeedback)
        XCTAssertEqual(
            store.state.collection.collectionSession.phase,
            .opened(kind: .definition, base: .ready, inflight: .none),
        )
    }

    /// Definition-only Collection의 명시적 refresh는 snapshot 저장 생략을 실패로 표시하지 않아야 한다.
    /// - 검증 내용: refresh 종료 후 compatibility 차단 feedback이 생성되지 않음
    /// - 사전 조건: write-back 비대상 definition-only Collection이 stale refresh 중임
    /// - 기대 결과: refresh는 정상 종료되고 저장 실패 feedback은 표시되지 않음
    func testRefreshDefinitionOnlyCollection_withSuccessfulResponse_doesNotPresentWriteBackFeedback() async {
        var state = makeReadyContentState()
        state.collection.collectionSession.document?.compatibility = makeDefinitionOnlyCompatibility()
        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .refreshingHydratedSnapshot,
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off

        await store.send(.collection(.refreshResponseReceived(
            SearchResponsePayload(itemCount: 0),
            wasDirtyBeforeApplyingResponse: false,
        )))
        await store.finish()

        XCTAssertNil(store.state.composer.transientFeedback)
        XCTAssertEqual(
            store.state.collection.collectionSession.phase,
            .opened(kind: .definition, base: .stale, inflight: .none),
        )
    }

    // MARK: - RCL-003-retrieve_entries_with_filters

    /// RCL-003-retrieve_entries_with_filters: FileManager content state는 layout collection mode를 collection mode로 노출함
    /// FileManager page state가 EntryViewLayout의 collection mode를 collection 저장 가능성 판단에 연결하는지 검증한다.
    /// - 검증 내용: `entryViewLayout.isCollectionMode`의 기본값과 활성 상태 확인
    /// - 사전 조건: 기본 `FileManagerContentState`
    /// - 기대 결과: 기본값은 false이고 layout state를 true로 설정하면 collection mode로 인식됨
    func testContentStateReflectsEntryViewLayoutCollectionMode() {
        var state = FileManagerContentState()

        XCTAssertFalse(state.entryViewLayout.isCollectionMode)

        state.entryViewLayout.isCollectionMode = true
        XCTAssertTrue(state.entryViewLayout.isCollectionMode)
    }

    /// RCL-003-retrieve_entries_with_filters: 저장 가능 상태는 collection context와 collection mode를 모두 요구함
    /// FileManager page가 collection 저장 자격을 query context와 presentation mode의 조합으로 계산하는지 검증한다.
    /// - 검증 내용: context만 있는 상태와 collection mode 활성 상태의 `canSaveCollection` 비교
    /// - 사전 조건: collection context가 존재하지만 collection mode는 비활성인 content state
    /// - 기대 결과: collection mode가 켜진 뒤에만 저장 가능 상태가 true가 됨
    func testCanSaveCollectionRequiresCollectionContextAndMode() {
        var state = FileManagerContentState()
        state.collection.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])

        XCTAssertFalse(state.canSaveCollection)

        state.entryViewLayout.isCollectionMode = true
        XCTAssertTrue(state.canSaveCollection)
    }

    /// RCL-003-retrieve_entries_with_filters: collection context만으로는 저장 가능 상태가 되지 않음
    /// FileManager page가 collection mode가 아닌 일반 탐색 상태를 collection 저장 대상으로 오판하지 않는지 검증한다.
    /// - 검증 내용: collection context가 있어도 `entryViewLayout.isCollectionMode == false`이면 `canSaveCollection == false`인지 확인
    /// - 사전 조건: collection context만 설정된 content state
    /// - 기대 결과: collection mode가 아니므로 저장 가능 상태가 false로 유지됨
    func testCanSaveCollectionFalseWhenCollectionModeDisabled() {
        var state = FileManagerContentState()
        state.collection.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])

        XCTAssertFalse(state.entryViewLayout.isCollectionMode)
        XCTAssertFalse(state.canSaveCollection)
    }

    private func makeReadyContentState() -> FileManagerContentState {
        let url = URL(fileURLWithPath: "/VoyagerFixtures/Collections/report.voycoll")
        let context = CollectionContext(query: "report", scopes: ["/VoyagerFixtures/Documents"], conditions: [])
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true
        state.collection.collectionContext = context
        state.collection.collectionSession.document = .init(
            url: url,
            name: "report",
            compatibility: makeAllowedCompatibility(),
        )
        state.collection.collectionSession.metadata.baseline = .init(context: context)
        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .ready,
            inflight: .none,
        )
        state.navigation.navigationState = .collection(.init(
            kind: .file(url: url, name: "report"),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
            compatibility: makeAllowedCompatibility(),
        ))
        return state
    }

    private func makeStaleContentState(query: String) -> FileManagerContentState {
        let url = URL(fileURLWithPath: "/VoyagerFixtures/Collections/report.voycoll")
        let context = CollectionContext(query: query, scopes: ["/VoyagerFixtures/Documents"], conditions: [])
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true
        state.collection.collectionContext = context
        state.collection.collectionSession.document = .init(
            url: url,
            name: "report",
            compatibility: makeAllowedCompatibility(),
        )
        state.collection.collectionSession.metadata.baseline = .init(context: context)
        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .none,
        )
        state.navigation.navigationState = .collection(.init(
            kind: .file(url: url, name: "report"),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
            compatibility: makeAllowedCompatibility(),
        ))
        state.composer.isCollectionMode = true
        state.composer.collectionContext = context
        state.composer.openedCollectionURL = url
        state.composer.openedCollectionCompatibility = makeAllowedCompatibility()
        return state
    }

    private func makeAllowedCompatibility() -> CollectionFileCompatibilityMetadata {
        .init(
            sourceSchemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
            migrationPath: [.currentSchemaV2],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: true,
            writeBackReason: .allowed,
        )
    }

    private func makeDefinitionOnlyCompatibility() -> CollectionFileCompatibilityMetadata {
        .init(
            sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
            migrationPath: [.definitionOnlyV1],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: false,
            writeBackReason: .allowed,
        )
    }
}

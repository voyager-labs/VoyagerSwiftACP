@_spi(Internals) import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
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
}

import AppKit
import ComposableArchitecture
import IdentifiedCollections
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EVM002FileManagerPagePresentationTests: XCTestCase {
    // MARK: - EVM-002-set_entries_view_as_list_table

    /// EVM-002-set_entries_view_as_list_table: 리스트 모드로 레이아웃 변경 시 상태 전이 검증
    /// 사용자가 리스트 뷰로 전환하면 entryViewLayout.mode가 .list로 업데이트되고 composer 동기화가 발생한다.
    /// - 검증 내용: view(.changeLayout(.list)) 액션이 mode를 .list로 변경하고 composer.syncCollectionState 이펙트를 트리거하는지 확인
    /// - 사전 조건: 기본 FileManagerContentState (mode 기본값)
    /// - 기대 결과: state.entryViewLayout.mode == .list, composer.syncCollectionState 수신
    func testChangeLayoutToListUpdatesMode() async {
        var state = FileManagerContentState()
        state.entryViewLayout.mode = .grid

        let store = makeFileManagerContentFeatureStore(initialState: state)

        await store.send(.view(.changeLayout(.list)))
        await store.receive(\.entryViewLayout.internal.setMode) {
            $0.entryViewLayout.mode = .list
            $0.entryViewLayout.outlineProjectionRevision += 1
        }

        await store.receive(\.composer.internal.syncCollectionState)
    }

    // MARK: - EVM-002-set_entries_view_as_icon_grid

    /// EVM-002-set_entries_view_as_icon_grid: 그리드 모드로 레이아웃 변경 시 상태 전이 검증
    /// 사용자가 아이콘 그리드 뷰로 전환하면 entryViewLayout.mode가 .grid로 업데이트되고 composer 동기화가 발생한다.
    /// - 검증 내용: view(.changeLayout(.grid)) 액션이 mode를 .grid로 변경하고 composer.syncCollectionState 이펙트를 트리거하는지 확인
    /// - 사전 조건: 기본 FileManagerContentState (mode 기본값)
    /// - 기대 결과: state.entryViewLayout.mode == .grid, composer.syncCollectionState 수신
    func testChangeLayoutToGridUpdatesMode() async {
        let store = makeFileManagerContentFeatureStore()

        await store.send(.view(.changeLayout(.grid)))
        await store.receive(\.entryViewLayout.internal.setMode) {
            $0.entryViewLayout.mode = .grid
            $0.entryViewLayout.outlineProjectionRevision += 1
        }

        await store.receive(\.composer.internal.syncCollectionState)
    }

    /// EVM-002-set_entries_view_as_icon_grid: 레이아웃 변경 시 UserDefaults 영속성 검증
    /// 그리드 모드로 전환 시 선택한 레이아웃 모드가 UserDefaults에 영속화된다.
    /// - 검증 내용: changeLayout(.grid) 후 userDefaultsClient.setString이 올바른 키와 값으로 호출되는지 확인
    /// - 사전 조건: 기본 FileManagerContentState, UserDefaultsStringRecorder 주입
    /// - 기대 결과: recorder에 SettingsKeys.viewLayout == EntryViewLayoutState.Mode.grid.rawValue 기록
    func testChangeLayoutPersistsToSettings() async {
        let recorder = UserDefaultsStringRecorder()
        let store = makeFileManagerContentFeatureStore(setString: recorder.record)

        await store.send(.view(.changeLayout(.grid)))
        await store.receive(\.entryViewLayout.internal.setMode) {
            $0.entryViewLayout.mode = .grid
            $0.entryViewLayout.outlineProjectionRevision += 1
        }

        await store.receive(\.composer.internal.syncCollectionState)

        XCTAssertEqual(recorder.value(forKey: SettingsKeys.viewLayout), EntryViewLayoutState.Mode.grid.rawValue)
    }

    /// EVM-002-set_entries_view_as_list_table: 레이아웃 변경 시 활성 이름 변경 취소 검증
    /// 다른 모드로 레이아웃 변경 시 진행 중인 rename 작업이 취소되어야 한다.
    /// - 검증 내용: renamingItemId가 존재하는 상태에서 changeLayout(.grid) 시 cancelRename 액션 수신 및 renamingItemId nil 설정
    /// - 사전 조건: mode == .list, renamingItemId == "test-entry-id"
    /// - 기대 결과: mode == .grid, renamingItemId == nil, cancelRename 액션 수신
    func testChangeLayoutCancelsActiveRename() async {
        let renamingId: EntryModel.ID = "test-entry-id"
        var state = FileManagerContentState()
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entryOperations.renamingItemId = renamingId

        let store = makeFileManagerContentFeatureStore(initialState: state)

        await store.send(.view(.changeLayout(.grid)))
        await store.receive(\.entryViewLayout.internal.setMode) {
            $0.entryViewLayout.mode = .grid
            $0.entryViewLayout.outlineProjectionRevision += 1
        }

        await store.receive(\.composer.internal.syncCollectionState)
        await store.receive(\.entryViewLayout.entryOperations.edit.cancelRename) {
            $0.entryViewLayout.entryOperations.renamingItemId = nil
        }
    }

    /// EVM-002-set_entries_view_as_list_table: 동일 모드 재선택 시 rename 취소 방지 검증
    /// 이미 활성화된 모드를 다시 선택하면 isModeChanging이 false이므로 rename이 취소되지 않는다.
    /// - 검증 내용: mode == .list 상태에서 changeLayout(.list) 시 cancelRename 액션이 발생하지 않는지 확인
    /// - 사전 조건: mode == .list, renamingItemId == "test-entry-id"
    /// - 기대 결과: renamingItemId 유지, cancelRename 미수신, composer.syncCollectionState만 수신
    func testChangeLayoutSameModeDoesNotCancelRename() async {
        let renamingId: EntryModel.ID = "test-entry-id"
        var state = FileManagerContentState()
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entryOperations.renamingItemId = renamingId

        let store = makeFileManagerContentFeatureStore(initialState: state)

        // 같은 모드로 변경 → isModeChanging == false → 취소 없음
        await store.send(.view(.changeLayout(.list)))
        await store.receive(\.entryViewLayout.internal.setMode) {
            $0.entryViewLayout.outlineProjectionRevision += 1
        }

        await store.receive(\.composer.internal.syncCollectionState)
        XCTAssertEqual(store.state.entryViewLayout.mode, .list)
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.renamingItemId, renamingId)
    }

    // MARK: - EVM-002-show_hide_hidden_entry

    /// store.exhaustivity = .off: loadItems 이후 itemsLoaded→arrangements 체인은 검증 대상이 아님
    /// EVM-002-show_hide_hidden_entry: 숨김 파일 토글 + 리로드 시 네비게이션/히스토리 불변 검증
    /// FileManagerContentFeature 전체 리듀서에서 toggleShowHiddenFilesAndReload가 entryViewLayout.toggleShowHiddenFiles +
    /// reload 체인을 트리거하며 네비게이션 라우트와 히스토리가 변경되지 않음을 증명한다.
    /// - 검증 내용: showHiddenFiles 토글, 현재 정렬 metadata priority를 포함한 reload, navigation history 불변 확인
    /// - 사전 조건: navigationState == .folder("/seed"), showHiddenFiles == false, sortKey == .kind
    /// - 기대 결과:
    ///   1) .entryViewLayout(.view(.toggleShowHiddenFiles)) 수신, showHiddenFiles == true
    ///   2) loadItems(path: "/seed", showHidden: true, priority: .active([.spotlight])) 수신
    ///   3) navigationState, backHistory, forwardHistory 변경 없음
    func testToggleShowHiddenFilesAndReloadPreservesNavigationHistory() async {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/seed")
        state.entryViewLayout.showHiddenFiles = false
        state.entryViewLayout.entryArrangements.sortKey = .kind

        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        let preNavigation = store.state.navigation.navigationState
        let preBackHistory = store.state.navigation.backHistory
        let preForwardHistory = store.state.navigation.forwardHistory

        // NavigationBridgeReducer가 effect만 반환 (상태 변이 없음)
        await store.send(.view(.toggleShowHiddenFilesAndReload))

        _ = await store.receive(\.entryViewLayout.view.toggleShowHiddenFiles) {
            $0.entryViewLayout.showHiddenFiles = true
        }

        _ = await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden,
                priority,
            )))) = action else { return false }
            return path == "/seed"
                && showHidden
                && priority == .active([.spotlight])
        }

        // 네비게이션 라우트와 히스토리가 변경되지 않았는지 확인
        XCTAssertEqual(store.state.navigation.navigationState, preNavigation)
        XCTAssertEqual(store.state.navigation.backHistory, preBackHistory)
        XCTAssertEqual(store.state.navigation.forwardHistory, preForwardHistory)
    }

    /// EVM-002-set_entries_view_as_list_table: metadata 정렬 변경 시 현재 root와 expanded folder reload
    /// Spotlight 기반 정렬을 선택하면 기존 core-only payload를 현재 priority로 다시 materialize하는지 검증한다.
    /// - 검증 내용: folder root load와 hierarchy metadata reload 액션이 동일한 active priority를 사용함
    /// - 사전 조건: folder route, sortKey == .kind, expanded hierarchy cache 존재
    /// - 기대 결과: loadItems와 arrangementMetadataPriorityChanged가 차례로 전달됨
    func testMetadataSortChangeReloadsRootAndExpandedHierarchy() async {
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/seed")
        let store = makeFileManagerContentFeatureStore(initialState: state)
        // store.exhaustivity = .off: arrangement apply 내부 액션은 metadata reload 계약의 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryArrangements(.setSortKey(.kind)))) {
            $0.entryViewLayout.entryArrangements.sortKey = .kind
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden: _,
                priority,
            )))) = action else { return false }
            return path == "/seed" && priority == .active([.spotlight])
        }
        await store.receive(\.entryViewLayout.hierarchy.arrangementMetadataPriorityChanged)
    }

    /// EVM-002-set_entries_view_as_list_table: collection metadata 정렬 변경 시 현재 path 재조회
    /// Collection의 기존 core-only payload를 새 metadata priority로 다시 materialize하도록 요청하는지 검증한다.
    /// - 검증 내용: collection mode에서 sortKey 변경이 현재 collection item path를 applyCollectionSearchPaths로 전달함
    /// - 사전 조건: collection mode, sortKey == .name, 현재 collection item 두 개 존재
    /// - 기대 결과: 두 item path와 현재 showHidden 값으로 collection materialization이 재요청됨
    func testMetadataSortChangeRematerializesCurrentCollectionPaths() async {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true
        state.entryViewLayout.collectionItems = [
            .temporaryFolder(id: "/collection/first", name: "first"),
            .temporaryFolder(id: "/collection/second", name: "second"),
        ]
        let store = makeFileManagerContentFeatureStore(initialState: state)
        // store.exhaustivity = .off: collection materialization 내부 stream은 현재 path 재요청 계약의 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryArrangements(.setSortKey(.kind)))) {
            $0.entryViewLayout.entryArrangements.sortKey = .kind
        }
        await store.receive { action in
            guard case let .entryViewLayout(.internal(.applyCollectionSearchPaths(paths, showHidden))) = action
            else { return false }
            return paths == ["/collection/first", "/collection/second"] && !showHidden
        }
    }

    /// EVM-002-set_entries_view_as_list_table: in-flight collection 정렬 변경 시 원본 path 유지
    /// partial batch만 도착한 replace stream을 새 metadata priority로 재시작해도 미도착 path가 보존되는지 검증한다.
    /// - 검증 내용: arrangement 변경이 partial collectionItems가 아닌 active replace 원본 paths를 재사용함
    /// - 사전 조건: 두 path replace가 진행 중이고 첫 번째 item만 materialize됨
    /// - 기대 결과: applyCollectionSearchPaths 재요청에 원본 path 두 개가 모두 포함됨
    func testMetadataSortChangePreservesInFlightCollectionSourcePaths() async {
        let first = EntryModel.temporaryFolder(id: "/collection/first", name: "first")
        let sourcePaths = [first.id, "/collection/second"]
        var layoutState = EntryViewLayoutState()
        layoutState.isCollectionMode = true
        _ = EntryViewLayoutFeature().reduce(
            into: &layoutState,
            action: .internal(.applyCollectionSearchPaths(paths: sourcePaths, showHidden: false)),
        )
        layoutState.collectionItems = [first]
        var state = FileManagerContentState()
        state.entryViewLayout = layoutState
        let store = makeFileManagerContentFeatureStore(initialState: state)
        // store.exhaustivity = .off: collection materialization stream은 원본 path 재사용 계약의 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryArrangements(.setSortKey(.kind)))) {
            $0.entryViewLayout.entryArrangements.sortKey = .kind
        }
        await store.receive { action in
            guard case let .entryViewLayout(.internal(.applyCollectionSearchPaths(paths, _))) = action
            else { return false }
            return paths == sourcePaths
        }
    }

    /// EVM-002-set_entries_view_as_list_table: in-flight append 정렬 변경 시 원본 path 유지
    /// partial append를 취소하고 metadata reload를 시작해도 미도착 path는 보존하고 제거 path는 제외하는지 검증한다.
    /// - 검증 내용: active append 원본 paths 병합과 remove lifecycle pruning
    /// - 사전 조건: 세 path append 중 하나만 도착했고 다른 하나는 제거됨
    /// - 기대 결과: 현재 item과 미도착 유효 path만 applyCollectionSearchPaths에 포함됨
    func testMetadataSortChangePreservesInFlightAppendPathsExceptRemovedPaths() async {
        let base = EntryModel.temporaryFolder(id: "/collection/base", name: "base")
        let arrived = EntryModel.temporaryFolder(id: "/collection/arrived", name: "arrived")
        let pendingPath = "/collection/pending"
        let removedPath = "/collection/removed"
        var layoutState = EntryViewLayoutState()
        layoutState.isCollectionMode = true
        layoutState.collectionItems = [base]
        _ = EntryViewLayoutFeature().reduce(
            into: &layoutState,
            action: .internal(.addCollectionPaths([arrived.id, pendingPath, removedPath])),
        )
        layoutState.collectionItems.append(arrived)
        _ = EntryViewLayoutFeature().reduce(
            into: &layoutState,
            action: .internal(.removeCollectionPaths([removedPath])),
        )
        var state = FileManagerContentState()
        state.entryViewLayout = layoutState
        let store = makeFileManagerContentFeatureStore(initialState: state)
        // store.exhaustivity = .off: collection materialization stream은 append 원본 path 재사용 계약의 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryArrangements(.setSortKey(.kind)))) {
            $0.entryViewLayout.entryArrangements.sortKey = .kind
        }
        await store.receive { action in
            guard case let .entryViewLayout(.internal(.applyCollectionSearchPaths(paths, _))) = action
            else { return false }
            return paths == [base.id, arrived.id, pendingPath]
        }
    }

    /// EVM-002-set_entries_view_as_list_table: metadata grouping 변경 시 현재 root와 expanded folder reload
    /// Tags 기반 grouping을 선택하면 기존 core-only payload를 현재 priority로 다시 materialize하는지 검증한다.
    /// - 검증 내용: folder root load와 hierarchy metadata reload 액션이 Tags 우선 priority를 사용함
    /// - 사전 조건: folder route, groupKey == .tags
    /// - 기대 결과: loadItems와 arrangementMetadataPriorityChanged가 차례로 전달됨
    func testMetadataGroupChangeReloadsRootAndExpandedHierarchy() async {
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/seed")
        let store = makeFileManagerContentFeatureStore(initialState: state)
        // store.exhaustivity = .off: arrangement apply 내부 액션은 metadata reload 계약의 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryArrangements(.setGroupKey(.tags)))) {
            $0.entryViewLayout.entryArrangements.groupKey = .tags
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden: _,
                priority,
            )))) = action else { return false }
            return path == "/seed" && priority == .active([.tags])
        }
        await store.receive(\.entryViewLayout.hierarchy.arrangementMetadataPriorityChanged)
    }

    // MARK: - EVM-002-set_entries_view_as_list_table

    /// EVM-002-set_entries_view_as_list_table: .grid → .list 전환 시 모드/영속성/composer 동기화 검증
    /// 초기 모드가 .grid인 상태에서 .list로 전환할 때 모드 변경, UserDefaults 영속화, composer 동기화가 모두 정상 동작함을 증명한다.
    /// - 검증 내용: changeLayout(.list)가 mode, SettingsKeys.viewLayout 저장값, composer.syncCollectionState를 함께 갱신하는지 확인
    /// - 사전 조건: entryViewLayout.mode == .grid
    /// - 기대 결과:
    ///   1) mode == .list
    ///   2) SettingsKeys.viewLayout에 "list" 영속화
    ///   3) composer.syncCollectionState 수신
    func testChangeLayoutFromGridToListPersistsAndSyncs() async {
        let recorder = UserDefaultsStringRecorder()
        var state = FileManagerContentState()
        state.entryViewLayout.mode = .grid

        let store = makeFileManagerContentFeatureStore(
            initialState: state,
            setString: recorder.record,
        )

        await store.send(.view(.changeLayout(.list)))
        await store.receive(\.entryViewLayout.internal.setMode) {
            $0.entryViewLayout.mode = .list
            $0.entryViewLayout.outlineProjectionRevision += 1
        }

        await store.receive(\.composer.internal.syncCollectionState)

        XCTAssertEqual(recorder.value(forKey: SettingsKeys.viewLayout), EntryViewLayoutState.Mode.list.rawValue)
        XCTAssertEqual(store.state.entryViewLayout.mode, .list)
    }

    // MARK: - EVM-002-view_entry_counts_in_current_page

    /// EVM-002-view_entry_counts_in_current_page: 선택 항목이 있는 상태 표시 소스 데이터 검증
    /// statusText가 `displayItems.count`와 `selectedIds.count`에서 계산될 수 있도록 reducer 상태의 소스 값을 증명한다.
    /// - 검증 내용: entryOperations.loadingContext.items 기반 displayItems와 selectedIds 개수가 breadcrumb statusText 입력으로 유지되는지
    /// 확인
    /// - 사전 조건: displayItems에 3개 항목, selectedIds에 2개 선택
    /// - 기대 결과: displayItems.count == 3, selectedIds.count == 2
    func testStatusTextSourceMatchesDisplayItemsAndSelectedIds() {
        var state = FileManagerContentState()
        let entries: [EntryModel] = [
            .temporaryFolder(id: "/seed/file-a", name: "file-a"),
            .temporaryFolder(id: "/seed/file-b", name: "file-b"),
            .temporaryFolder(id: "/seed/file-c", name: "file-c"),
        ]
        state.entryViewLayout.entryOperations.loadingContext.items = IdentifiedArrayOf(uniqueElements: entries)
        state.entryViewLayout.selectedIds = ["/seed/file-a", "/seed/file-c"]

        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        let total = store.state.entryViewLayout.displayItems.count
        let selected = store.state.entryViewLayout.selectedIds.count

        XCTAssertEqual(total, 3, "displayItems.count should match total item count for statusText")
        XCTAssertEqual(selected, 2, "selectedIds.count should match selected count for statusText")
        XCTAssertGreaterThan(selected, 0, "selected > 0 → statusText should be '\(selected) of \(total) selected'")
    }

    /// EVM-002-view_entry_counts_in_current_page: 선택 없음 시 statusText 소스 검증
    /// 선택 항목이 없을 때 statusText가 전체 항목 수만 표시할 수 있도록 reducer 상태의 소스 값을 증명한다.
    /// - 검증 내용: selectedIds가 비어 있는 경우 displayItems.count와 selectedIds.count가 statusText 입력으로 유지되는지 확인
    /// - 사전 조건: displayItems에 2개 항목, selectedIds가 비어 있음
    /// - 기대 결과: displayItems.count == 2, selectedIds.count == 0
    func testStatusTextSourceWithNoSelection() {
        var state = FileManagerContentState()
        let entries: [EntryModel] = [
            .temporaryFolder(id: "/seed/file-x", name: "file-x"),
            .temporaryFolder(id: "/seed/file-y", name: "file-y"),
        ]
        state.entryViewLayout.entryOperations.loadingContext.items = IdentifiedArrayOf(uniqueElements: entries)
        state.entryViewLayout.selectedIds = []

        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        let total = store.state.entryViewLayout.displayItems.count
        let selected = store.state.entryViewLayout.selectedIds.count

        XCTAssertEqual(total, 2)
        XCTAssertEqual(selected, 0, "selectedIds.count == 0 → statusText should be '\(total) items'")
    }

    // MARK: - VOY-578-render_identity

    /// VOY-578-render_identity: 같은 탭의 Directory 경로 변경은 렌더 identity를 유지한다.
    /// 사용자가 동일 탭에서 폴더 A에서 폴더 B로 이동해도 content root를 재마운트하지 않는 시나리오를 검증한다.
    /// - 검증 내용: 같은 active tab ID와 같은 Directory page kind의 최종 render identity 비교
    /// - 사전 조건: 동일한 active tab ID, 서로 다른 Directory 경로 `/directory-a`, `/directory-b`
    /// - 기대 결과: 두 최종 render identity가 동일하다.
    func testSameTabDirectoryPathChangeKeepsRenderIdentity() {
        let tabID = ContentTabID(rawValue: "tab-a")

        let directoryAIdentity = FileManagerContentChromeProps.renderIdentity(
            activeTabID: tabID,
            activePageAnchor: .directory(path: "/directory-a"),
        )
        let directoryBIdentity = FileManagerContentChromeProps.renderIdentity(
            activeTabID: tabID,
            activePageAnchor: .directory(path: "/directory-b"),
        )

        XCTAssertEqual(directoryAIdentity, directoryBIdentity)
    }

    /// VOY-578-render_identity: 탭 변경은 같은 Directory page kind도 새 렌더 identity를 만든다.
    /// 사용자가 다른 탭으로 전환하면 같은 종류의 페이지라도 content root가 재마운트되는 시나리오를 검증한다.
    /// - 검증 내용: 서로 다른 active tab ID와 같은 Directory page kind의 최종 render identity 비교
    /// - 사전 조건: `tab-a`, `tab-b`가 각각 Directory 페이지를 표시한다.
    /// - 기대 결과: 두 최종 render identity가 다르다.
    func testDifferentTabsUseDifferentRenderIdentities() {
        let firstIdentity = FileManagerContentChromeProps.renderIdentity(
            activeTabID: ContentTabID(rawValue: "tab-a"),
            activePageAnchor: .directory(path: "/shared"),
        )
        let secondIdentity = FileManagerContentChromeProps.renderIdentity(
            activeTabID: ContentTabID(rawValue: "tab-b"),
            activePageAnchor: .directory(path: "/shared"),
        )

        XCTAssertNotEqual(firstIdentity, secondIdentity)
    }

    /// VOY-578-render_identity: page kind 변경은 같은 탭에서도 새 렌더 identity를 만든다.
    /// 사용자가 같은 탭에서 Home, Directory, Collection, AI Chat 사이를 전환하는 remount 경계를 검증한다.
    /// - 검증 내용: 네 page kind의 anchor identity 값과 최종 render identity 상호 구분
    /// - 사전 조건: 동일한 active tab ID와 각 page kind의 대표 anchor
    /// - 기대 결과: anchor identity가 page kind별 고유 값이고 서로 다른 kind의 최종 identity가 다르다.
    func testPageKindsUseStableDistinctRenderIdentities() {
        let tabID = ContentTabID(rawValue: "tab-a")
        let anchors: [ContentTabPageAnchor] = [
            .homeDefault,
            .directory(path: "/directory"),
            .collectionFile(url: URL(fileURLWithPath: "/collection.voycoll")),
            .aiChat(sessionID: "session"),
        ]

        XCTAssertEqual(anchors.map(\.renderIdentity), ["home", "directory", "collection", "aiChat"])

        let identities = anchors.map {
            FileManagerContentChromeProps.renderIdentity(activeTabID: tabID, activePageAnchor: $0)
        }
        for firstIndex in identities.indices {
            for secondIndex in identities.indices where firstIndex < secondIndex {
                XCTAssertNotEqual(identities[firstIndex], identities[secondIndex])
            }
        }
    }

    /// VOY-578-render_identity: Collection anchor 전환은 같은 page kind identity를 유지한다.
    /// 저장 Collection과 virtual Collection 사이 전환이 content root를 재마운트하지 않는 시나리오를 검증한다.
    /// - 검증 내용: 같은 active tab ID의 Collection file 및 virtual Collection 최종 identity 비교
    /// - 사전 조건: 동일한 active tab ID와 서로 다른 Collection anchor 종류
    /// - 기대 결과: 두 anchor와 최종 render identity가 모두 동일한 Collection kind를 나타낸다.
    func testSameTabCollectionAnchorChangeKeepsRenderIdentity() {
        let tabID = ContentTabID(rawValue: "tab-a")
        let collectionFile = ContentTabPageAnchor.collectionFile(
            url: URL(fileURLWithPath: "/collection.voycoll"),
        )
        let virtualCollection = ContentTabPageAnchor.virtualCollection(id: "virtual-collection")

        XCTAssertEqual(collectionFile.renderIdentity, "collection")
        XCTAssertEqual(virtualCollection.renderIdentity, "collection")
        XCTAssertEqual(
            FileManagerContentChromeProps.renderIdentity(activeTabID: tabID, activePageAnchor: collectionFile),
            FileManagerContentChromeProps.renderIdentity(activeTabID: tabID, activePageAnchor: virtualCollection),
        )
    }

    /// EVM-002-set_entries_view_as_list_table: root 교체 시 현재 list만 접근성 child로 유지함
    /// content root가 바뀐 뒤 VoiceOver가 이전 EntryListView를 계속 탐색하지 않는지 검증한다.
    /// - 검증 내용: non-list child 보존, stale list 제거, current descendant list 추가
    /// - 사전 조건: 기존 accessibility children에 stale list와 일반 view가 있고 새 list가 렌더됨
    /// - 기대 결과: 결과 children에는 일반 view와 current list만 포함됨
    func testAccessibilityChildrenReplaceStaleEntryListWithCurrentList() {
        let retainedView = NSView(frame: .zero)
        let staleList = EntryListView()
        let currentList = EntryListView()

        let children = MainContainerSplitCoordinator.entryListAccessibilityChildren(
            existingChildren: [retainedView, staleList],
            currentEntryListViews: [currentList],
        )

        XCTAssertEqual(children.count, 2)
        XCTAssertTrue(children.contains { ($0 as? NSView) === retainedView })
        XCTAssertTrue(children.contains { ($0 as? NSView) === currentList })
        XCTAssertFalse(children.contains { ($0 as? NSView) === staleList })
    }

    // MARK: - VOY-578-ordinary_directory_loading

    /// VOY-578-ordinary_directory_loading: 일반 Directory 로딩은 엔트리를 유지하고 투명 input blocker로 입력을 차단한다.
    /// 새 경로 로딩 중 기존 list/grid를 시각적으로 그대로 유지하면서 stale entry 조작을 막는 시나리오를 검증한다.
    /// - 검증 내용: ordinary loading presentation의 retained entries, loading indicator, input blocker, pointer, keyboard 정책
    /// - 사전 조건: entryOperations.isLoading == true, isCollectionMode == false, Collection 로딩 상태 아님
    /// - 기대 결과: replacement와 ProgressView indicator는 없고 투명 blocker가 있으며 pointer와 keyboard dispatch가 차단된다.
    func testOrdinaryDirectoryLoadingRetainsEntriesWithoutIndicatorAndBlocksInput() {
        let policy = ContentPagePresentationPolicy.resolve(
            isCollectionSearching: false,
            isCollectionContentLoading: false,
            isEntryLoading: true,
            isCollectionMode: false,
        )

        XCTAssertEqual(policy, .ordinaryDirectoryLoadingOverlay)
        XCTAssertFalse(policy.replacesEntriesWithLoading, "ordinary loading must not show the replacement ProgressView")
        XCTAssertTrue(policy.showsInputBlocker)
        XCTAssertFalse(policy.allowsEntryInteraction)
        XCTAssertTrue(policy.hidesEntriesFromAccessibility)
        XCTAssertTrue(policy.requiresKeyCommandFocus)
        XCTAssertFalse(policy.allowsKeyboardCommandDispatch)
    }

    /// VOY-578-ordinary_directory_loading: Collection 로딩은 기존 spinner replacement 정책을 유지한다.
    /// Collection 검색과 content 로딩이 일반 Directory input blocker 정책으로 바뀌지 않는 회귀 방지 시나리오를 검증한다.
    /// - 검증 내용: 기존 두 Collection 로딩 신호의 ProgressView replacement 및 입력 정책
    /// - 사전 조건: isCollectionSearching 또는 isCollectionContentLoading 중 하나가 true
    /// - 기대 결과: 엔트리는 spinner로 교체되고 ordinary input blocker는 없으며 기존 keyboard dispatch 정책은 유지된다.
    func testCollectionLoadingKeepsReplacementPolicy() {
        let policies = [
            ContentPagePresentationPolicy.resolve(
                isCollectionSearching: true,
                isCollectionContentLoading: false,
                isEntryLoading: true,
                isCollectionMode: true,
            ),
            ContentPagePresentationPolicy.resolve(
                isCollectionSearching: false,
                isCollectionContentLoading: true,
                isEntryLoading: true,
                isCollectionMode: true,
            ),
        ]

        for policy in policies {
            XCTAssertEqual(policy, .collectionReplacementLoading)
            XCTAssertTrue(policy.replacesEntriesWithLoading)
            XCTAssertFalse(policy.showsInputBlocker)
            XCTAssertFalse(policy.hidesEntriesFromAccessibility)
            XCTAssertFalse(policy.requiresKeyCommandFocus)
            XCTAssertTrue(policy.allowsKeyboardCommandDispatch)
        }
    }
}

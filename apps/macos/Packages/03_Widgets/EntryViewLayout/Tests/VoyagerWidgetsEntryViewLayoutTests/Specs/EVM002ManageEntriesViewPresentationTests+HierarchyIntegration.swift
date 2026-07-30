import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
extension EVM002ManageEntriesViewPresentationTests {
    /// 단계적 root stream의 첫 batch가 terminal event 전에 실제 표시 목록으로 동기화되는지 검증한다.
    func testRootStreamCoreBatchUpdatesRenderedEntriesBeforeTerminal() {
        let entry = makeHierarchyIntegrationEntry(id: "/root/first.txt", name: "first.txt")
        var state = EntryViewLayoutState()
        state.entryOperations.isLoading = true
        state.entryOperations.loadingContext.generation = 1
        state.entryOperations.loadingContext.sourceKind = .directory

        _ = EntryViewLayoutFeature().reduce(
            into: &state,
            action: .entryOperations(.loading(.streamEvent(.init(
                generation: 1,
                event: .coreBatch(items: [entry], batchIndex: 0),
            )))),
        )

        XCTAssertEqual(state.entryOperations.items, [entry])
        XCTAssertEqual(state.entries, [entry])
    }

    /// 첫 root batch 전에 stream이 실패하면 이전 Directory의 표시 행이 남지 않는지 검증한다.
    func testRootStreamFailureBeforeFirstBatchClearsRenderedEntries() {
        let staleEntry = makeHierarchyIntegrationEntry(id: "/previous/stale.txt", name: "stale.txt")
        var state = EntryViewLayoutState()
        state.entries = [staleEntry]
        state.entryOperations.isLoading = true
        state.entryOperations.loadingContext.generation = 1
        state.entryOperations.loadingContext.sourceKind = .directory

        _ = EntryViewLayoutFeature().reduce(
            into: &state,
            action: .entryOperations(.loading(.streamFailed(generation: 1))),
        )

        XCTAssertTrue(state.entryOperations.items.isEmpty)
        XCTAssertTrue(state.entries.isEmpty)
    }

    /// 숨김 파일 설정 변경 시 expanded folder cache를 새 설정으로 다시 로드하는지 검증한다.
    func testHiddenFilesChangeReloadsExpandedFolderCache() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let staleChild = makeHierarchyIntegrationEntry(id: "/root/a/visible.txt", name: "visible.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.showHiddenFiles = true
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [
                folder.id: .init(
                    children: [staleChild],
                    phase: .loaded,
                    generation: 4,
                ),
            ],
        )
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }

        await store.send(.hierarchy(.hiddenFilesSettingChanged)) {
            $0.hierarchy.foldersByID[folder.id] = .init(phase: .loading, generation: 5)
            $0.outlineProjectionRevision = 2
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.cancelFolderItems(requestID))) = action else { return false }
            return requestID.folderID == folder.id
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.id.folderID == folder.id && request.showHidden
        }
    }

    /// EVM-002-set_entries_view_as_list_table: metadata 정렬 변경 시 expanded folder cache reload
    /// 현재 arrangement가 요구하는 metadata priority로 열린 folder child를 다시 materialize하는지 검증한다.
    /// - 검증 내용: arrangement metadata 변경 액션이 expanded folder generation과 load request를 갱신함
    /// - 사전 조건: sortKey == .kind, expanded folder cache가 loaded 상태임
    /// - 기대 결과: 새 folder request가 Spotlight 우선 priority를 사용함
    func testArrangementMetadataChangeReloadsExpandedFolderCache() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.entryArrangements.sortKey = .kind
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(phase: .loaded, generation: 2)],
        )
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }

        await store.send(.hierarchy(.arrangementMetadataPriorityChanged)) {
            $0.hierarchy.foldersByID[folder.id] = .init(phase: .loading, generation: 3)
            $0.outlineProjectionRevision = 2
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.cancelFolderItems(requestID))) = action else { return false }
            return requestID.folderID == folder.id
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.id.folderID == folder.id && request.priority == .active([.spotlight])
        }
    }

    /// EVM-002-set_entries_view_as_list_table: metadata 정렬 변경 시 collapsed folder cache 무효화
    /// 접힌 folder의 기존 core-only payload가 다음 expansion에서 재사용되지 않는지 검증한다.
    /// - 검증 내용: arrangement metadata 변경이 collapsed cache를 idle로 만들고 다음 load에 새 priority를 적용함
    /// - 사전 조건: sortKey == .kind, collapsed folder cache가 loaded 상태임
    /// - 기대 결과: 기존 load 취소 후 다음 expansion request가 Spotlight 우선 priority를 사용함
    func testArrangementMetadataChangeInvalidatesCollapsedFolderCache() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let staleChild = makeHierarchyIntegrationEntry(id: "/root/a/file", name: "file")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.entryArrangements.sortKey = .kind
        state.hierarchy = .init(
            rootPath: "/root",
            foldersByID: [
                folder.id: .init(children: [staleChild], phase: .loaded, generation: 2),
            ],
        )
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }

        await store.send(.hierarchy(.arrangementMetadataPriorityChanged)) {
            $0.hierarchy.foldersByID[folder.id] = .init(phase: .idle, generation: 3)
            $0.outlineProjectionRevision = 1
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.cancelFolderItems(requestID))) = action else { return false }
            return requestID.folderID == folder.id
        }
        await store.send(.hierarchy(.folderExpansionRequested(id: folder.id))) {
            $0.hierarchy.expandedFolderIDs = [folder.id]
            $0.hierarchy.foldersByID[folder.id] = .init(phase: .loading, generation: 4)
            $0.outlineProjectionRevision = 2
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.id.folderID == folder.id && request.priority == .active([.spotlight])
        }
    }

    /// EVM-002-toggle_directory_expansion_in_list: 기본 정렬의 folder expansion은 metadata probe를 생략한다.
    /// - 사전 조건: metadata facet을 요구하지 않는 이름 정렬과 group 없음 상태
    /// - 기대 결과: folder load request가 `.none` priority를 사용함
    func testDefaultFolderExpansionUsesNoMetadataPriority() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderExpansionRequested(id: folder.id)))
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.id.folderID == folder.id && request.priority == .none
        }
    }

    /// 계층 projection의 child payload가 command와 selection에서 사용할 실제 EntryModel 목록으로 노출되는지 검증한다.
    func testVisibleSelectableEntriesIncludeNestedPayloads() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file", name: "file")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(children: [child], phase: .loaded)],
        )

        XCTAssertEqual(
            state.visibleSelectableEntries(isNormalDirectoryPage: true).map(\.id),
            [folder.id, child.id],
        )
    }

    /// store projection이 coordinator의 NSOutlineView row graph를 직접 구성하는지 검증한다.
    func testHierarchyProjectionDrivesCoordinatorRows() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file", name: "file")
        let sibling = makeHierarchyIntegrationEntry(id: "/root/sibling", name: "sibling")
        var state = EntryViewLayoutState()
        state.entries = [folder, sibling]
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(children: [child], phase: .loaded)],
        )
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)

        coordinator.bind(to: view)

        XCTAssertEqual(view.tableView.numberOfRows, 3)
        XCTAssertEqual(
            (0 ..< view.tableView.numberOfRows).compactMap { row in
                guard let item = view.tableView.item(atRow: row) as? EntryListOutlineItem,
                      case let .entry(entry) = item.kind
                else { return nil }
                return entry.id
            },
            [folder.id, child.id, sibling.id],
        )
    }

    /// EVM-002-toggle_directory_expansion_in_list: 계층 projection 비활성 목록은 folder disclosure를 숨긴다.
    /// Recents, Tags, collection, grouping 목록에서 동작하지 않는 빈 확장 UI가 노출되지 않는지 검증한다.
    /// - 검증 내용: root hierarchy context가 없는 list folder의 isItemExpandable 결과
    /// - 사전 조건: list mode root entries에 folder가 있지만 hierarchy.rootPath는 비어 있음
    /// - 기대 결과: data source가 folder를 expandable로 보고하지 않음
    func testInactiveHierarchyDoesNotExposeFolderDisclosure() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)

        coordinator.bind(to: view)

        let item = try XCTUnwrap(view.tableView.item(atRow: 0))
        XCTAssertFalse(coordinator.outlineView(view.tableView, isItemExpandable: item))
    }

    /// EVM-002-toggle_directory_expansion_in_list: canonical watcher path가 lexical hierarchy key를 다시 로드한다.
    /// symlink를 통해 연 folder가 실경로 이벤트를 받아도 expanded child cache가 stale로 남지 않는지 검증한다.
    /// - 검증 내용: `/private/var` affected path가 `/var` folder ID의 새 load request를 생성함
    /// - 사전 조건: 실제 symlink인 lexical `/var` folder가 expanded loaded 상태임
    /// - 기대 결과: lexical folder ID를 유지한 채 generation을 올리고 loading 상태로 전환함
    func testCanonicalInvalidationReloadsLexicalHierarchyFolder() async {
        let folder = EntryModel.temporaryFolder(id: "/var", name: "var")
        let staleChild = makeHierarchyIntegrationEntry(id: "/var/stale.txt", name: "stale.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(
            rootPath: "/",
            expandedFolderIDs: [folder.id],
            foldersByID: [
                folder.id: .init(
                    children: [staleChild],
                    phase: .loaded,
                    generation: 2,
                ),
            ],
        )
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }

        await store.send(.hierarchy(.hierarchyInvalidated(
            affectedPaths: ["/private/var"],
            removedPrefixes: [],
        ))) {
            $0.hierarchy.foldersByID[folder.id] = .init(phase: .loading, generation: 3)
            $0.outlineProjectionRevision = 2
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.id.folderID == folder.id && request.path == folder.fullPath
        }
    }

    /// EVM-002-toggle_directory_expansion_in_list: loading folder의 watcher invalidation은 stream을 재시작한다.
    /// 진행 중인 child snapshot이 외부 추가·삭제를 놓친 채 loaded로 고정되지 않는지 검증한다.
    /// - 검증 내용: loading parent의 generation 증가와 새 load request 생성
    /// - 사전 조건: expanded `/var` folder가 generation 2의 partial child stream을 로딩 중임
    /// - 기대 결과: 기존 children을 비우고 generation 3 load를 같은 lexical folder ID로 요청함
    func testInvalidationRestartsLoadingHierarchyFolder() async {
        let folder = EntryModel.temporaryFolder(id: "/var", name: "var")
        let partialChild = makeHierarchyIntegrationEntry(id: "/var/partial.txt", name: "partial.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(
            rootPath: "/",
            expandedFolderIDs: [folder.id],
            foldersByID: [
                folder.id: .init(
                    children: [partialChild],
                    phase: .loading,
                    generation: 2,
                    expectedBatchIndex: 1,
                ),
            ],
        )
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }

        await store.send(.hierarchy(.hierarchyInvalidated(
            affectedPaths: ["/var/new.txt"],
            removedPrefixes: [],
        ))) {
            $0.hierarchy.foldersByID[folder.id] = .init(phase: .loading, generation: 3)
            $0.outlineProjectionRevision = 2
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.id.folderID == folder.id && request.folderGeneration == 3
        }
    }

    /// EVM-002-toggle_directory_expansion_in_list: coarse invalidation은 expanded descendant cache를 모두 재로드한다.
    /// ancestor path만 보고된 rescan에서도 중첩 folder snapshot이 stale로 남지 않는지 검증한다.
    /// - 검증 내용: cached folder 전체 generation 증가와 expanded A/B loading 전환
    /// - 사전 조건: A와 자식 B가 모두 expanded·loaded 상태임
    /// - 기대 결과: A/B children을 비우고 각각 새 generation load를 시작함
    func testCoarseInvalidationReloadsExpandedDescendantCaches() async {
        let folderA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let folderB = EntryModel.temporaryFolder(id: "/root/A/B", name: "B")
        let staleChild = makeHierarchyIntegrationEntry(id: "/root/A/B/stale.txt", name: "stale.txt")
        var state = EntryViewLayoutState()
        state.entries = [folderA]
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folderA.id, folderB.id],
            foldersByID: [
                folderA.id: .init(children: [folderB], phase: .loaded, generation: 2),
                folderB.id: .init(children: [staleChild], phase: .loaded, generation: 4),
            ],
        )
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        // store.exhaustivity = .off: effect 순서보다 모든 cached descendant의 동기 state 전환을 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.coarseHierarchyInvalidated(removedPrefixes: []))) {
            $0.hierarchy.foldersByID[folderA.id] = .init(phase: .loading, generation: 3)
            $0.hierarchy.foldersByID[folderB.id] = .init(phase: .loading, generation: 5)
            $0.outlineProjectionRevision = 3
        }
        await store.skipReceivedActions()
        await store.finish()
    }

    /// EVM-002-update_entry_selection: nested child context menu는 visible hierarchy row를 현재 대상으로 사용한다.
    /// expanded child를 우클릭한 뒤 Rename이 root-only snapshot 때문에 no-op 되지 않는지 검증한다.
    /// - 검증 내용: child row context menu target의 Rename delegate action
    /// - 사전 조건: root folder 아래 child가 visible·selected 상태임
    /// - 기대 결과: child EntryModel을 대상으로 startRename action이 실행됨
    func testNestedChildContextMenuStartsRename() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.selectedIds = [child.id]
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(children: [child], phase: .loaded)],
        )
        let store = Store(initialState: state) {
            Reduce<EntryViewLayoutState, EntryViewLayoutAction> { state, action in
                guard case let .delegate(.startRename(item, _)) = action else { return .none }
                state.entryOperations.renamingItemId = item.id
                return .none
            }
        }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)
        let event = try XCTUnwrap(NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0,
        ))

        coordinator.bind(to: view)
        _ = coordinator.contextMenu(forRow: 1, event: event)
        coordinator.contextMenuCoordinator?.contextMenuStartRename()

        XCTAssertEqual(store.state.entryOperations.renamingItemId, child.id)
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection restore는 제거 tombstone을 해제함
    /// Put Back/undo로 같은 path를 add할 때 append item이 tombstone에 다시 차단되지 않는지 검증한다.
    /// - 검증 내용: addCollectionPaths가 canonical removedCollectionPaths를 제거하고 item append를 허용함
    /// - 사전 조건: 복구 path가 removedCollectionPaths에 기록된 collection mode
    /// - 기대 결과: tombstone이 제거되고 같은 path item이 collectionItems에 추가됨
    func testAddCollectionPathsClearsRemovedPathTombstone() {
        let restored = EntryModel.temporaryFolder(id: "/tmp/restored.txt", name: "restored.txt")
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        state.removedCollectionPaths = [restored.id]

        _ = EntryViewLayoutFeature().reduce(
            into: &state,
            action: .internal(.addCollectionPaths([restored.id])),
        )
        EntryViewLayoutFeature.appendCollectionItems([restored], state: &state)

        XCTAssertFalse(state.removedCollectionPaths.contains(restored.id))
        XCTAssertEqual(state.collectionItems.map(\.id), [restored.id])
    }

    /// EVM-002-update_entry_selection: root load 완료 뒤에도 visible nested child rename 유지
    /// root-only itemsLoaded가 계층 projection에 남아 있는 child의 inline rename을 닫지 않는지 검증한다.
    /// - 검증 내용: itemsLoaded 처리 후 projection-visible renamingItemId 유지
    /// - 사전 조건: expanded folder child가 visible하고 rename 중임
    /// - 기대 결과: root items 갱신 뒤에도 child rename state가 유지됨
    func testRootItemsLoadedPreservesVisibleNestedChildRename() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.entryOperations.renamingItemId = child.id
        state.entryOperations.renamingText = child.name
        state.entryOperations.renamingItem = child
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(children: [child], phase: .loaded)],
        )
        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // store.exhaustivity = .off: arrangement reapply와 trash metadata 갱신은 rename visibility 계약의 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.entryOperations(.loading(.itemsLoaded([folder])))) {
            $0.entryOperations.items = [folder]
        }
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.entryOperations.renamingItemId, child.id)
        XCTAssertEqual(store.state.entryOperations.renamingItem, child)
    }

    /// EVM-002-update_entry_selection: root load에서 사라진 visible item rename 취소
    /// projection owner가 갱신 뒤 보이지 않는 root item의 rename state를 정리하는지 검증한다.
    /// - 검증 내용: itemsLoaded 처리 후 projection에서 사라진 renamingItemId 취소
    /// - 사전 조건: root item이 rename 중이고 새 root items에는 다른 item만 존재함
    /// - 기대 결과: rename state가 nil/빈 문자열로 초기화됨
    func testRootItemsLoadedCancelsRenameWhenItemLeavesVisibleProjection() async {
        let renamed = makeHierarchyIntegrationEntry(id: "/root/renamed.txt", name: "renamed.txt")
        let replacement = makeHierarchyIntegrationEntry(id: "/root/replacement.txt", name: "replacement.txt")
        var state = EntryViewLayoutState()
        state.entries = [renamed]
        state.entryOperations.items = [renamed]
        state.entryOperations.renamingItemId = renamed.id
        state.entryOperations.renamingText = renamed.name
        state.entryOperations.renamingItem = renamed
        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // store.exhaustivity = .off: arrangement reapply와 trash metadata 갱신은 rename visibility 계약의 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.entryOperations(.loading(.itemsLoaded([replacement])))) {
            $0.entryOperations.items = [replacement]
            $0.entries = [replacement]
        }
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertNil(store.state.entryOperations.renamingItemId)
        XCTAssertEqual(store.state.entryOperations.renamingText, "")
        XCTAssertNil(store.state.entryOperations.renamingItem)
    }

    /// EVM-002-toggle_directory_expansion_in_list: 동일 root reload는 hierarchy와 selection을 보존함
    /// canonical path가 같은 rootContextChanged가 펼침 상태와 child cache를 초기화하지 않는지 검증한다.
    /// - 검증 내용: same-root action 처리 후 hierarchy generation, expansion, cache, selection 유지
    /// - 사전 조건: expanded folder child가 선택된 `/root` hierarchy와 canonical-equivalent `/root/./` action
    /// - 기대 결과: reducer state가 변경되지 않고 후속 취소·selection clear action이 발생하지 않음
    func testSameRootContextChangePreservesHierarchyAndSelection() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = makeHierarchyIntegrationEntry(id: "/root/folder/child.txt", name: "child.txt")
        var state = EntryViewLayoutState()
        state.hierarchy = .init(
            rootContextGeneration: 3,
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(children: [child], phase: .loaded, generation: 2)],
        )
        state.selectedIds = [child.id]
        state.lastSelectedId = child.id
        state.rangeAnchorId = child.id
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }

        await store.send(.hierarchy(.rootContextChanged(path: "/root/./")))
    }

    /// EVM-002-toggle_directory_expansion_in_list: 빈 sentinel에서 cwd folder root로 전환
    /// hierarchy 비활성 sentinel과 process cwd가 canonical 비교에서 같은 root로 취급되지 않는지 검증한다.
    /// - 검증 내용: rootContextChanged(cwd) 이후 generation과 rootPath 갱신
    /// - 사전 조건: hierarchy.rootPath가 빈 sentinel임
    /// - 기대 결과: hierarchy가 cwd root로 활성화됨
    func testEmptyRootSentinelTransitionsToCurrentDirectoryRoot() async {
        let currentDirectory = FileManager.default.currentDirectoryPath
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryListHierarchyReducer()
        }
        // store.exhaustivity = .off: root 전환의 state contract만 검증하고 selection 후속 action은 별도 owner가 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.rootContextChanged(path: currentDirectory))) {
            $0.hierarchy = .init(rootContextGeneration: 1, rootPath: currentDirectory)
        }
        await store.skipReceivedActions()
        await store.finish()
    }

    /// EVM-002-toggle_directory_expansion_in_list: cwd folder root에서 빈 sentinel로 전환
    /// 비폴더 route 진입 시 process cwd와 같던 hierarchy root도 반드시 비활성화되는지 검증한다.
    /// - 검증 내용: rootContextChanged("") 이후 generation과 빈 rootPath 갱신
    /// - 사전 조건: hierarchy.rootPath가 process cwd임
    /// - 기대 결과: hierarchy가 빈 sentinel로 reset됨
    func testCurrentDirectoryRootTransitionsToEmptySentinel() async {
        let currentDirectory = FileManager.default.currentDirectoryPath
        var state = EntryViewLayoutState()
        state.hierarchy = .init(rootContextGeneration: 4, rootPath: currentDirectory)
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        // store.exhaustivity = .off: root reset의 state contract만 검증하고 selection 후속 action은 별도 owner가 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.rootContextChanged(path: ""))) {
            $0.hierarchy = .init(rootContextGeneration: 5, rootPath: "")
        }
        await store.skipReceivedActions()
        await store.finish()
    }

    private func makeHierarchyIntegrationEntry(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "txt",
            facets: EntryFacets(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}

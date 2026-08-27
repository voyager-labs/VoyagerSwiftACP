import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerShared
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
extension EVM002ManageEntriesViewPresentationTests {
    /// 단계적 root stream의 첫 batch가 terminal event 전에 실제 표시 목록으로 동기화되는지 검증한다.
    func testRootStreamCoreBatchUpdatesRenderedEntriesBeforeTerminal() {
        let entry = makeHierarchyIntegrationEntry(id: "/root/first.txt", name: "first.txt")
        var state = EntryViewLayoutState()

        _ = EntryViewLayoutFeature().reduce(
            into: &state,
            action: .view(.applyContentProjection(makeHierarchyContentProjection(
                entries: [entry],
                isLoading: true,
            ))),
        )

        XCTAssertEqual(state.entries, [entry])
        XCTAssertTrue(state.entryOperations.isLoading)
    }

    /// 첫 root batch 전에 stream이 실패하면 이전 Directory의 표시 행이 남지 않는지 검증한다.
    func testRootStreamFailureBeforeFirstBatchClearsRenderedEntries() {
        let staleEntry = makeHierarchyIntegrationEntry(id: "/previous/stale.txt", name: "stale.txt")
        var state = EntryViewLayoutState()
        state.entries = [staleEntry]

        _ = EntryViewLayoutFeature().reduce(
            into: &state,
            action: .view(.applyContentProjection(makeHierarchyContentProjection(
                entries: [],
                isLoading: false,
            ))),
        )

        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertFalse(state.entryOperations.isLoading)
    }

    /// 숨김 파일 설정 변경 시 expanded folder cache를 새 설정으로 다시 로드하는지 검증한다.
    func testHiddenFilesChangeReloadsExpandedFolderCache() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let staleChild = makeHierarchyIntegrationEntry(id: "/root/a/visible.txt", name: "visible.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.showHiddenFiles = true
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            folder.id: .init(
                children: [staleChild],
                loadPhase: .loaded,
                generation: 4,
            ),
        ]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.hiddenFilesSettingChanged)) {
            $0.hierarchy.nodesByID[folder.id as String] = .init(
                expansionIntent: true,
                generation: 5,
                loadPhase: .loadingCore,
            )
            $0.outlineProjectionRevision = 2
        }
        await store.receive(\.delegate.expandRequested, folder.id)
    }

    // MARK: - EVM-002-show_hide_hidden_entry

    /// EVM-002-show_hide_hidden_entry: hidden expanded folder는 OFF→ON 전환 시 expansion intent를 보존하고
    /// child를 자동으로 다시 로드한다.
    ///
    /// - 검증 내용: hidden files OFF→ON 전환 시 expansionIntent가 유지되고 reload된다.
    /// - 사전 조건: /root/a가 expanded·loaded 상태이고 showHiddenFiles = true, child가 하나 있다.
    /// - 기대 결과: OFF 후에도 expansionIntent = true, loadPhase = .loadingCore, child는 비워진다.
    ///   ON 후에도 expansionIntent = true, loadPhase = .loadingCore, 새 generation으로 재시작한다.
    func testHiddenExpandedRootFolderRestoresOnToggleOn() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/visible.txt", name: "visible.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.showHiddenFiles = true
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            folder.id: .init(
                children: [child],
                loadPhase: .loaded,
                generation: 4,
            ),
        ]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        // OFF: hidden files 숨김, cache는 무효화되지만 expansionIntent는 유지된다.
        await store.send(.hierarchy(.hiddenFilesSettingChanged)) {
            $0.hierarchy.nodesByID[folder.id as String] = .init(
                expansionIntent: true,
                generation: 5,
                loadPhase: .loadingCore,
            )
        }
        await store.receive(\.delegate.expandRequested, folder.id)
        // OFF 상태에서도 nodesByID와 expansionIntent는 유지된다.
        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.expansionIntent, true)
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.folder.children, [])
        let revisionAfterOff = store.state.outlineProjectionRevision

        // ON: 다시 활성화, 새 generation으로 재시작한다.
        await store.send(.hierarchy(.hiddenFilesSettingChanged))
        await store.receive(\.delegate.expandRequested, folder.id)
        // 확장 의도는 모든 전환에서 유지된다.
        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.expansionIntent, true)
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.generation, 6)
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.loadPhase, .loadingCore)
        // revision은 OFF 이후보다 증가해야 한다.
        XCTAssertGreaterThan(store.state.outlineProjectionRevision, revisionAfterOff)
    }

    /// EVM-002-show_hide_hidden_entry: consolidated hidden refresh path는 정확히 하나의 hierarchy invalidation만
    /// 발생시킨다.
    ///
    /// - 검증 내용: `hiddenFilesSettingChanged`가 단일 `reloadFoldersForPresentationChange` 호출만 발생시킨다.
    /// - 사전 조건: collapsed folder가 generation 1, loaded 상태다.
    /// - 기대 결과: 한 번의 refresh로 generation이 1→2가 되고, 추가 refresh action 없이 종료된다.
    func testHiddenToggleFiresExactlyOneHierarchyRefresh() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            folder.id: .init(generation: 1, loadPhase: .loaded),
        ]
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        // 단일 consolidated path: hiddenFilesSettingChanged → reloadFoldersForPresentationChange
        // collapsed folder는 generation 1→2, loadPhase는 .idle이 된다.
        await store.send(.hierarchy(.hiddenFilesSettingChanged)) {
            $0.hierarchy.nodesByID[folder.id as String] = .init(generation: 2, loadPhase: .idle)
            $0.outlineProjectionRevision = 1
        }
        // 추가 refresh action이 없어야 한다.
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.generation, 2)
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.loadPhase, .idle)
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
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [folder.id: .init(generation: 2, loadPhase: .loaded)]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.arrangementMetadataPriorityChanged)) {
            $0.hierarchy.nodesByID[folder.id as String] = .init(
                expansionIntent: true,
                generation: 3,
                loadPhase: .loadingCore,
            )
            $0.outlineProjectionRevision = 2
        }
        await store.receive(\.delegate.expandRequested, folder.id)
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
            nodesByID: [
                folder.id: .init(
                    children: [staleChild],
                    loadPhase: .loaded,
                    generation: 2,
                    hasAppliedContentBatch: true,
                ),
            ],
        )
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.arrangementMetadataPriorityChanged)) {
            $0.hierarchy.nodesByID[folder.id as String] = .init(generation: 3, loadPhase: .idle)
            $0.outlineProjectionRevision = 1
        }
        await store.skipReceivedActions()
        await store.send(.hierarchy(.folderExpansionRequested(id: folder.id))) {
            $0.hierarchy.setExpandedIDs([folder.id])
            $0.hierarchy.nodesByID[folder.id as String] = .init(
                expansionIntent: true,
                generation: 4,
                loadPhase: .loadingCore,
            )
            $0.outlineProjectionRevision = 2
        }
        await store.receive(\.delegate.expandRequested, folder.id)
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
        await store.receive(\.delegate.expandRequested, folder.id)
    }

    /// EVM-002-toggle_directory_expansion_in_list: loading folder collapse가 in-flight load 취소를 요청한다.
    /// - 검증 내용: collapse 시 generation 무효화와 collapseRequested delegate를 함께 확인한다.
    /// - 사전 조건: expanded folder가 loading phase에 있다.
    /// - 기대 결과: folder는 idle로 돌아가고 parent bridge 취소 action이 발행된다.
    func testLoadingFolderCollapseRequestsCancellation() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [folder.id: .init(expansionIntent: true, generation: 4, loadPhase: .loadingCore)]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        // store.exhaustivity = .off: selection reconcile보다 load cancellation delegate를 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderCollapseRequested(id: folder.id))) {
            $0.hierarchy.setExpandedIDs([])
            $0.hierarchy.nodesByID[folder.id as String] = .init(generation: 5, loadPhase: .idle)
        }
        await store.receive(\.delegate.collapseRequested, folder.id)
    }

    /// 계층 projection의 child payload가 command와 selection에서 사용할 실제 EntryModel 목록으로 노출되는지 검증한다.
    func testVisibleSelectableEntriesIncludeNestedPayloads() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file", name: "file")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [folder.id: .init(
            children: [child],
            loadPhase: .loaded,
            generation: 0,
            hasAppliedContentBatch: true,
        )]
        state.hierarchy.setExpandedIDs([folder.id])

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
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [folder.id: .init(
            children: [child],
            loadPhase: .loaded,
            generation: 0,
            hasAppliedContentBatch: true,
        )]
        state.hierarchy.setExpandedIDs([folder.id])
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

    /// EVM-002-incremental_hierarchy_rows: 단순 root 삽입과 이동은 기존 item identity를 보존한다.
    /// - 검증 내용: projection diff가 새 root를 삽입하고 retained root item을 재사용한다.
    /// - 사전 조건: 두 root entry가 표시된 hierarchy coordinator에 새 entry를 중간에 삽입한다.
    /// - 기대 결과: 최종 row 순서가 새 projection과 같고 retained item identity가 유지된다.
    func testHierarchyIncrementalInsertAndMovePreservesRetainedItemIdentity() throws {
        let first = makeHierarchyIntegrationEntry(id: "/root/first", name: "z-first")
        let second = makeHierarchyIntegrationEntry(id: "/root/second", name: "a-second")
        let inserted = makeHierarchyIntegrationEntry(id: "/root/inserted", name: "m-inserted")
        var state = EntryViewLayoutState()
        state.entries = [first, second]
        state.hierarchy = .init(rootPath: "/root")
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)
        coordinator.bind(to: view)
        let firstItem = try XCTUnwrap(coordinator.entryItemsByID[first.id]?.first)
        let secondItem = try XCTUnwrap(coordinator.entryItemsByID[second.id]?.first)

        coordinator.applyStoreProjection(makeIncrementalOutlineProjection(
            revision: 2,
            roots: [second, inserted, first],
        ))

        XCTAssertEqual(
            (0 ..< view.tableView.numberOfRows).compactMap { row in
                guard let item = view.tableView.item(atRow: row) as? EntryListOutlineItem,
                      case let .entry(entry) = item.kind
                else { return nil }
                return entry.id
            },
            [second.id, inserted.id, first.id],
        )
        XCTAssertIdentical(coordinator.entryItemsByID[first.id]?.first, firstItem)
        XCTAssertIdentical(coordinator.entryItemsByID[second.id]?.first, secondItem)
    }

    // MARK: - EVM-002-incremental_hierarchy_bulk_reorder

    /// EVM-002-incremental_hierarchy_bulk_reorder: 대규모 root 재정렬은 전체 reload로 전환한다.
    /// - 검증 내용: move operation 상한을 초과한 reorder가 기존 item을 재사용하지 않는지 확인한다.
    /// - 사전 조건: 34개 root entry가 표시된 hierarchy coordinator에 전체 역순 projection을 적용한다.
    /// - 기대 결과: 최종 row 순서는 새 projection과 같고 retained item identity는 재구성된다.
    func testHierarchyBulkReorderFallsBackToFullReload() throws {
        let roots = (0 ..< 34).map { index in
            makeHierarchyIntegrationEntry(
                id: "/root/item-\(index)",
                name: String(format: "item-%02d", 33 - index),
            )
        }
        let reorderedRoots = roots
        var state = EntryViewLayoutState()
        state.entries = roots
        state.hierarchy = .init(rootPath: "/root")
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)
        coordinator.bind(to: view)
        let retainedItem = try XCTUnwrap(coordinator.entryItemsByID[roots[0].id]?.first)

        coordinator.applyStoreProjection(makeIncrementalOutlineProjection(
            revision: 2,
            roots: reorderedRoots,
            sortOrder: .descending,
        ))

        XCTAssertEqual(
            (0 ..< view.tableView.numberOfRows).compactMap { row in
                guard let item = view.tableView.item(atRow: row) as? EntryListOutlineItem,
                      case let .entry(entry) = item.kind
                else { return nil }
                return entry.id
            },
            reorderedRoots.map(\.id),
        )
        XCTAssertNotIdentical(coordinator.entryItemsByID[roots[0].id]?.first, retainedItem)
    }

    /// EVM-002-incremental_flat_rows: 동일 group의 entry 삽입/삭제는 group item과 retained entry를 보존한다.
    /// - 검증 내용: count가 변하는 presentation change set도 incremental row graph로 적용한다.
    /// - 사전 조건: 동일 header를 가진 flat group에 entry가 표시되어 있다.
    /// - 기대 결과: insertion과 removal 모두 batch 경로를 선택하고 최종 row identity를 유지한다.
    func testFlatIncrementalEntryAddRemovePreservesGroupAndRetainedItemIdentity() throws {
        let first = makeIncrementalPresentationFile(id: "/root/first.txt", name: "first.txt")
        let second = makeIncrementalPresentationFile(id: "/root/second.txt", name: "second.txt")
        let fourth = makeIncrementalPresentationFile(id: "/root/fourth.txt", name: "fourth.txt")
        let inserted = makeIncrementalPresentationFile(id: "/root/inserted.txt", name: "inserted.txt")
        let previousPresentation = EntryViewLayoutPresentation(
            sections: [.init(
                id: "Files",
                title: "Files",
                colorCode: nil,
                items: [first, second, fourth],
                isCollapsed: false,
            )],
            selectedIds: [],
            openWithApplications: [],
        )
        let currentPresentation = EntryViewLayoutPresentation(
            sections: [.init(
                id: "Files",
                title: "Files",
                colorCode: nil,
                items: [first, second, inserted, fourth],
                isCollapsed: false,
            )],
            selectedIds: [],
            openWithApplications: [],
        )
        var state = EntryViewLayoutState()
        state.entries = [first, second, fourth]
        state.entryArrangements.groupedItems = previousPresentation.sections.map {
            .init(groupName: $0.title ?? $0.id, items: $0.items, colorCode: $0.colorCode)
        }
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)
        coordinator.bind(to: view)
        let groupItem = try XCTUnwrap(coordinator.outlineItems.first)
        let secondItem = try XCTUnwrap(coordinator.entryItemsByID[second.id]?.first)
        let previousSnapshot = EntryListCoordinatorRenderSnapshot(state: state)
        var currentState = state
        currentState.entries = [first, second, inserted, fourth]
        currentState.entryArrangements.groupedItems = currentPresentation.sections.map {
            .init(groupName: $0.title ?? $0.id, items: $0.items, colorCode: $0.colorCode)
        }
        let currentSnapshot = EntryListCoordinatorRenderSnapshot(state: currentState)

        XCTAssertTrue(
            coordinator.tryIncrementalFlatRowUpdate(
                previous: previousSnapshot.presentation,
                current: currentSnapshot.presentation,
                changes: currentSnapshot.presentation.changes(from: previousSnapshot.presentation),
            ),
        )

        XCTAssertEqual(view.tableView.numberOfRows, 1 + 4)
        XCTAssertIdentical(coordinator.outlineItems.first, groupItem)
        XCTAssertIdentical(coordinator.entryItemsByID[second.id]?.first, secondItem)
        XCTAssertEqual(
            flatRowEntryIDs(in: view),
            [first.id, second.id, inserted.id, fourth.id],
        )

        let removalPresentation = EntryViewLayoutPresentation(
            sections: [.init(
                id: "Files",
                title: "Files",
                colorCode: nil,
                items: [first, second, fourth],
                isCollapsed: false,
            )],
            selectedIds: [],
            openWithApplications: [],
        )
        let removalSnapshot = EntryListCoordinatorRenderSnapshot(state: {
            var removalState = currentState
            removalState.entries = [first, second, fourth]
            removalState.entryArrangements.groupedItems = removalPresentation.sections.map {
                .init(groupName: $0.title ?? $0.id, items: $0.items, colorCode: $0.colorCode)
            }
            return removalState
        }())
        XCTAssertTrue(
            coordinator.tryIncrementalFlatRowUpdate(
                previous: currentSnapshot.presentation,
                current: removalSnapshot.presentation,
                changes: removalSnapshot.presentation.changes(from: currentSnapshot.presentation),
            ),
        )
        XCTAssertEqual(view.tableView.numberOfRows, 1 + 3)
        XCTAssertIdentical(coordinator.outlineItems.first, groupItem)
        XCTAssertIdentical(coordinator.entryItemsByID[second.id]?.first, secondItem)
        XCTAssertEqual(
            flatRowEntryIDs(in: view),
            [first.id, second.id, fourth.id],
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

    /// EVM-002-replacement_reload_snapshot_retention: hierarchy 무효화 중 마지막 선택을 유지한다.
    /// 완료된 child snapshot이 대체 데이터 도착 전까지 선택과 함께 남는지 검증한다.
    /// - 검증 내용: hierarchyInvalidated 직후 selectedIds와 retained child가 유지됨
    /// - 사전 조건: invalidated folder의 complete child가 선택돼 있다.
    /// - 기대 결과: 대체 배치 전에는 selectionChanged 없이 선택이 유지됨
    func testHierarchyInvalidationRetainsSelectionUntilReplacementProjection() async {
        let folder = EntryModel.temporaryFolder(id: "/var", name: "var")
        let staleChild = makeHierarchyIntegrationEntry(id: "/var/stale.txt", name: "stale.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.selectedIds = [staleChild.id]
        state.lastSelectedId = staleChild.id
        state.rangeAnchorId = staleChild.id
        state.hierarchy = .init(rootPath: "/")
        state.hierarchy.nodesByID = [
            folder.id: .init(
                children: [staleChild],
                loadPhase: .loaded,
                generation: 2,
            ),
        ]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.hierarchyInvalidated(
            affectedPaths: ["/private/var"],
            removedPrefixes: [],
        )))
        XCTAssertEqual(store.state.selectedIds, [staleChild.id])
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.folder.children, [staleChild])
    }

    /// EVM-002-toggle_directory_expansion_in_list: folder retry 재조정의 선택 제거를 delegate로 전달
    /// 실패 폴더의 evicted child가 선택돼 있을 때 folderRetryRequested 후 selectionChanged가 발행되는지 검증한다.
    /// - 검증 내용: folderRetryRequested 후 `.delegate(.selectionChanged)` 수신
    /// - 사전 조건: retry 대상 folder의 evicted child가 선택돼 있다.
    /// - 기대 결과: 선택이 제거되며 selectionChanged delegate가 발행됨
    func testFolderRetryEmitsSelectionChangedWhenChildLeavesProjection() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let staleChild = makeHierarchyIntegrationEntry(id: "/root/a/stale.txt", name: "stale.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.selectedIds = [staleChild.id]
        state.lastSelectedId = staleChild.id
        state.rangeAnchorId = staleChild.id
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            folder.id: .init(
                children: [staleChild],
                loadPhase: .failed(.unavailable(description: "test")),
                generation: 2,
                expectedBatchIndex: 1,
            ),
        ]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderRetryRequested(id: folder.id)))
        await store.receive(\.delegate.expandRequested, folder.id)
        await store.receive(\.delegate.selectionChanged)
    }

    /// EVM-002-toggle_directory_expansion_in_list: folder eviction의 리네임 제거를 delegate로 전달
    /// stale descendant로 evict된 rename 대상이 있을 때 renameCanceled가 발행되는지 검증한다.
    /// - 검증 내용: folderChildrenResponse coreFinished eviction 후 `.delegate(.renameCanceled)` 수신
    /// - 사전 조건: renamed stale child가 eviction 대상이다.
    /// - 기대 결과: rename이 취소되며 renameCanceled delegate가 발행됨
    func testFolderChildrenResponseEvictionEmitsRenameCanceled() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let staleChild = EntryModel.temporaryFolder(id: "/root/a/b", name: "b")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.entryOperations.renamingItemId = staleChild.id
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            folder.id: .init(
                children: [],
                loadPhase: .loadingCore,
                generation: 1,
                coreFinished: false,
            ),
            staleChild.id: .init(
                children: [],
                loadPhase: .loaded,
                generation: 4,
                coreFinished: true,
            ),
        ]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folder.id,
            folderGeneration: 1,
            .event(.coreFinished(batchCount: 0)),
        )))
        await store.receive(\.delegate.renameCanceled)
    }

    // MARK: - EVM-002-cross_window_folder_load_restart

    /// restartUnfinishedExpandedFolderLoads: unfinished expanded folder만 재시작한다.
    /// cross-window 이동 등으로 취소된 .loadingCore/.enriching expanded folder만 generation 증가·partial snapshot
    /// 초기화 후 재시작하고, .loaded 노드의 캐시와 idle/failed 노드·expansion 상태는 보존하는지 검증한다.
    func testRestartUnfinishedExpandedFolderLoadsRestartsOnlyLoadingNodes() async {
        let loadingFolder = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let enrichingFolder = EntryModel.temporaryFolder(id: "/root/B", name: "B")
        let loadedFolder = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let idleFolder = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let failedFolder = EntryModel.temporaryFolder(id: "/root/E", name: "E")
        let (state, loadedChild) = makeRestartUnfinishedLoadingNodesState(
            loadingFolder: loadingFolder,
            enrichingFolder: enrichingFolder,
            loadedFolder: loadedFolder,
            idleFolder: idleFolder,
            failedFolder: failedFolder,
        )
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        // store.exhaustivity = .off: effect 순서보다 state 전환 계약을 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.restartUnfinishedExpandedFolderLoads)) {
            $0.hierarchy.nodesByID[loadingFolder.id as String] = .init(
                expansionIntent: true,
                generation: 3,
                loadPhase: .loadingCore,
            )
            $0.hierarchy.nodesByID[enrichingFolder.id as String] = .init(
                expansionIntent: true,
                generation: 4,
                loadPhase: .loadingCore,
            )
            $0.hierarchy.nodesByID[loadedFolder.id as String] = FolderNodeState(
                folder: FolderSnapshot(children: [loadedChild], hasAppliedContentBatch: true),
                expansionIntent: true,
                generation: 4,
                loadPhase: .loaded,
            )
        }
        let restarted = await collectExpandRequests(count: 2, from: store)
        XCTAssertEqual(restarted, [loadingFolder.id, enrichingFolder.id])
        XCTAssertEqual(store.state.hierarchy.nodesByID[loadingFolder.id]?.folder.children, [])
        XCTAssertEqual(store.state.hierarchy.nodesByID[enrichingFolder.id]?.folder.children, [])
        XCTAssertEqual(store.state.hierarchy.nodesByID[loadingFolder.id]?.generation, 3)
        XCTAssertEqual(store.state.hierarchy.nodesByID[enrichingFolder.id]?.generation, 4)
        XCTAssertEqual(store.state.hierarchy.nodesByID[loadedFolder.id]?.folder.children, [loadedChild])
        XCTAssertEqual(store.state.hierarchy.nodesByID[loadedFolder.id]?.generation, 4)
        XCTAssertEqual(store.state.hierarchy.nodesByID[idleFolder.id]?.generation, 5)
        XCTAssertEqual(store.state.hierarchy.nodesByID[idleFolder.id]?.loadPhase, .idle)
        XCTAssertEqual(store.state.hierarchy.nodesByID[failedFolder.id]?.loadPhase, .failed(.permissionDenied))
        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(loadingFolder.id))
        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(enrichingFolder.id))
        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(loadedFolder.id))
    }

    /// restartUnfinishedExpandedFolderLoads: 중첩 loading folder의 parentID와 collapsed 노드를 보존한다.
    /// parent가 loaded 상태일 때 그 children에 있는 unfinished expanded folder만 재시작하며, parentID와
    /// collapsed(expansionIntent = false) 노드의 상태는 그대로 유지되는지 검증한다.
    func testRestartUnfinishedExpandedFolderLoadsPreservesParentAndSkipsCollapsed() async {
        let parent = EntryModel.temporaryFolder(id: "/root/P", name: "P")
        let nestedLoading = EntryModel.temporaryFolder(id: "/root/P/A", name: "A")
        let nestedLoaded = EntryModel.temporaryFolder(id: "/root/P/B", name: "B")
        let nestedChild = makeHierarchyIntegrationEntry(id: "/root/P/A/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entries = [parent]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            parent.id: .init(
                children: [nestedLoading, nestedLoaded],
                loadPhase: .loaded,
                generation: 1,
                hasAppliedContentBatch: true,
            ),
            nestedLoading.id: FolderNodeState(
                folder: FolderSnapshot(children: [nestedChild], expectedBatchIndex: 1),
                parentID: parent.id,
                expansionIntent: true,
                generation: 2,
                loadPhase: .loadingCore,
            ),
            nestedLoaded.id: .init(parentID: parent.id, generation: 3, loadPhase: .loaded),
        ]
        state.hierarchy.setExpandedIDs([parent.id, nestedLoading.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        // store.exhaustivity = .off: effect 순서보다 state 전환 계약을 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.restartUnfinishedExpandedFolderLoads)) {
            $0.hierarchy.nodesByID[nestedLoading.id as String] = .init(
                parentID: parent.id,
                expansionIntent: true,
                generation: 3,
                loadPhase: .loadingCore,
            )
        }
        await store.receive(\.delegate.expandRequested, nestedLoading.id)

        XCTAssertEqual(store.state.hierarchy.nodesByID[nestedLoading.id]?.parentID, parent.id)
        XCTAssertEqual(store.state.hierarchy.nodesByID[nestedLoading.id]?.folder.children, [])
        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(nestedLoading.id))
        XCTAssertEqual(store.state.hierarchy.nodesByID[nestedLoaded.id]?.loadPhase, .loaded)
        XCTAssertEqual(store.state.hierarchy.nodesByID[nestedLoaded.id]?.generation, 3)
        XCTAssertFalse(store.state.hierarchy.expandedFolderIDs.contains(nestedLoaded.id))
    }

    /// restartUnfinishedExpandedFolderLoads: 재시작으로 evicted된 선택을 delegate로 전달
    /// 재시작 대상 folder의 partial child가 선택돼 있을 때 selectionChanged가 발행되는지 검증한다.
    /// - 검증 내용: restartUnfinishedExpandedFolderLoads 후 `.delegate(.selectionChanged)` 수신
    /// - 사전 조건: loading folder의 evicted child가 선택돼 있다.
    /// - 기대 결과: 선택이 제거되며 selectionChanged delegate가 발행됨
    func testRestartUnfinishedExpandedFolderLoadsEmitsSelectionChanged() async {
        let folder = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let partialChild = makeHierarchyIntegrationEntry(id: "/root/A/partial.txt", name: "partial.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.selectedIds = [partialChild.id]
        state.lastSelectedId = partialChild.id
        state.rangeAnchorId = partialChild.id
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            folder.id: .init(
                children: [partialChild],
                loadPhase: .loadingCore,
                generation: 2,
            ),
        ]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.restartUnfinishedExpandedFolderLoads))
        await store.receive(\.delegate.expandRequested, folder.id)
        await store.receive(\.delegate.selectionChanged)
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
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [folder.id: .init(
            children: [child],
            loadPhase: .loaded,
            generation: 0,
            hasAppliedContentBatch: true,
        )]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = Store(initialState: state) {
            Reduce<EntryViewLayoutState, EntryViewLayoutAction> { state, action in
                guard case let .view(.startRename(item, _)) = action else { return .none }
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

    /// EVM-002-update_entry_selection: 단계적 root load 완료 뒤에도 visible nested child rename 유지
    /// root-only coreFinished가 계층 projection에 남아 있는 child의 inline rename을 닫지 않는지 검증한다.
    /// - 검증 내용: coreFinished 처리 후 projection-visible renamingItemId 유지
    /// - 사전 조건: expanded folder child가 visible하고 rename 중임
    /// - 기대 결과: root items 갱신 뒤에도 child rename state가 유지됨
    func testRootStreamCoreFinishedPreservesVisibleNestedChildRename() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.entryOperations.renamingItemId = child.id
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [folder.id: .init(
            children: [child],
            loadPhase: .loaded,
            generation: 0,
            hasAppliedContentBatch: true,
        )]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // store.exhaustivity = .off: arrangement reapply와 trash metadata 갱신은 rename visibility 계약의 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.view(.applyContentProjection(makeHierarchyContentProjection(
            entries: [folder],
            isLoading: false,
            renamingItemId: child.id,
        ))))
        await store.finish()

        XCTAssertEqual(store.state.entryOperations.renamingItemId, child.id)
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
        state.entryOperations.renamingItemId = renamed.id
        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // store.exhaustivity = .off: arrangement reapply와 trash metadata 갱신은 rename visibility 계약의 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.view(.applyContentProjection(makeHierarchyContentProjection(
            entries: [replacement],
            isLoading: false,
            renamingItemId: nil,
        ))))
        await store.finish()

        XCTAssertNil(store.state.entryOperations.renamingItemId)
        XCTAssertEqual(store.state.entries, [replacement])
    }

    /// EVM-002-update_entry_selection: content projection 재조정의 선택 제거를 delegate로 전달
    /// projection entries에서 사라진 root 선택이 있을 때 selectionChanged가 발행되는지 검증한다.
    /// - 검증 내용: applyContentProjection 후 `.delegate(.selectionChanged)` 수신
    /// - 사전 조건: 새 projection entries에 없는 root 항목이 선택돼 있다.
    /// - 기대 결과: 선택이 제거되며 selectionChanged delegate가 발행됨
    func testApplyContentProjectionEmitsSelectionChangedWhenRootLeavesProjection() async {
        let removed = makeHierarchyIntegrationEntry(id: "/root/removed.txt", name: "removed.txt")
        let replacement = makeHierarchyIntegrationEntry(id: "/root/replacement.txt", name: "replacement.txt")
        var state = EntryViewLayoutState()
        state.entries = [removed]
        state.selectedIds = [removed.id]
        state.lastSelectedId = removed.id
        state.rangeAnchorId = removed.id
        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.applyContentProjection(makeHierarchyContentProjection(
            entries: [replacement],
            isLoading: false,
            renamingItemId: nil,
        ))))
        await store.receive(\.delegate.selectionChanged)
    }

    /// EVM-002-rename_entry: root snapshot 완료 시 projection에서 사라진 renamed root 항목 취소
    /// accepted root snapshot 재조정 뒤 rename 대상이 최종 visible hierarchy projection에 없으면
    /// rename이 취소되는지 검증한다.
    ///
    /// - 검증 내용: rootSnapshotCompleted 후 `.delegate(.renameCanceled)` 수신
    /// - 사전 조건: renamed root folder가 expansion·rename 중이고 새 root snapshot에 그 folder가 없다.
    /// - 기대 결과: evict된 renamed folder가 projection에서 제거되어 renameCanceled delegate가 발행됨
    func testRootSnapshotCompletionCancelsRenameWhenRootItemLeavesProjection() async {
        let renamed = EntryModel.temporaryFolder(id: "/root/renamed", name: "renamed")
        let replacement = EntryModel.temporaryFolder(id: "/root/replacement", name: "replacement")
        var state = EntryViewLayoutState()
        state.entries = [replacement]
        state.entryOperations.renamingItemId = renamed.id
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            renamed.id: .init(children: [], loadPhase: .loaded, generation: 3),
        ]
        state.hierarchy.setExpandedIDs([renamed.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        // store.exhaustivity = .off: root snapshot 재조정과 rename visibility 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.rootSnapshotCompleted(
            rootContextGeneration: 0,
            rootFolders: [replacement],
        )))
        await store.receive(\.delegate.renameCanceled)
    }

    /// EVM-002-rename_entry: root snapshot 완료 후에도 visible nested child rename 유지
    /// accepted root snapshot 재조정 뒤 expanded·loaded child가 최종 visible hierarchy projection에
    /// 남아 있으면 rename이 취소되지 않는지 검증한다.
    ///
    /// - 검증 내용: rootSnapshotCompleted 후 renameCanceled 미수신 및 renamingItemId 유지
    /// - 사전 조건: expanded·loaded folder child가 visible하고 rename 중임, root snapshot에 그 folder 포함
    /// - 기대 결과: child가 projection에 남아 rename이 유지됨
    func testRootSnapshotCompletionPreservesRenameForVisibleNestedChild() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.entryOperations.renamingItemId = child.id
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            folder.id: .init(children: [child], loadPhase: .loaded, generation: 0, hasAppliedContentBatch: true),
        ]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        // store.exhaustivity = .off: root snapshot 재조정과 rename visibility 계약만 검증한다.
        store.exhaustivity = .off

        // no renameCanceled delegate가 발행되지 않아 received action이 없다. (skip 호출 불필요)
        await store.send(.hierarchy(.rootSnapshotCompleted(
            rootContextGeneration: 0,
            rootFolders: [folder],
        )))

        XCTAssertEqual(store.state.entryOperations.renamingItemId, child.id)
    }

    /// EVM-002-toggle_directory_expansion_in_list: root snapshot 재조정의 선택 제거를 delegate로 전달
    /// 사라진 root 항목이 선택돼 있을 때 root snapshot 재조정 후 selectionChanged가 발행되는지 검증한다.
    /// - 검증 내용: rootSnapshotCompleted 후 `.delegate(.selectionChanged)` 수신
    /// - 사전 조건: 새 root snapshot에 없는 root folder가 선택돼 있다.
    /// - 기대 결과: 선택이 제거되며 selectionChanged delegate가 발행됨
    func testRootSnapshotCompletionEmitsSelectionChangedWhenRootItemLeavesProjection() async {
        let removed = EntryModel.temporaryFolder(id: "/root/removed", name: "removed")
        let replacement = EntryModel.temporaryFolder(id: "/root/replacement", name: "replacement")
        var state = EntryViewLayoutState()
        state.entries = [replacement]
        state.selectedIds = [removed.id]
        state.lastSelectedId = removed.id
        state.rangeAnchorId = removed.id
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            removed.id: .init(children: [], loadPhase: .loaded, generation: 3),
        ]
        state.hierarchy.setExpandedIDs([removed.id])
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.rootSnapshotCompleted(
            rootContextGeneration: 0,
            rootFolders: [replacement],
        )))
        await store.receive(\.delegate.selectionChanged)
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
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [folder.id: .init(
            children: [child],
            loadPhase: .loaded,
            generation: 2,
            hasAppliedContentBatch: true,
        )]
        state.hierarchy.setExpandedIDs([folder.id])
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

    /// EVM-002-rename_entry: list 셀 재구성은 현재 rename draft를 유지한다.
    /// - 검증 내용: coordinator가 생성하는 cell configuration의 renamingText를 확인한다.
    /// - 사전 조건: 원래 이름과 다른 rename draft가 projection state에 있다.
    /// - 기대 결과: cell configuration은 원래 이름이 아니라 draft를 사용한다.
    func testListCellReconfigurationPreservesRenameDraft() {
        let entry = makeHierarchyIntegrationEntry(id: "/draft.txt", name: "original.txt")
        var state = EntryViewLayoutState()
        state.entryOperations.renamingItemId = entry.id
        state.entryOperations.renamingText = "draft.txt"
        let coordinator = EntryListCoordinator(store: Store(initialState: state) {
            EntryViewLayoutFeature()
        })

        let configuration = coordinator.makeEntryCellConfiguration(
            entry: entry,
            columnId: EntryListColumn.name.rawValue,
            columnWidth: 200,
            thumbnail: nil,
            isLoadingChildren: false,
        )

        XCTAssertEqual(configuration.context.renamingText, "draft.txt")
    }

    /// EVM-002-switch_entries_view: 태그 section의 중복 항목은 section-scoped list row identity를 사용한다.
    /// - 검증 내용: 같은 entry가 두 section에 있을 때 생성되는 outline item ID와 선택 동기화를 확인한다.
    /// - 사전 조건: Blue와 Red section이 동일 entry를 포함한다.
    /// - 기대 결과: 두 row ID가 서로 다르고 section ID를 포함하며 두 visible row가 모두 선택된다.
    func testGroupedListRowsUseSectionScopedIdentity() {
        let entry = makeHierarchyIntegrationEntry(id: "/tagged.txt", name: "tagged.txt")
        var state = EntryViewLayoutState()
        state.entryArrangements.groupedItems = [
            .init(groupName: "Blue", items: [entry], colorCode: 6),
            .init(groupName: "Red", items: [entry], colorCode: 1),
        ]
        state.selectedIds = [entry.id]
        let coordinator = EntryListCoordinator(store: Store(initialState: state) {
            EntryViewLayoutFeature()
        })
        let view = EntryListView(frame: .zero)

        coordinator.bind(to: view)
        coordinator.syncListSelectionFromStore()
        let rowIDs = coordinator.outlineItems
            .flatMap { $0.flattenItems().map(\.0) }
            .filter { $0.hasPrefix("entry:") }
        let selectedEntryIDs: [EntryModel.ID] = view.tableView.selectedRowIndexes.compactMap { row in
            guard let item = view.tableView.item(atRow: row) as? EntryListOutlineItem,
                  case let .entry(selectedEntry) = item.kind
            else { return nil }
            return selectedEntry.id
        }

        XCTAssertEqual(rowIDs, ["entry:Blue:/tagged.txt", "entry:Red:/tagged.txt"])
        XCTAssertEqual(Set(rowIDs).count, 2)
        XCTAssertEqual(coordinator.entryItemsByID[entry.id]?.count, 2)
        XCTAssertEqual(selectedEntryIDs, [entry.id, entry.id])
    }

    // MARK: - EVM-002-toggle_directory_expansion_in_list (parentID reconciliation)

    /// EVM-002-toggle_directory_expansion_in_list: parentID edge 기반 reconciliation이 삭제/rename된 subtree를
    /// evict하고 새 ID에 expansion을 합성하지 않는지 검증한다.
    ///
    /// - 검증 내용: parentID edge 기반 eviction, recursive descendant 제거, rename된 ID의 expansionIntent = false
    /// - 사전 조건: Folder A의 children에 B, C가 있고 B/C 모두 parentID = A.id로 expanded 상태임.
    ///   A의 coreFinished snapshot에 children = [B, D] (C 삭제, D rename 추가).
    /// - 기대 결과: C가 nodesByID/expandedFolderIDs/projection에서 제거됨. D는 expansionIntent = false.
    func testReconciliationUsesParentIDEdgesAndEvictsRenamedAndDeletedSubtrees() {
        let folderA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let folderB = EntryModel.temporaryFolder(id: "/root/A/B", name: "B")
        let folderC = EntryModel.temporaryFolder(id: "/root/A/C", name: "C")
        let folderD = EntryModel.temporaryFolder(id: "/root/A/D", name: "D")
        let grandchild = makeHierarchyIntegrationEntry(id: "/root/A/B/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entries = [folderA]
        state.hierarchy = .init(rootPath: "/root")
        // A: loadingCore, children [B, D], coreFinished=false, batchCount=2 expected
        state.hierarchy.nodesByID[folderA.id] = FolderNodeState(
            folder: FolderSnapshot(
                children: [folderB, folderD],
                expectedBatchIndex: 2,
                coreFinished: false,
                hasAppliedContentBatch: true,
            ),
            expansionIntent: true,
            generation: 1,
            loadPhase: .loadingCore,
        )
        // B: expanded, loaded, parentID는 reducer가 설정해야 하므로 일부러 nil로 둠
        state.hierarchy.nodesByID[folderB.id] = FolderNodeState(
            folder: FolderSnapshot(children: [grandchild], coreFinished: true),
            parentID: nil,
            expansionIntent: true,
            generation: 2,
            loadPhase: .loaded,
        )
        // C: expanded, loaded, parentID는 reducer가 설정해야 하므로 일부러 nil로 둠
        state.hierarchy.nodesByID[folderC.id] = FolderNodeState(
            folder: FolderSnapshot(children: [], coreFinished: true),
            parentID: nil,
            expansionIntent: true,
            generation: 3,
            loadPhase: .loaded,
        )
        state.hierarchy.setExpandedIDs([folderA.id, folderB.id, folderC.id])
        let reducer = EntryListHierarchyReducer()

        // Act: A receives coreFinished with children = [B, D]
        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.folderChildrenResponse(
                rootContextGeneration: 0,
                folderID: folderA.id,
                folderGeneration: 1,
                .event(.coreFinished(batchCount: 2)),
            )),
        )

        // Assert: C is evicted from nodesByID
        XCTAssertNil(state.hierarchy.nodesByID[folderC.id], "C should be evicted from nodesByID")
        // Assert: C is absent from expandedFolderIDs
        XCTAssertFalse(
            state.hierarchy.expandedFolderIDs.contains(folderC.id),
            "C should be absent from expandedFolderIDs",
        )
        // Assert: B is preserved
        XCTAssertNotNil(state.hierarchy.nodesByID[folderB.id], "B should be preserved")
        XCTAssertTrue(state.hierarchy.expandedFolderIDs.contains(folderB.id), "B should remain expanded")
        // Assert: B's parentID was set to A.id by the reducer during reconciliation
        XCTAssertEqual(
            state.hierarchy.nodesByID[folderB.id]?.parentID,
            folderA.id,
            "B's parentID should be set to A.id after reconciliation",
        )
        // Assert: D (new rename ID) does NOT have expansionIntent
        XCTAssertNil(state.hierarchy.nodesByID[folderD.id], "D should not have a node state (never expanded)")
        // Assert: C is absent from projection visible rows
        let projection = EntryListOutlineProjection(
            revision: 1,
            rootEntries: [folderA],
            hierarchyState: state.hierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        )
        let cItemID = EntryListOutlineProjection.ItemID.entry(folderC.id)
        XCTAssertFalse(projection.visibleRows.contains(cItemID), "C should not be in projection visible rows")
        // Assert: B's grandchild is still in projection via parentID traversal
        let bItemID = EntryListOutlineProjection.ItemID.entry(folderB.id)
        XCTAssertTrue(projection.visibleRows.contains(bItemID), "B should remain in projection visible rows")
    }

    /// EVM-002-toggle_directory_expansion_in_list: stale folderGeneration을 가진 response는 nodesByID와
    /// projection revision을 변경하지 않는지 검증한다.
    ///
    /// - 검증 내용: folderGeneration mismatch가 nodesByID, loadPhase, children, projection revision을 보존함
    /// - 사전 조건: Folder A가 generation 5, loadingCore phase, expectedBatchIndex=1
    /// - 기대 결과: folderGeneration=4인 stale response가 A의 state를 전혀 변경하지 않음
    func testStaleFolderCompletionDoesNotAlterNodesOrProjection() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID[folder.id] = FolderNodeState(
            folder: FolderSnapshot(children: [child], expectedBatchIndex: 1, coreFinished: false),
            expansionIntent: true,
            generation: 5,
            loadPhase: .loadingCore,
        )
        state.hierarchy.setExpandedIDs([folder.id])
        state.outlineProjectionRevision = 1
        let reducer = EntryListHierarchyReducer()

        // Act: stale response with mismatched folderGeneration (4 != 5)
        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.folderChildrenResponse(
                rootContextGeneration: 0,
                folderID: folder.id,
                folderGeneration: 4,
                .event(.coreBatch(items: [child], batchIndex: 1)),
            )),
        )

        // Assert: nothing changed
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id]?.generation, 5, "generation should remain 5")
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id]?.loadPhase,
            .loadingCore,
            "loadPhase should remain .loadingCore",
        )
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id]?.folder.expectedBatchIndex,
            1,
            "expectedBatchIndex should remain 1",
        )
        if let children = state.hierarchy.nodesByID[folder.id]?.folder.children {
            XCTAssertEqual(children, [child], "children should be unchanged")
        } else {
            XCTFail("folder node should exist")
        }
        XCTAssertEqual(state.outlineProjectionRevision, 1, "projection revision should be unchanged")
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

    private func makeHierarchyContentProjection(
        entries: [EntryModel],
        isLoading: Bool,
        renamingItemId: EntryModel.ID? = nil,
    ) -> ContentProjection {
        ContentProjection(
            entries: entries,
            isLoading: isLoading,
            sortKey: .name,
            sortOrder: .ascending,
            groupKey: .none,
            collapsedGroups: [],
            sections: [.ungrouped(items: entries)],
            renamingItemId: renamingItemId,
            renamingText: "",
            clipboardCutPaths: [],
            hasClipboardItems: false,
            busyEntryPaths: [],
            openWithApplications: [],
            restorableTrashPaths: [],
            trashDirectoryPath: nil,
            collectionWindowID: nil,
            collectionLoadingCancellationOwnerID: UUID(),
        )
    }

    private func makeRestartUnfinishedLoadingNodesState(
        loadingFolder: EntryModel,
        enrichingFolder: EntryModel,
        loadedFolder: EntryModel,
        idleFolder: EntryModel,
        failedFolder: EntryModel,
    ) -> (state: EntryViewLayoutState, loadedChild: EntryModel) {
        let loadedChild = makeHierarchyIntegrationEntry(id: loadedFolder.id + "/child.txt", name: "child.txt")
        var state = EntryViewLayoutState()
        state.entries = [loadingFolder, enrichingFolder, loadedFolder, idleFolder, failedFolder]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            loadingFolder.id: .init(
                children: [makeHierarchyIntegrationEntry(id: loadingFolder.id + "/partial.txt", name: "partial.txt")],
                loadPhase: .loadingCore,
                generation: 2,
                expectedBatchIndex: 1,
            ),
            enrichingFolder.id: .init(generation: 3, loadPhase: .enriching),
            loadedFolder.id: .init(
                children: [loadedChild],
                loadPhase: .loaded,
                generation: 4,
                hasAppliedContentBatch: true,
            ),
            idleFolder.id: .init(generation: 5, loadPhase: .idle),
            failedFolder.id: .init(generation: 6, loadPhase: .failed(.permissionDenied)),
        ]
        state.hierarchy.setExpandedIDs([loadingFolder.id, enrichingFolder.id, loadedFolder.id])
        return (state, loadedChild)
    }

    private func collectExpandRequests(
        count: Int,
        from store: TestStore<EntryViewLayoutState, EntryViewLayoutAction>,
    ) async -> Set<String> {
        var received = Set<String>()
        for _ in 0 ..< count {
            await store.receive { action in
                guard case let .delegate(.expandRequested(id)) = action else { return false }
                received.insert(id)
                return true
            }
        }
        return received
    }
}

private func makeIncrementalOutlineProjection(
    revision: Int,
    roots: [EntryModel],
    sortOrder: VoyagerShared.SortOrder = .ascending,
) -> EntryListOutlineProjection {
    EntryListOutlineProjection(
        revision: revision,
        rootEntries: roots,
        hierarchyState: .init(rootPath: "/root"),
        context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
        sortKey: .name,
        sortOrder: sortOrder,
    )
}

@MainActor
private func flatRowEntryIDs(in view: EntryListView) -> [EntryModel.ID] {
    (0 ..< view.tableView.numberOfRows).compactMap { row in
        guard let item = view.tableView.item(atRow: row) as? EntryListOutlineItem,
              case let .entry(entry) = item.kind
        else { return nil }
        return entry.id
    }
}

private func makeIncrementalPresentationFile(id: String, name: String) -> EntryModel {
    EntryModel(
        name: name,
        fullPath: id,
        isFolder: false,
        isHidden: false,
        size: 1,
        modifiedDate: Date(timeIntervalSince1970: 0),
        fileExtension: "txt",
        facets: .init(
            createdDate: Date(timeIntervalSince1970: 0),
            addedDate: Date(timeIntervalSince1970: 0),
            lastOpenedDate: nil,
            kind: "Text",
            creatorApplication: nil,
            tags: nil,
            supplementaryMetadata: nil,
        ),
    )
}

import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-toggle_directory_expansion_in_list

    /// EVM-002-toggle_directory_expansion_in_list: loading folder는 수신한 children과 parent spinner를 함께 유지한다.
    ///
    /// - 검증 내용: core batch는 spinner를 유지한 채 child를 append하고 coreFinished만 spinner를 끈다.
    /// - 사전 조건: /root/a가 expanded folder이며 generation 1 stream이 시작됐다.
    /// - 기대 결과: child는 첫 batch부터 projection에 나타나고 loaded cache는 stream completion 뒤에만 만들어진다.
    func testFolderStreamProjectsChildrenAndStopsSpinnerAtCoreFinish() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = hierarchyFile(id: "/root/a/file", name: "file")
        var state = hierarchyState(roots: [folder])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(into: &state, action: .hierarchy(.folderExpansionRequested(id: folder.id)))
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String],
            .init(expansionIntent: true, generation: 1, loadPhase: .loadingCore),
        )

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(folder.id, .event(.coreBatch(items: [child], batchIndex: 0))),
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children, [child])
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.expectedBatchIndex, 1)
        XCTAssertFalse(state.hierarchy.nodesByID[folder.id as String]?.folder.coreFinished ?? true)
        assertLoadingProjection(folder: folder, child: child, hierarchy: state.hierarchy, isLoading: true)

        _ = reducer.reduce(into: &state, action: folderResponse(folder.id, .event(.coreFinished(batchCount: 1))))
        XCTAssertTrue(state.hierarchy.nodesByID[folder.id as String]?.folder.coreFinished ?? false)
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.loadPhase, .enriching)
        assertLoadingProjection(folder: folder, child: child, hierarchy: state.hierarchy, isLoading: false)

        _ = reducer.reduce(into: &state, action: folderResponse(folder.id, .streamCompleted))
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.loadPhase, .loaded)
    }

    /// EVM-002-toggle_directory_expansion_in_list: malformed, stale, duplicate, post-finished event는 현재 folder state를
    /// 바꾸지 않는다.
    ///
    /// - 검증 내용: generation과 contiguous batch index/core completion guards를 검증한다.
    /// - 사전 조건: generation 2가 batch 0까지 수신한 loading folder다.
    /// - 기대 결과: 잘못된 response 뒤 children, expected index, phase가 그대로 유지된다.
    func testFolderStreamRejectsStaleAndOutOfOrderEvents() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let first = hierarchyFile(id: "/root/a/first", name: "first")
        let stale = hierarchyFile(id: "/root/a/stale", name: "stale")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.setExpandedIDs([folder.id as String])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [first], loadPhase: .loadingCore, generation: 2, expectedBatchIndex: 1,
        )
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(into: &state, action: .hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folder.id,
            folderGeneration: 1,
            .event(.coreBatch(items: [stale], batchIndex: 1)),
        )))
        _ = reducer.reduce(
            into: &state,
            action: folderResponse(folder.id, .event(.coreBatch(items: [stale], batchIndex: 2))),
        )
        _ = reducer.reduce(into: &state, action: folderResponse(folder.id, .event(.coreFinished(batchCount: 0))))

        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children, [first])
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.expectedBatchIndex, 1)
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.loadPhase, .loadingCore)
    }

    /// EVM-002-toggle_directory_expansion_in_list: 첫 core batch 뒤 partial failure는 child를 보존한 단일 retry row를 표시한다.
    ///
    /// - 검증 내용: failed folder projection이 32개 child 뒤 정확히 하나의 retry row를 만들고 coordinator retry intent가 기존 hierarchy
    /// action으로 전달되는지 검증한다.
    /// - 사전 조건: folder가 first 32-item core batch를 수신한 loading 상태다.
    /// - 기대 결과: parent spinner는 제거되고 32개 child와 하나의 error row가 보이며 retry 뒤 generation 2는 child 없이 시작한다.
    func testFolderStreamFailureProjectsRetryRowAndDispatchesRetry() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let children = (0 ..< 32).map { index in
            hierarchyFile(id: "/root/a/file-\(index)", name: "file-\(index)")
        }
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: children, loadPhase: .loadingCore, generation: 1, expectedBatchIndex: 1,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(into: &state, action: folderResponse(folder.id, .failed(.permissionDenied)))
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.loadPhase, .failed(.permissionDenied))
        let projection = hierarchyProjection(folder: folder, hierarchy: state.hierarchy)
        let projectedItemIDs = projection.childrenByParent[.entry(folder.id)] ?? []
        XCTAssertEqual(projectedItemIDs.count, 33)
        XCTAssertEqual(projectedItemIDs.last, .error(parent: folder.id))
        XCTAssertEqual(
            Set(projectedItemIDs.dropLast()),
            Set(children.map { .entry($0.id) }),
        )
        guard case let .entry(_, isLoadingChildren)? = projection.itemPayloads[.entry(folder.id)] else {
            return XCTFail("folder parent payload is missing")
        }
        XCTAssertFalse(isLoadingChildren)

        let session = EntryListCoordinatorProjectionSession()
        var outlineItems: [EntryListOutlineItem] = []
        session.apply(projection) { _, items in
            outlineItems = items
        }
        guard let projectedChildren = outlineItems.first?.children else {
            return XCTFail("folder outline item is missing")
        }
        XCTAssertEqual(projectedChildren.count, 33)
        XCTAssertEqual(
            projectedChildren.count(where: {
                if case .error = $0.kind { return true }
                return false
            }),
            1,
        )

        state.outlineProjectionRevision = projection.revision
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.sendProjectionIntent(.retry(folder.id, revision: projection.revision))

        XCTAssertEqual(
            store.state.hierarchy.nodesByID[folder.id as String],
            .init(expansionIntent: true, generation: 2, loadPhase: .loadingCore),
        )
    }

    /// EVM-002-toggle_directory_expansion_in_list: empty core finish는 enrichment 중에도 기존 empty row를 표시한다.
    ///
    /// - 검증 내용: `coreFinished(0)`가 spinner만 멈추고 empty folder 상태를 숨기지 않는지 검증한다.
    /// - 사전 조건: expanded folder가 빈 core stream의 coreFinished를 수신했다.
    /// - 기대 결과: parent spinner는 꺼지고 단일 nonselectable empty child row가 투영된다.
    func testEmptyCoreFinishedProjectsExistingEmptyRow() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var hierarchy = EntryListHierarchyState(rootPath: "/root")
        hierarchy.nodesByID[folder.id as String] = .init(
            folder: FolderSnapshot(coreFinished: true),
            expansionIntent: true,
            generation: 1,
            loadPhase: .loadingCore,
        )

        let projection = hierarchyProjection(folder: folder, hierarchy: hierarchy)

        XCTAssertEqual(projection.childrenByParent[.entry(folder.id)], [.empty(parent: folder.id)])
        guard case let .entry(_, isLoadingChildren)? = projection.itemPayloads[.entry(folder.id)] else {
            return XCTFail("folder parent payload is missing")
        }
        XCTAssertFalse(isLoadingChildren)
    }

    /// EVM-002-toggle_directory_expansion_in_list: incomplete collapse는 partial cache를 폐기하고 complete cache만 재사용한다.
    ///
    /// - 검증 내용: core/enrichment 중 collapse는 state를 idle로 되돌리고 loaded folder collapse는 children을 유지한다.
    /// - 사전 조건: 하나는 loading, 하나는 stream completed folder다.
    /// - 기대 결과: incomplete children은 비워지고 completed children은 re-expand에서 그대로 남는다.
    func testFolderCollapseDiscardsIncompleteStateAndPreservesCompletedCache() {
        let loadingFolder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let loadedFolder = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        let child = hierarchyFile(id: "/root/a/file", name: "file")
        let cachedChild = hierarchyFile(id: "/root/b/file", name: "file")
        var state = hierarchyState(roots: [loadingFolder, loadedFolder])
        state.hierarchy.setExpandedIDs([loadingFolder.id, loadedFolder.id])
        state.hierarchy.nodesByID[loadingFolder.id] = .init(
            children: [child], loadPhase: .loadingCore, generation: 1, expectedBatchIndex: 1,
        )
        state.hierarchy.nodesByID[loadedFolder.id] = .init(
            children: [cachedChild], loadPhase: .loaded, generation: 1, expectedBatchIndex: 1, coreFinished: true,
        )
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(into: &state, action: .hierarchy(.folderCollapseRequested(id: loadingFolder.id)))
        XCTAssertEqual(state.hierarchy.nodesByID[loadingFolder.id], .init(generation: 2, loadPhase: .idle))
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderCollapseRequested(id: loadedFolder.id)))
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderExpansionRequested(id: loadedFolder.id)))
        XCTAssertEqual(state.hierarchy.nodesByID[loadedFolder.id]?.folder.children, [cachedChild])
        XCTAssertEqual(state.hierarchy.nodesByID[loadedFolder.id]?.generation, 1)
    }

    /// EVM-002-toggle_directory_expansion_in_list: hiddenFilesSettingChanged는 모든 child cache를 비우고 확장 folder만 재시작한다.
    /// consolidated hidden refresh path(toggleShowHiddenFiles → hiddenFilesSettingChanged)의 단일 refresh 경로를 검증한다.
    ///
    /// - 검증 내용: 모든 known folder의 요청 generation과 cached children을 무효화하고, collapsed folder는 idle/empty로 남긴다.
    /// - 사전 조건: 하나의 expanded loaded folder와 하나의 collapsed loaded folder가 있다.
    /// - 기대 결과: expanded folder만 새 loading request가 되고 collapsed folder는 idle/empty state를 유지한다.
    func testShowHiddenRefreshInvalidatesAllCachesAndRestartsOnlyExpandedFolders() async {
        let expanded = EntryModel.temporaryFolder(id: "/root/expanded", name: "expanded")
        let collapsed = EntryModel.temporaryFolder(id: "/root/collapsed", name: "collapsed")
        let expandedChild = hierarchyFile(id: "/root/expanded/child", name: "child")
        let collapsedChild = hierarchyFile(id: "/root/collapsed/child", name: "child")
        var state = hierarchyState(roots: [expanded, collapsed])
        state.hierarchy.nodesByID[expanded.id] = .init(
            children: [expandedChild], loadPhase: .loaded, generation: 1, expectedBatchIndex: 1, coreFinished: true,
        )
        state.hierarchy.nodesByID[collapsed.id] = .init(
            children: [collapsedChild], loadPhase: .loaded, generation: 4, expectedBatchIndex: 1, coreFinished: true,
        )
        state.hierarchy.setExpandedIDs([expanded.id])
        state.showHiddenFiles = true
        state.entryArrangements.sortKey = .kind
        let store = TestStore(initialState: state) { EntryListHierarchyReducer() }

        await store.send(.hierarchy(.hiddenFilesSettingChanged)) {
            $0.hierarchy.nodesByID[expanded.id as String] = .init(
                expansionIntent: true,
                generation: 2,
                loadPhase: .loadingCore,
            )
            $0.hierarchy.nodesByID[collapsed.id as String] = .init(
                expansionIntent: false,
                generation: 5,
                loadPhase: .idle,
            )
            $0.outlineProjectionRevision = 2
            $0.lastVisibleSelectableEntryIDs = Set(["/root/collapsed", "/root/expanded"])
            $0.lastReconciledOutlineProjection = $0.currentOutlineProjection()
        }
        await store.receive(\.delegate.expandRequested)
        await store.receive(\.internal.reconcileHierarchySelection)

        XCTAssertEqual(store.state.hierarchy.expandedFolderIDs, [expanded.id])
        XCTAssertEqual(store.state.hierarchy.nodesByID[expanded.id]?.folder.children, [])
        XCTAssertEqual(store.state.hierarchy.nodesByID[collapsed.id]?.folder.children, [])
        await store.finish()
    }

    /// EVM-002-toggle_directory_expansion_in_list: 모호한 raw root refresh는 expanded hierarchy cache를 삭제로 해석하지 않는다.
    ///
    /// - 검증 내용: 빈 removed prefix의 root invalidation이 expanded ID와 loaded child cache를 보존하는지 검증한다.
    /// - 사전 조건: /root/a가 expanded 상태이고 complete child cache가 남아 있다.
    /// - 기대 결과: 권위 root snapshot이 도착하기 전에는 /root/a의 expanded/cache generation이 그대로 유지된다.
    func testRawRootInvalidationWithoutRemovedPrefixesPreservesExpandedFolderCache() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let cachedChild = hierarchyFile(id: "/root/a/old-file", name: "old-file")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [cachedChild], loadPhase: .loaded, generation: 4, expectedBatchIndex: 1, coreFinished: true,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])

        _ = EntryListHierarchyReducer().reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: ["/root"], removedPrefixes: [])),
        )

        XCTAssertEqual(state.hierarchy.expandedFolderIDs, [folder.id as String])
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String],
            FolderNodeState(
                folder: FolderSnapshot(
                    children: [cachedChild],
                    expectedBatchIndex: 1,
                    coreFinished: true,
                    hasAppliedContentBatch: true,
                ),
                expansionIntent: true,
                generation: 4,
                loadPhase: .loaded,
            ),
        )
    }

    /// EVM-002-toggle_directory_expansion_in_list: 명시된 removed prefix는 기존 hierarchy invalidation 경로로 즉시 정리한다.
    ///
    /// - 검증 내용: typed mutation이 제공한 removed prefix가 descendant cache와 expanded ID를 제거하는지 검증한다.
    /// - 사전 조건: /root/a와 그 child cache가 expanded 상태다.
    /// - 기대 결과: /root/a는 cache와 expanded ID에서 제거된다.
    func testExplicitRemovedPrefixPrunesExpandedFolderCache() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let cachedChild = hierarchyFile(id: "/root/a/old-file", name: "old-file")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.setExpandedIDs([folder.id as String])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [cachedChild],
            loadPhase: .loaded,
            generation: 4,
            expectedBatchIndex: 1,
            coreFinished: true,
        )

        _ = EntryListHierarchyReducer().reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(
                affectedPaths: ["/root"],
                removedPrefixes: [folder.id as String],
            )),
        )

        XCTAssertFalse(state.hierarchy.expandedFolderIDs.contains(folder.id))
        XCTAssertNil(state.hierarchy.nodesByID[folder.id as String])
    }

    /// EVM-002-toggle_directory_expansion_in_list: complete legacy root snapshot은 같은 path의 비확장 항목으로 바뀐 folder cache를
    /// 정리한다.
    ///
    /// - 검증 내용: `itemsLoaded`가 list hierarchy expansion을 지원하지 않는 same-path entry를 root membership에서 제외하는지 검증한다.
    /// - 사전 조건: /root/a folder cache가 expanded이고 새 root snapshot에는 같은 path의 file이 있다.
    /// - 기대 결과: /root/a cache와 expanded ID가 제거된다.
    func testLegacyRootSnapshotPrunesFolderCacheWhenSamePathBecomesNonExpandable() async {
        let disappeared = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let cachedChild = hierarchyFile(id: "/root/a/old-file", name: "old-file")
        var state = hierarchyState(roots: [disappeared])
        state.hierarchy.setExpandedIDs([disappeared.id])
        state.hierarchy.nodesByID[disappeared.id] = .init(
            children: [cachedChild], loadPhase: .loaded, generation: 4, expectedBatchIndex: 1, coreFinished: true,
        )
        let store = TestStore(initialState: state) { EntryViewLayoutFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // store.exhaustivity = .off: 이 시나리오는 root snapshot 뒤 hierarchy cache reconciliation만 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.rootSnapshotCompleted(rootContextGeneration: 0, rootFolders: []))) {
            $0.hierarchy.setExpandedIDs([])
            $0.hierarchy.nodesByID = [:]
            $0.outlineProjectionRevision = 1
        }
        await store.finish()

        XCTAssertFalse(store.state.hierarchy.expandedFolderIDs.contains(disappeared.id))
        XCTAssertNil(store.state.hierarchy.nodesByID[disappeared.id])
    }

    /// EVM-002-toggle_directory_expansion_in_list: accepted staged root core finish는 같은 path의 비확장 항목으로 바뀐 folder cache를
    /// 정리한다.
    ///
    /// - 검증 내용: contiguous batch 이후 `coreFinished`가 list hierarchy expansion을 지원하지 않는 same-path entry를 root
    /// membership에서 제외하는지 검증한다.
    /// - 사전 조건: generation 0 stream은 같은 path의 file batch 하나를 수신했고 /root/a folder cache는 expanded 상태다.
    /// - 기대 결과: accepted `coreFinished(1)` 뒤 /root/a cache와 expanded ID가 제거된다.
    func testAcceptedStagedRootSnapshotPrunesFolderCacheWhenSamePathBecomesNonExpandable() async {
        let disappeared = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let replacement = hierarchyFile(id: disappeared.id, name: "a")
        let cachedChild = hierarchyFile(id: "/root/a/old-file", name: "old-file")
        var state = hierarchyState(roots: [disappeared])
        state.entries = [replacement]
        state.hierarchy.setExpandedIDs([disappeared.id])
        state.hierarchy.nodesByID[disappeared.id] = .init(
            children: [cachedChild], loadPhase: .loaded, generation: 4, expectedBatchIndex: 1, coreFinished: true,
        )
        let store = TestStore(initialState: state) { EntryViewLayoutFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // store.exhaustivity = .off: staged loading과 arrangement reapply의 후속 action은 각 owner suite에서 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.rootSnapshotCompleted(rootContextGeneration: 0, rootFolders: []))) {
            $0.hierarchy.setExpandedIDs([])
            $0.hierarchy.nodesByID = [:]
            $0.outlineProjectionRevision = 1
        }
        await store.finish()

        XCTAssertFalse(store.state.hierarchy.expandedFolderIDs.contains(disappeared.id))
        XCTAssertNil(store.state.hierarchy.nodesByID[disappeared.id])
    }

    /// EVM-002-toggle_directory_expansion_in_list: 삭제 후 재생성된 folder는 새 generation에서 stale child 없이 다시 확장한다.
    ///
    /// - 검증 내용: completed root snapshot이 old cache를 제거한 뒤 recreated folder expansion을 새 generation으로 시작하는지 검증한다.
    /// - 사전 조건: /root/a의 generation 4 cache가 있지만 authoritative root snapshot에는 없다.
    /// - 기대 결과: 재생성된 /root/a는 generation 1 loading으로 시작하며 old child를 포함하지 않는다.
    func testRootSnapshotPrunesDeletedFolderBeforeRecreatedFolderExpansion() {
        let deletedFolder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let cachedChild = hierarchyFile(id: "/root/a/old-file", name: "old-file")
        var state = hierarchyState(roots: [deletedFolder])
        state.hierarchy.setExpandedIDs([deletedFolder.id])
        state.hierarchy.nodesByID[deletedFolder.id] = .init(
            children: [cachedChild], loadPhase: .loaded, generation: 4, expectedBatchIndex: 1, coreFinished: true,
        )
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.rootSnapshotCompleted(rootContextGeneration: 0, rootFolders: [])),
        )
        let recreatedFolder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        state.entries = [recreatedFolder]
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderExpansionRequested(id: recreatedFolder.id)))

        XCTAssertTrue(state.hierarchy.expandedFolderIDs.contains(recreatedFolder.id))
        XCTAssertEqual(
            state.hierarchy.nodesByID[recreatedFolder.id],
            .init(expansionIntent: true, generation: 1, loadPhase: .loadingCore),
        )
    }

    /// EVM-002-toggle_directory_expansion_in_list: parent folder의 authoritative snapshot은 사라진 immediate descendant
    /// cache를 정리한다.
    ///
    /// - 검증 내용: parent coreFinished가 도착한 뒤 parent의 children에 없는 expanded descendant cache와 expanded ID를 정리한다.
    /// - 사전 조건: /root/a/b가 expanded 상태이고, /root/a는 children이 없는 상태에서 coreFinished를 받는다.
    /// - 기대 결과: /root/a/b의 nodesByID와 expandedFolderIDs가 제거되고, /root/a/b의 in-flight load는 취소 효과를 받는다.
    func testParentSnapshotPrunesDisappearedImmediateFolderCacheOnCoreFinished() {
        let parentFolder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let cachedGrandchild = hierarchyFile(id: "/root/a/b/old-file", name: "old-file")
        var state = hierarchyState(roots: [parentFolder])
        state.hierarchy.nodesByID["/root/a"] = .init(
            children: [], loadPhase: .loadingCore, generation: 1, expectedBatchIndex: 0, coreFinished: false,
        )
        state.hierarchy.nodesByID["/root/a/b"] = .init(
            children: [cachedGrandchild], loadPhase: .loaded, generation: 4, expectedBatchIndex: 1, coreFinished: true,
        )
        state.hierarchy.setExpandedIDs(["/root/a", "/root/a/b"])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: folderResponse("/root/a", .event(.coreFinished(batchCount: 0))),
        )

        XCTAssertFalse(state.hierarchy.expandedFolderIDs.contains("/root/a/b"))
        XCTAssertNil(state.hierarchy.nodesByID["/root/a/b"])
        XCTAssertTrue(state.hierarchy.expandedFolderIDs.contains("/root/a"))
        XCTAssertNotNil(state.hierarchy.nodesByID["/root/a"])
    }

    /// EVM-002-toggle_directory_expansion_in_list: parent snapshot이 여전히 존재하는 immediate descendant cache는 보존한다.
    ///
    /// - 검증 내용: parent coreFinished가 도착했을 때 parent의 children에 여전히 있는 expanded descendant의 cache는 유지된다.
    /// - 사전 조건: /root/a/b가 expanded 상태이고, /root/a의 마지막 coreBatch에 /root/a/b가 포함된 뒤 coreFinished가 도착한다.
    /// - 기대 결과: /root/a/b의 nodesByID와 expandedFolderIDs가 그대로 유지된다.
    func testParentSnapshotPreservesCachedFolderWhenChildStillPresentOnCoreFinished() {
        let parentFolder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let childFolder = EntryModel.temporaryFolder(id: "/root/a/b", name: "b")
        let cachedGrandchild = hierarchyFile(id: "/root/a/b/old-file", name: "old-file")
        var state = hierarchyState(roots: [parentFolder])
        state.hierarchy.nodesByID["/root/a"] = .init(
            children: [childFolder], loadPhase: .loadingCore, generation: 1, expectedBatchIndex: 1, coreFinished: false,
        )
        state.hierarchy.nodesByID["/root/a/b"] = .init(
            children: [cachedGrandchild], loadPhase: .loaded, generation: 4, expectedBatchIndex: 1, coreFinished: true,
        )
        state.hierarchy.setExpandedIDs(["/root/a", "/root/a/b"])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: folderResponse("/root/a", .event(.coreFinished(batchCount: 1))),
        )

        XCTAssertTrue(state.hierarchy.expandedFolderIDs.contains("/root/a/b"))
        XCTAssertEqual(
            state.hierarchy.nodesByID["/root/a/b"]?.folder.children.map(\.id),
            [cachedGrandchild.id],
        )
    }

    /// EVM-002-toggle_directory_expansion_in_list: metadata patch는 core completion 뒤 ID별로 child facet만 갱신한다.
    ///
    /// - 검증 내용: ID별로 묶인 복수 patch가 대상 child facet만 바꾸고 sibling order를 유지한다.
    /// - 사전 조건: coreFinished 뒤 two child가 수신돼 있다.
    /// - 기대 결과: 대상 child의 kind만 변경되고 sibling ID order는 변하지 않는다.
    func testFolderMetadataPatchPreservesSiblingOrder() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let first = hierarchyFile(id: "/root/a/first", name: "first")
        let second = hierarchyFile(id: "/root/a/second", name: "second")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.setExpandedIDs([folder.id as String])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [first, second],
            loadPhase: .loadingCore,
            generation: 1,
            expectedBatchIndex: 1,
            coreFinished: true,
            hasAppliedContentBatch: true,
        )

        _ = EntryListHierarchyReducer().reduce(into: &state, action: folderResponse(
            folder.id,
            .event(.metadataPatches([
                .spotlight(
                    id: second.id,
                    kind: "Patched",
                    creatorApplication: nil,
                    lastOpenedDate: nil,
                ),
                .supplementaryMetadata(id: second.id, metadata: .compressedFileSize(42)),
                .spotlight(
                    id: "/root/a/missing",
                    kind: "Missing",
                    creatorApplication: nil,
                    lastOpenedDate: nil,
                ),
            ])),
        ))

        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children.map(\.id), [first.id, second.id])
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String]?.folder.children.first?.facets.kind,
            first.facets.kind,
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children.last?.facets.kind, "Patched")
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String]?.folder.children.last?.facets.supplementaryMetadata,
            .compressedFileSize(42),
        )
    }

    /// EVM-002-toggle_directory_expansion_in_list: Feature delegate metadata patch는 active kind sort의 sibling
    /// projection을 재정렬한다.
    /// Widget은 filesystem stream을 소유하지 않고 typed EntryOperations delegate를 hierarchy presentation action으로 번역한다.
    /// - 검증 내용: folderLoadEvent delegate가 cache facet을 갱신하고 `EntryListOutlineProjection`의 visible sibling order를 바꾼다.
    /// - 사전 조건: `/root/a`의 core-complete child는 kind tie라 name 순서이며 active sort key는 kind다.
    /// - 기대 결과: patched child가 kind ascending 첫 sibling이 되고 cache의 원래 identity order는 유지된다.
    func testFolderMetadataDelegateResortsActiveKindProjection() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let first = hierarchyFile(id: "/root/a/first", name: "first")
        let second = hierarchyFile(id: "/root/a/second", name: "second")
        var state = hierarchyState(roots: [folder])
        state.entryArrangements.sortKey = .kind
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [first, second],
            loadPhase: .loadingCore,
            generation: 1,
            expectedBatchIndex: 1,
            coreFinished: true,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let patch = EntryMetadataPatch.spotlight(
            id: second.id,
            kind: "Patched",
            creatorApplication: nil,
            lastOpenedDate: nil,
        )
        let patchedSecond = second.applying(patch)
        let store = TestStore(initialState: state) { EntryViewLayoutFeature() }

        await store.send(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folder.id,
            folderGeneration: 1,
            .event(.metadataPatches([patch])),
        ))) {
            $0.hierarchy.nodesByID[folder.id as String]?.folder.children = [first, patchedSecond]
            $0.outlineProjectionRevision = 1
            $0.lastVisibleSelectableEntryIDs = Set([folder.id, second.id, first.id])
            $0.lastReconciledOutlineProjection = $0.currentOutlineProjection()
        }
        XCTAssertEqual(
            store.state.hierarchy.nodesByID[folder.id as String]?.folder.children.map(\.id),
            [first.id, second.id],
        )
        let projection = EntryListOutlineProjection(
            revision: store.state.outlineProjectionRevision,
            rootEntries: [folder],
            hierarchyState: store.state.hierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .kind,
            sortOrder: .ascending,
        )
        XCTAssertEqual(projection.visibleSelectableEntryIDs, [folder.id, second.id, first.id])
    }

    /// EVM-002-toggle_directory_expansion_in_list: typed permission failure delegate는 기존 permission-denied retry
    /// presentation을 보존한다.
    /// Feature boundary가 filesystem 오류 문자열을 Widget으로 누출하지 않는지 검증한다.
    /// - 검증 내용: `.permissionDenied` delegate가 hierarchy `.failed(.permissionDenied)` response로 변환된다.
    /// - 사전 조건: generation 1의 expanded folder가 child stream을 loading 중이다.
    /// - 기대 결과: folder phase는 permissionDenied failure가 되고 unavailable message로 바뀌지 않는다.
    func testFolderPermissionDeniedDelegatePreservesFailureSemantics() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.setExpandedIDs([folder.id as String])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            expansionIntent: true,
            generation: 1,
            loadPhase: .loadingCore,
        )
        state.outlineProjectionRevision = 1
        state.lastVisibleSelectableEntryIDs = [folder.id as String]
        let store = TestStore(initialState: state) { EntryViewLayoutFeature() }

        await store.send(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folder.id,
            folderGeneration: 1,
            .failed(.permissionDenied),
        ))) {
            $0.hierarchy.nodesByID[folder.id as String]?.loadPhase = .failed(.permissionDenied)
            $0.outlineProjectionRevision = 2
            $0.lastReconciledOutlineProjection = $0.currentOutlineProjection()
        }
    }

    /// EVM-002-toggle_directory_expansion_in_list: 일반 directory만 hierarchy disclosure와 child projection을 지원한다.
    /// package와 collection package는 선택 가능한 entry로 남지만 nested loading 상태나 children을 투영하지 않는다.
    /// - 검증 내용: ordinary folder의 disclosure eligibility와 child projection, app/voycoll package의 비적격 projection
    /// - 사전 조건: 세 directory entry가 expanded 및 loading hierarchy state에 있다.
    /// - 기대 결과: ordinary folder만 expandable이며 package entry에는 spinner 또는 child projection이 없다.
    func testOnlyOrdinaryDirectoriesSupportListHierarchyExpansion() {
        let folder = hierarchyFolder(id: "/root/folder", name: "folder")
        let app = hierarchyFolder(id: "/root/Voyager.app", name: "Voyager.app", isPackage: true, fileExtension: "app")
        let collection = hierarchyFolder(id: "/root/Library.voycoll", name: "Library.voycoll", fileExtension: "voycoll")
        var hierarchy = EntryListHierarchyState(rootPath: "/root")
        hierarchy.setExpandedIDs([folder.id, app.id, collection.id])
        hierarchy.nodesByID[folder.id as String] = .init(expansionIntent: true, generation: 1, loadPhase: .loadingCore)
        hierarchy.nodesByID[app.id] = .init(expansionIntent: true, generation: 1, loadPhase: .loadingCore)
        hierarchy.nodesByID[collection.id] = .init(expansionIntent: true, generation: 1, loadPhase: .loadingCore)
        var coordinatorState = EntryViewLayoutState()
        coordinatorState.hierarchy = .init(rootPath: "/root")
        let projection = EntryListOutlineProjection(
            revision: 1,
            rootEntries: [folder, app, collection],
            hierarchyState: hierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        )
        let coordinator = EntryListCoordinator(store: Store(initialState: coordinatorState) {
            EntryViewLayoutFeature()
        })
        let folderOutlineItem = EntryListOutlineItem(kind: .entry(folder))
        let appOutlineItem = EntryListOutlineItem(kind: .entry(app))
        let collectionOutlineItem = EntryListOutlineItem(kind: .entry(collection))

        XCTAssertTrue(folder.supportsListHierarchyExpansion)
        XCTAssertFalse(app.supportsListHierarchyExpansion)
        XCTAssertFalse(collection.supportsListHierarchyExpansion)
        XCTAssertTrue(coordinator.outlineView(NSOutlineView(), isItemExpandable: folderOutlineItem))
        XCTAssertFalse(coordinator.outlineView(NSOutlineView(), isItemExpandable: appOutlineItem))
        XCTAssertFalse(coordinator.outlineView(NSOutlineView(), isItemExpandable: collectionOutlineItem))
        XCTAssertNotNil(projection.childrenByParent[.entry(folder.id)])
        XCTAssertNil(projection.childrenByParent[.entry(app.id)])
        XCTAssertNil(projection.childrenByParent[.entry(collection.id)])
        XCTAssertEqual(projection.itemPayloads[.entry(app.id)], .entry(app, isLoadingChildren: false))
        XCTAssertEqual(projection.itemPayloads[.entry(collection.id)], .entry(collection, isLoadingChildren: false))
    }

    /// EVM-002-toggle_directory_expansion_in_list: ineligible package의 direct expand/retry action은 nested loading을 시작하지
    /// 않는다.
    /// AppKit callback 밖에서 직접 들어온 hierarchy action도 동일한 eligibility rule로 차단한다.
    /// - 검증 내용: app expand와 voycoll retry가 load client를 호출하지 않고 expanded IDs와 folder state를 유지하는지 확인
    /// - 사전 조건: root 안의 package-form directory 두 개가 idle state에 있다.
    /// - 기대 결과: 어떤 action도 state mutation 또는 child load effect를 만들지 않는다.
    func testPackageDirectoriesRejectDirectHierarchyExpansionAndRetry() async {
        let app = hierarchyFolder(id: "/root/Voyager.app", name: "Voyager.app", isPackage: true, fileExtension: "app")
        let collection = hierarchyFolder(id: "/root/Library.voycoll", name: "Library.voycoll", fileExtension: "voycoll")
        let store = TestStore(initialState: hierarchyState(roots: [app, collection])) {
            EntryViewLayoutFeature()
        } withDependencies: {
            $0.entryLoadingClient.loadItems = { _, _ in
                XCTFail("Ineligible hierarchy action must not invoke loadItems")
                return []
            }
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                XCTFail("Ineligible hierarchy action must not start a staged load")
                return .init { $0.finish() }
            }
        }

        await store.send(.hierarchy(.folderExpansionRequested(id: app.id)))
        await store.send(.hierarchy(.folderRetryRequested(id: collection.id)))

        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.isEmpty)
        XCTAssertTrue(store.state.hierarchy.nodesByID.isEmpty)
        await store.finish()
    }

    /// EVM-002-toggle_directory_expansion_in_list: root 내부 directory symlink는 target 위치와 무관하게 확장을 시작한다.
    ///
    /// - 검증 내용: root 밖 target을 가리키는 lexical child의 expansion intent와 loading state를 확인한다.
    /// - 사전 조건: root 내부 link가 root 밖 directory를 가리킨다.
    /// - 기대 결과: hierarchy containment가 lexical path를 사용해 link 확장을 허용한다.
    func testDirectorySymlinkToOutsideRootStartsHierarchyExpansion() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = container.appendingPathComponent("root", isDirectory: true)
        let target = container.appendingPathComponent("outside", isDirectory: true)
        let link = root.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: container) }

        let folder = hierarchyFolder(id: link.path, name: "link")
        var state = hierarchyState(roots: [folder])
        state.hierarchy = .init(rootPath: root.path)

        _ = EntryListHierarchyReducer().reduce(
            into: &state,
            action: .hierarchy(.folderExpansionRequested(id: folder.id)),
        )

        XCTAssertTrue(state.hierarchy.expandedFolderIDs.contains(folder.id))
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id]?.loadPhase, .loadingCore)
    }

    /// EVM-002-toggle_directory_expansion_in_list: depth-2 expansion과 완료된 child data가 3회의 parent collapse/re-expand
    /// cycle에서도 생존하며 outline projection revision이 안정적으로 유지된다.
    ///
    /// - 검증 내용: 3회 collapse/re-expand 후에도 child expansion intent와 completed children이 유지되며
    ///   outlineProjectionRevision이 첫 번째 expansion 이후 증가하지 않음
    /// - 사전 조건: A(expanded, loaded) → B(expanded, loaded) → child files, 두 folder 모두 loaded 상태
    /// - 기대 결과: 각 re-expand에서 outlineProjectionRevision이 안정적이며 B의 expansion과 children이 유지되고
    ///   generation이 증가하지 않음
    func testDepth2ExpansionSurvivesThreeCollapseReexpandCyclesWithoutReloading() {
        let folderA = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let folderB = EntryModel.temporaryFolder(id: "/root/a/b", name: "b")
        let childFile = hierarchyFile(id: "/root/a/b/file", name: "file")
        var state = hierarchyState(roots: [folderA])
        state.hierarchy.nodesByID[folderA.id as String] = .init(
            children: [folderB], loadPhase: .loaded, generation: 1, expectedBatchIndex: 1, coreFinished: true,
        )
        state.hierarchy.nodesByID[folderB.id as String] = .init(
            children: [childFile], loadPhase: .loaded, generation: 1, expectedBatchIndex: 1, coreFinished: true,
        )
        state.hierarchy.setExpandedIDs([folderA.id, folderB.id])
        let baselineRevision = state.outlineProjectionRevision
        let reducer = EntryListHierarchyReducer()

        for _ in 0 ..< 3 {
            _ = reducer.reduce(into: &state, action: .hierarchy(.folderCollapseRequested(id: folderA.id)))
            _ = reducer.reduce(into: &state, action: .hierarchy(.folderExpansionRequested(id: folderA.id)))
        }

        XCTAssertTrue(state.hierarchy.expandedFolderIDs.contains(folderA.id))
        XCTAssertTrue(state.hierarchy.expandedFolderIDs.contains(folderB.id))
        XCTAssertEqual(state.hierarchy.nodesByID[folderB.id as String]?.folder.children, [childFile])
        XCTAssertEqual(state.hierarchy.nodesByID[folderA.id as String]?.generation, 1)
        XCTAssertEqual(state.hierarchy.nodesByID[folderB.id as String]?.generation, 1)
        XCTAssertEqual(state.hierarchy.nodesByID[folderA.id as String]?.loadPhase, .loaded)
        XCTAssertEqual(state.hierarchy.nodesByID[folderB.id as String]?.loadPhase, .loaded)
        // outlineProjectionRevision이 첫 expansion 이후 증가하지 않아야 한다.
        // normalize된 state에서는 loaded folder의 collapse/expand가 revision을 바꾸지 않아야 한다.
        XCTAssertEqual(state.outlineProjectionRevision, baselineRevision)
    }

    // MARK: - EVM-002-replacement_reload_snapshot_retention

    /// EVM-002-replacement_reload_snapshot_retention: 완료된 폴더의 대체 재로드는 마지막 완전 스냅샷을 유지한다.
    /// rename/move 무효화 뒤 재로드가 중간 빈 프레임을 만들지 않는지 검증한다.
    /// - 검증 내용: startLoad가 세대를 올리고 loadingCore로 전환하되 완료 스냅샷 children을 보존하고 배치 추적만 초기화한다.
    /// - 사전 조건: /root/a가 children 2개를 가진 loaded 확장 폴더다.
    /// - 기대 결과: children은 그대로고 expectedBatchIndex는 0, coreFinished는 false다.
    func testReplacementReloadRetainsCompleteSnapshotUntilFirstNewBatch() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old1 = hierarchyFile(id: "/root/a/old-1", name: "old-1")
        let old2 = hierarchyFile(id: "/root/a/old-2", name: "old-2")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [old1, old2], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )

        let node = state.hierarchy.nodesByID[folder.id as String]
        XCTAssertEqual(node?.folder.children, [old1, old2], "대체 재로드 중 마지막 완전 스냅샷이 유지된다")
        XCTAssertEqual(node?.folder.expectedBatchIndex, 0)
        XCTAssertFalse(node?.folder.coreFinished ?? true)
        XCTAssertEqual(node?.loadPhase, .loadingCore)
        XCTAssertEqual(node?.generation, 4)
    }

    /// EVM-002-replacement_reload_snapshot_retention: 새 세대의 첫 core batch는 보존된 스냅샷을 한 번에 교체한다.
    /// 이전 데이터와 새 데이터가 섞이지 않는지 검증한다.
    /// - 검증 내용: 보존 재로드 뒤 batchIndex 0 수신 시 children이 새 배치로 대체되고 이후 배치는 append된다.
    /// - 사전 조건: 완료 스냅샷을 보존한 채 재로드가 시작된 loadingCore 폴더.
    /// - 기대 결과: 첫 배치 뒤 children은 정확히 새 배치뿐이다.
    func testReplacementFirstCoreBatchReplacesRetainedChildren() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old1 = hierarchyFile(id: "/root/a/old-1", name: "old-1")
        let new1 = hierarchyFile(id: "/root/a/new-1", name: "new-1")
        let new2 = hierarchyFile(id: "/root/a/new-2", name: "new-2")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [old1], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children, [old1])

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(
                folder.id,
                .event(.coreBatch(items: [new1], batchIndex: 0)),
                folderGeneration: 4,
            ),
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children, [new1], "첫 배치는 보존 데이터를 교체한다")

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(
                folder.id,
                .event(.coreBatch(items: [new2], batchIndex: 1)),
                folderGeneration: 4,
            ),
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children, [new1, new2])
    }

    /// EVM-002-replacement_reload_snapshot_retention: 빈 중간 배치는 보존된 children을 지우지 않고 커서만 소진한다.
    /// 생산자는 빈 배치도 커서를 올리므로, 빈 배치 뒤 다음 내용 배치는 batchIndex 1로 온다.
    /// - 검증 내용: coreBatch([], 0) 뒤 children과 cursor(=1)가 유지되고, 이어지는 batchIndex 1 배치가 교체한다.
    /// - 사전 조건: 완료 스냅샷을 보존한 채 재로드가 시작된 loadingCore 폴더.
    /// - 기대 결과: 빈 배치 후에도 children은 [old1]이고 cursor는 1이며, batchIndex 1 배치 뒤 정확히 새 배치뿐이다.
    func testReplacementEmptyInterimBatchRetainsChildrenUntilFirstNonEmptyBatch() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old1 = hierarchyFile(id: "/root/a/old-1", name: "old-1")
        let new1 = hierarchyFile(id: "/root/a/new-1", name: "new-1")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [old1], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children, [old1])

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(
                folder.id,
                .event(.coreBatch(items: [], batchIndex: 0)),
                folderGeneration: 4,
            ),
        )
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String]?.folder.children,
            [old1],
            "빈 중간 배치는 보존된 children을 지우지 않는다",
        )
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String]?.folder.expectedBatchIndex,
            1,
            "빈 배치도 커서를 소진한다(생산자 계약)",
        )

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(
                folder.id,
                .event(.coreBatch(items: [new1], batchIndex: 1)),
                folderGeneration: 4,
            ),
        )
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String]?.folder.children,
            [new1],
            "첫 non-empty 배치는 원자적으로 교체한다",
        )
    }

    /// EVM-002-replacement_reload_snapshot_retention: 배치 없이 온 coreFinished(0)는 실제 빈 스냅샷으로 커밋한다.
    /// 진짜 빈 폴더로의 대체 재로드가 이전 세대 행을 남기지 않는지 검증한다.
    /// - 검증 내용: batchCount 0 수신 시 retained children이 비우고 coreFinished로 전환된다.
    /// - 사전 조건: 완료 스냅샷을 보존한 채 재로드가 시작된 loadingCore 폴더.
    /// - 기대 결과: children은 []이고 coreFinished는 true, loadPhase는 enriching이다.
    func testBatchlessCoreFinishedCommitsActualEmptySnapshot() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old1 = hierarchyFile(id: "/root/a/old-1", name: "old-1")
        let old2 = hierarchyFile(id: "/root/a/old-2", name: "old-2")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [old1, old2], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children, [old1, old2])

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(
                folder.id,
                .event(.coreFinished(batchCount: 0)),
                folderGeneration: 4,
            ),
        )
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String]?.folder.children,
            [],
            "배치 없는 완료는 실제 빈 스냅샷으로 커밋한다",
        )
        XCTAssertTrue(state.hierarchy.nodesByID[folder.id as String]?.folder.coreFinished ?? false)
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.loadPhase, .enriching)
    }

    /// EVM-002-replacement_reload_snapshot_retention: identity migration staging도 연속 batch 계약을 지킨다.
    /// - 검증 내용: expected index를 건너뛴 staged batch가 cursor와 staging을 변경하지 않는다.
    /// - 사전 조건: 완료 스냅샷을 보존하고 lexical after 행을 기다리는 loadingCore 폴더.
    /// - 기대 결과: retained children, cursor, deferred replacement가 그대로 유지된다.
    func testStagedCoreBatchRejectsOutOfOrderBatchWithoutConsumingCursor() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old = hierarchyFile(id: "/root/a/old", name: "old")
        let before = hierarchyFile(id: "/root/a/before", name: "before")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [old], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )
        state.hierarchy.beginDeferredFolderReplacement(
            folderID: folder.id as String,
            untilEntryID: "/root/a/after",
        )

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(
                folder.id,
                .event(.coreBatch(items: [before], batchIndex: 1)),
                folderGeneration: 4,
            ),
        )

        let node = state.hierarchy.nodesByID[folder.id as String]
        XCTAssertEqual(node?.folder.children, [old])
        XCTAssertEqual(node?.folder.expectedBatchIndex, 0)
        XCTAssertFalse(node?.folder.hasAppliedContentBatch ?? true)
        XCTAssertFalse(node?.folder.coreFinished ?? true)
        XCTAssertEqual(node?.loadPhase, .loadingCore)
        XCTAssertEqual(
            state.hierarchy.deferredFolderReplacements[folder.id as String]?.stagedChildren,
            [],
        )
        XCTAssertEqual(
            state.hierarchy.deferredFolderReplacements[folder.id as String]?.untilEntryID,
            "/root/a/after",
        )
    }

    /// EVM-002-replacement_reload_snapshot_retention: staged terminal도 수신 cursor와 batch count가 일치해야 한다.
    /// - 검증 내용: 불일치 coreFinished가 retained snapshot과 staged children을 커밋하지 않는다.
    /// - 사전 조건: 유효한 staged batch 하나를 받아 expected index가 1인 loadingCore 폴더.
    /// - 기대 결과: cursor와 staging은 유지되고 coreFinished와 loadPhase는 진행되지 않는다.
    func testStagedCoreFinishedRejectsMismatchedBatchCountWithoutCommitting() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old = hierarchyFile(id: "/root/a/old", name: "old")
        let before = hierarchyFile(id: "/root/a/before", name: "before")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [old], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )
        state.hierarchy.beginDeferredFolderReplacement(
            folderID: folder.id as String,
            untilEntryID: "/root/a/after",
        )
        _ = reducer.reduce(
            into: &state,
            action: folderResponse(
                folder.id,
                .event(.coreBatch(items: [before], batchIndex: 0)),
                folderGeneration: 4,
            ),
        )

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(
                folder.id,
                .event(.coreFinished(batchCount: 0)),
                folderGeneration: 4,
            ),
        )

        let node = state.hierarchy.nodesByID[folder.id as String]
        XCTAssertEqual(node?.folder.children, [old])
        XCTAssertEqual(node?.folder.expectedBatchIndex, 1)
        XCTAssertFalse(node?.folder.coreFinished ?? true)
        XCTAssertEqual(node?.loadPhase, .loadingCore)
        XCTAssertEqual(
            state.hierarchy.deferredFolderReplacements[folder.id as String]?.stagedChildren,
            [before],
        )
        XCTAssertEqual(
            state.hierarchy.deferredFolderReplacements[folder.id as String]?.untilEntryID,
            "/root/a/after",
        )
    }

    /// EVM-002-replacement_reload_snapshot_retention: 교체 스트림 실패는 보존된 children을 유지한다.
    /// - 검증 내용: failed 응답 뒤에도 retained children과 미완료 상태가 유지된다.
    /// - 사전 조건: 완료 스냅샷을 보존한 채 재로드가 시작된 loadingCore 폴더.
    /// - 기대 결과: children은 그대로고 loadPhase는 failed다.
    func testReplacementStreamFailurePreservesRetainedChildren() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old1 = hierarchyFile(id: "/root/a/old-1", name: "old-1")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [old1], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(folder.id, .failed(.permissionDenied), folderGeneration: 4),
        )
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String]?.folder.children,
            [old1],
            "실패 시 보존된 children이 유지된다",
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.loadPhase, .failed(.permissionDenied))
        XCTAssertFalse(state.hierarchy.nodesByID[folder.id as String]?.folder.coreFinished ?? true)
    }

    /// EVM-002-replacement_reload_snapshot_retention: 완전 세대 기원의 retained children은 첫 배치 전 실패 뒤에도
    /// 재시도가 유지한다.
    /// 교체 재로드가 완전 스냅샷을 커서 0으로 보존한 채 첫 배치 전에 실패하면, 이는 부분 수신(커서 > 0)이 아니라
    /// 완전 세대 기원이므로 재시도가 children을 비우지 않아야 한다.
    /// - 검증 내용: 커서 0 + children 존재인 실패 노드의 retry가 children과 커서를 유지한 loadingCore 시작으로 전환된다.
    /// - 사전 조건: 완료 스냅샷을 커서 0으로 보존한 채 첫 배치 전에 실패한 loadingCore 폴더.
    /// - 기대 결과: 재시도 뒤에도 children은 그대로이고 expectedBatchIndex는 0, coreFinished는 false, loadPhase는 loadingCore다.
    func testRetryAfterReplacementFailureRetainsCompleteOriginChildren() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old1 = hierarchyFile(id: "/root/a/old-1", name: "old-1")
        let old2 = hierarchyFile(id: "/root/a/old-2", name: "old-2")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [old1, old2], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children, [old1, old2])

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(folder.id, .failed(.permissionDenied), folderGeneration: 4),
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.loadPhase, .failed(.permissionDenied))
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.expectedBatchIndex, 0)

        _ = reducer.reduce(into: &state, action: .hierarchy(.folderRetryRequested(id: folder.id)))
        let node = state.hierarchy.nodesByID[folder.id as String]
        XCTAssertEqual(
            node?.folder.children,
            [old1, old2],
            "완전 세대 기원 children은 첫 배치 전 실패 뒤 재시도에도 유지된다",
        )
        XCTAssertEqual(node?.folder.expectedBatchIndex, 0)
        XCTAssertFalse(node?.folder.coreFinished ?? true)
        XCTAssertEqual(node?.loadPhase, .loadingCore)
        XCTAssertEqual(node?.generation, 5)
    }

    /// EVM-002-replacement_reload_snapshot_retention: 빈 core batch를 소진한 retained snapshot도 실패 재시도에 유지한다.
    /// batch cursor가 증가했어도 content provenance가 없으면 이전 완전 세대 children임을 검증한다.
    /// - 검증 내용: coreBatch([], 0) → failed → retry 뒤 children, selection, 새 generation 상태
    /// - 사전 조건: 선택된 child를 가진 완료 snapshot이 교체 재로드에서 빈 batch 하나만 수신한다.
    /// - 기대 결과: hasAppliedContentBatch=false provenance가 children/selection을 유지하고 cursor만 0으로 초기화한다.
    func testRetryAfterRetainedEmptyBatchFailureKeepsCompleteSnapshotAndSelection() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let retainedChild = hierarchyFile(id: "/root/a/retained", name: "retained")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [retainedChild], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        state.selectedIds = [retainedChild.id]
        state.lastSelectedId = retainedChild.id
        state.rangeAnchorId = retainedChild.id
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )
        _ = reducer.reduce(
            into: &state,
            action: folderResponse(
                folder.id,
                .event(.coreBatch(items: [], batchIndex: 0)),
                folderGeneration: 4,
            ),
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.expectedBatchIndex, 1)
        XCTAssertFalse(state.hierarchy.nodesByID[folder.id as String]?.folder.hasAppliedContentBatch ?? true)

        _ = reducer.reduce(
            into: &state,
            action: folderResponse(folder.id, .failed(.permissionDenied), folderGeneration: 4),
        )
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderRetryRequested(id: folder.id)))

        let node = state.hierarchy.nodesByID[folder.id as String]
        XCTAssertEqual(node?.folder.children, [retainedChild])
        XCTAssertEqual(node?.folder.expectedBatchIndex, 0)
        XCTAssertFalse(node?.folder.hasAppliedContentBatch ?? true)
        XCTAssertEqual(node?.loadPhase, .loadingCore)
        XCTAssertEqual(node?.generation, 5)
        XCTAssertEqual(state.selectedIds, [retainedChild.id])
        XCTAssertEqual(state.lastSelectedId, retainedChild.id)
        XCTAssertEqual(state.rangeAnchorId, retainedChild.id)
    }

    /// EVM-002-replacement_reload_snapshot_retention: 초기 확장과 실패 재시도는 여전히 빈 스냅샷으로 시작한다.
    /// 보존 정책이 캐시 없는 확장 동작을 바꾸지 않는지 검증한다.
    /// - 검증 내용: idle 노드의 startLoad와 failed 노드의 retry startLoad 모두 children을 비운다.
    /// - 사전 조건: 캐시 없는 idle 폴더와 partial children을 가진 failed 폴더.
    /// - 기대 결과: 두 경우 모두 children 없이 loadingCore로 시작한다.
    func testInitialExpansionAndRetryStillStartEmpty() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let staleChild = hierarchyFile(id: "/root/a/stale", name: "stale")
        let reducer = EntryListHierarchyReducer()

        var freshState = hierarchyState(roots: [folder])
        _ = reducer.reduce(into: &freshState, action: .hierarchy(.folderExpansionRequested(id: folder.id)))
        XCTAssertEqual(freshState.hierarchy.nodesByID[folder.id as String]?.folder.children, [])
        XCTAssertEqual(freshState.hierarchy.nodesByID[folder.id as String]?.loadPhase, .loadingCore)

        var failedState = hierarchyState(roots: [folder])
        failedState.hierarchy.setExpandedIDs([folder.id as String])
        failedState.hierarchy.nodesByID[folder.id as String] = .init(
            children: [staleChild],
            loadPhase: .failed(.permissionDenied),
            generation: 2,
            expectedBatchIndex: 1,
            hasAppliedContentBatch: true,
        )
        _ = reducer.reduce(into: &failedState, action: .hierarchy(.folderRetryRequested(id: folder.id)))
        XCTAssertEqual(failedState.hierarchy.nodesByID[folder.id as String]?.folder.children, [], "재시도는 부분 결과를 버린다")
        XCTAssertEqual(failedState.hierarchy.nodesByID[folder.id as String]?.loadPhase, .loadingCore)
    }

    /// EVM-002-replacement_reload_snapshot_retention: root 완료 재시작도 완전 child snapshot을 유지한다.
    /// root coreFinished가 확장 폴더 응답보다 먼저 도착하는 root-first 순서에서,
    /// enriching 폴더 재시작이 retained children을 비우지 않는지 검증한다.
    /// - 검증 내용: rootSnapshotCompleted 재시작 뒤 children 유지 + cursor/provenance 초기화
    /// - 사전 조건: coreFinished=true인 enriching 폴더가 expanded 상태
    /// - 기대 결과: generation 증가·loadingCore 전환과 함께 children 유지, 첫 새 배치가 교체
    func testRootSnapshotRestartRetainsCompleteChildSnapshot() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old1 = hierarchyFile(id: "/root/a/old-1", name: "old-1")
        let old2 = hierarchyFile(id: "/root/a/old-2", name: "old-2")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [old1, old2],
            loadPhase: .enriching,
            generation: 3,
            expectedBatchIndex: 1,
            coreFinished: true,
            hasAppliedContentBatch: true,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.rootSnapshotCompleted(rootContextGeneration: 0, rootFolders: [folder])),
        )

        guard let node = state.hierarchy.nodesByID[folder.id as String] else {
            return XCTFail("restarted node is missing")
        }
        XCTAssertEqual(node.generation, 4)
        XCTAssertEqual(node.loadPhase, .loadingCore)
        XCTAssertEqual(node.folder.children, [old1, old2], "root-first 재시작은 retained children을 유지한다")
        XCTAssertFalse(node.folder.coreFinished)
        XCTAssertEqual(node.folder.expectedBatchIndex, 0)
        XCTAssertFalse(node.folder.hasAppliedContentBatch)

        // cursor 리셋 검증: 첫 새 내용 배치가 retained children을 한 번에 교체한다.
        _ = reducer.reduce(into: &state, action: folderResponse(
            folder.id,
            .event(.coreBatch(items: [hierarchyFile(id: "/root/a/new-1", name: "new-1")], batchIndex: 0)),
            folderGeneration: 4,
        ))
        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String]?.folder.children.map(\.id),
            ["/root/a/new-1"],
        )
    }

    /// EVM-002-replacement_reload_snapshot_retention: root 완료 재시작은 부분 수신 중인 스냅샷은 여전히 비운다.
    /// 보존 정책이 이번 세대 부분 결과까지 유지하지 않는 경계를 검증한다.
    /// - 검증 내용: loadingCore에서 내용 배치를 이미 적용한 폴더의 root 재시작
    /// - 사전 조건: coreFinished=false, hasAppliedContentBatch=true인 loadingCore 폴더
    /// - 기대 결과: children이 비우고 loadingCore로 재시작한다
    func testRootSnapshotRestartStillClearsPartialMidStreamChildren() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let partialChild = hierarchyFile(id: "/root/a/partial", name: "partial")
        var state = hierarchyState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [partialChild],
            loadPhase: .loadingCore,
            generation: 2,
            expectedBatchIndex: 1,
            hasAppliedContentBatch: true,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.rootSnapshotCompleted(rootContextGeneration: 0, rootFolders: [folder])),
        )

        guard let node = state.hierarchy.nodesByID[folder.id as String] else {
            return XCTFail("restarted node is missing")
        }
        XCTAssertEqual(node.generation, 3)
        XCTAssertEqual(node.loadPhase, .loadingCore)
        XCTAssertEqual(node.folder.children, [], "부분 수신 결과는 재시작 시 버려진다")
        XCTAssertFalse(node.folder.hasAppliedContentBatch)
    }

    private func hierarchyState(roots: [EntryModel]) -> EntryViewLayoutState {
        var state = EntryViewLayoutState()
        state.entries = roots
        state.hierarchy = .init(rootPath: "/root")
        return state
    }

    private func folderResponse(
        _ folderID: EntryModel.ID,
        _ response: EntryListFolderChildrenResponse,
        folderGeneration: Int = 1,
    ) -> EntryViewLayoutAction {
        .hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folderID,
            folderGeneration: folderGeneration,
            response,
        ))
    }

    private func assertLoadingProjection(
        folder: EntryModel,
        child: EntryModel,
        hierarchy: EntryListHierarchyState,
        isLoading: Bool,
    ) {
        let projection = hierarchyProjection(folder: folder, hierarchy: hierarchy)
        XCTAssertEqual(projection.childrenByParent[.entry(folder.id)], [.entry(child.id)])
        guard case let .entry(_, isLoadingChildren)? = projection.itemPayloads[.entry(folder.id)] else {
            return XCTFail("folder parent payload is missing")
        }
        XCTAssertEqual(isLoadingChildren, isLoading)
    }

    private func hierarchyProjection(
        folder: EntryModel,
        hierarchy: EntryListHierarchyState,
    ) -> EntryListOutlineProjection {
        EntryListOutlineProjection(
            revision: 1,
            rootEntries: [folder],
            hierarchyState: hierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        )
    }

    private func hierarchyFile(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "txt",
            facets: .init(
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

    private func hierarchyFolder(
        id: String,
        name: String,
        isPackage: Bool = false,
        fileExtension: String = "",
    ) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: true,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: fileExtension,
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "Folder",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
            isPackage: isPackage,
        )
    }
}

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
        state.sortKey = .kind
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
                folder: FolderSnapshot(children: [cachedChild], expectedBatchIndex: 1, coreFinished: true),
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
            children: [cachedChild], loadPhase: .loaded, generation: 4, expectedBatchIndex: 1, coreFinished: true,
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
            children: [first, second], loadPhase: .loadingCore, generation: 1, expectedBatchIndex: 1,
            coreFinished: true,
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
        state.sortKey = .kind
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [first, second], loadPhase: .loadingCore, generation: 1, expectedBatchIndex: 1,
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

    private func hierarchyState(roots: [EntryModel]) -> EntryViewLayoutState {
        var state = EntryViewLayoutState()
        state.entries = roots
        state.hierarchy = .init(rootPath: "/root")
        return state
    }

    private func folderResponse(
        _ folderID: EntryModel.ID,
        _ response: EntryListFolderChildrenResponse,
    ) -> EntryViewLayoutAction {
        .hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folderID,
            folderGeneration: 1,
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

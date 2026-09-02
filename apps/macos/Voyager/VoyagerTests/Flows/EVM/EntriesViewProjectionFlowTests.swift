// FLOW-ID: evm.entries_view_projection
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntriesViewProjectionFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.folder_expansion_projects_immediate_children

    /// EVM-002-toggle_directory_expansion_in_list: folder disclosure는 immediate child를 visible outline row로 투영한다.
    /// 사용자가 directory list에서 folder를 펼친 뒤 child가 parent 아래에 표시되는 production composition을 검증한다.
    /// - 검증 내용: FileManagerContentFeature의 hierarchy expansion, staged child stream, visible selectable projection 연결.
    /// - 사전 조건: `/flow/current` list directory에 collapsed folder와 staged child stream이 있다.
    /// - 기대 결과: folder와 immediate child가 보이고 route/history는 expansion 전과 같다.
    func testFolderExpansionProjectsImmediateChildrenWithoutNavigation() async {
        let folder = EntryModel.temporaryFolder(id: "/flow/current/folder", name: "folder")
        let child = entryFile(id: "/flow/current/folder/child", name: "child")
        let store = makeStore(roots: [folder], dependencies: {
            $0.entryLoadingClient.stagedLoadItems = { url, _, _ in
                XCTAssertEqual(url.path, folder.fullPath)
                return Self.stream(events: [
                    .coreBatch(items: [child], batchIndex: 0),
                    .coreFinished(batchCount: 1),
                ])
            }
        })
        // store.exhaustivity = .off: flow는 child projection과 route/history 결과만 검증한다.
        store.exhaustivity = .off

        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        await store.send(.entryViewLayout(.hierarchy(.folderExpansionRequested(id: folder.id))))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(_, folderID, _, response))) = action
            else {
                return false
            }
            return folderID == folder.id
                && response == .event(.coreBatch(items: [child], batchIndex: 0))
        }
        let loadingProjection = outlineProjection(for: store.state.entryViewLayout)
        guard case let .entry(_, isLoadingChildren)? = loadingProjection.itemPayloads[.entry(folder.id)] else {
            return XCTFail("Expected the expanded folder to own the child loading indicator")
        }
        XCTAssertTrue(isLoadingChildren)
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(_, folderID, _, response))) = action
            else {
                return false
            }
            return folderID == folder.id
                && response == .event(.coreFinished(batchCount: 1))
        }
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(_, folderID, _, response))) = action
            else {
                return false
            }
            return folderID == folder.id && response == .streamCompleted
        }

        XCTAssertEqual(
            store.state.entryViewLayout.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
            [folder.id, child.id],
        )
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)

        await store.send(.entryViewLayout(.hierarchy(.folderCollapseRequested(id: folder.id))))
        await store.receive(\.entryViewLayout.internal.reconcileHierarchySelection)

        XCTAssertEqual(
            store.state.entryViewLayout.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
            [folder.id],
        )
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
    }

    // FLOW-PATH: happy_path.root_entries_appear_progressively

    /// EVM-002-view_entry_counts_in_current_page: root entries는 core batch가 도착하는 즉시 visible projection에 나타난다.
    /// 사용자가 directory를 여는 동안 첫 core batch를 받아도 나머지 stream을 기다리지 않고 entry row를 보는 경로를 검증한다.
    /// - 검증 내용: root staged loading의 first-batch event와 Entries View projection 연결.
    /// - 사전 조건: `/flow/current` list directory가 비어 있고 staged root stream이 첫 entry를 먼저 반환한다.
    /// - 기대 결과: 첫 batch 수신 직후 root entry가 표시되고 entry loading blocker가 해제된다.
    func testRootEntriesAppearOnFirstCoreBatch() async {
        let entry = entryFile(id: "/flow/current/first.txt", name: "first.txt")
        let store = makeStore(roots: [], dependencies: {
            $0.entryLoadingClient.stagedLoadItems = { url, _, _ in
                XCTAssertEqual(url.path, "/flow/current")
                return Self.stream(events: [
                    .coreBatch(items: [entry], batchIndex: 0),
                    .coreFinished(batchCount: 1),
                ])
            }
        })
        // store.exhaustivity = .off: flow는 first-batch visible result와 loading feedback만 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.loadItems(
            path: "/flow/current",
            showHidden: false,
        )))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.streamEvent(event)))) = action
            else { return false }
            return event.event == .coreBatch(items: [entry], batchIndex: 0)
        }
        await store.receive(\.entryViewLayout.view.applyContentProjection)

        XCTAssertEqual(store.state.entryViewLayout.entries, [entry])
        XCTAssertFalse(store.state.entryViewLayout.entryOperations.isLoading)
    }

    // FLOW-PATH: happy_path.multiple_folder_expansion_is_independent

    /// EVM-002-toggle_directory_expansion_in_list: 여러 folder disclosure는 서로 독립적으로 child를 투영한다.
    /// 사용자가 한 directory list에서 둘 이상의 folder를 동시에 펼치는 경로를 검증한다.
    /// - 검증 내용: 두 folder의 staged child stream이 각각 visible outline rows로 합쳐진다.
    /// - 사전 조건: `/flow/current` list directory에 두 collapsed folder가 있고 각 child stream이 준비되어 있다.
    /// - 기대 결과: 두 folder와 각 immediate child가 모두 visible selectable dataset에 남는다.
    func testMultipleExpandedFoldersProjectIndependentChildren() async {
        let firstFolder = EntryModel.temporaryFolder(id: "/flow/current/first", name: "first")
        let secondFolder = EntryModel.temporaryFolder(id: "/flow/current/second", name: "second")
        let firstChild = entryFile(id: "/flow/current/first/child", name: "child")
        let secondChild = entryFile(id: "/flow/current/second/child", name: "child")
        let store = makeStore(roots: [firstFolder, secondFolder], dependencies: {
            $0.entryLoadingClient.stagedLoadItems = { url, _, _ in
                let child = url.path == firstFolder.id ? firstChild : secondChild
                return Self.stream(events: [
                    .coreBatch(items: [child], batchIndex: 0),
                    .coreFinished(batchCount: 1),
                ])
            }
        })
        // store.exhaustivity = .off: flow는 독립 folder들의 visible projection만 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderExpansionRequested(id: firstFolder.id))))
        await store.skipReceivedActions()
        await store.send(.entryViewLayout(.hierarchy(.folderExpansionRequested(id: secondFolder.id))))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.entryViewLayout.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
            [firstFolder.id, firstChild.id, secondFolder.id, secondChild.id],
        )
    }

    // FLOW-PATH: alternate_path.collapse_reconciles_visible_selection

    /// EVM-002-update_entry_selection: folder collapse는 hidden descendant를 selection과 selected count에서 제외한다.
    /// 사용자가 expanded child를 선택한 뒤 folder를 접는 경로를 검증한다.
    /// - 검증 내용: collapse 후 visible projection과 current selection reconciliation.
    /// - 사전 조건: `/flow/current/folder/child`가 visible하고 선택된 expanded hierarchy다.
    /// - 기대 결과: child가 visible dataset과 selection에서 사라지고 root folder만 남는다.
    func testFolderCollapseRemovesDescendantFromVisibleSelection() async {
        let folder = EntryModel.temporaryFolder(id: "/flow/current/folder", name: "folder")
        let child = entryFile(id: "/flow/current/folder/child", name: "child")
        let store = makeStore(roots: [folder]) {
            $0.entryViewLayout.hierarchy.nodesByID[folder.id] = .init(
                children: [child],
                loadPhase: .loaded,
                generation: 1,
                expectedBatchIndex: 1,
                coreFinished: true,
            )
            $0.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
            $0.entryViewLayout.selectedIds = [child.id]
            $0.entryViewLayout.lastSelectedId = child.id
            $0.entryViewLayout.rangeAnchorId = child.id
        }
        // store.exhaustivity = .off: flow는 selection reconciliation과 visible projection만 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderCollapseRequested(id: folder.id))))
        await store.receive(\.entryViewLayout.internal.reconcileHierarchySelection)

        XCTAssertEqual(store.state.entryViewLayout.visibleSelectableEntryIDs(isNormalDirectoryPage: true), [folder.id])
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.isEmpty)
    }

    // FLOW-PATH: alternate_path.partial_child_failure_keeps_visible_children

    /// EVM-002-toggle_directory_expansion_in_list: partial child failure는 기존 child와 folder-local retry row를 유지한다.
    /// 사용자가 child loading 중 부분 결과와 실패 상태를 함께 보는 경로를 검증한다.
    /// - 검증 내용: failed folder projection의 visible child 보존과 retry 가능 error row.
    /// - 사전 조건: expanded folder가 child batch 하나를 수신한 뒤 permission failure를 받는다.
    /// - 기대 결과: child는 visible하고 folder-local error row가 추가된다.
    func testPartialChildFailureRetainsChildrenAndLocalRetry() async {
        let folder = EntryModel.temporaryFolder(id: "/flow/current/folder", name: "folder")
        let child = entryFile(id: "/flow/current/folder/child", name: "child")
        let store = makeLayoutStore(roots: [folder])
        // store.exhaustivity = .off: flow는 내부 delegate보다 visible error/retry projection만 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderExpansionRequested(id: folder.id)))
        await store.send(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folder.id,
            folderGeneration: 1,
            .event(.coreBatch(items: [child], batchIndex: 0)),
        )))
        await store.send(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folder.id,
            folderGeneration: 1,
            .failed(.permissionDenied),
        )))

        let projection = outlineProjection(for: store.state)
        XCTAssertEqual(projection.visibleSelectableEntryIDs, [folder.id, child.id])
        XCTAssertEqual(projection.childrenByParent[.entry(folder.id)]?.last, .error(parent: folder.id))
        XCTAssertEqual(projection.childrenByParent[.entry(folder.id)]?.count, 2)

        await store.send(.hierarchy(.folderRetryRequested(id: folder.id)))
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.generation, 2)
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.loadPhase, .loadingCore)
        XCTAssertTrue(store.state.hierarchy.nodesByID[folder.id]?.folder.children.isEmpty ?? false)
    }

    // FLOW-PATH: alternate_path.collapse_during_loading_discards_partial_results

    /// EVM-002-toggle_directory_expansion_in_list: loading 중 collapse는 partial result를 버리고 re-expand를 새 load로 시작한다.
    /// 사용자가 child batch를 받은 직후 folder를 접었다가 다시 펼치는 경로를 검증한다.
    /// - 검증 내용: collapse 후 visible child 제거와 새 expansion generation.
    /// - 사전 조건: folder가 generation 1 loading 상태이고 child 하나가 부분 표시된 상태다.
    /// - 기대 결과: collapse 후 child가 사라지고 re-expand 후 새로운 loading request가 시작된다.
    func testCollapseDuringLoadingDiscardsPartialResultsBeforeReexpand() async {
        let folder = EntryModel.temporaryFolder(id: "/flow/current/folder", name: "folder")
        let child = entryFile(id: "/flow/current/folder/child", name: "child")
        let store = makeLayoutStore(roots: [folder])
        // store.exhaustivity = .off: flow는 stream delegate 순서보다 collapse/re-expand 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderExpansionRequested(id: folder.id)))
        await store.send(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folder.id,
            folderGeneration: 1,
            .event(.coreBatch(items: [child], batchIndex: 0)),
        )))
        XCTAssertEqual(
            store.state.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
            [folder.id, child.id],
        )

        await store.send(.hierarchy(.folderCollapseRequested(id: folder.id)))
        await store.receive(\.internal.reconcileHierarchySelection)
        XCTAssertEqual(store.state.visibleSelectableEntryIDs(isNormalDirectoryPage: true), [folder.id])
        XCTAssertTrue(store.state.hierarchy.nodesByID[folder.id]?.folder.children.isEmpty ?? false)

        await store.send(.hierarchy(.folderExpansionRequested(id: folder.id)))
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.generation, 3)
        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.loadPhase, .loadingCore)
    }

    // FLOW-PATH: alternate_path.sibling_local_sort

    /// EVM-004-sort_entries_by_property: hierarchy sort는 root와 각 folder의 sibling 경계를 유지한다.
    /// 사용자가 expanded hierarchy에서 이름 정렬을 바꿔도 서로 다른 parent의 child가 섞이지 않는지 검증한다.
    /// - 검증 내용: root siblings와 folder-local child siblings의 arrangement projection.
    /// - 사전 조건: root 두 folder와 각 folder의 child 두 개가 expanded loaded 상태다.
    /// - 기대 결과: 각 parent 내부에서만 이름 오름차순이 적용되고 root/child 경계가 유지된다.
    func testHierarchySortRemainsLocalToSiblingBoundaries() async {
        let first = EntryModel.temporaryFolder(id: "/flow/current/first", name: "z-first")
        let second = EntryModel.temporaryFolder(id: "/flow/current/second", name: "a-second")
        let firstChildA = entryFile(id: "/flow/current/first/a", name: "a")
        let firstChildZ = entryFile(id: "/flow/current/first/z", name: "z")
        let secondChildA = entryFile(id: "/flow/current/second/a", name: "a")
        let secondChildZ = entryFile(id: "/flow/current/second/z", name: "z")
        let store = makeStore(roots: [first, second]) {
            $0.entryViewLayout.entryArrangements.sortKey = .dateModified
            $0.entryViewLayout.hierarchy.nodesByID[first.id] = .init(
                children: [firstChildZ, firstChildA],
                loadPhase: .loaded,
                generation: 1,
                expectedBatchIndex: 2,
                coreFinished: true,
            )
            $0.entryViewLayout.hierarchy.nodesByID[second.id] = .init(
                children: [secondChildZ, secondChildA],
                loadPhase: .loaded,
                generation: 1,
                expectedBatchIndex: 2,
                coreFinished: true,
            )
            $0.entryViewLayout.hierarchy.setExpandedIDs([first.id, second.id])
        }
        // store.exhaustivity = .off: flow는 arrangement reducer의 내부 delegate 대신 sibling-local order를 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryArrangements(.setSortKey(.name))))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.entryViewLayout.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
            [second.id, secondChildA.id, secondChildZ.id, first.id, firstChildA.id, firstChildZ.id],
        )
    }

    // FLOW-PATH: alternate_path.flat_modes_disable_hierarchy

    /// EVM-002-toggle_directory_expansion_in_list: grid, collection, active grouping은 flat projection으로 hierarchy
    /// disclosure를 비활성화한다.
    /// 사용자가 hierarchy 가능한 folder가 있는 다른 presentation mode에서 expand를 시도하는 경로를 검증한다.
    /// - 검증 내용: grid와 grouped list에서 child가 표시되지 않고 root만 selectable한지 확인한다.
    /// - 사전 조건: folder 하나가 있는 directory state를 grid 또는 active grouping으로 구성한다.
    /// - 기대 결과: 두 flat mode 모두 visible projection이 root-only다.
    func testGridAndGroupedModesKeepProjectionFlat() async {
        let folder = EntryModel.temporaryFolder(id: "/flow/current/folder", name: "folder")
        for (mode, isCollectionMode, groupKey) in [
            (EntryViewLayoutState.Mode.grid, false, GroupKey.none),
            (.list, false, .kind),
            (.list, true, .none),
        ] {
            let store = makeLayoutStore(roots: [folder]) {
                $0.mode = mode
                $0.isCollectionMode = isCollectionMode
                $0.entryArrangements.groupKey = groupKey
            }
            // store.exhaustivity = .off: flow는 flat mode의 visible root projection만 검증한다.
            store.exhaustivity = .off

            await store.send(.hierarchy(.folderExpansionRequested(id: folder.id)))
            XCTAssertEqual(
                store.state.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
                [folder.id],
            )
            XCTAssertTrue(store.state.hierarchy.nodesByID.isEmpty)
        }
    }

    // FLOW-PATH: invalid_projection.non_folder_rows_have_no_disclosure

    /// EVM-002-toggle_directory_expansion_in_list: folder가 아닌 row는 disclosure를 통한 child projection을 만들지 않는다.
    /// 사용자가 일반 file row를 folder처럼 펼치려 해도 visible projection이 바뀌지 않는지 검증한다.
    /// - 검증 내용: non-folder row의 hierarchy expansion no-op.
    /// - 사전 조건: `/flow/current/readme.txt` 하나가 list directory root에 표시된다.
    /// - 기대 결과: child row나 hierarchy node 없이 file row 하나만 visible하다.
    func testNonFolderRowsDoNotProjectDisclosureChildren() async {
        let file = entryFile(id: "/flow/current/readme.txt", name: "readme.txt")
        let store = makeLayoutStore(roots: [file])
        // store.exhaustivity = .off: flow는 invalid input의 visible no-op만 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderExpansionRequested(id: file.id)))

        XCTAssertEqual(store.state.visibleSelectableEntryIDs(isNormalDirectoryPage: true), [file.id])
        XCTAssertTrue(store.state.hierarchy.nodesByID.isEmpty)
    }

    // FLOW-PATH: alternate_path.stale_child_results_are_ignored

    /// EVM-002-toggle_directory_expansion_in_list: root navigation 중 도착한 stale child result는 current page에 반영되지 않는다.
    /// 사용자가 child loading 중 다른 directory로 이동한 뒤 늦은 child result를 받는 경로를 검증한다.
    /// - 검증 내용: root context generation guard와 current visible projection.
    /// - 사전 조건: `/flow/current/folder` loading request 뒤 `/flow/next`로 root context가 변경된다.
    /// - 기대 결과: old child는 visible projection에 나타나지 않는다.
    func testRootNavigationIgnoresStaleChildResults() async {
        let folder = EntryModel.temporaryFolder(id: "/flow/current/folder", name: "folder")
        let staleChild = entryFile(id: "/flow/current/folder/stale", name: "stale")
        let store = makeLayoutStore(roots: [folder])
        // store.exhaustivity = .off: flow는 root context와 stale child exclusion만 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderExpansionRequested(id: folder.id)))
        await store.send(.hierarchy(.rootContextChanged(path: "/flow/next")))
        await store.skipReceivedActions()

        await store.send(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folder.id,
            folderGeneration: 1,
            .event(.coreBatch(items: [staleChild], batchIndex: 0)),
        )))

        XCTAssertEqual(store.state.hierarchy.rootPath, "/flow/next")
        XCTAssertFalse(store.state.visibleSelectableEntryIDs(isNormalDirectoryPage: true)
            .contains(staleChild.id))
    }

    // FLOW-PATH: alternate_path.mutation_invalidates_expanded_hierarchy

    /// EVM-002-toggle_directory_expansion_in_list: hierarchy를 변경한 mutation은 stale child projection을 무시하고 새 load를 시작한다.
    /// 사용자가 expanded folder의 child를 변경한 뒤 filesystem mutation refresh를 받는 경로를 검증한다.
    /// - 검증 내용: `pathsMutated` composition이 affected parent hierarchy를 invalidate한다.
    /// - 사전 조건: `/flow/current/folder`가 expanded loaded 상태이고 child mutation path가 전달된다.
    /// - 기대 결과: 기존 child cache가 재검증을 위해 loading 상태로 전환되고 stale child가 현재 projection을 독점하지 않는다.
    func testMutationInvalidatesExpandedFolderBeforeNewProjection() async {
        let folder = EntryModel.temporaryFolder(id: "/flow/current/folder", name: "folder")
        let oldChild = entryFile(id: "/flow/current/folder/old", name: "old")
        let store = makeStore(
            roots: [folder],
            configure: {
                $0.entryViewLayout.hierarchy.nodesByID[folder.id] = .init(
                    children: [oldChild],
                    loadPhase: .loaded,
                    generation: 1,
                    expectedBatchIndex: 1,
                    coreFinished: true,
                )
                $0.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
            },
            dependencies: {
                $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                    Self.stream(events: [.coreBatch(items: [], batchIndex: 0)])
                }
            },
        )
        // store.exhaustivity = .off: flow는 mutation-to-reload projection만 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.lifecycle(.pathsMutated([
            "/flow/current/folder/new",
        ])))))
        await store.receive(\.entryViewLayout.hierarchy.hierarchyInvalidated)
        await store.receive(\.entryViewLayout.entryOperations.loading.loadFolderItems)

        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[folder.id]?.loadPhase, .loadingCore)
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[folder.id]?.folder.children,
            [oldChild],
            "완료된 child snapshot은 새 replacement batch가 올 때까지 유지한다",
        )
        XCTAssertTrue(store.state.entryViewLayout.visibleSelectableEntryIDs(isNormalDirectoryPage: true)
            .contains(oldChild.id))
        await store.skipReceivedActions()
        await store.finish()
    }

    // FLOW-PATH: alternate_path.mutation_ignores_stale_child_response

    /// EVM-002-toggle_directory_expansion_in_list: mutation 뒤 이전 child load 응답은 현재 projection을 오염시키지 않는다.
    /// 사용자가 expanded folder의 항목을 변경한 뒤 이전 요청이 늦게 도착하는 경로를 검증한다.
    /// - 검증 내용: mutation invalidation이 새 generation을 시작한 뒤 이전 generation의 child 응답을 무시하는지 확인한다.
    /// - 사전 조건: `/flow/current/folder`가 expanded loaded 상태이고 mutation으로 새 load가 시작되었다.
    /// - 기대 결과: 이전 요청의 child가 visible selectable projection에 다시 나타나지 않는다.
    func testMutationIgnoresStaleChildResponse() async {
        let folder = EntryModel.temporaryFolder(id: "/flow/current/folder", name: "folder")
        let oldChild = entryFile(id: "/flow/current/folder/old", name: "old")
        let staleChild = entryFile(id: "/flow/current/folder/stale", name: "stale")
        let store = makeLayoutStore(roots: [folder]) {
            $0.hierarchy.nodesByID[folder.id] = .init(
                children: [oldChild],
                loadPhase: .loaded,
                generation: 1,
                expectedBatchIndex: 1,
                coreFinished: true,
            )
            $0.hierarchy.setExpandedIDs([folder.id])
        }
        // store.exhaustivity = .off: invalidation의 reload delegate 외에 projection 결과만 검증한다.
        store.exhaustivity = .off

        await store.send(.hierarchy(.hierarchyInvalidated(
            affectedPaths: ["/flow/current/folder/new"],
            removedPrefixes: [],
        )))
        await store.receive(\.delegate.expandRequested, folder.id)

        await store.send(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folder.id,
            folderGeneration: 1,
            .event(.coreBatch(items: [staleChild], batchIndex: 0)),
        )))

        XCTAssertEqual(store.state.hierarchy.nodesByID[folder.id]?.generation, 2)
        XCTAssertEqual(
            store.state.hierarchy.nodesByID[folder.id]?.folder.children,
            [oldChild],
            "stale response는 retained snapshot을 덮어쓰지 않는다",
        )
        XCTAssertEqual(
            store.state.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
            [folder.id, oldChild.id],
        )
    }

    // FLOW-PATH: alternate_path.failed_folder_does_not_block_sibling_interaction

    /// EVM-002-toggle_directory_expansion_in_list: 한 folder의 실패 상태가 sibling folder의 expansion을 막지 않는다.
    /// 사용자가 한 folder의 Retry 가능한 실패 상태를 보는 동안 다른 folder를 펼치는 경로를 검증한다.
    /// - 검증 내용: failed folder의 partial child와 error row를 유지하면서 sibling child load를 독립적으로 투영한다.
    /// - 사전 조건: `/flow/current` list에 실패한 folder와 idle sibling folder가 있고 sibling child stream이 준비되어 있다.
    /// - 기대 결과: 실패한 folder는 failed 상태를 유지하고 sibling folder와 child는 visible projection에 추가된다.
    func testFailedFolderDoesNotBlockSiblingExpansion() async {
        let failedFolder = EntryModel.temporaryFolder(id: "/flow/current/failed", name: "failed")
        let activeFolder = EntryModel.temporaryFolder(id: "/flow/current/active", name: "active")
        let partialChild = entryFile(id: "/flow/current/failed/partial", name: "partial")
        let activeChild = entryFile(id: "/flow/current/active/child", name: "child")
        let store = makeStore(
            roots: [failedFolder, activeFolder],
            configure: {
                $0.entryViewLayout.hierarchy.nodesByID[failedFolder.id] = .init(
                    children: [partialChild],
                    loadPhase: .failed(.permissionDenied),
                    generation: 1,
                    expectedBatchIndex: 1,
                )
                $0.entryViewLayout.hierarchy.setExpandedIDs([failedFolder.id])
            },
            dependencies: {
                $0.entryLoadingClient.stagedLoadItems = { url, _, _ in
                    XCTAssertEqual(url.path, activeFolder.fullPath)
                    return Self.stream(events: [
                        .coreBatch(items: [activeChild], batchIndex: 0),
                        .coreFinished(batchCount: 1),
                    ])
                }
            },
        )
        // store.exhaustivity = .off: sibling load의 내부 bridge action보다 독립적인 visible projection을 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderExpansionRequested(id: activeFolder.id))))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[failedFolder.id]?.loadPhase,
            .failed(.permissionDenied),
        )
        XCTAssertEqual(
            store.state.entryViewLayout.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
            [activeFolder.id, activeChild.id, failedFolder.id, partialChild.id],
        )
    }

    private func makeStore(
        roots: [EntryModel],
        configure: (inout FileManagerContentState) -> Void = { _ in },
        dependencies: (inout DependencyValues) -> Void = { _ in },
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/flow/current")
        state.entryViewLayout.entryOperations.items = IdentifiedArrayOf(uniqueElements: roots)
        state.entryViewLayout.entries = roots
        state.entryViewLayout.hierarchy = .init(rootPath: "/flow/current")
        configure(&state)
        return TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient.setString = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            dependencies(&$0)
        }
    }

    private func makeLayoutStore(
        roots: [EntryModel],
        configure: (inout EntryViewLayoutState) -> Void = { _ in },
    ) -> TestStore<EntryViewLayoutState, EntryViewLayoutAction> {
        var state = EntryViewLayoutState()
        state.entries = roots
        state.hierarchy = .init(rootPath: "/flow/current")
        configure(&state)
        return TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }
    }

    nonisolated private static func stream(events: [EntryLoadEvent]) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    private func outlineProjection(for state: EntryViewLayoutState) -> EntryListOutlineProjection {
        EntryListOutlineProjection(
            revision: state.outlineProjectionRevision,
            rootEntries: state.entries,
            hierarchyState: state.hierarchy,
            context: .init(
                mode: state.mode,
                isNormalDirectoryPage: true,
                hasActiveGrouping: state.entryArrangements.groupKey != .none,
            ),
            sortKey: state.entryArrangements.sortKey,
            sortOrder: state.entryArrangements.sortOrder,
        )
    }

    private func entryFile(id: String, name: String) -> EntryModel {
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
}

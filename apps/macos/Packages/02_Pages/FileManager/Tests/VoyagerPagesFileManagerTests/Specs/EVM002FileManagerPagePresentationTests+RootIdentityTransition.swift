import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002FileManagerPagePresentationTests {
    /// EVM-002-command_external_refresh_correlation: buffered root reload은 terminal commit 후에만 identity selection을 옮긴다.
    /// - 검증 내용: coreBatch의 candidate 축적 중에는 before 선택과 전이를 유지하고, streamFinished가 candidate를 commit한 뒤 after 선택으로 한 번
    /// 이동한다.
    /// - 사전 조건: before→after root 전이와 preserved directory reload candidate가 있다.
    /// - 기대 결과: coreBatch 후 before 선택 유지, streamFinished 후 after 선택 및 전이 소비.
    func testBufferedRootReloadMigratesIdentitySelectionAfterTerminalCommit() async {
        let rootPath = "/root"
        let before = EntryModel.temporaryFolder(id: "\(rootPath)/before", name: "before")
        let after = EntryModel.temporaryFolder(id: "\(rootPath)/after", name: "after")
        var state = rootTransitionState(rootPath: rootPath, before: before, afterPath: after.id)
        state.entryViewLayout.entryOperations.loadingContext.preservedDirectoryReloadItems = []
        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [after], batchIndex: 0),
        ))))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [before.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreFinished(batchCount: 1),
        ))))))
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFinished(generation: 1)))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [after.id])
        XCTAssertNil(store.state.pendingIdentityTransition)
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else { return false }
            return projection.entries == [after]
        }
        await store.receive(\.entryViewLayout.hierarchy.rootSnapshotCompleted)
    }

    /// EVM-002-command_external_refresh_correlation: partial root stream failure는 stale identity transition을 폐기한다.
    /// - 검증 내용: after-path 없는 current root coreBatch 뒤 streamFailed가 transition을 유지하지 않는다.
    /// - 사전 조건: before 선택과 current root generation identity transition이 있다.
    /// - 기대 결과: partial failure 후 pendingIdentityTransition이 nil이다.
    func testPartialRootStreamFailureDiscardsIdentityTransition() async {
        let rootPath = "/root"
        let before = EntryModel.temporaryFolder(id: "\(rootPath)/before", name: "before")
        let unrelated = EntryModel.temporaryFolder(id: "\(rootPath)/unrelated", name: "unrelated")
        let store = makeFileManagerContentFeatureStore(initialState: rootTransitionState(
            rootPath: rootPath,
            before: before,
            afterPath: "\(rootPath)/after",
        ))
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [unrelated], batchIndex: 0),
        ))))))
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFailed(generation: 1)))))
        XCTAssertNil(store.state.pendingIdentityTransition)
        await store.receive(\.entryViewLayout.internal.reconcileHierarchySelection)
    }

    /// EVM-002-command_external_refresh_correlation: source root의 streamFinished도 destination migration까지 projection을
    /// hold한다.
    /// - 검증 내용: root stream이 coreBatch·coreFinished를 지나 streamFinished에서 items를 교체할 때 before 행이 포함된 projection이 유지되고,
    /// destination folder batch에서 after로 선택·행이 한 번에 이동한다.
    /// - 사전 조건: preservationOwner=.root(1), projectionOwner=.folder(dest,3)인 교차 폴더 이동 전이와 root 재로드 stream.
    /// - 기대 결과: streamFinished 뒤 projection entries에 before 유지, destination batch 뒤 after 선택 + 전이 소비.
    func testStreamFinishedRetainsRootSourceProjectionUntilDestinationMigration() async {
        let rootPath = "/root"
        let before = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        let unrelated = EntryModel.temporaryFolder(id: "/root/kept", name: "kept")
        let destination = EntryModel.temporaryFolder(id: "/root/dest", name: "dest")
        let after = EntryModel.temporaryFolder(id: "/root/dest/after", name: "after")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.navigation.navigationState = .folder(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [unrelated, destination]
        state.entryViewLayout.entryOperations.items = [unrelated, destination]
        state.entryViewLayout.entryOperations.loadingContext.items = [unrelated, destination]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destination.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: after.id,
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            preservationOwner: .root(generation: 1),
        )

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [unrelated, destination], batchIndex: 0),
        ))))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else { return false }
            return projection.entries.map(\.id).sorted() == [destination.id, unrelated.id]
        }
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [before.id])

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreFinished(batchCount: 1),
        ))))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else { return false }
            return projection.entries.map(\.id).sorted() == [destination.id, unrelated.id]
        }
        await store.receive(\.entryViewLayout.hierarchy.rootSnapshotCompleted)
        await receiveFolderRestart(store, folderID: destination.id, folderGeneration: 4)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [before.id])
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.projectionOwner,
            .folder(id: destination.id, generation: 4),
        )

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFinished(generation: 1)))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else { return false }
            return projection.entries.map(\.id).sorted() == [destination.id, unrelated.id]
        }
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [before.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destination.id,
            folderGeneration: 4,
            .event(.coreBatch(items: [after], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [after.id])
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destination.id,
            folderGeneration: 4,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
    }

    /// EVM-002-command_external_refresh_correlation: identity reload가 소유 중인 root에는 aggregate reload를 예약하지 않는다.
    /// - 검증 내용: root 전이 소유자가 현재 또는 다음 세대인 동안 .internal(.reloadDirectoryListing)는 loadItems를 발행하지 않는다.
    /// - 사전 조건: entryActionCompleted가 rebase한 .root(2) 소유자와 generation 1인 active folder route.
    /// - 기대 결과: reloadDirectoryListing 뒤에도 loadItems effect와 세대 bump가 없다.
    func testAggregateReloadYieldsToPendingIdentityReloadOwner() async {
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/before",
            afterPath: "/root/after",
            rootPath: "/root",
            refreshGeneration: 1,
        )
        state.pendingIdentityTransition?.projectionOwner = .root(generation: 2)

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { _ in }
            }
        }

        await store.send(.internal(.reloadDirectoryListing))
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.loadingContext.generation, 1)
        XCTAssertFalse(store.state.entryViewLayout.entryOperations.isLoading)
        await store.finish()
    }

    /// EVM-002-command_external_refresh_correlation: 비종료 empty source staging은 retained children을 유지한다.
    /// - 검증 내용: source 첫 batch가 비어 있고 destination after가 먼저 와도 source children을 []로 덮지 않는다.
    /// - 사전 조건: expanded source/destination 폴더와 childA가 남은 source retained snapshot.
    /// - 기대 결과: migration 시점에 source children == [childA], 전이는 destination coreFinished에서 소비.
    func testNonterminalEmptySourceStagingKeepsRetainedChildrenUntilTerminal() async {
        let rootPath = "/root"
        let before = EntryModel.temporaryFolder(id: "/root/src/before", name: "before")
        let childA = EntryModel.temporaryFolder(id: "/root/src/childA", name: "childA")
        let source = EntryModel.temporaryFolder(id: "/root/src", name: "src")
        let destination = EntryModel.temporaryFolder(id: "/root/dst", name: "dst")
        let after = EntryModel.temporaryFolder(id: "/root/dst/after", name: "after")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.navigation.navigationState = .folder(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [source, destination]
        state.entryViewLayout.entryOperations.items = [source, destination]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            children: [childA],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: after.id,
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            preservationOwner: .folder(id: source.id, generation: 3),
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: source.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [before.id])

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destination.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [after], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [after.id])
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[source.id]?.folder.children.map(\.id),
            [childA.id],
            "비종료 empty staging은 retained children을 덮지 않는다",
        )
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destination.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
    }

    /// EVM-002-command_external_refresh_correlation: 다중 선택 이동도 전이로 함께 migration한다.
    /// - 검증 내용: 두 선택 항목을 담은 record로 전이가 만들어지고, buffered reload terminal에서 두 after ID로 모두 이동한다.
    /// - 사전 조건: before1·before2 선택과 2-target pasteFileMove record, preserved directory reload.
    /// - 기대 결과: streamFinished 뒤 selectedIds == [after1, after2], 전이 소비, selectionChanged 1회.
    func testMultiSelectionMoveMigratesAllSelectedIdentities() async {
        let rootPath = "/root"
        let before1 = EntryModel.temporaryFolder(id: "/root/before1", name: "before1")
        let before2 = EntryModel.temporaryFolder(id: "/root/before2", name: "before2")
        let after1 = EntryModel.temporaryFolder(id: "/root/after1", name: "after1")
        let after2 = EntryModel.temporaryFolder(id: "/root/after2", name: "after2")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [before1, before2]
        state.entryViewLayout.entries = [before1, before2]
        state.entryViewLayout.selectedIds = [before1.id, before2.id]
        state.entryViewLayout.lastSelectedId = before2.id
        state.entryViewLayout.rangeAnchorId = before2.id
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.loadingContext.preservedDirectoryReloadItems = []
        state.entryViewLayout.entryOperations.isReloading = true
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [
                .init(beforePath: before1.id, afterPath: after1.id),
                .init(beforePath: before2.id, afterPath: after2.id),
            ],
        )
        _ = FileManagerContentIdentityTransitionCoordinator.recordIfEligible(record, state: &state)
        XCTAssertNotNil(state.pendingIdentityTransition, "다중 선택 이동도 전이를 만든다")
        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [after1, after2], batchIndex: 0),
        ))))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [before1.id, before2.id])

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreFinished(batchCount: 1),
        ))))))
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFinished(generation: 1)))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [after1.id, after2.id])
        XCTAssertNil(store.state.pendingIdentityTransition)
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else { return false }
            return projection.entries.map(\.id).sorted() == [after1.id, after2.id]
        }
        await store.receive(\.entryViewLayout.hierarchy.rootSnapshotCompleted)
    }

    private func receiveFolderRestart(
        _ store: TestStore<FileManagerContentState, FileManagerContentAction>,
        folderID: String,
        folderGeneration: Int,
    ) async {
        await store.receive { action in
            guard case let .entryViewLayout(.delegate(.expandRequested(id))) = action else { return false }
            return id == folderID
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadFolderItems(request)))) = action
            else { return false }
            return request.id.folderID == folderID && request.folderGeneration == folderGeneration
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.folderStreamFinished(request)))) = action
            else { return false }
            return request.id.folderID == folderID && request.folderGeneration == folderGeneration
        }
    }

    private func rootTransitionState(
        rootPath: String,
        before: EntryModel,
        afterPath: String,
    ) -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [before]
        state.entryViewLayout.entries = [before]
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: afterPath,
            rootPath: rootPath,
            refreshGeneration: 1,
        )
        return state
    }
}

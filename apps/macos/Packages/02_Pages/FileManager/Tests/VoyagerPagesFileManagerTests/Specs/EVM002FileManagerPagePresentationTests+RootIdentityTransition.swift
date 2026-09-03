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
        let store = makeFileManagerContentFeatureStore(initialState: state)
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

    /// EVM-002-command_external_refresh_correlation: command echo 상관관계는 additional 이동 경로도 포함한다.
    /// - 검증 내용: additional before/after와 그 하위 경로의 FSEvent가 transitionOverlaps에서 겹침으로 판정된다.
    /// - 사전 조건: additionalMoves가 하나 있는 대기 전이.
    /// - 기대 결과: additional 경로·하위는 true, 무관 경로는 false.
    func testTransitionOverlapsCoversAdditionalMoves() {
        var transition = FileManagerContentState.EntryIdentityTransition(
            recordID: UUID(),
            beforePath: "/root/a",
            afterPath: "/root/b",
            rootPath: "/root",
            refreshGeneration: 1,
        )
        transition.additionalMoves = [
            .init(beforePath: "/root/c", afterPath: "/root/d"),
        ]

        XCTAssertTrue(
            FileManagerContentIdentityTransitionCoordinator.transitionOverlaps("/root/c", transition),
            "additional before 경로도 echo 병합 대상이다",
        )
        XCTAssertTrue(
            FileManagerContentIdentityTransitionCoordinator.transitionOverlaps("/root/d/child", transition),
            "additional after 하위 경로도 echo 병합 대상이다",
        )
        XCTAssertFalse(
            FileManagerContentIdentityTransitionCoordinator.transitionOverlaps("/root/z", transition),
            "무관한 경로는 병합하지 않는다",
        )
    }

    /// EVM-002-command_external_refresh_correlation: 추가 symlink 이동도 lexical after 행으로 migration한다.
    /// - 검증 내용: additional pair의 raw lexical after가 destination symlink 행과 매칭되어 선택이 이동한다.
    /// - 사전 조건: 실제 symlink rename의 canonical after가 존재하고 lexical 행이 배치에 도착한다.
    /// - 기대 결과: selectedIds가 lexical newlink 행을 포함하고 전이는 소비된다.
    func testAdditionalSymlinkMoveMigratesToLexicalRow() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dirURL = rootURL.appendingPathComponent("dir", isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let targetURL = rootURL.appendingPathComponent("target.txt")
        try FileManager.default.createFile(atPath: targetURL.path, contents: Data())
        let newLinkURL = dirURL.appendingPathComponent("newlink")
        try FileManager.default.createSymbolicLink(at: newLinkURL, withDestinationURL: targetURL)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let oldLink = dirURL.appendingPathComponent("oldlink").path
        let primaryBefore = rootURL.appendingPathComponent("f1").path
        let primaryAfter = rootURL.appendingPathComponent("g1").path

        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(rootURL.path)
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.selectedIds = [primaryBefore, oldLink]

        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [
                .init(beforePath: primaryBefore, afterPath: primaryAfter),
                .init(beforePath: oldLink, afterPath: newLinkURL.path),
            ],
        )
        _ = FileManagerContentIdentityTransitionCoordinator.recordIfEligible(record, state: &state)
        let transition = try XCTUnwrap(state.pendingIdentityTransition, "다중 이동 전이가 만들어진다")
        XCTAssertEqual(transition.additionalMoves.count, 1)

        let primaryAfterEntry = EntryModel.temporaryFolder(id: primaryAfter, name: "g1")
        let lexicalLinkEntry = EntryModel.temporaryFolder(id: newLinkURL.path, name: "newlink")
        _ = FileManagerContentIdentityTransitionCoordinator.migrateSelection(
            entries: [primaryAfterEntry, lexicalLinkEntry],
            projectionOwner: .root(generation: 1),
            state: &state,
        )

        XCTAssertEqual(
            Set(state.entryViewLayout.selectedIds),
            [primaryAfter, newLinkURL.path],
            "additional symlink 이동은 lexical 행으로 migration한다",
        )
        XCTAssertNil(state.pendingIdentityTransition)
    }

    /// EVM-002-command_external_refresh_correlation: additional 이동의 source 폴더도 migration까지 보류·커밋한다.
    /// - 검증 내용: additional source 폴더의 batch가 staging 보류되고, destination migration 시 커밋된다.
    /// - 사전 조건: primary source A·additional source C·destination D가 모두 expanded 상태다.
    /// - 기대 결과: C batch 뒤 holdsUntilMigration staging이 생기고, D batch 뒤 C children이 커밋되며 선택이 이동한다.
    func testAdditionalSourceFolderStagesAndCommitsAtMigration() async {
        let rootPath = "/root"
        let sourceA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let sourceC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let destination = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let beforeA = EntryModel.temporaryFolder(id: "/root/A/before", name: "before")
        let beforeC = EntryModel.temporaryFolder(id: "/root/C/before", name: "before")
        let afterA = EntryModel.temporaryFolder(id: "/root/D/afterA", name: "afterA")
        let afterC = EntryModel.temporaryFolder(id: "/root/D/afterC", name: "afterC")
        let unrelatedC = EntryModel.temporaryFolder(id: "/root/C/kept", name: "kept")
        let unreceivedC = EntryModel.temporaryFolder(id: "/root/C/unreceived", name: "unreceived")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [sourceA, sourceC, destination]
        state.entryViewLayout.entryOperations.items = [sourceA, sourceC, destination]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        for (folder, children) in [(sourceA, [beforeA]), (sourceC, [beforeC, unreceivedC])] {
            state.entryViewLayout.hierarchy.nodesByID[folder.id] = .init(
                children: children,
                loadPhase: .loadingCore,
                generation: 3,
                expectedBatchIndex: 0,
                coreFinished: false,
            )
        }
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([sourceA.id, sourceC.id, destination.id])
        state.entryViewLayout.selectedIds = [beforeA.id, beforeC.id]
        state.entryViewLayout.lastSelectedId = beforeA.id
        state.entryViewLayout.rangeAnchorId = beforeA.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforeA.id,
            afterPath: afterA.id,
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            preservationOwner: .folder(id: sourceA.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeC.id,
                    afterPath: afterC.id,
                    afterLexicalPath: "",
                    sourceOwner: .folder(id: sourceC.id, generation: 3),
                ),
            ],
        )
        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off
        let rootContextGeneration = state.entryViewLayout.hierarchy.rootContextGeneration

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: sourceC.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [unrelatedC], batchIndex: 0)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[sourceC.id]?.folder.children.map(\.id),
            [beforeC.id, unreceivedC.id],
            "additional source 폴더도 migration까지 retained children을 유지한다",
        )
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, ["/root/A/before", beforeC.id])

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: destination.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [afterA, afterC], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [afterA.id, afterC.id])
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[sourceC.id]?.folder.children.map(\.id),
            [beforeC.id, unreceivedC.id],
            "non-terminal additional source staging은 retained children을 교체하지 않는다",
        )
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: sourceC.id)?.stagedChildren
                .map(\.id),
            [unrelatedC.id],
        )
        XCTAssertTrue(
            store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: sourceC.id)?
                .migrationCompleted ?? false,
        )
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: sourceC.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[sourceC.id]?.folder.children.map(\.id),
            [unrelatedC.id],
            "source coreFinished 뒤 staged snapshot이 커밋된다",
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: destination.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
    }

    /// EVM-002-command_external_refresh_correlation: destination이 다른 additional 이동은 자체 batch에서 migration된다.
    /// - 검증 내용: primary terminal에서도 pending pair가 남아 전이를 소비하지 않고, destination batch에서 선택이 이동한 뒤 소비된다.
    /// - 사전 조건: primary destination A와 additional destination C가 모두 expanded 상태인 undo 방향 전이.
    /// - 기대 결과: A terminal 뒤 전이 유지, C batch 뒤 r2 선택 + 전이 소비.
    func testAdditionalDestinationOwnerMigratesInOwnBatchAndDefersConsumption() async {
        let destinationA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let destinationC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let beforeY = EntryModel.temporaryFolder(id: "/root/D/y", name: "y")
        let r1 = EntryModel.temporaryFolder(id: "/root/A/r1", name: "r1")
        let r2 = EntryModel.temporaryFolder(id: "/root/C/r2", name: "r2")
        let (state, rootContextGeneration) = additionalDestinationFixture()
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: destinationA.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [r1], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [r1.id, beforeY.id])
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: destinationA.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNotNil(store.state.pendingIdentityTransition, "pending pair가 있으면 primary terminal도 전이를 소비하지 않는다")
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [r1.id, beforeY.id])

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [r2], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [r1.id, r2.id])
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
    }

    /// EVM-002-command_external_refresh_correlation: primary before는 raw lexical ID로만 매칭한다.
    /// - 검증 내용: rename된 symlink의 target만 선택돼 있으면 canonical 충돌로 target 선택을 교체하지 않는다.
    /// - 사전 조건: 실제 symlink와 그 target 중 target만 선택된 상태에서 symlink rename 전이.
    /// - 기대 결과: migration이 일어나지 않고 target 선택이 유지되며 전이는 만료된다.
    func testPrimaryBeforeMatchesLexicalSelectionOnly() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dirURL = rootURL.appendingPathComponent("dir", isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let targetURL = rootURL.appendingPathComponent("target.txt")
        try FileManager.default.createFile(atPath: targetURL.path, contents: Data())
        let linkURL = dirURL.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        let newLinkURL = dirURL.appendingPathComponent("link2")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(rootURL.path)
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.selectedIds = [targetURL.path]

        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: linkURL.path, afterPath: newLinkURL.path)],
        )
        _ = FileManagerContentIdentityTransitionCoordinator.recordIfEligible(record, state: &state)

        let newLinkEntry = EntryModel.temporaryFolder(id: newLinkURL.path, name: "link2")
        _ = FileManagerContentIdentityTransitionCoordinator.migrateSelection(
            entries: [newLinkEntry],
            projectionOwner: .root(generation: 1),
            state: &state,
        )

        XCTAssertEqual(
            Array(state.entryViewLayout.selectedIds),
            [targetURL.path],
            "canonical 충돌로 target 선택을 symlink로 교체하지 않는다",
        )
        XCTAssertNil(state.pendingIdentityTransition, "lexical before가 선택돼 있지 않으면 전이는 만료된다")
    }

    /// EVM-002-command_external_refresh_correlation: additional destination owner는 rebuild 전 hierarchy에서 캡처한다.
    /// - 검증 내용: recordIfEligible이 expanded destination folder의 ID·generation을 pair에 저장한다.
    /// - 사전 조건: destination C가 generation 3으로 expanded이고 다중 move record가 완료된다.
    /// - 기대 결과: hierarchy node 제거 후에도 pair destinationOwner는 C의 다음 reload generation 4이다.
    func testRecordCapturesAdditionalDestinationOwnerBeforeHierarchyRebuild() throws {
        let rootPath = "/root"
        let destination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destination.id])
        state.entryViewLayout.selectedIds = ["/root/before1", "/root/before2"]
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [
                .init(beforePath: "/root/before1", afterPath: "/root/after1"),
                .init(beforePath: "/root/before2", afterPath: "/root/C/after2"),
            ],
        )

        _ = FileManagerContentIdentityTransitionCoordinator.recordIfEligible(record, state: &state)
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = nil

        let transition = try XCTUnwrap(state.pendingIdentityTransition)
        XCTAssertEqual(
            transition.additionalMoves.first?.destinationOwner,
            .folder(id: destination.id, generation: 4),
        )
    }

    /// EVM-002-command_external_refresh_correlation: 동일 destination의 모든 pending after가 도착할 때까지 hold한다.
    /// - 검증 내용: 2개 pair가 같은 destination C를 공유하고 after가 배치별로 나뉘면 retained children이 유지되고
    /// 모든 after 도착 시 combine된다.
    /// - 사전 조건: C를 destination으로 공유하는 pair 2건과 retained children 3건.
    /// - 기대 결과: batch0 뒤 children 유지, batch1 뒤 combine, coreFinished 뒤 전이 소비.
    func testSharedDestinationWaitsThroughUnrelatedBatchBeforeTerminal() async throws {
        let rootPath = "/root"
        let destinationC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let old1 = EntryModel.temporaryFolder(id: "/root/C/old1", name: "old1")
        let old2 = EntryModel.temporaryFolder(id: "/root/C/old2", name: "old2")
        let old3 = EntryModel.temporaryFolder(id: "/root/C/old3", name: "old3")
        let before1 = EntryModel.temporaryFolder(id: "/root/before1", name: "before1")
        let before2 = EntryModel.temporaryFolder(id: "/root/before2", name: "before2")
        let after1 = EntryModel.temporaryFolder(id: "/root/C/after1", name: "after1")
        let after2 = EntryModel.temporaryFolder(id: "/root/C/after2", name: "after2")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entries = [
            destinationC,
            EntryModel.temporaryFolder(id: "/root/a", name: "a"),
            before1,
            before2,
        ]
        state.entryViewLayout.entryOperations.items = [destinationC]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[destinationC.id] = .init(
            children: [old1, old2, old3],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destinationC.id])
        state.entryViewLayout.selectedIds = ["/root/a", before1.id, before2.id]
        state.entryViewLayout.lastSelectedId = before1.id
        state.entryViewLayout.rangeAnchorId = before1.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/a",
            afterPath: "/root/b",
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: before1.id,
                    afterPath: after1.id,
                    sourceOwner: .root(generation: 1),
                    destinationOwner: .folder(id: destinationC.id, generation: 3),
                ),
                .init(
                    beforePath: before2.id,
                    afterPath: after2.id,
                    sourceOwner: .root(generation: 1),
                    destinationOwner: .folder(id: destinationC.id, generation: 3),
                ),
            ],
        )
        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [after1], batchIndex: 0)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[destinationC.id]?.folder.children.map(\.id),
            [old1.id, old2.id, old3.id],
            "다른 after가 남아 있으면 retained children을 유지한다",
        )

        let unrelated = EntryModel.temporaryFolder(id: "/root/C/unrelated", name: "unrelated")
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [unrelated], batchIndex: 1)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[destinationC.id]?.folder.children.map(\.id),
            [old1.id, old2.id, old3.id],
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [after2], batchIndex: 2)),
        ))))
        let combinedChildren = store.state.entryViewLayout.hierarchy.nodesByID[destinationC.id]?.folder.children
            .map(\.id) ?? []
        XCTAssertTrue(combinedChildren.contains(after1.id), "첫 after staging이 combine된다")
        XCTAssertTrue(combinedChildren.contains(unrelated.id), "unrelated batch staging도 combine된다")
        XCTAssertTrue(combinedChildren.contains(after2.id), "마지막 after 행이 combine된다")
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 3)),
        ))))
        let transition = try XCTUnwrap(
            store.state.pendingIdentityTransition,
            "primary 미이전이면 전이는 pending으로 유지된다",
        )
        XCTAssertTrue(transition.additionalMoves.allSatisfy(\.migrated))
    }

    /// EVM-002-command_external_refresh_correlation: additional destination 실패도 pair를 해소한다.
    /// - 검증 내용: additional destination 폴더 스트림 실패가 pending pair를 해소해 root terminal에서 전이가 닫힌다.
    /// - 사전 조건: root primary + additional destination C(폴더) 전이.
    /// - 기대 결과: C .failed 뒤 root batch migration 시 전이가 소비된다(nil).
    func testAdditionalDestinationFailureResolvesPairsAndClosesTransition() async {
        let rootPath = "/root"
        let destinationC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let before2 = EntryModel.temporaryFolder(id: "/root/C/before2", name: "before2")
        let after2 = EntryModel.temporaryFolder(id: "/root/C/after2", name: "after2")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [
            destinationC,
            EntryModel.temporaryFolder(id: "/root/a", name: "a"),
            EntryModel.temporaryFolder(id: "/root/b", name: "b"),
        ]
        state.entryViewLayout.entryOperations.items = [
            destinationC,
            EntryModel.temporaryFolder(id: "/root/a", name: "a"),
        ]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[destinationC.id] = .init(
            children: [before2],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destinationC.id])
        state.entryViewLayout.selectedIds = ["/root/a", before2.id]
        state.entryViewLayout.lastSelectedId = "/root/a"
        state.entryViewLayout.rangeAnchorId = "/root/a"
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/a",
            afterPath: "/root/b",
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: before2.id,
                    afterPath: after2.id,
                    sourceOwner: .root(generation: 1),
                    destinationOwner: .folder(id: destinationC.id, generation: 3),
                ),
            ],
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
            folderID: destinationC.id,
            folderGeneration: 3,
            .failed(.permissionDenied),
        ))))
        XCTAssertNotNil(
            store.state.pendingIdentityTransition,
            "primary terminal 전까지는 전이가 유지된다",
        )

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(
                items: [destinationC, EntryModel.temporaryFolder(id: "/root/b", name: "b")],
                batchIndex: 0,
            ),
        ))))))
        XCTAssertEqual(
            Set(store.state.entryViewLayout.selectedIds),
            ["/root/b", before2.id],
            "실패한 pair의 before 선택은 유지된다",
        )
        XCTAssertNil(store.state.pendingIdentityTransition, "모든 destination이 종결된 뒤 전이가 소비된다")
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
    }

    func dualSourceFixture() -> (FileManagerContentState, Int) {
        let rootPath = "/root"
        let sourceA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let sourceC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let destD1 = EntryModel.temporaryFolder(id: "/root/D1", name: "D1")
        let destD2 = EntryModel.temporaryFolder(id: "/root/D2", name: "D2")
        let beforeA = EntryModel.temporaryFolder(id: "/root/A/before", name: "before")
        let keptA = EntryModel.temporaryFolder(id: "/root/A/kept", name: "kept")
        let beforeC = EntryModel.temporaryFolder(id: "/root/C/before", name: "before")
        let keptC = EntryModel.temporaryFolder(id: "/root/C/kept", name: "kept")
        let afterA = EntryModel.temporaryFolder(id: "/root/D1/after", name: "after")
        let afterC = EntryModel.temporaryFolder(id: "/root/D2/after", name: "after")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [sourceA, sourceC, destD1, destD2]
        state.entryViewLayout.entryOperations.items = [sourceA, sourceC, destD1, destD2]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[sourceA.id] = .init(
            children: [beforeA, keptA],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.nodesByID[sourceC.id] = .init(
            children: [beforeC, keptC],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.nodesByID[destD1.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.nodesByID[destD2.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([sourceA.id, sourceC.id, destD1.id, destD2.id])
        state.entryViewLayout.selectedIds = [beforeA.id, beforeC.id]
        state.entryViewLayout.lastSelectedId = beforeA.id
        state.entryViewLayout.rangeAnchorId = beforeA.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforeA.id,
            afterPath: afterA.id,
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .folder(id: destD1.id, generation: 3),
            preservationOwner: .folder(id: sourceA.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeC.id,
                    afterPath: afterC.id,
                    sourceOwner: .folder(id: sourceC.id, generation: 3),
                    destinationOwner: .folder(id: destD2.id, generation: 3),
                ),
            ],
        )
        return (state, state.entryViewLayout.hierarchy.rootContextGeneration)
    }

    private func mixedPairFixture() -> (FileManagerContentState, Int) {
        let rootPath = "/root"
        let sourceD = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let destinationA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let destinationC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let beforeX = EntryModel.temporaryFolder(id: "/root/D/x", name: "x")
        let beforeY = EntryModel.temporaryFolder(id: "/root/D/y", name: "y")
        let beforeZ = EntryModel.temporaryFolder(id: "/root/D/z", name: "z")
        let r1 = EntryModel.temporaryFolder(id: "/root/A/r1", name: "r1")
        let r2 = EntryModel.temporaryFolder(id: "/root/A/r2", name: "r2")
        let r3 = EntryModel.temporaryFolder(id: "/root/C/r3", name: "r3")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [sourceD, destinationA, destinationC]
        state.entryViewLayout.entryOperations.items = [sourceD, destinationA, destinationC]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[sourceD.id] = .init(
            children: [beforeX, beforeY, beforeZ],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.nodesByID[destinationA.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.nodesByID[destinationC.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([sourceD.id, destinationA.id, destinationC.id])
        state.entryViewLayout.selectedIds = [beforeX.id, beforeY.id, beforeZ.id]
        state.entryViewLayout.lastSelectedId = beforeX.id
        state.entryViewLayout.rangeAnchorId = beforeX.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforeX.id,
            afterPath: r1.id,
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .folder(id: destinationA.id, generation: 3),
            preservationOwner: .folder(id: sourceD.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeY.id,
                    afterPath: r2.id,
                    sourceOwner: .folder(id: sourceD.id, generation: 3),
                ),
                .init(
                    beforePath: beforeZ.id,
                    afterPath: r3.id,
                    sourceOwner: .folder(id: sourceD.id, generation: 3),
                    destinationOwner: .folder(id: destinationC.id, generation: 3),
                ),
            ],
        )
        return (state, state.entryViewLayout.hierarchy.rootContextGeneration)
    }

    private func additionalDestinationFixture() -> (FileManagerContentState, Int) {
        let rootPath = "/root"
        let sourceD = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let destinationA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let destinationC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let beforeX = EntryModel.temporaryFolder(id: "/root/D/x", name: "x")
        let beforeY = EntryModel.temporaryFolder(id: "/root/D/y", name: "y")
        let r1 = EntryModel.temporaryFolder(id: "/root/A/r1", name: "r1")
        let r2 = EntryModel.temporaryFolder(id: "/root/C/r2", name: "r2")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [sourceD, destinationA, destinationC]
        state.entryViewLayout.entryOperations.items = [sourceD, destinationA, destinationC]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        for (folder, children) in [
            (destinationA, [EntryModel]()),
            (destinationC, [EntryModel]()),
            (sourceD, [beforeX, beforeY]),
        ] {
            state.entryViewLayout.hierarchy.nodesByID[folder.id] = .init(
                children: children,
                loadPhase: .loadingCore,
                generation: 3,
                expectedBatchIndex: 0,
                coreFinished: false,
            )
        }
        state.entryViewLayout.hierarchy.setExpandedIDs([sourceD.id, destinationA.id, destinationC.id])
        state.entryViewLayout.selectedIds = [beforeX.id, beforeY.id]
        state.entryViewLayout.lastSelectedId = beforeX.id
        state.entryViewLayout.rangeAnchorId = beforeX.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforeX.id,
            afterPath: r1.id,
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .folder(id: destinationA.id, generation: 3),
            preservationOwner: .folder(id: sourceD.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeY.id,
                    afterPath: r2.id,
                    afterLexicalPath: "",
                    sourceOwner: .folder(id: sourceD.id, generation: 3),
                    destinationOwner: .folder(id: destinationC.id, generation: 3),
                ),
            ],
        )
        return (state, state.entryViewLayout.hierarchy.rootContextGeneration)
    }

    /// EVM-002-command_external_refresh_correlation: root pair terminal은 미이전 folder primary를 보존한다.
    /// - 검증 내용: root destination pair가 먼저 migration돼도 folder primary batch까지 전이를 유지한다.
    /// - 사전 조건: primary → expanded A, additional → root인 undo 전이와 preserved root reload.
    /// - 기대 결과: streamFinished 뒤 root pair만 이전되고, A batch·terminal 뒤 전이가 소비된다.
    func testMixedDestinationRootPairMigratesAtRootTerminal() async {
        let rootPath = "/root"
        let sourceD = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let destinationA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let beforeX = EntryModel.temporaryFolder(id: "/root/D/x", name: "x")
        let beforeY = EntryModel.temporaryFolder(id: "/root/D/y", name: "y")
        let r1 = EntryModel.temporaryFolder(id: "/root/A/r1", name: "r1")
        let rootY = EntryModel.temporaryFolder(id: "/root/y", name: "y")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entries = [sourceD, destinationA]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.loadingContext.preservedDirectoryReloadItems = []
        state.entryViewLayout.entryOperations.isReloading = true
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[sourceD.id] = .init(
            children: [beforeX, beforeY],
            loadPhase: .loaded,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[destinationA.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([sourceD.id, destinationA.id])
        state.entryViewLayout.selectedIds = [beforeX.id, beforeY.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforeX.id,
            afterPath: r1.id,
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .folder(id: destinationA.id, generation: 3),
            preservationOwner: .folder(id: sourceD.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeY.id,
                    afterPath: rootY.id,
                    afterLexicalPath: "",
                    sourceOwner: .folder(id: sourceD.id, generation: 3),
                    destinationOwner: .root(generation: 1),
                ),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in AsyncThrowingStream { _ in } }
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [sourceD, destinationA, rootY], batchIndex: 0),
        ))))))
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreFinished(batchCount: 1),
        ))))))
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFinished(generation: 1)))))
        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            [beforeX.id, rootY.id],
            "root destination pair가 terminal 커밋에서 migration된다",
        )
        XCTAssertNotNil(store.state.pendingIdentityTransition)
        XCTAssertEqual(store.state.pendingIdentityTransition?.primaryMigrated, false)
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, true)
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else { return false }
            return projection.entries.map(\.id).sorted() == [destinationA.id, sourceD.id, rootY.id]
        }
        await store.receive(\.entryViewLayout.hierarchy.rootSnapshotCompleted)
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.projectionOwner,
            .folder(id: destinationA.id, generation: 4),
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationA.id,
            folderGeneration: 4,
            .event(.coreBatch(items: [r1], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [r1.id, rootY.id])
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationA.id,
            folderGeneration: 4,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
        await store.skipInFlightEffects()
    }

    /// EVM-002-command_external_refresh_correlation: additional before도 lexical 행 ID로만 교체한다.
    /// - 검증 내용: canonical으로 겹치는 실제 경로 선택은 유지하고 lexical before 선택만 after로 이동한다.
    /// - 사전 조건: beforeLexicalPath가 지정된 additional pair와 lexical·canonical 선택이 공존한다.
    /// - 기대 결과: lexical before만 dst로 이동하고 canonical 실제 경로 선택은 유지된다.
    func testAdditionalBeforeMatchesLexicalRowOverCanonicalCollision() {
        var transition = FileManagerContentState.EntryIdentityTransition(
            recordID: UUID(),
            beforePath: "/root/a",
            afterPath: "/root/b",
            rootPath: "/root",
            refreshGeneration: 1,
        )
        transition.additionalMoves = [
            .init(
                beforePath: "/root/real/file",
                afterPath: "/root/dst/file",
                beforeLexicalPath: "/root/link/file",
            ),
        ]
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.selectedIds = [
            "/root/a",
            "/root/link/file",
            "/root/real/file",
        ]
        state.pendingIdentityTransition = transition

        _ = FileManagerContentIdentityTransitionCoordinator.migrateSelection(
            entries: [
                EntryModel.temporaryFolder(id: "/root/b", name: "b"),
                EntryModel.temporaryFolder(id: "/root/dst/file", name: "file"),
            ],
            projectionOwner: .root(generation: 1),
            state: &state,
        )

        XCTAssertEqual(
            Set(state.entryViewLayout.selectedIds),
            ["/root/b", "/root/real/file", "/root/dst/file"],
            "canonical 실제 경로 선택은 유지되고 lexical before만 이동한다",
        )
        XCTAssertNil(state.pendingIdentityTransition)
    }

    /// EVM-002-command_external_refresh_correlation: nil-owner additional pair도 migrated로 기록된다.
    /// - 검증 내용: primary destination을 공유하는 additional pair가 migration되면 migrated 플래그가 세팅되어
    /// 별도 destination terminal에서 allSatisfy 소비가 가능하다.
    /// - 사전 조건: primary dest A(폴더), additional p1(dest A, nil-owner), p2(dest C, 폴더) 전이.
    /// - 기대 결과: C coreFinished 뒤 전이가 소비된다(nil이 된다).
    func testPrimaryOwnedAdditionalPairMarksMigratedForTerminalConsumption() async {
        let destinationA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let destinationC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let beforeZ = EntryModel.temporaryFolder(id: "/root/D/z", name: "z")
        let r1 = EntryModel.temporaryFolder(id: "/root/A/r1", name: "r1")
        let r2 = EntryModel.temporaryFolder(id: "/root/A/r2", name: "r2")
        let r3 = EntryModel.temporaryFolder(id: "/root/C/r3", name: "r3")
        let (state, rootContextGeneration) = mixedPairFixture()
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
            folderID: destinationA.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [r1, r2], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [r1.id, r2.id, beforeZ.id])
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationA.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNotNil(store.state.pendingIdentityTransition, "pending pair가 있으면 primary terminal도 소비하지 않는다")

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [r3], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [r1.id, r2.id, r3.id])
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition, "모든 pair가 해소되면 additional terminal에서 소비한다")
    }

    /// EVM-002-command_external_refresh_correlation: rebase 후에도 root destination pair가 terminal에서 migration된다.
    /// - 검증 내용: rebaseForNextRootReload가 additional root destination owner를 다음 세대로 올린다.
    /// - 사전 조건: primary dest가 폴더이고 additional dest가 root인 전이에 rebase가 적용된다.
    /// - 기대 결과: rebase 뒤 generation 2 스트림 terminal에서 pair가 migration된다.
    func testRebaseForNextRootReloadRebasesAdditionalRootOwners() async {
        let rootPath = "/root"
        let sourceD = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let destinationA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let beforeX = EntryModel.temporaryFolder(id: "/root/D/x", name: "x")
        let beforeY = EntryModel.temporaryFolder(id: "/root/D/y", name: "y")
        let r1 = EntryModel.temporaryFolder(id: "/root/A/r1", name: "r1")
        let rootY = EntryModel.temporaryFolder(id: "/root/y", name: "y")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [sourceD, destinationA]
        state.entryViewLayout.entryOperations.items = [sourceD, destinationA]
        state.entryViewLayout.entryOperations.loadingContext.generation = 2
        state.entryViewLayout.entryOperations.loadingContext.preservedDirectoryReloadItems = []
        state.entryViewLayout.entryOperations.isReloading = true
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[sourceD.id] = .init(
            children: [beforeX, beforeY],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.nodesByID[destinationA.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([sourceD.id, destinationA.id])
        state.entryViewLayout.selectedIds = [beforeX.id, beforeY.id]
        state.entryViewLayout.lastSelectedId = beforeX.id
        state.entryViewLayout.rangeAnchorId = beforeX.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforeX.id,
            afterPath: r1.id,
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .folder(id: destinationA.id, generation: 3),
            preservationOwner: .folder(id: sourceD.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeY.id,
                    afterPath: rootY.id,
                    sourceOwner: .folder(id: sourceD.id, generation: 3),
                    destinationOwner: .root(generation: 1),
                ),
            ],
        )
        FileManagerContentIdentityTransitionCoordinator.rebaseForNextRootReload(state: &state)
        XCTAssertEqual(
            state.pendingIdentityTransition?.additionalMoves.first?.destinationOwner,
            .root(generation: 2),
            "rebase가 additional root destination owner를 올린다",
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
            folderID: destinationA.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [r1], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [r1.id, beforeY.id])
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 2,
            event: .coreBatch(items: [sourceD, destinationA, rootY], batchIndex: 0),
        ))))))
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 2,
            event: .coreFinished(batchCount: 1),
        ))))))
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFinished(generation: 2)))))
        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            [r1.id, rootY.id],
            "rebase된 generation으로 root pair가 terminal에서 migration된다",
        )
        XCTAssertNil(store.state.pendingIdentityTransition)
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else { return false }
            return projection.entries.map(\.id).sorted() == [destinationA.id, sourceD.id, rootY.id]
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

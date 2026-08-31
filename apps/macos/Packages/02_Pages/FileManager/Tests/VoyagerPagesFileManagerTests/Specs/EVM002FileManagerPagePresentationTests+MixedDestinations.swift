import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002FileManagerPagePresentationTests {
    /// EVM-002-command_external_refresh_correlation: primary가 root여도 additional folder terminal에서 소비한다.
    /// - 검증 내용: root primary + folder additional 전이가 folder coreFinished에서 닫힌다.
    /// - 사전 조건: expanded folder C로의 additional pair가 migration 완료된 상태.
    /// - 기대 결과: C coreFinished 뒤 전이가 소비된다(nil이 된다).
    func testPrimaryRootTransitionConsumesAtAdditionalFolderTerminal() async {
        let rootPath = "/root"
        let destinationC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let beforeC = EntryModel.temporaryFolder(id: "/root/C/before", name: "before")
        let afterC = EntryModel.temporaryFolder(id: "/root/C/after", name: "after")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [
            destinationC,
            EntryModel.temporaryFolder(id: "/root/a", name: "a"),
            EntryModel.temporaryFolder(id: "/root/b", name: "b"),
        ]
        state.entryViewLayout.entryOperations.items = [destinationC]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[destinationC.id] = .init(
            children: [beforeC],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destinationC.id])
        state.entryViewLayout.selectedIds = ["/root/a", beforeC.id]
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
                    beforePath: beforeC.id,
                    afterPath: afterC.id,
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

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(
                items: [destinationC, EntryModel.temporaryFolder(id: "/root/b", name: "b")],
                batchIndex: 0,
            ),
        ))))))
        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            ["/root/b", beforeC.id],
            "root batch에서 primary가 migration된다",
        )
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [afterC], batchIndex: 0)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            ["/root/b", afterC.id],
            "folder pair는 destination batch에서 migration된다",
        )
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition, "primary가 root여도 additional terminal에서 소비한다")
    }

    /// EVM-002-replacement_reload_snapshot_retention: shared destination은 primary-first batch도 전체 after까지 보류한다.
    /// - 검증 내용: C primary after, unrelated, additional after 순서의 세 batch를 retained replacement로 누적한다.
    /// - 사전 조건: primary와 nil-owner additional pair가 expanded destination C를 공유한다.
    /// - 기대 결과: 첫 두 batch는 old children을 유지하고 마지막 after에서 세 batch를 한 번에 커밋한다.
    func testSharedPrimaryDestinationWaitsAfterPrimaryFirstBatch() async {
        let destination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let old1 = EntryModel.temporaryFolder(id: "/root/C/old1", name: "old1")
        let old2 = EntryModel.temporaryFolder(id: "/root/C/old2", name: "old2")
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/p", name: "p")
        let beforeAdditional = EntryModel.temporaryFolder(id: "/root/q", name: "q")
        let afterPrimary = EntryModel.temporaryFolder(id: "/root/C/p", name: "p")
        let afterAdditional = EntryModel.temporaryFolder(id: "/root/C/q", name: "q")
        let unrelated = EntryModel.temporaryFolder(id: "/root/C/kept", name: "kept")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = [destination, beforePrimary, beforeAdditional]
        state.entryViewLayout.hierarchy = .init(rootPath: "/root")
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [old1, old2],
            loadPhase: .loadingCore,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destination.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeAdditional.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: afterPrimary.id,
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeAdditional.id,
                    afterPath: afterAdditional.id,
                    sourceOwner: .root(generation: 1),
                ),
            ],
        )
        var probe = state
        FileManagerContentIdentityTransitionCoordinator.beginDeferredFolderReplacementIfNeeded(
            folderID: destination.id,
            items: [afterPrimary],
            state: &probe,
        )
        XCTAssertEqual(
            probe.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: destination.id)?.untilEntryID,
            afterAdditional.id,
        )
        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: destination.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [afterPrimary], batchIndex: 0)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[destination.id]?.folder.children,
            [old1, old2],
        )
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: destination.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [unrelated], batchIndex: 1)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[destination.id]?.folder.children,
            [old1, old2],
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: destination.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [afterAdditional], batchIndex: 2)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[destination.id]?.folder.children,
            [afterPrimary, unrelated, afterAdditional],
        )
        XCTAssertEqual(Set(store.state.entryViewLayout.selectedIds), [afterPrimary.id, afterAdditional.id])
        XCTAssertNil(store.state.pendingIdentityTransition)
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
    }

    /// EVM-002-replacement_reload_snapshot_retention: shared destination additional-first는 primary after를 기다린다.
    /// - 검증 내용: additional after만 온 owner batch가 primary sentinel을 만들고 additional 선택만 이전한다.
    /// - 사전 조건: primary와 nil-owner additional pair가 같은 folder generation을 사용한다.
    /// - 기대 결과: deferred untilEntryID는 primary after이고 migration 결과는 additional 변경을 보고한다.
    func testSharedPrimaryDestinationAdditionalFirstDefersForPrimaryAfter() {
        let destination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/p", name: "p")
        let beforeAdditional = EntryModel.temporaryFolder(id: "/root/q", name: "q")
        let afterPrimary = EntryModel.temporaryFolder(id: "/root/C/p", name: "p")
        let afterAdditional = EntryModel.temporaryFolder(id: "/root/C/q", name: "q")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.hierarchy = .init(rootPath: "/root")
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeAdditional.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: afterPrimary.id,
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            additionalMoves: [
                .init(beforePath: beforeAdditional.id, afterPath: afterAdditional.id),
            ],
        )

        FileManagerContentIdentityTransitionCoordinator.beginDeferredFolderReplacementIfNeeded(
            folderID: destination.id,
            items: [afterAdditional],
            state: &state,
        )
        XCTAssertEqual(
            state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: destination.id)?.untilEntryID,
            afterPrimary.id,
        )
        XCTAssertTrue(FileManagerContentIdentityTransitionCoordinator.migrateSelection(
            entries: [afterAdditional],
            projectionOwner: .folder(id: destination.id, generation: 3),
            state: &state,
        ))
        XCTAssertEqual(Set(state.entryViewLayout.selectedIds), [beforePrimary.id, afterAdditional.id])
    }

    /// EVM-002-command_external_refresh_correlation: current root 실패는 root pair만 종결한다.
    /// - 검증 내용: entryActionCompleted reload 실패가 additional root pair를 해소하고 folder primary 기회를 유지한다.
    /// - 사전 조건: primary D/x→A/r1, additional D/y→root/y 이동이 invalidation/startLoad를 통과한다.
    /// - 기대 결과: 실패 뒤 root pair 종결, A migration·terminal 뒤 전이와 source hold가 닫힌다.
    func testMixedDestinationRootFailureKeepsPrimaryFolderTransition() async {
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
        _ = state.entryViewLayout.entryOperations.loadingContext.begin(
            sourceKind: .directory,
            preservesSnapshot: false,
            directoryPath: rootPath,
        )
        state.entryViewLayout.entryOperations.items = [sourceD, destinationA]
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[sourceD.id] = .init(
            children: [beforeX, beforeY],
            loadPhase: .loaded,
            generation: 3,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[destinationA.id] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 3,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([sourceD.id, destinationA.id])
        state.entryViewLayout.selectedIds = [beforeX.id, beforeY.id]
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [
                .init(beforePath: beforeX.id, afterPath: r1.id),
                .init(beforePath: beforeY.id, afterPath: rootY.id),
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

        await store.send(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))))
        await store.receive { action in
            guard case .entryViewLayout(.hierarchy(.hierarchyInvalidated)) = action else { return false }
            return true
        }
        await store.receive(\.entryViewLayout.entryOperations.loading.loadItems)
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.loadingContext.isBufferingPreservedDirectoryReload)
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFailed(generation: 1)))))
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFailed(generation: 2)))))
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, true)
        XCTAssertEqual(store.state.pendingIdentityTransition?.primaryMigrated, false)
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: sourceD.id)?
                .holdsUntilMigration,
            true,
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationA.id,
            folderGeneration: 4,
            .event(.coreBatch(items: [r1], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [r1.id, beforeY.id])
        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: sourceD.id))
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationA.id,
            folderGeneration: 4,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[sourceD.id]?.folder.children.map(\.id),
            [beforeX.id, beforeY.id],
        )
        await store.skipInFlightEffects()
    }

    /// EVM-002-replacement_reload_snapshot_retention: root additional migration은 pending primary source를 커밋하지 않는다.
    /// - 검증 내용: D staging 완료 뒤 root pair가 먼저 migration돼도 primary A 전까지 D retained snapshot을 유지한다.
    /// - 사전 조건: entryActionCompleted가 primary와 additional의 shared source D hold를 pre-arm한다.
    /// - 기대 결과: root terminal 뒤 D hold 유지, A migration 뒤 staging이 한 번 커밋되고 전이가 닫힌다.
    func testRootAdditionalMigrationKeepsPendingPrimarySourceStaging() async {
        let rootPath = "/root"
        let sourceD = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let destinationA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let beforeX = EntryModel.temporaryFolder(id: "/root/D/x", name: "x")
        let beforeY = EntryModel.temporaryFolder(id: "/root/D/y", name: "y")
        let r1 = EntryModel.temporaryFolder(id: "/root/A/r1", name: "r1")
        let rootY = EntryModel.temporaryFolder(id: "/root/y", name: "y")
        let kept = EntryModel.temporaryFolder(id: "/root/D/kept", name: "kept")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entries = [sourceD, destinationA]
        _ = state.entryViewLayout.entryOperations.loadingContext.begin(
            sourceKind: .directory,
            preservesSnapshot: false,
            directoryPath: rootPath,
        )
        state.entryViewLayout.entryOperations.items = [sourceD, destinationA]
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        for (folder, children) in [(sourceD, [beforeX, beforeY]), (destinationA, [])] {
            state.entryViewLayout.hierarchy.nodesByID[folder.id] = .init(
                children: children,
                loadPhase: .loaded,
                generation: 3,
                coreFinished: true,
            )
        }
        state.entryViewLayout.hierarchy.setExpandedIDs([sourceD.id, destinationA.id])
        state.entryViewLayout.selectedIds = [beforeX.id, beforeY.id]
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [
                .init(beforePath: beforeX.id, afterPath: r1.id),
                .init(beforePath: beforeY.id, afterPath: rootY.id),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryQuickLookClient = .previewValue
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in AsyncThrowingStream { _ in } }
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))))
        await store.receive { action in
            guard case .entryViewLayout(.hierarchy(.hierarchyInvalidated)) = action else { return false }
            return true
        }
        await store.receive(\.entryViewLayout.entryOperations.loading.loadItems)
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.loadingContext.isBufferingPreservedDirectoryReload)
        await completeHeldFolderReload(store, folderID: sourceD.id, item: kept)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [beforeX.id, beforeY.id])
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.additionalMoves.first?.destinationOwner,
            .root(generation: 2),
        )

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 2,
            event: .coreBatch(items: [sourceD, destinationA, rootY], batchIndex: 0),
        ))))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [beforeX.id, beforeY.id])
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 2,
            event: .coreFinished(batchCount: 1),
        ))))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [beforeX.id, beforeY.id])
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFinished(generation: 2)))))
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, true)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [beforeX.id, rootY.id])
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[sourceD.id]?.folder.children, [beforeX, beforeY])
        XCTAssertNotNil(store.state.pendingIdentityTransition)
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }
        await store.receive(\.entryViewLayout.hierarchy.rootSnapshotCompleted)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: destinationA.id,
            folderGeneration: 5,
            .event(.coreBatch(items: [r1], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [r1.id, rootY.id])
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[sourceD.id]?.folder.children, [kept])
        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: sourceD.id))
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: destinationA.id,
            folderGeneration: 5,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
        await store.skipInFlightEffects()
    }

    /// EVM-002-command_external_refresh_correlation: additional terminal은 primary migration 완료를 기다린다.
    /// - 검증 내용: additional folder가 먼저 완료돼도 primary 미이전이면 전이를 유지하고, root batch migration 뒤 소비한다.
    /// - 사전 조건: primary root + additional folder C 전이에서 C batch/coreFinished가 먼저 도착한다.
    /// - 기대 결과: C coreFinished 뒤 전이 유지, root batch migration 뒤 소비와 선택 [b, afterC].
    func testAdditionalTerminalWaitsForPrimaryMigration() async {
        let rootPath = "/root"
        let destinationC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let beforeC = EntryModel.temporaryFolder(id: "/root/C/before", name: "before")
        let afterC = EntryModel.temporaryFolder(id: "/root/C/after", name: "after")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [destinationC, EntryModel.temporaryFolder(id: "/root/a", name: "a")]
        state.entryViewLayout.entryOperations.items = [destinationC]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[destinationC.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: false,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destinationC.id])
        state.entryViewLayout.selectedIds = ["/root/a", beforeC.id]
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
                    beforePath: beforeC.id,
                    afterPath: afterC.id,
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
            .event(.coreBatch(items: [afterC], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, ["/root/a", afterC.id])
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationC.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNotNil(
            store.state.pendingIdentityTransition,
            "primary가 미이전이면 additional terminal에서 전이를 소비하지 않는다",
        )

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(
                items: [destinationC, EntryModel.temporaryFolder(id: "/root/b", name: "b")],
                batchIndex: 0,
            ),
        ))))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, ["/root/b", afterC.id])
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        XCTAssertNil(store.state.pendingIdentityTransition, "primary migration 뒤 전이가 소비된다")
    }

    /// EVM-002-replacement_reload_snapshot_retention: additional destination 폴더도 after 행 전까지 보류한다.
    /// - 검증 내용: additional destination의 after 미포함 첫 batch가 retained children을 즉시 교체하지 않는다.
    /// - 사전 조건: retained children을 가진 expanded folder C가 additional destination인 전이.
    /// - 기대 결과: after 미포함 batch 뒤에도 retained children이 유지되고 staging이 누적된다.
    func testAdditionalDestinationHoldsRetainedChildrenUntilAfterRow() async {
        let rootPath = "/root"
        let destinationC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let old1 = EntryModel.temporaryFolder(id: "/root/C/old1", name: "old1")
        let old2 = EntryModel.temporaryFolder(id: "/root/C/old2", name: "old2")
        let old3 = EntryModel.temporaryFolder(id: "/root/C/old3", name: "old3")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [destinationC]
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
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/a",
            afterPath: "/root/b",
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: "/root/a",
                    afterPath: "/root/C/moved",
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
            .event(.coreBatch(items: [old1], batchIndex: 0)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[destinationC.id]?.folder.children.map(\.id),
            [old1.id, old2.id, old3.id],
            "additional destination의 after 미포함 batch는 retained children을 즉시 교체하지 않는다",
        )
        XCTAssertNotNil(store.state.pendingIdentityTransition)
    }

    /// EVM-002-replacement_reload_snapshot_retention: additional root source도 migration까지 보류한다.
    /// - 검증 내용: primary preservation은 folder여도 미이전 additional sourceOwner가 root면 streamFinished projection을 hold한다.
    /// - 사전 조건: primary source folder + additional source root인 혼합 전이.
    /// - 기대 결과: pair 미이전 시 true, migration 완료 후 false.
    func testAdditionalRootSourceHoldsProjectionUntilMigration() {
        var state = FileManagerContentState()
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/source/before",
            afterPath: "/root/destination/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: "/root/destination", generation: 3),
            preservationOwner: .folder(id: "/root/source", generation: 3),
            additionalMoves: [
                .init(
                    beforePath: "/root/additional",
                    afterPath: "/root/destination/additional",
                    sourceOwner: .root(generation: 1),
                ),
            ],
        )
        let terminal: FileManagerContentAction = .entryViewLayout(
            .entryOperations(.loading(.streamFinished(generation: 1))),
        )

        XCTAssertTrue(
            FileManagerContentIdentityTransitionCoordinator.holdsRootProjection(on: terminal, state: state),
        )

        state.pendingIdentityTransition?.additionalMoves[0].migrated = true
        XCTAssertFalse(
            FileManagerContentIdentityTransitionCoordinator.holdsRootProjection(on: terminal, state: state),
        )
    }

    /// EVM-002-command_external_refresh_correlation: stale additional destination failure는 current pair를 해소하지 않는다.
    /// - 검증 내용: stale folder generation과 stale rootContext generation의 failure가 migrated 상태를 바꾸지 않는다.
    /// - 사전 조건: current additional destination owner C generation 4.
    /// - 기대 결과: 두 stale failure 뒤에도 pair.migrated == false.
    func testStaleAdditionalDestinationFailureDoesNotResolveCurrentGeneration() {
        let destination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        var state = FileManagerContentState()
        state.entryViewLayout.hierarchy = .init(rootContextGeneration: 2, rootPath: "/root")
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 4,
        )
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/a",
            afterPath: "/root/b",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: "/root/before",
                    afterPath: "/root/C/after",
                    destinationOwner: .folder(id: destination.id, generation: 4),
                ),
            ],
        )

        FileManagerContentIdentityTransitionCoordinator.resolveFolderTransition(
            on: .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration: 2,
                folderID: destination.id,
                folderGeneration: 3,
                .failed(.permissionDenied),
            ))),
            state: &state,
        )
        FileManagerContentIdentityTransitionCoordinator.resolveFolderTransition(
            on: .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration: 1,
                folderID: destination.id,
                folderGeneration: 4,
                .failed(.permissionDenied),
            ))),
            state: &state,
        )

        XCTAssertEqual(state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
    }

    /// EVM-002-command_external_refresh_correlation: same-generation rejected failure는 pair를 해소하지 않는다.
    /// - 검증 내용: owner generation은 같지만 current node가 loaded라 failed 응답을 받지 않는 경우 migrated를 유지한다.
    /// - 사전 조건: additional destination C generation 4, node loadPhase loaded.
    /// - 기대 결과: failure 처리 뒤 pair.migrated == false.
    func testRejectedAdditionalDestinationFailureDoesNotResolveCurrentPair() async {
        let destination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        var state = FileManagerContentState()
        state.entryViewLayout.hierarchy = .init(rootContextGeneration: 2, rootPath: "/root")
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 4,
        )
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/a",
            afterPath: "/root/b",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: "/root/before",
                    afterPath: "/root/C/after",
                    destinationOwner: .folder(id: destination.id, generation: 4),
                ),
            ],
        )
        let store = TestStore(initialState: state) { FileManagerContentFeature() }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 2,
            folderID: destination.id,
            folderGeneration: 4,
            .failed(.permissionDenied),
        ))))

        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
    }

    /// EVM-002-command_external_refresh_correlation: primary folder failure는 pending additional pair를 기다린다.
    /// - 검증 내용: primary A failure를 node terminal 상태로 유지하고 C pair가 pending이면 보존한 뒤 C failure에서 소비한다.
    /// - 사전 조건: primary destination A와 additional destination C가 generation 3이다.
    /// - 기대 결과: A failure 뒤 전이 유지, C failure 뒤 전이 nil.
    func testPrimaryFolderFailureWaitsForAdditionalDestinationTerminal() async {
        let source = EntryModel.temporaryFolder(id: "/root/source", name: "source")
        let beforeA = EntryModel.temporaryFolder(id: "/root/source/a", name: "a")
        let beforeC = EntryModel.temporaryFolder(id: "/root/source/c", name: "c")
        var state = FileManagerContentState()
        state.entryViewLayout.entries = [
            source,
            EntryModel.temporaryFolder(id: "/root/A", name: "A"),
            EntryModel.temporaryFolder(id: "/root/C", name: "C"),
        ]
        state.entryViewLayout.hierarchy = .init(rootPath: "/root")
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            folder: FolderSnapshot(children: [beforeA, beforeC]),
            expansionIntent: true,
            generation: 3,
            loadPhase: .loaded,
        )
        state.entryViewLayout.hierarchy.nodesByID["/root/A"] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.nodesByID["/root/C"] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id])
        state.entryViewLayout.selectedIds = [beforeA.id, beforeC.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/source/a",
            afterPath: "/root/A/a",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: "/root/A", generation: 3),
            additionalMoves: [
                .init(
                    beforePath: "/root/source/c",
                    afterPath: "/root/C/c",
                    destinationOwner: .folder(id: "/root/C", generation: 3),
                ),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryQuickLookClient = .previewValue
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: "/root/A",
            folderGeneration: 3,
            .failed(.permissionDenied),
        ))))
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: "/root/C",
            folderGeneration: 3,
            .failed(.permissionDenied),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
    }

    /// EVM-002-command_external_refresh_correlation: root snapshot restart는 additional folder owner도 rebase한다.
    /// - 검증 내용: source/destination owner generation 3이 current node generation 4로 올라가고 terminal이 소비된다.
    /// - 사전 조건: restarted source S·destination C node generation 4와 primaryMigrated 전이.
    /// - 기대 결과: owner generation 4, C coreFinished 뒤 전이 nil.
    func testRootSnapshotRestartRebasesAdditionalOwnersAndSettlesTerminal() async {
        let source = EntryModel.temporaryFolder(id: "/root/S", name: "S")
        let destination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        var state = FileManagerContentState()
        state.entryViewLayout.entries = [source, destination]
        state.entryViewLayout.hierarchy = .init(rootPath: "/root")
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/a",
            afterPath: "/root/b",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: "/root/S/before",
                    afterPath: "/root/C/after",
                    sourceOwner: .folder(id: source.id, generation: 3),
                    destinationOwner: .folder(id: destination.id, generation: 3),
                ),
            ],
        )
        state.pendingIdentityTransition?.primaryMigrated = true
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.rootSnapshotCompleted(
            rootContextGeneration: 0,
            rootFolders: [source, destination],
        ))))
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.additionalMoves.first?.sourceOwner,
            .folder(id: source.id, generation: 4),
        )
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.additionalMoves.first?.destinationOwner,
            .folder(id: destination.id, generation: 4),
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: destination.id,
            folderGeneration: 4,
            .event(.coreFinished(batchCount: 0)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
    }

    /// EVM-002-replacement_reload_snapshot_retention: migrated additional source는 새 hold를 만들지 않는다.
    /// - 검증 내용: explicit sourceOwner와 nil→primary fallback owner 모두 migrated 상태면 deferred replacement를 생성하지 않는다.
    /// - 사전 조건: explicit source S와 primary projection S를 사용하는 nil source pair.
    /// - 기대 결과: 두 상태 모두 deferred replacement == nil.
    func testMigratedAdditionalSourceDoesNotCreateExplicitOrFallbackHold() {
        let feature = FileManagerContentFeature()
        var explicitState = FileManagerContentState()
        explicitState.entryViewLayout.hierarchy = .init(rootPath: "/root")
        explicitState.entryViewLayout.hierarchy.nodesByID["/root/S"] = .init(
            children: [EntryModel.temporaryFolder(id: "/root/S/before", name: "before")],
            loadPhase: .loadingCore,
            generation: 3,
        )
        explicitState.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/a",
            afterPath: "/root/D/a",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: "/root/D", generation: 3),
            additionalMoves: [
                .init(
                    beforePath: "/root/S/before",
                    afterPath: "/root/D/after",
                    sourceOwner: .folder(id: "/root/S", generation: 3),
                    migrated: true,
                ),
            ],
        )
        _ = feature.reduce(
            into: &explicitState,
            action: .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration: 0,
                folderID: "/root/S",
                folderGeneration: 3,
                .event(.coreBatch(items: [], batchIndex: 0)),
            ))),
        )
        XCTAssertNil(explicitState.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: "/root/S"))

        var fallbackState = FileManagerContentState()
        fallbackState.entryViewLayout.hierarchy = .init(rootPath: "/root")
        fallbackState.entryViewLayout.hierarchy.nodesByID["/root/S"] = .init(
            children: [EntryModel.temporaryFolder(id: "/root/S/before", name: "before")],
            loadPhase: .loadingCore,
            generation: 3,
        )
        fallbackState.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/S/a",
            afterPath: "/root/S/b",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: "/root/S", generation: 3),
            additionalMoves: [
                .init(
                    beforePath: "/root/S/additional",
                    afterPath: "/root/D/additional",
                    sourceOwner: nil,
                    destinationOwner: .folder(id: "/root/D", generation: 3),
                    migrated: true,
                ),
            ],
        )
        fallbackState.pendingIdentityTransition?.primaryMigrated = true
        _ = feature.reduce(
            into: &fallbackState,
            action: .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration: 0,
                folderID: "/root/S",
                folderGeneration: 3,
                .event(.coreBatch(items: [], batchIndex: 0)),
            ))),
        )
        XCTAssertNil(fallbackState.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: "/root/S"))
    }

    /// EVM-002-replacement_reload_snapshot_retention: nil additional root source는 primary root fallback으로 hold한다.
    /// - 검증 내용: sourceOwner nil + primary root 조합이 streamFinished projection을 migration 전까지 유지한다.
    /// - 사전 조건: nil sourceOwner additional pair가 미이전 상태다.
    /// - 기대 결과: migration 전 true, migration 후 false.
    func testNilAdditionalRootSourceOwnerHoldsProjectionUntilMigration() {
        var state = FileManagerContentState()
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/a",
            afterPath: "/root/b",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: "/root/additional",
                    afterPath: "/root/C/additional",
                    sourceOwner: nil,
                    destinationOwner: .folder(id: "/root/C", generation: 3),
                ),
            ],
        )
        let terminal: FileManagerContentAction = .entryViewLayout(
            .entryOperations(.loading(.streamFinished(generation: 1))),
        )

        XCTAssertTrue(
            FileManagerContentIdentityTransitionCoordinator.holdsRootProjection(on: terminal, state: state),
        )
        state.pendingIdentityTransition?.additionalMoves[0].migrated = true
        XCTAssertFalse(
            FileManagerContentIdentityTransitionCoordinator.holdsRootProjection(on: terminal, state: state),
        )
    }

    /// EVM-002-replacement_reload_snapshot_retention: nil additional folder source는 primary folder fallback으로 hold한다.
    /// - 검증 내용: sourceOwner nil + primary folder 조합이 deferred replacement를 migration hold로 생성한다.
    /// - 사전 조건: primary projection owner C generation 3과 nil sourceOwner pair.
    /// - 기대 결과: C deferred replacement의 holdsUntilMigration == true.
    func testNilAdditionalFolderSourceOwnerHoldsProjectionUntilMigration() {
        var state = FileManagerContentState()
        state.entryViewLayout.hierarchy = .init(rootPath: "/root")
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/C/a",
            afterPath: "/root/C/b",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: "/root/C", generation: 3),
            additionalMoves: [
                .init(
                    beforePath: "/root/C/additional",
                    afterPath: "/root/D/additional",
                    sourceOwner: nil,
                    destinationOwner: .folder(id: "/root/D", generation: 3),
                ),
            ],
        )

        FileManagerContentIdentityTransitionCoordinator.beginDeferredFolderReplacementIfNeeded(
            folderID: "/root/C",
            items: [],
            state: &state,
        )

        XCTAssertEqual(
            state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: "/root/C")?.holdsUntilMigration,
            true,
        )
    }

    /// EVM-002-replacement_reload_snapshot_retention: identity invalidation 뒤 batchless source terminal도 보존한다.
    /// - 검증 내용: entryActionCompleted가 pre-arm한 hold가 emitted invalidation/startLoad를 지나 coreFinished까지 유지된다.
    /// - 사전 조건: 서로 다른 expanded source 폴더의 두 선택이 같은 expanded destination으로 이동한다.
    /// - 기대 결과: source terminal 뒤 before 행 유지, destination migration 뒤 source staging 커밋 및 전이 소비.
    func testBatchlessAdditionalFolderSourceCompletionHoldsProjectionUntilMigration() async {
        let rootPath = "/root"
        let sourceA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let sourceC = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let destination = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let beforeA = EntryModel.temporaryFolder(id: "/root/A/before", name: "before")
        let beforeC = EntryModel.temporaryFolder(id: "/root/C/before", name: "before")
        let afterA = EntryModel.temporaryFolder(id: "/root/D/afterA", name: "afterA")
        let afterC = EntryModel.temporaryFolder(id: "/root/D/afterC", name: "afterC")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entries = [sourceA, sourceC, destination]
        state.entryViewLayout.entryOperations.items = [sourceA, sourceC, destination]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[sourceA.id] = .init(
            children: [beforeA],
            loadPhase: .loaded,
            generation: 3,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[sourceC.id] = .init(
            children: [beforeC],
            loadPhase: .loaded,
            generation: 3,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 3,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([sourceA.id, sourceC.id, destination.id])
        state.entryViewLayout.selectedIds = [beforeA.id, beforeC.id]
        state.entryViewLayout.lastSelectedId = beforeA.id
        state.entryViewLayout.rangeAnchorId = beforeA.id
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [
                .init(beforePath: beforeA.id, afterPath: afterA.id),
                .init(beforePath: beforeC.id, afterPath: afterC.id),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryQuickLookClient = .previewValue
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in AsyncThrowingStream { _ in } }
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: sourceC.id)?
                .holdsUntilMigration,
            true,
        )
        await store.receive { action in
            guard case .entryViewLayout(.hierarchy(.hierarchyInvalidated)) = action else { return false }
            return true
        }
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[sourceC.id]?.generation, 4)
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: sourceC.id)?
                .holdsUntilMigration,
            true,
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: sourceC.id,
            folderGeneration: 4,
            .event(.coreFinished(batchCount: 0)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[sourceC.id]?.folder.children.map(\.id),
            [beforeC.id],
        )
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.contains(beforeC.id))
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destination.id,
            folderGeneration: 4,
            .event(.coreBatch(items: [afterA, afterC], batchIndex: 0)),
        ))))
        XCTAssertEqual(Set(store.state.entryViewLayout.selectedIds), [afterA.id, afterC.id])
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[sourceC.id]?.folder.children, [])
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destination.id,
            folderGeneration: 4,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
        await store.skipInFlightEffects()
    }

    /// EVM-002-replacement_reload_snapshot_retention: destination-first nil source fallback은 source terminal 뒤 해제된다.
    /// - 검증 내용: 같은 effective source S를 공유하는 nil-owner pair 2건이 순차 migration될 때 hold 수명을 추적한다.
    /// - 사전 조건: primary X→S, additional S→D·S→E 이동이 entryActionCompleted invalidation을 통과한다.
    /// - 기대 결과: D·E 뒤 hold와 staged snapshot을 유지하고, 늦은 S terminal 뒤 현재 snapshot을 커밋한다.
    func testDestinationFirstNilFallbackSourceHoldCommitsAfterSourceTerminal() async {
        let rootPath = "/root"
        let source = EntryModel.temporaryFolder(id: "/root/X", name: "X")
        let shared = EntryModel.temporaryFolder(id: "/root/S", name: "S")
        let destinationD = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let destinationE = EntryModel.temporaryFolder(id: "/root/E", name: "E")
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/X/p", name: "p")
        let beforeQ = EntryModel.temporaryFolder(id: "/root/S/q", name: "q")
        let beforeR = EntryModel.temporaryFolder(id: "/root/S/r", name: "r")
        let afterPrimary = EntryModel.temporaryFolder(id: "/root/S/p-prime", name: "p-prime")
        let afterQ = EntryModel.temporaryFolder(id: "/root/D/q-prime", name: "q-prime")
        let afterR = EntryModel.temporaryFolder(id: "/root/E/r-prime", name: "r-prime")
        let kept = EntryModel.temporaryFolder(id: "/root/S/kept", name: "kept")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entries = [source, shared, destinationD, destinationE]
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        for (folder, children) in [
            (source, [beforePrimary]),
            (shared, [beforeQ, beforeR]),
            (destinationD, []),
            (destinationE, []),
        ] {
            state.entryViewLayout.hierarchy.nodesByID[folder.id] = .init(
                children: children,
                loadPhase: .loaded,
                generation: 3,
                coreFinished: true,
            )
        }
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, shared.id, destinationD.id, destinationE.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeQ.id, beforeR.id]
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [
                .init(beforePath: beforePrimary.id, afterPath: afterPrimary.id),
                .init(beforePath: beforeQ.id, afterPath: afterQ.id),
                .init(beforePath: beforeR.id, afterPath: afterR.id),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryQuickLookClient = .previewValue
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in AsyncThrowingStream { _ in } }
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))))
        await store.receive { action in
            guard case .entryViewLayout(.hierarchy(.hierarchyInvalidated)) = action else { return false }
            return true
        }
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.additionalMoves.allSatisfy { $0.sourceOwner == nil },
            true,
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationD.id,
            folderGeneration: 4,
            .event(.coreBatch(items: [afterQ], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.map(\.migrated), [true, false])
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: shared.id)?.holdsUntilMigration,
            true,
        )
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: destinationE.id,
            folderGeneration: 4,
            .event(.coreBatch(items: [afterR], batchIndex: 0)),
        ))))
        XCTAssertNotNil(store.state.pendingIdentityTransition)
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: shared.id,
        )?.migrationCompleted, true)
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: shared.id,
            folderGeneration: 4,
            .event(.coreBatch(items: [afterPrimary, kept], batchIndex: 0)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[shared.id]?.folder.children,
            [beforeQ, beforeR],
        )
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: shared.id)?.stagedChildren,
            [afterPrimary, kept],
        )
        XCTAssertEqual(
            Set(store.state.entryViewLayout.selectedIds),
            [afterPrimary.id, afterQ.id, afterR.id],
        )
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: shared.id,
            folderGeneration: 4,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: shared.id))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[shared.id]?.folder.children,
            [afterPrimary, kept],
        )
        await store.skipInFlightEffects()
    }

    /// EVM-002-command_external_refresh_correlation: canonical alias terminal은 lexical owner 하나만 해소한다.
    /// - 검증 내용: 같은 target을 가리키는 두 symlink folder 중 terminal action의 exact lexical owner만 migrated 처리한다.
    /// - 사전 조건: alias A와 alias B가 canonical path를 공유하고 각각 pending additional pair를 소유한다.
    /// - 기대 결과: A terminal 뒤 B pair와 전이가 유지되고 B terminal 뒤에만 전이가 소비된다.
    func testLexicalAliasDestinationTerminalResolvesOnlyExactOwner() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = rootURL.appendingPathComponent("target", isDirectory: true)
        let aliasAURL = rootURL.appendingPathComponent("alias-a")
        let aliasBURL = rootURL.appendingPathComponent("alias-b")
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasAURL, withDestinationURL: targetURL)
        try FileManager.default.createSymbolicLink(at: aliasBURL, withDestinationURL: targetURL)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let beforeA = EntryModel.temporaryFolder(id: rootURL.appendingPathComponent("before-a").path, name: "before-a")
        let beforeB = EntryModel.temporaryFolder(id: rootURL.appendingPathComponent("before-b").path, name: "before-b")
        let aliasA = EntryModel.temporaryFolder(id: aliasAURL.path, name: "alias-a")
        let aliasB = EntryModel.temporaryFolder(id: aliasBURL.path, name: "alias-b")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootURL.path)
        state.entryViewLayout.entries = [beforeA, beforeB, aliasA, aliasB]
        state.entryViewLayout.entryOperations.items = [beforeA, beforeB, aliasA, aliasB]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootURL.path)
        state.entryViewLayout.hierarchy.nodesByID[aliasA.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.nodesByID[aliasB.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([aliasA.id, aliasB.id])
        state.entryViewLayout.selectedIds = [beforeA.id, beforeB.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: rootURL.appendingPathComponent("primary-before").path,
            afterPath: rootURL.appendingPathComponent("primary-after").path,
            rootPath: rootURL.path,
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: beforeA.id,
                    afterPath: aliasAURL.appendingPathComponent("after").path,
                    destinationOwner: .folder(id: aliasA.id, generation: 3),
                ),
                .init(
                    beforePath: beforeB.id,
                    afterPath: aliasBURL.appendingPathComponent("after").path,
                    destinationOwner: .folder(id: aliasB.id, generation: 3),
                ),
            ],
        )
        state.pendingIdentityTransition?.primaryMigrated = true
        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        XCTAssertEqual(
            FileManagerContentIdentityTransitionCoordinator.canonicalizedPath(aliasA.id),
            FileManagerContentIdentityTransitionCoordinator.canonicalizedPath(aliasB.id),
        )
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: aliasA.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 0)),
        ))))
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.map(\.migrated), [true, false])

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: aliasB.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 0)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
    }

    private func completeHeldFolderReload(
        _ store: TestStore<FileManagerContentState, FileManagerContentAction>,
        folderID: EntryModel.ID,
        item: EntryModel,
    ) async {
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folderID,
            folderGeneration: 4,
            .event(.coreBatch(items: [item], batchIndex: 0)),
        ))))
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folderID,
            folderGeneration: 4,
            .event(.coreFinished(batchCount: 1)),
        ))))
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folderID,
            folderGeneration: 4,
            .streamCompleted,
        ))))
    }
}

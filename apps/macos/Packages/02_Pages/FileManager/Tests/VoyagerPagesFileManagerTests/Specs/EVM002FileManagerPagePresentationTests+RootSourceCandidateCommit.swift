import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002FileManagerPagePresentationTests {
    /// EVM-002-replacement_reload_snapshot_retention: primary root source candidate는 destination migration에서 commit된다.
    /// - 검증 내용: before가 visible root entries에 있는 상태에서 buffered candidate가 이를 제거한 뒤 destination을 migration한다.
    /// - 사전 조건: preservationOwner=root이고 expanded destination generation 4가 after batch를 기다린다.
    /// - 기대 결과: applyContentProjection/rootSnapshotCompleted 뒤 root before가 사라지고 after selection은 유지된다.
    func testRootSourceCandidateCommitsOnDestinationMigration() async {
        let fixture = makePrimaryRootSourceCandidateFixture()
        await finishBufferedRootSourceReload(fixture.store, candidate: [fixture.destination])
        let store = makeRootSourceCandidateStore(fixture.store.state)
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.projectionOwner,
            .folder(id: fixture.destination.id, generation: 4),
        )
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[fixture.destination.id]?.generation, 4)

        await store.send(folderResponse(
            fixture.destination.id,
            generation: 4,
            items: [fixture.after],
            batchIndex: 0,
        ))
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await receiveRootCandidateProjection(store, expectedEntries: [fixture.destination])

        XCTAssertEqual(store.state.entryViewLayout.entries, [fixture.destination])
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertFalse(store.state.entryViewLayout.entries.contains(where: { $0.id == fixture.before.id }))
    }

    /// EVM-002-replacement_reload_snapshot_retention: additional root source의 마지막 migration도 candidate를 commit한다.
    /// - 검증 내용: primary destination batch 뒤 root hold를 유지하고 additional after batch에서 candidate를 적용한다.
    /// - 사전 조건: folder-source primary와 root-source nil-owner additional pair가 expanded destination을 공유한다.
    /// - 기대 결과: 첫 batch 뒤 before root row 유지, 두 번째 batch 뒤 before 제거와 두 after selection 보존.
    func testAdditionalRootSourceCandidateCommitsOnDestinationMigration() async {
        let rootPath = "/root"
        let beforeRoot = EntryModel.temporaryFolder(id: "/root/root-before", name: "root-before")
        let source = EntryModel.temporaryFolder(id: "/root/S", name: "S")
        let destination = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/S/p", name: "p")
        let afterPrimary = EntryModel.temporaryFolder(id: "/root/D/p", name: "p")
        let afterAdditional = EntryModel.temporaryFolder(id: "/root/D/q", name: "q")
        var state = bufferedRootSourceState(rootPath: rootPath, entries: [beforeRoot, source, destination])
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            children: [beforePrimary], loadPhase: .loaded, generation: 3, coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeRoot.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: afterPrimary.id,
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            preservationOwner: .folder(id: source.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeRoot.id,
                    afterPath: afterAdditional.id,
                    sourceOwner: .root(generation: 1),
                ),
            ],
        )
        let store = makeRootSourceCandidateStore(state)
        await finishBufferedRootSourceReload(store, candidate: [source, destination])
        let migrationStore = makeRootSourceCandidateStore(store.state)

        await migrationStore.send(folderResponse(destination.id, generation: 4, items: [afterPrimary], batchIndex: 0))
        await migrationStore.receive(\.entryViewLayout.delegate.selectionChanged)
        XCTAssertTrue(migrationStore.state.entryViewLayout.entries.contains(where: { $0.id == beforeRoot.id }))

        await migrationStore.send(folderResponse(
            destination.id,
            generation: 4,
            items: [afterAdditional],
            batchIndex: 1,
        ))
        await migrationStore.receive(\.entryViewLayout.delegate.selectionChanged)
        await receiveRootCandidateProjection(migrationStore, expectedEntries: [source, destination])

        XCTAssertEqual(Set(migrationStore.state.entryViewLayout.entries.map(\.id)), [source.id, destination.id])
        XCTAssertEqual(Set(migrationStore.state.entryViewLayout.selectedIds), [afterPrimary.id, afterAdditional.id])
        XCTAssertFalse(migrationStore.state.entryViewLayout.entries.contains(where: { $0.id == beforeRoot.id }))
    }

    /// EVM-002-replacement_reload_snapshot_retention: stale destination migration은 root candidate를 commit하지 않는다.
    /// - 검증 내용: stale generation after batch를 거부한 뒤 current generation batch에서만 candidate를 적용한다.
    /// - 사전 조건: buffered streamFinished 뒤 visible entries에는 before, authoritative items에는 destination만 있다.
    /// - 기대 결과: stale 뒤 ghost-prevention commit 없음, current 뒤 before 제거와 after selection 보존.
    func testStaleDestinationMigrationDoesNotCommitRootSourceCandidate() async {
        let fixture = makePrimaryRootSourceCandidateFixture()
        await finishBufferedRootSourceReload(fixture.store, candidate: [fixture.destination])
        let store = makeRootSourceCandidateStore(fixture.store.state)
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.projectionOwner,
            .folder(id: fixture.destination.id, generation: 4),
        )
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[fixture.destination.id]?.generation, 4)

        await store.send(folderResponse(
            fixture.destination.id,
            generation: 3,
            items: [fixture.after],
            batchIndex: 0,
        ))
        XCTAssertEqual(
            Set(store.state.entryViewLayout.entries.map(\.id)),
            [fixture.before.id, fixture.hidden.id, fixture.destination.id],
        )
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.before.id])

        await store.send(folderResponse(
            fixture.destination.id,
            generation: 4,
            items: [fixture.after],
            batchIndex: 0,
        ))
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await receiveRootCandidateProjection(store, expectedEntries: [fixture.destination])
        XCTAssertEqual(store.state.entryViewLayout.entries, [fixture.destination])
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
    }

    /// EVM-002-replacement_reload_snapshot_retention: root candidate commit은 제거된 hierarchy subtree를 정리한다.
    /// - 검증 내용: retained rootSnapshot이 materialize한 before child/descendant를 migration commit 뒤 검사한다.
    /// - 사전 조건: authoritative candidate에는 destination만 있고 visible root에는 recursive before subtree가 있다.
    /// - 기대 결과: before root node와 모든 descendant node가 candidate commit에서 제거된다.
    func testRootSourceCandidateCommitReconcilesRemovedHierarchySubtree() async {
        let fixture = makePrimaryRootSourceCandidateFixture()
        await finishBufferedRootSourceReload(fixture.store, candidate: [fixture.destination])
        let store = await migratePrimaryRootCandidate(fixture)

        XCTAssertNil(store.state.entryViewLayout.hierarchy.nodesByID[fixture.before.id])
        XCTAssertNil(store.state.entryViewLayout.hierarchy.nodesByID[fixture.staleChild.id])
        XCTAssertNil(store.state.entryViewLayout.hierarchy.nodesByID[fixture.staleDescendant.id])
    }

    /// EVM-002-replacement_reload_snapshot_retention: root candidate commit은 숨겨진 root selection을 정리한다.
    /// - 검증 내용: before와 hidden root rows를 선택한 retained projection에서 destination migration을 완료한다.
    /// - 사전 조건: candidate에는 선택된 hidden root ID가 없고 destination after만 hierarchy에 도착한다.
    /// - 기대 결과: hidden selection/node는 제거되고 migrated after selection만 유지된다.
    func testRootSourceCandidateCommitReconcilesHiddenSelection() async {
        let fixture = makePrimaryRootSourceCandidateFixture(selectHidden: true)
        await finishBufferedRootSourceReload(fixture.store, candidate: [fixture.destination])
        let store = await migratePrimaryRootCandidate(fixture)

        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertFalse(store.state.entryViewLayout.entries.contains(where: { $0.id == fixture.hidden.id }))
        XCTAssertNil(store.state.entryViewLayout.hierarchy.nodesByID[fixture.hidden.id])
    }

    /// EVM-002-replacement_reload_snapshot_retention: root candidate reconciliation은 active destination load를
    /// 재시작하지 않는다.
    /// - 검증 내용: generation 4 destination after batch 직후 candidate commit의 node generation/loadPhase를 검사한다.
    /// - 사전 조건: streamFinished root snapshot이 destination을 generation 4 loadingCore로 시작했다.
    /// - 기대 결과: candidate commit 뒤에도 generation 4와 current after children이 그대로 유지된다.
    func testRootSourceCandidateCommitPreservesActiveDestinationGeneration() async {
        let fixture = makePrimaryRootSourceCandidateFixture()
        await finishBufferedRootSourceReload(fixture.store, candidate: [fixture.destination])
        let store = await migratePrimaryRootCandidate(fixture)

        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[fixture.destination.id]?.generation, 4)
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[fixture.destination.id]?.loadPhase, .loadingCore)
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[fixture.destination.id]?.folder.children,
            [fixture.after],
        )
    }

    private func makePrimaryRootSourceCandidateFixture(
        selectHidden: Bool = false,
    ) -> PrimaryRootSourceCandidateFixture {
        let before = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        let hidden = EntryModel.temporaryFolder(id: "/root/hidden", name: ".hidden")
        let destination = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let after = EntryModel.temporaryFolder(id: "/root/D/after", name: "after")
        let staleChild = EntryModel.temporaryFolder(id: "/root/before/stale", name: "stale")
        let staleDescendant = EntryModel.temporaryFolder(id: "/root/before/stale/child", name: "child")
        var state = bufferedRootSourceState(rootPath: "/root", entries: [before, hidden, destination])
        state.entryViewLayout.hierarchy.nodesByID[before.id] = .init(
            children: [staleChild], loadPhase: .loaded, generation: 2, coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[staleChild.id] = .init(
            folder: .init(children: [staleDescendant], coreFinished: true, hasAppliedContentBatch: true),
            parentID: before.id,
            generation: 2,
            loadPhase: .loaded,
        )
        state.entryViewLayout.hierarchy.nodesByID[staleDescendant.id] = .init(
            parentID: staleChild.id, generation: 1, loadPhase: .loaded,
        )
        state.entryViewLayout.hierarchy.nodesByID[hidden.id] = .init(
            children: [], loadPhase: .loaded, generation: 1, coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([before.id, staleChild.id, destination.id])
        state.entryViewLayout.selectedIds = selectHidden ? [before.id, hidden.id] : [before.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: after.id,
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            preservationOwner: .root(generation: 1),
        )
        return .init(
            store: makeRootSourceCandidateStore(state),
            before: before,
            hidden: hidden,
            destination: destination,
            after: after,
            staleChild: staleChild,
            staleDescendant: staleDescendant,
        )
    }

    private func migratePrimaryRootCandidate(
        _ fixture: PrimaryRootSourceCandidateFixture,
    ) async -> TestStore<FileManagerContentState, FileManagerContentAction> {
        let store = makeRootSourceCandidateStore(fixture.store.state)
        await store.send(folderResponse(
            fixture.destination.id,
            generation: 4,
            items: [fixture.after],
            batchIndex: 0,
        ))
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await receiveRootCandidateProjection(store, expectedEntries: [fixture.destination])
        return store
    }

    private func bufferedRootSourceState(
        rootPath: String,
        entries: [EntryModel],
    ) -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entries = entries
        state.entryViewLayout.entryOperations.items = IdentifiedArray(uniqueElements: entries)
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.loadingContext.preservedDirectoryReloadItems = []
        state.entryViewLayout.entryOperations.isReloading = true
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        return state
    }

    private func makeRootSourceCandidateStore(
        _ state: FileManagerContentState,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryQuickLookClient = .previewValue
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in AsyncThrowingStream { _ in } }
        }
        store.exhaustivity = .off
        return store
    }

    private func finishBufferedRootSourceReload(
        _ store: TestStore<FileManagerContentState, FileManagerContentAction>,
        candidate: [EntryModel],
    ) async {
        let retainedIDs = Set(store.state.entryViewLayout.entries.map(\.id))
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: candidate, batchIndex: 0),
        ))))))
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreFinished(batchCount: 1),
        ))))))
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFinished(generation: 1)))))
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else { return false }
            return Set(projection.entries.map(\.id)) == retainedIDs
        }
        await store.receive(\.entryViewLayout.hierarchy.rootSnapshotCompleted)
        if case let .folder(destinationID, generation) = store.state.pendingIdentityTransition?.projectionOwner {
            await store.receive(\.entryViewLayout.delegate.expandRequested, destinationID)
            await store.receive { action in
                guard case let .entryViewLayout(.entryOperations(.loading(.loadFolderItems(request)))) = action
                else { return false }
                return request.id.folderID == destinationID && request.folderGeneration == generation
            }
            await store.skipInFlightEffects()
        }
        XCTAssertEqual(Set(store.state.entryViewLayout.entries.map(\.id)), retainedIDs)
        XCTAssertEqual(Array(store.state.entryViewLayout.entryOperations.items), candidate)
    }

    private func receiveRootCandidateProjection(
        _ store: TestStore<FileManagerContentState, FileManagerContentAction>,
        expectedEntries: [EntryModel],
    ) async {
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else { return false }
            return Set(projection.entries.map(\.id)) == Set(expectedEntries.map(\.id))
        }
        await store.receive(\.entryViewLayout.hierarchy.rootSnapshotReconciled)
    }

    private func folderResponse(
        _ folderID: EntryModel.ID,
        generation: Int,
        items: [EntryModel],
        batchIndex: Int,
    ) -> FileManagerContentAction {
        .entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folderID,
            folderGeneration: generation,
            .event(.coreBatch(items: items, batchIndex: batchIndex)),
        )))
    }
}

private struct PrimaryRootSourceCandidateFixture {
    let store: TestStore<FileManagerContentState, FileManagerContentAction>
    let before: EntryModel
    let hidden: EntryModel
    let destination: EntryModel
    let after: EntryModel
    let staleChild: EntryModel
    let staleDescendant: EntryModel
}

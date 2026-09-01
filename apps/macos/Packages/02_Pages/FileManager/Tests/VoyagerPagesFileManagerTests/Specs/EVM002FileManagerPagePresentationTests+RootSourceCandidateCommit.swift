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

    /// EVM-002-replacement_reload_snapshot_retention: root 성공 terminal도 primary pair를 정산한다.
    /// primary after가 root projection에서 필터링되어도 pending additional destination까지 primary staging을 붙잡지 않는지 검증한다.
    /// - 검증 내용: root terminal에서 primaryMigrated와 primary source staging을 정산하고 additional pair는 유지한다.
    /// - 사전 조건: root primary pair와 별도 expanded destination additional pair, primary source의 staged snapshot이 있다.
    /// - 기대 결과: primary source children과 stale selection은 즉시 정산되고 additional pair만 pending으로 남는다.
    func testRootSuccessSettlesPrimaryPairWithPendingAdditionalDestination() {
        let rootPath = "/root"
        let primarySource = EntryModel.temporaryFolder(id: "/root/S1", name: "S1")
        let additionalSource = EntryModel.temporaryFolder(id: "/root/S2", name: "S2")
        let additionalDestination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let primaryBefore = EntryModel.temporaryFolder(id: "/root/S1/a", name: "a")
        let additionalBefore = EntryModel.temporaryFolder(id: "/root/S2/b", name: "b")
        var state = bufferedRootSourceState(
            rootPath: rootPath,
            entries: [primaryBefore, additionalBefore, additionalDestination],
        )
        state.entryViewLayout.hierarchy.nodesByID[primarySource.id] = .init(
            children: [primaryBefore],
            loadPhase: .enriching,
            generation: 3,
            coreFinished: true,
            hasAppliedContentBatch: false,
        )
        state.entryViewLayout.hierarchy.nodesByID[additionalSource.id] = .init(
            children: [additionalBefore],
            loadPhase: .loadingCore,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.nodesByID[additionalDestination.id] = .init(
            generation: 3,
            loadPhase: .loadingCore,
        )
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: primarySource.id,
            untilEntryID: "/root/primary-after",
            holdsUntilMigration: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([
            primarySource.id,
            additionalSource.id,
            additionalDestination.id,
        ])
        state.entryViewLayout.selectedIds = [primaryBefore.id, additionalBefore.id]
        state.entryViewLayout.lastSelectedId = primaryBefore.id
        state.entryViewLayout.rangeAnchorId = primaryBefore.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: primaryBefore.id,
            afterPath: "/root/primary-after",
            rootPath: rootPath,
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: .folder(id: primarySource.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: additionalBefore.id,
                    afterPath: "/root/C/b",
                    sourceOwner: .folder(id: additionalSource.id, generation: 3),
                    destinationOwner: .folder(id: additionalDestination.id, generation: 3),
                ),
            ],
        )

        let terminalized = FileManagerContentIdentityTransitionCoordinator.resolveRootDestinationSuccess(
            generation: 1,
            state: &state,
        )

        XCTAssertTrue(terminalized)
        XCTAssertEqual(state.pendingIdentityTransition?.primaryMigrated, true)
        XCTAssertEqual(state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
        XCTAssertEqual(state.entryViewLayout.hierarchy.nodesByID[primarySource.id]?.folder.children, [])
        XCTAssertNil(state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: primarySource.id))
        XCTAssertFalse(state.entryViewLayout.selectedIds.contains(primaryBefore.id))
        XCTAssertTrue(state.entryViewLayout.selectedIds.contains(additionalBefore.id))
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

    /// EVM-002-replacement_reload_snapshot_retention: destination collapse terminal도 root candidate를 commit한다.
    /// - 검증 내용: buffered candidate가 before를 제거한 뒤 destination collapse로 root source hold를 해제한다.
    /// - 사전 조건: expanded destination generation 4와 pending primary root preservation owner가 있다.
    /// - 기대 결과: collapse response 없이 transition을 닫고 authoritative root entries/subtree를 적용한다.
    func testRootSourceCandidateCommitsOnDestinationCollapse() async {
        let fixture = makePrimaryRootSourceCandidateFixture()
        await finishBufferedRootSourceReload(fixture.store, candidate: [fixture.destination])
        let store = makeRootSourceCandidateStore(fixture.store.state)

        await store.send(.entryViewLayout(.hierarchy(.folderCollapseRequested(id: fixture.destination.id))))
        await receiveRootCandidateProjection(store, expectedEntries: [fixture.destination])

        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertEqual(store.state.entryViewLayout.entries, [fixture.destination])
        XCTAssertNil(store.state.entryViewLayout.hierarchy.nodesByID[fixture.before.id])
        store.exhaustivity = .on
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await store.receive(\.entryViewLayout.entryOperations.lifecycle.syncSelectedEntryIDs)
        await store.receive(\.delegate.currentContextChanged)
        await store.finish()
    }

    /// EVM-002-replacement_reload_snapshot_retention: destination failure terminal도 root candidate를 commit한다.
    /// - 검증 내용: after 없는 accepted folder failure가 root source hold와 ghost before row를 함께 정리한다.
    /// - 사전 조건: buffered root candidate는 authoritative destination만 포함한다.
    /// - 기대 결과: transition/source hold 종료와 applyContentProjection/root reconciliation이 한 번 발생한다.
    func testRootSourceCandidateCommitsOnDestinationFailure() async {
        let fixture = makePrimaryRootSourceCandidateFixture()
        await finishBufferedRootSourceReload(fixture.store, candidate: [fixture.destination])
        let store = makeRootSourceCandidateStore(fixture.store.state)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: fixture.destination.id,
            folderGeneration: 4,
            .failed(.permissionDenied),
        ))))
        await receiveRootCandidateProjection(store, expectedEntries: [fixture.destination])

        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertEqual(store.state.entryViewLayout.entries, [fixture.destination])
        XCTAssertNil(store.state.entryViewLayout.hierarchy.nodesByID[fixture.before.id])
    }

    func testRootSourceCandidateCommitsOnDestinationSuccessWithoutAfterRow() async {
        let fixture = makePrimaryRootSourceCandidateFixture()
        await finishBufferedRootSourceReload(fixture.store, candidate: [fixture.destination])
        let store = makeRootSourceCandidateStore(fixture.store.state)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: fixture.destination.id,
            folderGeneration: 4,
            .event(.coreFinished(batchCount: 0)),
        ))))
        await receiveRootCandidateProjection(store, expectedEntries: [fixture.destination])

        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertEqual(store.state.entryViewLayout.entries, [fixture.destination])
        XCTAssertNil(store.state.entryViewLayout.hierarchy.nodesByID[fixture.before.id])
    }

    /// EVM-002-command_external_refresh_correlation: successful root terminal은 누락 additional root pair도 종결한다.
    /// - 검증 내용: folder primary migration 뒤 root candidate에 additional after가 없는 streamFinished를 처리한다.
    /// - 사전 조건: primary destination A는 migrated, additional root pair와 shared source D hold는 pending이다.
    /// - 기대 결과: root terminal이 pair/source hold/transition을 정리하고 candidate projection을 유지한다.
    func testRootSuccessTerminalSettlesMissingAdditionalPair() async {
        let source = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let destination = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/D/p", name: "p")
        let beforeAdditional = EntryModel.temporaryFolder(id: "/root/D/q", name: "q")
        let afterPrimary = EntryModel.temporaryFolder(id: "/root/A/p", name: "p")
        var state = bufferedRootSourceState(rootPath: "/root", entries: [source, destination])
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            folder: .init(
                children: [beforePrimary, beforeAdditional],
                retainsPreviousGenerationChildren: true,
            ),
            generation: 3,
            loadPhase: .loadingCore,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeAdditional.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: afterPrimary.id,
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            preservationOwner: .folder(id: source.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeAdditional.id,
                    afterPath: "/root/missing-after",
                    sourceOwner: .folder(id: source.id, generation: 3),
                    destinationOwner: .root(generation: 1),
                ),
            ],
        )
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: source.id,
            untilEntryID: "/root/missing-after",
            holdsUntilMigration: true,
        )
        let store = makeRootSourceCandidateStore(state)

        await store.send(folderResponse(destination.id, generation: 3, items: [afterPrimary], batchIndex: 0))
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await finishBufferedRootSourceReload(store, candidate: [source, destination])

        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: source.id))
        XCTAssertEqual(Set(store.state.entryViewLayout.entries.map(\.id)), [source.id, destination.id])
        let retainedChildren = store.state.entryViewLayout.hierarchy.nodesByID[source.id]?.folder.children
        XCTAssertEqual(retainedChildren, [beforePrimary, beforeAdditional])
    }

    /// EVM-002-replacement_reload_snapshot_retention: primary failure는 unrelated destination 전에 root candidate를
    /// commit한다.
    /// - 검증 내용: A failure 뒤 candidate projection/root reconciliation과 pending C pair를 함께 검사한다.
    /// - 사전 조건: primary source는 root, unrelated additional destination C와 folder source S hold가 pending이다.
    /// - 기대 결과: root before ghost는 즉시 제거되고 transition/C pair/S hold는 유지된다.
    func testRootSourceCandidateCommitsOnPrimaryFailureWithUnrelatedPendingDestination() async {
        let fixture = makePrimaryFailureWithUnrelatedDestinationFixture()
        await finishBufferedRootSourceReload(
            fixture.store,
            candidate: [fixture.source, fixture.primaryDestination, fixture.additionalDestination],
        )
        let store = makeRootSourceCandidateStore(fixture.store.state)

        await store.send(primaryDestinationFailure(fixture))
        await receiveRootCandidateProjection(
            store,
            expectedEntries: [fixture.source, fixture.primaryDestination, fixture.additionalDestination],
        )

        XCTAssertFalse(store.state.entryViewLayout.entries.contains(where: { $0.id == fixture.beforePrimary.id }))
        XCTAssertNotNil(store.state.pendingIdentityTransition)
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
        XCTAssertNotNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: fixture.source.id,
        ))
    }

    /// EVM-002-command_external_refresh_correlation: primary failure candidate commit은 unrelated transition을 유지한다.
    /// - 검증 내용: A failure commit 뒤 C failure terminal까지 transition/source staging 수명을 추적한다.
    /// - 사전 조건: A와 C는 generation 4, primary root hold와 additional folder-source hold가 분리돼 있다.
    /// - 기대 결과: A 뒤 pending, C 뒤 transition과 S hold가 종료된다.
    func testRootSourceCandidateCommitKeepsUnrelatedDestinationTransition() async {
        let fixture = makePrimaryFailureWithUnrelatedDestinationFixture()
        await finishBufferedRootSourceReload(
            fixture.store,
            candidate: [fixture.source, fixture.primaryDestination, fixture.additionalDestination],
        )
        let store = makeRootSourceCandidateStore(fixture.store.state)

        await store.send(primaryDestinationFailure(fixture))
        await receiveRootCandidateProjection(
            store,
            expectedEntries: [fixture.source, fixture.primaryDestination, fixture.additionalDestination],
        )
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: fixture.additionalDestination.id,
            folderGeneration: 4,
            .failed(.permissionDenied),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: fixture.source.id))
    }

    /// EVM-002-replacement_reload_snapshot_retention: repeated primary failure는 candidate를 중복 commit하지 않는다.
    /// - 검증 내용: 첫 A failure settlement 상태를 fresh TestStore로 넘겨 같은 failure를 다시 보낸다.
    /// - 사전 조건: candidate는 이미 applied/reconciled됐고 unrelated C pair만 transition에 남아 있다.
    /// - 기대 결과: 두 번째 failure는 projection effect 없이 상태를 그대로 유지한다.
    func testRootSourceCandidateFailureReleaseIsIdempotent() async {
        let fixture = makePrimaryFailureWithUnrelatedDestinationFixture()
        await finishBufferedRootSourceReload(
            fixture.store,
            candidate: [fixture.source, fixture.primaryDestination, fixture.additionalDestination],
        )
        let firstStore = makeRootSourceCandidateStore(fixture.store.state)
        await firstStore.send(primaryDestinationFailure(fixture))
        await receiveRootCandidateProjection(
            firstStore,
            expectedEntries: [fixture.source, fixture.primaryDestination, fixture.additionalDestination],
        )
        let repeatStore = makeRootSourceCandidateStore(firstStore.state)

        await repeatStore.send(primaryDestinationFailure(fixture))
        await repeatStore.finish()

        XCTAssertNotNil(repeatStore.state.pendingIdentityTransition)
        XCTAssertEqual(
            Set(repeatStore.state.entryViewLayout.entries.map(\.id)),
            [fixture.source.id, fixture.primaryDestination.id, fixture.additionalDestination.id],
        )
    }

    /// EVM-002-replacement_reload_snapshot_retention: primary failure는 additional root source가 끝날 때까지 기다린다.
    /// - 검증 내용: A failure 후 aggregate root-source check actions를 처리하고 visible root/transition을 검사한다.
    /// - 사전 조건: primary와 unrelated C pair의 before rows가 모두 root source이며 candidate에는 둘 다 없다.
    /// - 기대 결과: A failure만으로 candidate를 commit하지 않고 C before/selection/transition을 유지한다.
    func testPrimaryFailureWaitsForAdditionalRootSourceBeforeCandidateCommit() async {
        let fixture = makeAggregateRootSourceFailureFixture()
        await finishBufferedRootSourceReload(
            fixture.store,
            candidate: [fixture.primaryDestination, fixture.additionalDestination],
        )
        let store = makeRootSourceCandidateStore(fixture.store.state)

        await store.send(aggregatePrimaryFailure(fixture))
        await store.skipReceivedActions()

        XCTAssertTrue(store.state.entryViewLayout.entries.contains(where: { $0.id == fixture.beforeAdditional.id }))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.beforePrimary.id, fixture.beforeAdditional.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition)
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
    }

    /// EVM-002-replacement_reload_snapshot_retention: unrelated destination terminal은 final root release에서 한 번
    /// commit한다.
    /// - 검증 내용: A failure no-op 뒤 C failure가 candidate projection/reconciliation을 유일하게 발생시킨다.
    /// - 사전 조건: primary owner는 terminal이고 additional root-source C pair만 pending이다.
    /// - 기대 결과: C terminal 뒤 before rows/transition이 제거되고 authoritative A/C roots만 남는다.
    func testUnrelatedDestinationTerminalCommitsRootCandidateExactlyOnce() async {
        let fixture = makeAggregateRootSourceFailureFixture()
        await finishBufferedRootSourceReload(
            fixture.store,
            candidate: [fixture.primaryDestination, fixture.additionalDestination],
        )
        let store = makeRootSourceCandidateStore(fixture.store.state)
        await store.send(aggregatePrimaryFailure(fixture))
        await store.skipReceivedActions()

        await store.send(aggregateAdditionalFailure(fixture))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertEqual(
            Set(store.state.entryViewLayout.entries.map(\.id)),
            [fixture.primaryDestination.id, fixture.additionalDestination.id],
        )
        XCTAssertFalse(store.state.entryViewLayout.entries.contains(where: { $0.id == fixture.beforeAdditional.id }))

        let repeatStore = makeRootSourceCandidateStore(store.state)
        await repeatStore.send(aggregateAdditionalFailure(fixture))
        await repeatStore.finish()
    }

    /// EVM-002-command_external_refresh_correlation: aggregate root release 전에는 pending selection을 제거하지 않는다.
    /// - 검증 내용: A failure와 check action 뒤 C before의 visible/selected identity를 함께 확인한다.
    /// - 사전 조건: candidate는 두 before rows를 제외하지만 additional root-source pair는 미종결이다.
    /// - 기대 결과: C terminal 전까지 beforeAdditional이 entries와 selectedIds에 모두 남는다.
    func testAggregateRootSourceReleaseDoesNotDropPendingSelection() async {
        let fixture = makeAggregateRootSourceFailureFixture()
        await finishBufferedRootSourceReload(
            fixture.store,
            candidate: [fixture.primaryDestination, fixture.additionalDestination],
        )
        let store = makeRootSourceCandidateStore(fixture.store.state)

        await store.send(aggregatePrimaryFailure(fixture))
        await store.skipReceivedActions()

        XCTAssertTrue(store.state.entryViewLayout.entries.contains(where: { $0.id == fixture.beforeAdditional.id }))
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.contains(fixture.beforeAdditional.id))
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

    private func makePrimaryFailureWithUnrelatedDestinationFixture() -> PrimaryFailureRootCandidateFixture {
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        let source = EntryModel.temporaryFolder(id: "/root/S", name: "S")
        let primaryDestination = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let additionalDestination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let beforeAdditional = EntryModel.temporaryFolder(id: "/root/S/q", name: "q")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [beforePrimary, source, primaryDestination, additionalDestination],
        )
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            folder: .init(children: [beforeAdditional], retainsPreviousGenerationChildren: true),
            generation: 3,
            loadPhase: .loadingCore,
        )
        for destination in [primaryDestination, additionalDestination] {
            state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
                children: [], loadPhase: .loadingCore, generation: 3,
            )
        }
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, primaryDestination.id, additionalDestination.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeAdditional.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: "/root/A/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: primaryDestination.id, generation: 3),
            preservationOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: beforeAdditional.id,
                    afterPath: "/root/C/q",
                    sourceOwner: .folder(id: source.id, generation: 3),
                    destinationOwner: .folder(id: additionalDestination.id, generation: 3),
                ),
            ],
        )
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: source.id,
            untilEntryID: "/root/C/q",
            holdsUntilMigration: true,
        )
        return .init(
            store: makeRootSourceCandidateStore(state),
            source: source,
            primaryDestination: primaryDestination,
            additionalDestination: additionalDestination,
            beforePrimary: beforePrimary,
        )
    }

    private func makeAggregateRootSourceFailureFixture() -> AggregateRootSourceFailureFixture {
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/p", name: "p")
        let beforeAdditional = EntryModel.temporaryFolder(id: "/root/q", name: "q")
        let primaryDestination = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let additionalDestination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [beforePrimary, beforeAdditional, primaryDestination, additionalDestination],
        )
        for destination in [primaryDestination, additionalDestination] {
            state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
                children: [], loadPhase: .loadingCore, generation: 3,
            )
        }
        state.entryViewLayout.hierarchy.setExpandedIDs([primaryDestination.id, additionalDestination.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeAdditional.id]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: "/root/A/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: primaryDestination.id, generation: 3),
            preservationOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: beforeAdditional.id,
                    afterPath: "/root/C/after",
                    sourceOwner: .root(generation: 1),
                    destinationOwner: .folder(id: additionalDestination.id, generation: 3),
                ),
            ],
        )
        return .init(
            store: makeRootSourceCandidateStore(state),
            primaryDestination: primaryDestination,
            additionalDestination: additionalDestination,
            beforePrimary: beforePrimary,
            beforeAdditional: beforeAdditional,
        )
    }

    private func primaryDestinationFailure(
        _ fixture: PrimaryFailureRootCandidateFixture,
    ) -> FileManagerContentAction {
        .entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: fixture.primaryDestination.id,
            folderGeneration: 4,
            .failed(.permissionDenied),
        )))
    }

    private func aggregatePrimaryFailure(
        _ fixture: AggregateRootSourceFailureFixture,
    ) -> FileManagerContentAction {
        .entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: fixture.primaryDestination.id,
            folderGeneration: 4,
            .failed(.permissionDenied),
        )))
    }

    private func aggregateAdditionalFailure(
        _ fixture: AggregateRootSourceFailureFixture,
    ) -> FileManagerContentAction {
        .entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: fixture.additionalDestination.id,
            folderGeneration: 4,
            .failed(.permissionDenied),
        )))
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

    func bufferedRootSourceState(
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

    func makeRootSourceCandidateStore(
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

    func finishBufferedRootSourceReload(
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

    func receiveRootCandidateProjection(
        _ store: TestStore<FileManagerContentState, FileManagerContentAction>,
        expectedEntries: [EntryModel],
    ) async {
        await store.receive { action in
            guard case let .entryViewLayout(.view(.applyContentProjection(projection))) = action else { return false }
            return Set(projection.entries.map(\.id)) == Set(expectedEntries.map(\.id))
        }
        await store.receive(\.entryViewLayout.hierarchy.rootSnapshotReconciled)
    }

    func folderResponse(
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

private struct PrimaryFailureRootCandidateFixture {
    let store: TestStore<FileManagerContentState, FileManagerContentAction>
    let source: EntryModel
    let primaryDestination: EntryModel
    let additionalDestination: EntryModel
    let beforePrimary: EntryModel
}

private struct AggregateRootSourceFailureFixture {
    let store: TestStore<FileManagerContentState, FileManagerContentAction>
    let primaryDestination: EntryModel
    let additionalDestination: EntryModel
    let beforePrimary: EntryModel
    let beforeAdditional: EntryModel
}

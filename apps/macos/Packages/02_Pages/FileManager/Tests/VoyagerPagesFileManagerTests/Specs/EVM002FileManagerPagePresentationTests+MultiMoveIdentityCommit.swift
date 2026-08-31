import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002FileManagerPagePresentationTests {
    /// 다중 이동에서 additional pair가 anchor identity를 가리키면 primary migration이 anchor를 덮어쓰지 않는다.
    /// - 검증 내용: primary batch migration 뒤 lastSelectedId/rangeAnchorId가 additional before에 남는다.
    /// - 사전 조건: anchor가 pending additional pair의 before를 가리키고 primary after만 배치에 도착한다.
    /// - 기대 결과: anchor는 additional pair가 migration될 때까지 원래 identity를 유지한다.
    func testPrimaryMigrationPreservesAdditionalAnchorIdentity() async {
        let before = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        let after = EntryModel.temporaryFolder(id: "/root/D/after", name: "after")
        let destination = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        let beforeAdditional = EntryModel.temporaryFolder(id: "/root/S/q", name: "q")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [before, beforeAdditional, destination],
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destination.id])
        state.entryViewLayout.selectedIds = [before.id, beforeAdditional.id]
        state.entryViewLayout.lastSelectedId = beforeAdditional.id
        state.entryViewLayout.rangeAnchorId = beforeAdditional.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: after.id,
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            preservationOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: beforeAdditional.id,
                    afterPath: "/root/B/q",
                    sourceOwner: nil,
                    destinationOwner: .folder(id: "/root/B", generation: 3),
                ),
            ],
        )
        let store = makeRootSourceCandidateStore(state)

        await store.send(folderResponse(destination.id, generation: 3, items: [after], batchIndex: 0))

        XCTAssertEqual(store.state.entryViewLayout.lastSelectedId, beforeAdditional.id)
        XCTAssertEqual(store.state.entryViewLayout.rangeAnchorId, beforeAdditional.id)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [after.id, beforeAdditional.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition)
    }

    /// terminalized additional pair의 source staging은 즉시 커밋되고 pending pair의 staging은 유지된다.
    /// - 검증 내용: C terminal 뒤 S1 staging 커밋, S2 staging 보류, 전이 생존을 함께 검사한다.
    /// - 사전 조건: 서로 다른 source·destination의 pending pair 2개와 root 보존 primary가 있다.
    /// - 기대 결과: terminalized pair의 ghost before 행이 사라지고 다른 destination hold는 남는다.
    func testAdditionalTerminalCommitsTerminalizedPairSourceStaging() async {
        let state = makeMultiMoveSourceStagingState()
        let s1 = "/root/S1"
        let s2 = "/root/S2"
        let cDestination = "/root/C"
        let store = makeRootSourceCandidateStore(state)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: cDestination,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 0)),
        ))))

        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: s1))
        XCTAssertNotNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: s2))
        XCTAssertNotNil(store.state.pendingIdentityTransition)
    }

    /// 완료된 primary의 collapse로 세대가 어긋나도 pending destination 소유자가 current면 전이를 유지한다.
    /// - 검증 내용: primary stale 상태에서 additional 경로 rename FSEvent가 와도 discard하지 않는다.
    /// - 사전 조건: primaryMigrated=true, primary node는 collapse로 세대 증가, pending B pair는 current.
    /// - 기대 결과: 전이와 pending pair가 생존해 이후 destination batch의 selection migration을 보존한다.
    func testStalePrimaryKeepsPendingDestinationTransitionOnOverlapEvent() async {
        let primaryA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let destinationB = EntryModel.temporaryFolder(id: "/root/B", name: "B")
        var state = bufferedRootSourceState(rootPath: "/root", entries: [primaryA, destinationB])
        // collapse로 세대가 bump된 primary: owner 기록 세대 3, node는 4.
        state.entryViewLayout.hierarchy.nodesByID[primaryA.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 4,
        )
        state.entryViewLayout.hierarchy.nodesByID[destinationB.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([primaryA.id, destinationB.id])
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/primary",
            afterPath: "/root/A/primary",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: primaryA.id, generation: 3),
            preservationOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: "/root/S/q",
                    afterPath: "/root/B/q",
                    sourceOwner: .folder(id: "/root/S", generation: 3),
                    destinationOwner: .folder(id: destinationB.id, generation: 3),
                ),
            ],
        )
        state.pendingIdentityTransition?.primaryMigrated = true
        let store = makeRootSourceCandidateStore(state)

        await store.send(.externalFileSystemChanged([
            FileChangeGatewayEvent(path: "/root/S/q", flags: 0, emittedAt: .distantPast),
        ]))

        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
        XCTAssertNotNil(store.state.pendingIdentityTransition)
    }

    /// owner-scoped additional pair가 anchor identity를 가리킬 때 root batch migration이 anchor를 함께 이전한다.
    /// - 검증 내용: root 소유자 batch migration 뒤 lastSelectedId/rangeAnchorId가 pair after로 교체된다.
    /// - 사전 조건: anchor가 root destination pair의 before를 가리고 batch에 after 행만 도착한다.
    /// - 기대 결과: stale before anchor가 남지 않아 Quick Look·범위 선택 기준이 유지된다.
    func testOwnerScopedPairMigrationAdvancesAnchorIdentity() async {
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/primary", name: "primary")
        let beforeAdditional = EntryModel.temporaryFolder(id: "/root/S/q", name: "q")
        let afterAdditional = EntryModel.temporaryFolder(id: "/root/after-q", name: "q")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [beforePrimary, beforeAdditional],
        )
        state.entryViewLayout.selectedIds = [beforePrimary.id, beforeAdditional.id]
        state.entryViewLayout.lastSelectedId = beforeAdditional.id
        state.entryViewLayout.rangeAnchorId = beforeAdditional.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: "/root/A/primary",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: beforeAdditional.id,
                    afterPath: afterAdditional.id,
                    sourceOwner: nil,
                    destinationOwner: .root(generation: 1),
                ),
            ],
        )
        let store = makeRootSourceCandidateStore(state)

        await store.send(.entryViewLayout(.entryOperations(.loading(.itemsLoaded([
            beforePrimary,
            afterAdditional,
        ])))))

        XCTAssertEqual(store.state.entryViewLayout.lastSelectedId, afterAdditional.id)
        XCTAssertEqual(store.state.entryViewLayout.rangeAnchorId, afterAdditional.id)
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, true)
    }

    /// primary 공유 root destination의 nil-owner pair도 root 실패 terminal에서 종결한다.
    /// - 검증 내용: root streamFailed 뒤 nil-owner pair는 migrated로 정산되고 folder pair는 유지된다.
    /// - 사전 조건: primary projectionOwner가 root이고 nil-owner pair와 folder pair가 함께 pending이다.
    /// - 기대 결과: nil-owner pair의 staging이 정산돼 source ghost와 echo 억제 잔존이 사라진다.
    func testRootFailureSettlesPrimarySharedNilOwnerPair() async {
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/primary", name: "primary")
        let nilOwnerBefore = EntryModel.temporaryFolder(id: "/root/S/x", name: "x")
        let folderBefore = EntryModel.temporaryFolder(id: "/root/S/y", name: "y")
        let destinationB = EntryModel.temporaryFolder(id: "/root/B", name: "B")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [beforePrimary, nilOwnerBefore, folderBefore, destinationB],
        )
        state.entryViewLayout.hierarchy.nodesByID[destinationB.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destinationB.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, nilOwnerBefore.id, folderBefore.id]
        state.entryViewLayout.entryOperations.loadingContext.streamTerminal = true
        state.entryViewLayout.entryOperations.loadingContext.isIncomplete = true
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: "/root/after-primary",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: nilOwnerBefore.id,
                    afterPath: "/root/after-x",
                    sourceOwner: nil,
                    destinationOwner: nil,
                ),
                .init(
                    beforePath: folderBefore.id,
                    afterPath: "/root/B/y",
                    sourceOwner: .folder(id: "/root/S", generation: 3),
                    destinationOwner: .folder(id: destinationB.id, generation: 3),
                ),
            ],
        )
        let store = makeRootSourceCandidateStore(state)

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFailed(generation: 1)))))

        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.map(\.migrated), [true, false])
        XCTAssertNotNil(store.state.pendingIdentityTransition)
    }

    /// 보존 복원 시 다른 선택 행의 anchor identity는 유지된다.
    /// - 검증 내용: before 행만 잠시 선택에서 제거된 상태에서 복원하면 other 행 anchor가 유지된다.
    /// - 사전 조건: rename 대상과 다른 파일이 함께 선택됐고 Quick Look/Shift 기준은 other 행이다.
    /// - 기대 결과: lastSelectedId/rangeAnchorId가 무조건 primary before로 덮이지 않는다.
    func testPreservationRestoreKeepsOtherSelectedAnchor() {
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        let otherSelected = EntryModel.temporaryFolder(id: "/root/other", name: "other")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [beforePrimary, otherSelected],
        )
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.selectedIds = [beforePrimary.id, otherSelected.id]
        state.entryViewLayout.lastSelectedId = otherSelected.id
        state.entryViewLayout.rangeAnchorId = otherSelected.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: "/root/D/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: nil,
        )
        let trigger = FileManagerContentAction.entryViewLayout(.entryOperations(.loading(.itemsLoaded([
            beforePrimary,
            otherSelected,
        ]))))

        FileManagerContentIdentityTransitionCoordinator.markReplacementSelection(
            on: trigger,
            state: &state,
        )
        XCTAssertEqual(state.pendingIdentityTransition?.preserveSelectionForReplacementBatch, true)

        // 직접 호출 테스트는 projection reconcile을 생략하므로 before 행 제거 상태를 만든다.
        state.entryViewLayout.selectedIds.remove(beforePrimary.id)
        FileManagerContentIdentityTransitionCoordinator.resolveReplacementSelection(
            on: trigger,
            state: &state,
        )

        XCTAssertTrue(state.entryViewLayout.selectedIds.contains(beforePrimary.id), "before 행은 복원된다")
        XCTAssertEqual(state.entryViewLayout.lastSelectedId, otherSelected.id)
        XCTAssertEqual(state.entryViewLayout.rangeAnchorId, otherSelected.id)
    }

    /// before가 유일한 선택이어서 reconcile이 anchor를 비웠으면 복원 시 anchor도 되돌린다.
    /// - 검증 내용: nil anchor 상태에서 복원하면 lastSelectedId/rangeAnchorId가 restored ID로 설정된다.
    /// - 사전 조건: before 단일 선택으로 mark·reconcile되어 anchor가 nil이 된 대기 전이.
    /// - 기대 결과: selected ID뿐 아니라 두 anchor도 복원돼 Shift 기준과 Quick Look 동기화가 유지된다.
    func testPreservationRestoreRestoresNilAnchors() {
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [beforePrimary],
        )
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.selectedIds = [beforePrimary.id]
        state.entryViewLayout.lastSelectedId = beforePrimary.id
        state.entryViewLayout.rangeAnchorId = beforePrimary.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: "/root/D/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: nil,
        )
        let trigger = FileManagerContentAction.entryViewLayout(.entryOperations(.loading(.itemsLoaded([
            beforePrimary,
        ]))))

        FileManagerContentIdentityTransitionCoordinator.markReplacementSelection(
            on: trigger,
            state: &state,
        )
        XCTAssertEqual(state.pendingIdentityTransition?.preserveSelectionForReplacementBatch, true)

        // reconcile이 유일 선택이던 before 행과 anchor를 함께 비운 상태를 만든다.
        state.entryViewLayout.selectedIds.remove(beforePrimary.id)
        state.entryViewLayout.lastSelectedId = nil
        state.entryViewLayout.rangeAnchorId = nil
        FileManagerContentIdentityTransitionCoordinator.resolveReplacementSelection(
            on: trigger,
            state: &state,
        )

        XCTAssertTrue(state.entryViewLayout.selectedIds.contains(beforePrimary.id))
        XCTAssertEqual(state.entryViewLayout.lastSelectedId, beforePrimary.id)
        XCTAssertEqual(state.entryViewLayout.rangeAnchorId, beforePrimary.id)
    }

    /// 같은 root의 arrangement·hidden reload도 전이 세대를 재기준화한다.
    /// - 검증 내용: setGroupKey와 hidden toggle이 loadItems를 시작할 때 root 소유자 세대를 함께 올린다.
    /// - 사전 조건: root 소유자 대기 전이와 gen 1 로딩 컨텍스트가 있다.
    /// - 기대 결과: 두 우회 reload 경로 뒤에도 projectionOwner가 새 세대를 가리켜 전이가 생존한다.
    func testSameRootSideChannelReloadsRebaseTransitionGeneration() async {
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [beforePrimary],
        )
        state.navigation.navigationState = .folder("/root")
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: "/root/D/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: nil,
        )
        let store = makeRootSourceCandidateStore(state)

        await store.send(.entryViewLayout(.entryArrangements(.setGroupKey(.kind))))
        XCTAssertEqual(store.state.pendingIdentityTransition?.projectionOwner, .root(generation: 2))

        await store.send(.view(.toggleShowHiddenFilesAndReload))
        XCTAssertEqual(store.state.pendingIdentityTransition?.projectionOwner, .root(generation: 3))
    }

    /// 같은 folder 재적용(탭 복원) reload도 전이 세대를 재기준화한다.
    /// - 검증 내용: applyNavigationState(.folder 동일 경로) 뒤 root 소유자 세대가 함께 올라간다.
    /// - 사전 조건: root 소유자 대기 전이와 gen 1 로딩 컨텍스트가 있다.
    /// - 기대 결과: 탭 복원 reload 뒤에도 projectionOwner가 새 세대를 가리켜 전이가 생존한다.
    func testSameFolderReapplyReloadRebasesTransitionGeneration() async {
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [beforePrimary],
        )
        state.navigation.navigationState = .folder("/root")
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: "/root/D/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: nil,
        )
        let store = makeRootSourceCandidateStore(state)

        await store.send(.internal(.applyNavigationState(.folder("/root"))))
        XCTAssertEqual(store.state.pendingIdentityTransition?.projectionOwner, .root(generation: 2))
    }

    private func makeMultiMoveSourceStagingState() -> FileManagerContentState {
        let beforePrimary = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        let s1 = EntryModel.temporaryFolder(id: "/root/S1", name: "S1")
        let s2 = EntryModel.temporaryFolder(id: "/root/S2", name: "S2")
        let cDest = EntryModel.temporaryFolder(id: "/root/C", name: "C")
        let bDest = EntryModel.temporaryFolder(id: "/root/B", name: "B")
        let s1Before = EntryModel.temporaryFolder(id: "/root/S1/q", name: "q")
        let s2Before = EntryModel.temporaryFolder(id: "/root/S2/r", name: "r")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [beforePrimary, s1, s2, cDest, bDest, s1Before, s2Before],
        )
        for source in [s1, s2] {
            state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
                folder: .init(
                    children: [source.id == s1.id ? s1Before : s2Before],
                    retainsPreviousGenerationChildren: true,
                ),
                generation: 3,
                loadPhase: .loadingCore,
            )
        }
        for destination in [cDest, bDest] {
            state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
                children: [], loadPhase: .loadingCore, generation: 3,
            )
        }
        state.entryViewLayout.hierarchy.setExpandedIDs([s1.id, s2.id, cDest.id, bDest.id])
        state.entryViewLayout.selectedIds = [beforePrimary.id, s1Before.id, s2Before.id]
        configureMultiMoveStaging(&state, s1: s1, s2: s2, cDest: cDest, bDest: bDest)
        return state
    }

    private func configureMultiMoveStaging(
        _ state: inout FileManagerContentState,
        s1: EntryModel,
        s2: EntryModel,
        cDest: EntryModel,
        bDest: EntryModel,
    ) {
        let s1Before = "/root/S1/q"
        let s2Before = "/root/S2/r"
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/before",
            afterPath: "/root/C/q",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: s1Before,
                    afterPath: "/root/C/q",
                    sourceOwner: .folder(id: s1.id, generation: 3),
                    destinationOwner: .folder(id: cDest.id, generation: 3),
                ),
                .init(
                    beforePath: s2Before,
                    afterPath: "/root/B/r",
                    sourceOwner: .folder(id: s2.id, generation: 3),
                    destinationOwner: .folder(id: bDest.id, generation: 3),
                ),
            ],
        )
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: s1.id,
            untilEntryID: "/root/C/q",
            holdsUntilMigration: true,
        )
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: s2.id,
            untilEntryID: "/root/B/r",
            holdsUntilMigration: true,
        )
    }
}

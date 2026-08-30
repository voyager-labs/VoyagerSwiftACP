import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
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

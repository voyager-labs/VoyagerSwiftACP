import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002FileManagerPagePresentationTests {
    func testRootSuccessTerminalSettlesOnlyMatchingAdditionalPairs() async {
        let fixture = MatchingAdditionalPairsFixture()
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [fixture.source, fixture.primaryDestination, fixture.pendingDestination],
        )
        configureMatchingAdditionalPairsState(&state, fixture: fixture)
        let store = makeRootSourceCandidateStore(state)

        await store.send(folderResponse(
            fixture.primaryDestination.id,
            generation: 3,
            items: [fixture.afterPrimary],
            batchIndex: 0,
        ))
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await finishBufferedRootSourceReload(
            store,
            candidate: [fixture.source, fixture.primaryDestination, fixture.pendingDestination],
        )

        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.map(\.migrated), [true, false])
        XCTAssertNotNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: fixture.source.id))
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.contains(fixture.beforeFolderPair.id))
    }

    func testRootSuccessTerminalCommitsReleasedCandidateWithPendingFolderPair() async {
        let fixture = ReleasedRootCandidateFixture()
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [fixture.beforePrimary, fixture.source, fixture.pendingDestination],
        )
        configureReleasedRootCandidateState(&state, fixture: fixture)
        let store = makeRootSourceCandidateStore(state)

        await finishBufferedRootSourceReload(
            store,
            candidate: [fixture.afterPrimary, fixture.source, fixture.pendingDestination],
        )
        await receiveRootCandidateProjection(
            store,
            expectedEntries: [fixture.afterPrimary, fixture.source, fixture.pendingDestination],
        )

        XCTAssertEqual(store.state.pendingIdentityTransition?.primaryMigrated, true)
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
        XCTAssertFalse(store.state.entryViewLayout.entries.contains(where: { $0.id == fixture.beforePrimary.id }))
        XCTAssertNotNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: fixture.source.id))
    }

    private func configureMatchingAdditionalPairsState(
        _ state: inout FileManagerContentState,
        fixture: MatchingAdditionalPairsFixture,
    ) {
        state.entryViewLayout.hierarchy.nodesByID[fixture.source.id] = .init(
            folder: .init(
                children: [fixture.beforePrimary, fixture.beforeRootPair, fixture.beforeFolderPair],
                retainsPreviousGenerationChildren: true,
            ),
            generation: 3,
            loadPhase: .loadingCore,
        )
        for destination in [fixture.primaryDestination, fixture.pendingDestination] {
            state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
                children: [], loadPhase: .loadingCore, generation: 3,
            )
        }
        state.entryViewLayout.hierarchy.setExpandedIDs([
            fixture.source.id,
            fixture.primaryDestination.id,
            fixture.pendingDestination.id,
        ])
        state.entryViewLayout.selectedIds = [
            fixture.beforePrimary.id,
            fixture.beforeRootPair.id,
            fixture.beforeFolderPair.id,
        ]
        state.pendingIdentityTransition = fixture.transition
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: fixture.source.id,
            untilEntryID: "/root/missing-after",
            holdsUntilMigration: true,
        )
    }

    private func configureReleasedRootCandidateState(
        _ state: inout FileManagerContentState,
        fixture: ReleasedRootCandidateFixture,
    ) {
        state.entryViewLayout.hierarchy.nodesByID[fixture.source.id] = .init(
            folder: .init(children: [fixture.beforeAdditional], retainsPreviousGenerationChildren: true),
            generation: 3,
            loadPhase: .loadingCore,
        )
        state.entryViewLayout.hierarchy.nodesByID[fixture.pendingDestination.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([fixture.source.id, fixture.pendingDestination.id])
        state.entryViewLayout.selectedIds = [fixture.beforePrimary.id, fixture.beforeAdditional.id]
        state.pendingIdentityTransition = fixture.transition
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: fixture.source.id,
            untilEntryID: "/root/C/q",
            holdsUntilMigration: true,
        )
    }
}

private struct MatchingAdditionalPairsFixture {
    let source = EntryModel.temporaryFolder(id: "/root/D", name: "D")
    let primaryDestination = EntryModel.temporaryFolder(id: "/root/A", name: "A")
    let pendingDestination = EntryModel.temporaryFolder(id: "/root/B", name: "B")
    let beforePrimary = EntryModel.temporaryFolder(id: "/root/D/p", name: "p")
    let beforeRootPair = EntryModel.temporaryFolder(id: "/root/D/q", name: "q")
    let beforeFolderPair = EntryModel.temporaryFolder(id: "/root/D/r", name: "r")
    let afterPrimary = EntryModel.temporaryFolder(id: "/root/A/p", name: "p")

    var transition: FileManagerContentState.EntryIdentityTransition {
        .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: afterPrimary.id,
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: primaryDestination.id, generation: 3),
            preservationOwner: .folder(id: source.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: beforeRootPair.id,
                    afterPath: "/root/missing-after",
                    sourceOwner: .folder(id: source.id, generation: 3),
                    destinationOwner: .root(generation: 1),
                ),
                .init(
                    beforePath: beforeFolderPair.id,
                    afterPath: "/root/B/missing-after",
                    sourceOwner: .folder(id: source.id, generation: 3),
                    destinationOwner: .folder(id: pendingDestination.id, generation: 3),
                ),
            ],
        )
    }
}

private struct ReleasedRootCandidateFixture {
    let beforePrimary = EntryModel.temporaryFolder(id: "/root/before", name: "before")
    let afterPrimary = EntryModel.temporaryFolder(id: "/root/after", name: "after")
    let source = EntryModel.temporaryFolder(id: "/root/S", name: "S")
    let pendingDestination = EntryModel.temporaryFolder(id: "/root/C", name: "C")
    let beforeAdditional = EntryModel.temporaryFolder(id: "/root/S/q", name: "q")

    var transition: FileManagerContentState.EntryIdentityTransition {
        .init(
            recordID: UUID(),
            beforePath: beforePrimary.id,
            afterPath: afterPrimary.id,
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: beforeAdditional.id,
                    afterPath: "/root/C/q",
                    sourceOwner: .folder(id: source.id, generation: 3),
                    destinationOwner: .folder(id: pendingDestination.id, generation: 3),
                ),
            ],
        )
    }
}

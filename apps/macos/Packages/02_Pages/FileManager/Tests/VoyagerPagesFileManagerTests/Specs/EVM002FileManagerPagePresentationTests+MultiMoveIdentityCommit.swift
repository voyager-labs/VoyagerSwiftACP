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

    /// terminalized additional pair도 source terminal까지 staging을 유지하고 pending pair는 계속 보류한다.
    /// - 검증 내용: C terminal 뒤 S1 migration 완료 표시, source terminal 뒤 staging 커밋, S2 hold를 함께 검사한다.
    /// - 사전 조건: 서로 다른 source·destination의 pending pair 2개와 root 보존 primary가 있다.
    /// - 기대 결과: source terminal 전에는 retained snapshot을 유지하고 이후 S1 staging만 커밋한다.
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

        XCTAssertEqual(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: s1,
        )?.migrationCompleted, true)
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[s1]?.folder.children.map(\.id),
            ["/root/S1/q"],
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: s1,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 0)),
        ))))

        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: s1))
        XCTAssertNotNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: s2))
        XCTAssertNotNil(store.state.pendingIdentityTransition)
    }

    /// EVM-002-command_external_refresh_correlation: primary folder terminal은 lexical destination owner만 소비한다.
    /// 서로 다른 symlink 경로가 같은 canonical folder를 가리켜도 다른 expanded folder terminal이 primary 전이를 닫지 않는지 검증한다.
    /// - 검증 내용: canonical alias folder의 terminal response가 primary-only transition을 migrated/discard하지 않는다.
    /// - 사전 조건: 실제 fixture 기반 두 directory symlink와 각각의 동일 generation folder node가 있고 primary owner는 alias A다.
    /// - 기대 결과: alias B의 failure terminal 뒤에도 primary transition이 유지된다.
    func testPrimaryTerminalIgnoresCanonicalAliasForDifferentFolder() throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let targetDirectory = sandbox.fileURL.deletingLastPathComponent()
        let primaryDirectory = sandbox.symlinkedFileURL.deletingLastPathComponent()
        let unrelatedDirectory = sandbox.root.appendingPathComponent("link-b", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: unrelatedDirectory, withDestinationURL: targetDirectory)
        XCTAssertNotEqual(primaryDirectory.path, unrelatedDirectory.path)
        XCTAssertEqual(
            primaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path,
            unrelatedDirectory.standardizedFileURL.resolvingSymlinksInPath().path,
        )

        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(sandbox.root.path)
        state.entryViewLayout.hierarchy = .init(rootPath: sandbox.root.path)
        state.entryViewLayout.hierarchy.nodesByID[primaryDirectory.path] = .init(
            generation: 3,
            loadPhase: .loadingCore,
        )
        state.entryViewLayout.hierarchy.nodesByID[unrelatedDirectory.path] = .init(
            generation: 3,
            loadPhase: .failed(.permissionDenied),
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([primaryDirectory.path, unrelatedDirectory.path])
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "\(sandbox.root.path)/before",
            afterPath: "\(primaryDirectory.path)/after",
            rootPath: sandbox.root.path,
            refreshGeneration: 1,
            projectionOwner: .folder(id: primaryDirectory.path, generation: 3),
        )

        FileManagerContentIdentityTransitionCoordinator.resolveFolderTransition(
            on: .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration: 0,
                folderID: unrelatedDirectory.path,
                folderGeneration: 3,
                .failed(.permissionDenied),
            ))),
            state: &state,
        )

        XCTAssertNotNil(state.pendingIdentityTransition)
        XCTAssertEqual(state.pendingIdentityTransition?.primaryMigrated, false)
    }

    /// EVM-002-command_external_refresh_correlation: source staging은 source terminal까지 보류된다.
    /// - 검증 내용: destination migration 뒤에도 source staging은 커밋되지 않고 source terminal에서만 반영된다.
    /// - 사전 조건: 서로 다른 source/destination pair 2건이 모두 staging 보류 중이다.
    /// - 기대 결과: D1/D2 batch 뒤 C source children이 retained로 유지되고 C terminal 뒤 staging이 커밋된다.
    func testUnmigratedPairSourceStagingStaysHeldUntilItsSourceTerminal() async {
        let beforeC = EntryModel.temporaryFolder(id: "/root/C/before", name: "before")
        let keptC = EntryModel.temporaryFolder(id: "/root/C/kept", name: "kept")
        let keptA = EntryModel.temporaryFolder(id: "/root/A/kept", name: "kept")
        let afterA = EntryModel.temporaryFolder(id: "/root/D1/after", name: "after")
        let afterC = EntryModel.temporaryFolder(id: "/root/D2/after", name: "after")
        let (state, rootContextGeneration) = dualSourceFixture()
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
            folderID: "/root/A",
            folderGeneration: 3,
            .event(.coreBatch(items: [keptA], batchIndex: 0)),
        ))))
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: "/root/C",
            folderGeneration: 3,
            .event(.coreBatch(items: [keptC], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, ["/root/A/before", beforeC.id])

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: "/root/D1",
            folderGeneration: 3,
            .event(.coreBatch(items: [afterA], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [afterA.id, beforeC.id])
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID["/root/C"]?.folder.children.map(\.id),
            [beforeC.id, keptC.id],
            "미이전 pair의 source staging은 보류되어 retained children이 유지된다",
        )
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: "/root/D2",
            folderGeneration: 3,
            .event(.coreBatch(items: [afterC], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [afterA.id, afterC.id])
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID["/root/C"]?.folder.children.map(\.id),
            [beforeC.id, keptC.id],
            "pair migration 뒤에도 source terminal 전에는 retained children을 유지한다",
        )
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(
            folderID: "/root/C",
        )?.migrationCompleted, true)
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: "/root/D2",
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: "/root/C",
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID["/root/C"]?.folder.children.map(\.id),
            [keptC.id],
            "source terminal 뒤 source staging이 커밋된다",
        )
        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: "/root/C"))
        XCTAssertNil(store.state.pendingIdentityTransition)
    }

    /// terminal 정산로 커밋된 source staging에서 사라진 before 행의 선택·anchor를 정산한다.
    /// - 검증 내용: C terminal 뒤 S1의 before가 선택과 anchor에서 함께 제거되는지 확인한다.
    /// - 사전 조건: S1 source staging이 커밋 가능한 상태(coreFinished)이고 anchor가 before를 가리킨다.
    /// - 기대 결과: 존재하지 않는 before 경로가 breadcrumb·Quick Look 기준에 남지 않는다.
    func testAdditionalTerminalSettlesStalePairSelection() async {
        var state = makeMultiMoveSourceStagingState()
        state.entryViewLayout.hierarchy.nodesByID["/root/S1"]?.folder.coreFinished = true
        state.entryViewLayout.lastSelectedId = "/root/S1/q"
        state.entryViewLayout.rangeAnchorId = "/root/S1/q"
        let store = makeRootSourceCandidateStore(state)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: "/root/C",
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 0)),
        ))))
        await store.receive(\.entryViewLayout.delegate.selectionChanged)

        XCTAssertFalse(store.state.entryViewLayout.selectedIds.contains("/root/S1/q"))
        XCTAssertNil(store.state.entryViewLayout.lastSelectedId)
        XCTAssertNil(store.state.entryViewLayout.rangeAnchorId)
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.map(\.migrated), [true, false])
    }

    /// primary terminal 정산에서도 committed staging에서 사라진 before의 선택·anchor를 정산한다.
    /// - 검증 내용: destination collapse로 primary source staging이 커밋되면 primary before 선택이 제거된다.
    /// - 사전 조건: preservation이 folder source고 primary before만 선택된 상태로 collapse가 발생한다.
    /// - 기대 결과: primary before가 breadcrumb·Quick Look 기준에 stale로 남지 않는다.
    func testPrimaryCollapseSettlesStalePrimarySelection() async {
        let before = EntryModel.temporaryFolder(id: "/root/S/before", name: "before")
        let destination = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let source = EntryModel.temporaryFolder(id: "/root/S", name: "S")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [before, destination],
        )
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            folder: .init(children: [before], coreFinished: true),
            generation: 3,
            loadPhase: .loadingCore,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: "/root/A/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            preservationOwner: .folder(id: source.id, generation: 3),
        )
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: source.id,
            untilEntryID: "/root/A/after",
            holdsUntilMigration: true,
        )
        let store = makeRootSourceCandidateStore(state)

        await store.send(.entryViewLayout(.hierarchy(.folderCollapseRequested(id: destination.id))))

        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertFalse(store.state.entryViewLayout.selectedIds.contains(before.id))
        XCTAssertNil(store.state.entryViewLayout.lastSelectedId)
        XCTAssertNil(store.state.entryViewLayout.rangeAnchorId)
    }

    /// primary-only terminal discard에서도 stale primary 선택을 정산한다.
    /// - 검증 내용: A 실패 후 discard 뒤 primary before가 선택·anchor에서 제거되는지 확인한다.
    /// - 사전 조건: preservation folder staging이 커밋 가능하고 primary before만 선택돼 있다.
    /// - 기대 결과: 존재하지 않는 before 경로가 선택 기준에 남지 않는다.
    func testPrimaryTerminalDiscardSettlesStaleSelection() {
        let before = EntryModel.temporaryFolder(id: "/root/S/before", name: "before")
        let destination = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let source = EntryModel.temporaryFolder(id: "/root/S", name: "S")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [before, destination],
        )
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            folder: .init(children: [before], coreFinished: true),
            generation: 3,
            loadPhase: .loadingCore,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [], loadPhase: .failed(.permissionDenied), generation: 3,
        )
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: "/root/A/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            preservationOwner: .folder(id: source.id, generation: 3),
        )
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: source.id,
            untilEntryID: "/root/A/after",
            holdsUntilMigration: true,
        )
        FileManagerContentIdentityTransitionCoordinator.resolveFolderTransition(
            on: .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration: 0,
                folderID: destination.id,
                folderGeneration: 3,
                .failed(.permissionDenied),
            ))),
            state: &state,
        )

        XCTAssertNil(state.pendingIdentityTransition)
        XCTAssertFalse(state.entryViewLayout.selectedIds.contains(before.id))
        XCTAssertNil(state.entryViewLayout.lastSelectedId)
        XCTAssertNil(state.entryViewLayout.rangeAnchorId)
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

    /// EVM-002-command_external_refresh_correlation: primary migration 뒤 terminal 전에는 현재 owner를 유지한다.
    /// primary after batch가 먼저 도착한 뒤 rename echo가 와도 destination folder terminal 전까지 전이를 보존하는지 검증한다.
    /// - 검증 내용: primary-only transition의 overlapping `ItemRenamed` event가 pending identity transition을 폐기하지 않는다.
    /// - 사전 조건: primaryMigrated=true, expanded destination owner generation 3, destination은 아직 loadingCore다.
    /// - 기대 결과: 순수 command echo는 중복 refresh로 제거되고 pending identity transition은 유지된다.
    func testPrimaryOnlyMigrationKeepsCurrentOwnerUntilTerminal() async {
        let destination = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        var state = bufferedRootSourceState(rootPath: "/root", entries: [destination])
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destination.id])
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/before",
            afterPath: "/root/A/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
            preservationOwner: .root(generation: 1),
        )
        state.pendingIdentityTransition?.primaryMigrated = true
        let store = makeRootSourceCandidateStore(state)

        await store.send(.externalFileSystemChanged([
            FileChangeGatewayEvent(
                path: "/root/A/after",
                flags: UInt32(kFSEventStreamEventFlagItemRenamed),
                emittedAt: .distantPast,
            ),
        ]))

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

    /// EVM-002-command_external_refresh_correlation: root failure에서도 primary source를 즉시 정산한다.
    /// primary root pair의 reload가 실패해도 별도 folder destination pair가 primary source hold를 무기한 연장하지 않는지 검증한다.
    /// - 검증 내용: root streamFailed에서 primaryMigrated와 source staging을 정산하고 folder pair만 유지한다.
    /// - 사전 조건: expanded primary source의 terminal snapshot, root primary pair, pending folder additional pair가 있다.
    /// - 기대 결과: primary before 선택·source hold는 제거되고 additional folder pair와 transition은 유지된다.
    func testRootFailureSettlesPrimarySourceWithPendingFolderPair() async {
        let source = EntryModel.temporaryFolder(id: "/root/S", name: "S")
        let destination = EntryModel.temporaryFolder(id: "/root/B", name: "B")
        let primaryBefore = EntryModel.temporaryFolder(id: "/root/S/primary", name: "primary")
        let additionalBefore = EntryModel.temporaryFolder(id: "/root/T/additional", name: "additional")
        var state = bufferedRootSourceState(rootPath: "/root", entries: [source, destination])
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            children: [primaryBefore],
            loadPhase: .enriching,
            generation: 3,
            coreFinished: true,
            hasAppliedContentBatch: false,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loadingCore,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.beginDeferredFolderReplacement(
            folderID: source.id,
            untilEntryID: "/root/primary-after",
            holdsUntilMigration: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.entryViewLayout.selectedIds = [primaryBefore.id, additionalBefore.id]
        state.entryViewLayout.lastSelectedId = primaryBefore.id
        state.entryViewLayout.rangeAnchorId = primaryBefore.id
        state.entryViewLayout.entryOperations.loadingContext.streamTerminal = true
        state.entryViewLayout.entryOperations.loadingContext.isIncomplete = true
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: primaryBefore.id,
            afterPath: "/root/primary-after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: .folder(id: source.id, generation: 3),
            additionalMoves: [
                .init(
                    beforePath: additionalBefore.id,
                    afterPath: "/root/B/additional",
                    sourceOwner: .folder(id: "/root/T", generation: 3),
                    destinationOwner: .folder(id: destination.id, generation: 3),
                ),
            ],
        )
        let store = makeRootSourceCandidateStore(state)

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFailed(generation: 1)))))

        XCTAssertEqual(store.state.pendingIdentityTransition?.primaryMigrated, true)
        XCTAssertEqual(store.state.pendingIdentityTransition?.additionalMoves.first?.migrated, false)
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[source.id]?.folder.children, [])
        XCTAssertNil(store.state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: source.id))
        XCTAssertFalse(store.state.entryViewLayout.selectedIds.contains(primaryBefore.id))
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.contains(additionalBefore.id))
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

    /// 같은 root의 arrangement reload도 folder 소유자 세대를 재기준화한다.
    /// - 검증 내용: setGroupKey 뒤 pending pair의 destination folder owner가 새 세대로 올라간다.
    /// - 사전 조건: folder destination 소유자 pair와 expanded folder node가 gen 3으로 있다.
    /// - 기대 결과: reload가 폴더를 재시작해도 pair 소유자 세대가 동행해 전이가 생존한다.
    func testSameRootArrangementReloadRebasesFolderOwners() async {
        let beforeAdditional = EntryModel.temporaryFolder(id: "/root/S/q", name: "q")
        let destinationB = EntryModel.temporaryFolder(id: "/root/B", name: "B")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [beforeAdditional, destinationB],
        )
        state.entryViewLayout.hierarchy.nodesByID[destinationB.id] = .init(
            children: [], loadPhase: .loadingCore, generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destinationB.id])
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/primary",
            afterPath: "/root/A/primary",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: .root(generation: 1),
            additionalMoves: [
                .init(
                    beforePath: beforeAdditional.id,
                    afterPath: "/root/B/q",
                    sourceOwner: nil,
                    destinationOwner: .folder(id: destinationB.id, generation: 3),
                ),
            ],
        )
        let store = makeRootSourceCandidateStore(state)

        await store.send(.entryViewLayout(.entryArrangements(.setGroupKey(.kind))))

        XCTAssertEqual(
            store.state.pendingIdentityTransition?.additionalMoves.first?.destinationOwner,
            .folder(id: destinationB.id, generation: 4),
        )
        XCTAssertEqual(store.state.pendingIdentityTransition?.projectionOwner, .root(generation: 2))
    }

    /// EVM-002-command_external_refresh_correlation: 연속 hierarchy invalidation마다 예약된 folder owner를 전진시킨다.
    /// 첫 reload action이 적용되기 전에 두 번째 reload가 예약돼도 이미 N+1인 owner를 다시
    /// 다음 세대로 옮겨 실제 node의 N+2 generation과 transition을 일치시켜야 한다.
    /// - 검증 내용: 동일 expanded folder owner에 대한 연속 rebase가 generation을 두 번 증가
    /// - 사전 조건: folder node와 projection owner가 generation 3이고 두 invalidation이 연속 예약됨
    /// - 기대 결과: node가 아직 generation 3이어도 projectionOwner가 generation 5가 됨
    func testConsecutiveHierarchyInvalidationsAdvanceScheduledFolderOwner() {
        let destination = EntryModel.temporaryFolder(id: "/root/D", name: "D")
        var state = bufferedRootSourceState(
            rootPath: "/root",
            entries: [destination],
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 3,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([destination.id])
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: "/root/before",
            afterPath: "/root/D/after",
            rootPath: "/root",
            refreshGeneration: 1,
            projectionOwner: .folder(id: destination.id, generation: 3),
        )

        FileManagerContentIdentityTransitionCoordinator.rebaseForHierarchyInvalidation(
            affectedPaths: [destination.id],
            state: &state,
        )
        FileManagerContentIdentityTransitionCoordinator.rebaseForHierarchyInvalidation(
            affectedPaths: [destination.id],
            state: &state,
        )

        XCTAssertEqual(
            state.pendingIdentityTransition?.projectionOwner,
            .folder(id: destination.id, generation: 5),
        )
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

    /// EVM-002-command_external_refresh_correlation: canonical-equivalent alias navigation은 전이를 만료한다.
    /// 실제 root가 같아도 lexical route가 바뀌면 기존 identity after path와 pending refresh scope를
    /// 새 route에 재사용하지 않아야 한다.
    /// - 검증 내용: alias A→B 이동 시 pending identity transition과 external refresh를 함께 제거
    /// - 사전 조건: alias A current route와 canonical-equivalent alias B destination route, 대기 전이
    /// - 기대 결과: lexical root 변경으로 stale transition/scope가 만료됨
    func testCanonicalAliasNavigationExpiresIdentityTransition() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = rootURL.appendingPathComponent("target", isDirectory: true)
        let aliasAURL = rootURL.appendingPathComponent("alias-a")
        let aliasBURL = rootURL.appendingPathComponent("alias-b")
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasAURL, withDestinationURL: targetURL)
        try FileManager.default.createSymbolicLink(at: aliasBURL, withDestinationURL: targetURL)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let rootPath = aliasAURL.path
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.navigation.navigationState = .folder(rootPath)
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        let canonicalRootPath = FileManagerContentIdentityTransitionCoordinator.canonicalizedPath(rootPath)
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: canonicalRootPath + "/before.txt",
            afterPath: canonicalRootPath + "/after.txt",
            rootPath: canonicalRootPath,
            refreshGeneration: 1,
        )
        state.pendingExternalRefresh = .init(
            rootPath: canonicalRootPath,
            affectedPaths: [canonicalRootPath],
            removedPrefixes: [],
            requiresCoarseHierarchyReload: false,
        )
        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.folder(aliasBURL.path))))

        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertNil(store.state.pendingExternalRefresh)
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

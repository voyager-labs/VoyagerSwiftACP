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
        state.entryViewLayout.entries = [destinationC, EntryModel.temporaryFolder(id: "/root/a", name: "a")]
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
        print(
            "DBG C batch: sel:",
            store.state.entryViewLayout.selectedIds,
            "children:",
            store.state.entryViewLayout.hierarchy.nodesByID[destinationC.id]?.folder.children.map(\.id) as Any,
            "loadPhase:",
            store.state.entryViewLayout.hierarchy.nodesByID[destinationC.id]?.loadPhase as Any,
        )
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

    /// EVM-002-command_external_refresh_correlation: primary dest가 폴더면 root 스트림 실패로 전이를 폐기하지 않는다.
    /// - 검증 내용: additional root destination owner로 root 실패 세대가 일치해도 primary folder 전이는 유지된다.
    /// - 사전 조건: primary dest A(폴더), additional dest root인 혼합 undo 전이와 buffered root reload 실패.
    /// - 기대 결과: streamFailed 뒤에도 전이와 선택, source retained children이 유지된다.
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
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [sourceD, destinationA]
        state.entryViewLayout.entryOperations.items = [sourceD, destinationA]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
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
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFailed(generation: 1)))))
        XCTAssertNotNil(
            store.state.pendingIdentityTransition,
            "primary 폴더 destination의 migration 기회를 위해 전이가 유지된다",
        )
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [beforeX.id, beforeY.id])
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[sourceD.id]?.folder.children.map(\.id),
            [beforeX.id, beforeY.id],
            "root 실패는 source retained snapshot을 강등하지 않는다",
        )
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
}

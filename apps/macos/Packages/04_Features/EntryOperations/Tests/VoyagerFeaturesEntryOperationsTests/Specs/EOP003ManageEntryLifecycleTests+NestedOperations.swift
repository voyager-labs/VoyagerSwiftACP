import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import XCTest

extension EOP003ManageEntryLifecycleTests {
    /// EOP-003-empty_trash: Trash 비우기가 실제 파일 삭제로 이어지는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 fake Trash에 넣은 뒤 empty trash를 실행할 때 파일이 삭제되는지 확인한다.
    /// - 검증 내용: `.trash(.emptyTrash)`가 confirmation 후 trash 항목 전체 삭제와 완료 상태 갱신을 수행한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사한 뒤 fake Trash 디렉터리로 옮겨두고, confirmation
    /// alert는 승인으로 응답한다.
    /// - 기대 결과: trash 파일이 삭제되고, reducer state의 pending/complete 카운터가 초기화되며, 원본 fixture 경로는 유지된다.
    func testEmptyTrash_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let trashRoot = sandbox.root.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        let trashPath = trashRoot.appendingPathComponent("trash.txt")
        try FileManager.default.copyItem(at: sandbox.fileURL, to: trashPath)

        var initialState = EntryOperationsState()
        initialState.loadingContext.coreFinished = true
        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.entryOperationsAlertClient.showEmptyTrashConfirmationAlert = { _ in true }
        }

        // store.exhaustivity = .off: empty-trash confirmation and deletion are async integration steps.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.trash(.emptyTrash(paths: [trashPath.path])))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.deletedPaths, [trashPath])
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashPath.path))
        XCTAssertEqual(store.state.pendingEmptyTrashItemCount, 0)
        XCTAssertEqual(store.state.emptyTrashCompletedCount, 0)
        XCTAssertTrue(store.state.restorableTrashPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-003-move_entries_to_trash: 선택된 부모와 하위 항목은 부모만 Trash 이동으로 계획한다.
    /// 사용자가 하위 항목, 같은 raw-prefix peer, 부모를 표시 순서대로 함께 선택할 때 lifecycle planner가 부모와 peer만 유지하는지 확인한다.
    /// - 검증 내용: `.routing(.executeCommand)` planner가 선택된 조상 관계를 pathComponents로 판별하고 원본 fullPath 및 남은 표시 순서를 보존한다.
    /// - 사전 조건: 선택 목록에 descendant-first 부모-하위 항목 쌍과 조상이 아닌 raw-prefix peer를 구성한다.
    /// - 기대 결과: `.trash(.moveToTrash)`는 하위 항목을 제외한 peer와 부모 경로만 방출한다.
    func testMoveEntriesToTrash_plansTopmostSelectedPaths() throws {
        let scenario = makeTopmostLifecycleSelectionScenario()
        let outputs = EntryOperationsCommandPlanner.plan(
            command: .mutation(.moveSelectedItemsToTrash),
            context: scenario.context,
        )

        XCTAssertEqual(outputs.count, 1)
        guard case let .entryOperations(.trash(.moveToTrash(paths))) = try XCTUnwrap(outputs.first) else {
            return XCTFail("Trash 이동 명령은 moveToTrash payload를 계획해야 합니다.")
        }
        XCTAssertEqual(paths, scenario.expectedPaths)
    }

    /// EOP-003-delete_entries_immediately: 선택된 부모와 하위 항목은 부모만 즉시 삭제로 계획한다.
    /// 사용자가 하위 항목, 같은 raw-prefix peer, 부모를 표시 순서대로 함께 선택할 때 lifecycle planner가 부모와 peer만 유지하는지 확인한다.
    /// - 검증 내용: `.routing(.executeCommand)` planner가 선택된 조상 관계를 pathComponents로 판별하고 원본 fullPath 및 남은 표시 순서를 보존한다.
    /// - 사전 조건: 선택 목록에 descendant-first 부모-하위 항목 쌍과 조상이 아닌 raw-prefix peer를 구성한다.
    /// - 기대 결과: `.trash(.deleteImmediately)`는 하위 항목을 제외한 peer와 부모 경로만 방출한다.
    func testDeleteEntriesImmediately_plansTopmostSelectedPaths() throws {
        let scenario = makeTopmostLifecycleSelectionScenario()
        let outputs = EntryOperationsCommandPlanner.plan(
            command: .mutation(.deleteSelectedItemsImmediately),
            context: scenario.context,
        )

        XCTAssertEqual(outputs.count, 1)
        guard case let .entryOperations(.trash(.deleteImmediately(paths))) = try XCTUnwrap(outputs.first) else {
            return XCTFail("즉시 삭제 명령은 deleteImmediately payload를 계획해야 합니다.")
        }
        XCTAssertEqual(paths, scenario.expectedPaths)
    }

    /// EOP-003-put_deleted_entries_back: 선택된 부모와 하위 항목은 부모만 원래 위치 복귀로 계획한다.
    /// 사용자가 하위 항목, 같은 raw-prefix peer, 부모를 표시 순서대로 함께 선택할 때 lifecycle planner가 부모와 peer만 유지하는지 확인한다.
    /// - 검증 내용: `.routing(.executeCommand)` planner가 선택된 조상 관계를 pathComponents로 판별하고 원본 fullPath 및 남은 표시 순서를 보존한다.
    /// - 사전 조건: 선택 목록에 descendant-first 부모-하위 항목 쌍과 조상이 아닌 raw-prefix peer를 구성한다.
    /// - 기대 결과: `.trash(.putBackFromTrash)`는 하위 항목을 제외한 peer와 부모 경로만 방출한다.
    func testPutBackSelectedItems_plansTopmostSelectedPaths() throws {
        let scenario = makeTopmostLifecycleSelectionScenario()
        let outputs = EntryOperationsCommandPlanner.plan(
            command: .mutation(.putBackSelectedItems),
            context: scenario.context,
        )

        XCTAssertEqual(outputs.count, 1)
        guard case let .entryOperations(.trash(.putBackFromTrash(paths))) = try XCTUnwrap(outputs.first) else {
            return XCTFail("되돌리기 명령은 putBackFromTrash payload를 계획해야 합니다.")
        }
        XCTAssertEqual(paths, scenario.expectedPaths)
    }

    /// EOP-003-move_entries: 수용된 내부 drop 검증 거절은 metadata를 보존한 취소 terminal을 생성한다.
    /// 같은 부모 move와 source 하위 destination move/copy가 mutation으로 진행되지 않는지 확인한다.
    /// - 검증 내용: 작업 종류, operation ID, 실제 topmost source 수와 파일 작업/Undo/reload 부재
    /// - 사전 조건: 비어 있지 않은 source와 drag-and-drop metadata를 가진 세 수용 명령
    /// - 기대 결과: 명령마다 cancelled terminal 하나만 방출되고 상태와 외부 부작용은 변하지 않음
    func testAcceptedDropItemsValidationRejectionEmitsCancelledTerminalWithoutMutation() async throws {
        let mutationCalls = LockIsolated(0)
        let reloadRecorder = CallRecorder<[String]>()
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.moveFile = { _, _ in
            mutationCalls.withValue { $0 += 1 }
            throw FileOpError.system(message: "move must not run")
        }
        fileOps.pasteFile = { _, _ in
            mutationCalls.withValue { $0 += 1 }
            throw FileOpError.system(message: "copy must not run")
        }
        fileOps.postFileSystemChanged = reloadRecorder.record
        let undoSpy = UndoManagerSpy()
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = fileOps
            $0.undoManagerClient = undoSpy.client
        }
        for scenario in Self.acceptedDropRejectionScenarios {
            try await assertAcceptedDropRejection(scenario, store: store)
        }
        await store.finish()

        XCTAssertEqual(mutationCalls.value, 0)
        XCTAssertTrue(reloadRecorder.recorded.isEmpty)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertTrue(store.state.itemStates.isEmpty)
        XCTAssertTrue(undoSpy.registerUndoCalls.isEmpty)
    }

    /// EOP-003-move_entries: 미수용 raw drop과 source가 없는 수용 drop은 terminal 없이 끝난다.
    /// Product 상관관계가 없는 입력과 시도 대상이 없는 입력을 취소로 과대 집계하지 않는지 확인한다.
    /// - 검증 내용: raw 비어 있지 않은 검증 거절과 accepted zero-source의 action/state 부재
    /// - 사전 조건: 같은 부모 raw move와 빈 source accepted move metadata
    /// - 기대 결과: 두 입력 모두 terminal, mutation, Undo, reload를 만들지 않음
    func testUnacceptedAndZeroSourceDropItemsValidationRejectionRemainSilent() async throws {
        let mutationCalls = LockIsolated(0)
        let reloadRecorder = CallRecorder<[String]>()
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.moveFile = { _, _ in
            mutationCalls.withValue { $0 += 1 }
            throw FileOpError.system(message: "move must not run")
        }
        fileOps.postFileSystemChanged = reloadRecorder.record
        let undoSpy = UndoManagerSpy()
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = fileOps
            $0.undoManagerClient = undoSpy.client
        }
        let metadata = try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000324")),
            interaction: .moveEntries,
            source: .dragAndDrop,
        )

        await store.send(.routing(.dropItems(
            sourcePaths: ["/tmp/file.txt"],
            destinationPath: "/tmp",
            isOptionDrag: false,
        )))
        await store.send(.acceptedCommand(
            metadata: metadata,
            action: .routing(.dropItems(
                sourcePaths: [],
                destinationPath: "/tmp",
                isOptionDrag: false,
            )),
        ))
        await store.finish()

        XCTAssertEqual(mutationCalls.value, 0)
        XCTAssertTrue(reloadRecorder.recorded.isEmpty)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertTrue(store.state.itemStates.isEmpty)
        XCTAssertTrue(undoSpy.registerUndoCalls.isEmpty)
    }

    private static let acceptedDropRejectionScenarios = [
        AcceptedDropRejectionScenario(
            id: "00000000-0000-0000-0000-000000000321",
            interaction: .moveEntries,
            sourcePaths: ["/tmp/first.txt", "/tmp/second.txt"],
            destinationPath: "/tmp",
            isOptionDrag: false,
            operationKind: .pasteFileMove,
            cancelledCount: 2,
        ),
        AcceptedDropRejectionScenario(
            id: "00000000-0000-0000-0000-000000000322",
            interaction: .moveEntries,
            sourcePaths: ["/tmp/folder/child.txt", "/tmp/peer.txt", "/tmp/folder"],
            destinationPath: "/tmp/folder/nested",
            isOptionDrag: false,
            operationKind: .pasteFileMove,
            cancelledCount: 2,
        ),
        AcceptedDropRejectionScenario(
            id: "00000000-0000-0000-0000-000000000323",
            interaction: .copyEntries,
            sourcePaths: ["/tmp/folder/child.txt", "/tmp/peer.txt", "/tmp/folder"],
            destinationPath: "/tmp/folder/nested",
            isOptionDrag: true,
            operationKind: .pasteFileCopy,
            cancelledCount: 2,
        ),
    ]

    private struct AcceptedDropRejectionScenario {
        let id: String
        let interaction: EntryInteractionIdentity
        let sourcePaths: [String]
        let destinationPath: String
        let isOptionDrag: Bool
        let operationKind: OperationKind
        let cancelledCount: Int
    }

    private func assertAcceptedDropRejection(
        _ scenario: AcceptedDropRejectionScenario,
        store: TestStore<EntryOperationsFeature.State, EntryOperationsFeature.Action>,
    ) async throws {
        let commandID = try XCTUnwrap(UUID(uuidString: scenario.id))
        let metadata = EntryCommandMetadata(
            id: commandID,
            interaction: scenario.interaction,
            source: .dragAndDrop,
        )
        await store.send(.acceptedCommand(
            metadata: metadata,
            action: .routing(.dropItems(
                sourcePaths: scenario.sourcePaths,
                destinationPath: scenario.destinationPath,
                isOptionDrag: scenario.isOptionDrag,
            )),
        ))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.command == metadata
                && record.id == commandID
                && record.operationKind == scenario.operationKind
                && record.attemptedCount == scenario.cancelledCount
                && record.cancelledCount == scenario.cancelledCount
                && record.succeededCount == 0
                && record.failedCount == 0
                && record.targets.isEmpty
        }
    }

    /// EOP-003-empty_trash: Core loading 완료 전에는 Trash 비우기를 시작하지 않는다.
    /// 불완전한 Trash snapshot으로 삭제 범위를 확정하지 않도록 loading boundary를 검증한다.
    /// - 검증 내용: `.trash(.emptyTrash)`가 confirmation과 filesystem 삭제 effect를 만들지 않는다.
    /// - 사전 조건: `loadingContext.coreFinished`가 false인 초기 상태다.
    /// - 기대 결과: pending/completed count와 파일 삭제 기록이 변경되지 않는다.
    func testEmptyTrash_beforeCoreFinishedDoesNothing() async {
        let recorder = FileOpsRecorder()
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.entryOperationsAlertClient.showEmptyTrashConfirmationAlert = { _ in
                XCTFail("Core loading 완료 전에는 confirmation을 요청하면 안 됩니다.")
                return true
            }
        }

        await store.send(.trash(.emptyTrash(paths: ["/tmp/.Trash/file.txt"])))

        XCTAssertEqual(store.state.pendingEmptyTrashItemCount, 0)
        XCTAssertEqual(store.state.emptyTrashCompletedCount, 0)
        XCTAssertTrue(recorder.deletedPaths.isEmpty)
    }

    private struct TopmostLifecycleSelectionScenario {
        let context: EntryOperationsCommandContext
        let expectedPaths: [String]
    }

    private func makeTopmostLifecycleSelectionScenario() -> TopmostLifecycleSelectionScenario {
        let parent = EntryModelFixtures.makeEntry(path: "/tmp/Selected Folder", isFolder: true)
        let descendant = EntryModelFixtures.makeEntry(path: "/tmp/Selected Folder/nested/file.txt")
        let rawPrefixPeer = EntryModelFixtures.makeEntry(path: "/tmp/Selected Folder Copy.txt")
        let displayItems = [descendant, rawPrefixPeer, parent]
        return TopmostLifecycleSelectionScenario(
            context: EntryOperationsCommandContext(
                selectedIds: Set(displayItems.map(\.id)),
                displayItems: displayItems,
                currentPath: "/tmp",
            ),
            expectedPaths: [rawPrefixPeer.fullPath, parent.fullPath],
        )
    }
}

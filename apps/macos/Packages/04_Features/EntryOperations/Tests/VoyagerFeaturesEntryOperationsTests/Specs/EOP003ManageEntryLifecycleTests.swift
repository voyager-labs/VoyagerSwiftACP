import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import XCTest

private typealias EntryLoadSuspensionGate = EntryOperationsLoadSuspensionGate

@MainActor
final class EOP003ManageEntryLifecycleTests: XCTestCase {
    // MARK: - EOP-003-move_entries_to_trash

    /// EOP-003-move_entries_to_trash: 선택한 Entry가 실제 trash 위치로 이동되는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 Trash로 보낼 때 source 삭제, metadata 저장, undo record 생성이 함께 일어나는지 확인한다.
    /// - 검증 내용: `.trash(.moveToTrash)`가 실제 이동, state 갱신, trash metadata 저장을 수행한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, 샌드박스 내부에 fake Trash 디렉터리를 둔다.
    /// - 기대 결과: source는 사라지고 trash 경로에 파일이 생기며, reducer state와 FileOpsRecorder가 함께 갱신된다.
    func testMoveEntriesToTrash_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let trashRoot = sandbox.root.appendingPathComponent(".Trash")
        let sourcePath = sandbox.fileURL.path
        let trashPath = trashRoot.appendingPathComponent(sandbox.fileURL.lastPathComponent).path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder, trashRoot: trashRoot)
        }

        // store.exhaustivity = .off: trash move is an async integration flow; final state and filesystem are enough.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.trash(.moveToTrash(paths: [sourcePath])))
        await store.finish()
        await store.skipReceivedActions()

        let metadata = await store.dependencies.trashMetadataStoreClient.find(trashPath)
        XCTAssertEqual(metadata?.originalPath, sourcePath)
        XCTAssertEqual(recorder.trashedPaths, [URL(fileURLWithPath: trashPath)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashPath))
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertTrue(store.state.restorableTrashPaths.contains(trashPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-003-move_entries_to_trash: Trash 이동 클라이언트가 실패하면 상태가 실패로 남는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 Trash로 보내려 할 때 client failure가 reducer state에 정확히 반영되는지 확인한다.
    /// - 검증 내용: `.trash(.moveToTrash)`가 moveToTrashAndReturnURL 오류를 error state로 변환한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, moveToTrash 클라이언트는 실패를 던진다.
    /// - 기대 결과: source는 유지되고 trash 기록은 남지 않으며, reducer state에는 failure가 반영된다.
    func testMoveEntriesToTrash_clientFailure() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let sourcePath = sandbox.fileURL.path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeFailingTrashClient(recorder: recorder)
        }

        // store.exhaustivity = .off: failure is emitted asynchronously; we only need the final contract.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.trash(.moveToTrash(paths: [sourcePath])))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(recorder.trashedPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
        XCTAssertNotNil(store.state.itemStates[sourcePath]?.lastError)
    }

    // MARK: - EOP-003-delete_entries_immediately

    /// EOP-003-delete_entries_immediately: 선택한 Entry가 즉시 삭제되는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 즉시 삭제할 때 실제 파일이 제거되고 reducer state가 정리되는지 확인한다.
    /// - 검증 내용: `.trash(.deleteImmediately)`가 confirmation 이후 실제 deleteImmediately 호출로 이어진다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, 삭제 확인 alert는 승인으로 응답한다.
    /// - 기대 결과: source가 삭제되고 FileOpsRecorder에 delete 기록이 남으며, 원본 fixture 경로는 유지된다.
    func testDeleteEntriesImmediately_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let sourcePath = sandbox.fileURL.path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.entryOperationsAlertClient.showDeleteConfirmationAlert = { _ in true }
        }

        // store.exhaustivity = .off: delete confirmation + delete are asynchronous.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.trash(.deleteImmediately(paths: [sourcePath])))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.deletedPaths, [URL(fileURLWithPath: sourcePath)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-003-delete_entries_immediately: 즉시 삭제 client 실패가 error state로 남는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 즉시 삭제할 때 권한 오류가 발생하면 파일 보존과 실패 상태를 확인한다.
    /// - 검증 내용: `.trash(.deleteImmediately)`가 confirmation 이후 deleteImmediately 오류를 lifecycle failure로 변환한다.
    /// - 사전 조건: fixture를 FixtureSandbox로 복사하고, 삭제 확인 alert는 승인하며 delete client는 permission denied를 던진다.
    /// - 기대 결과: source와 원본 fixture는 유지되고, reducer state에는 실패가 반영된다.
    func testDeleteEntriesImmediately_permissionDeniedSetsLastError() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let sourcePath = sandbox.fileURL.path
        let error = FileOpError.system(message: "permission denied")

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeFailingDeleteClient(error: error)
            $0.entryOperationsAlertClient.showDeleteConfirmationAlert = { _ in true }
        }

        // store.exhaustivity = .off: delete confirmation과 실패 lifecycle은 비동기 체인이므로 최종 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.trash(.deleteImmediately(paths: [sourcePath])))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertEqual(store.state.itemStates[sourcePath]?.lastError, error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-003-empty_trash

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
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashPath.path))

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
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

    // MARK: - EOP-003-undo_entry_action

    /// EOP-003-undo_entry_action: move-to-trash 기록을 undo 하면 원래 위치로 돌아오는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 Trash에서 되돌릴 때 source 복구와 redo stack 갱신이 함께 일어나는지 확인한다.
    /// - 검증 내용: `.undoRedo(.undoEntryAction)`가 putBackFromTrash replay와 redo record 이동을 수행한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 fake Trash로 옮겨 둔 뒤, matching trash metadata와 undo record를 주입한다.
    /// - 기대 결과: trash 파일이 원래 경로로 복귀하고, undo stack은 비워지며 redo stack에 기록이 남는다.
    func testUndoEntryAction_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let trashRoot = sandbox.root.appendingPathComponent(".Trash")
        let sourcePath = sandbox.fileURL.path
        let trashPath = trashRoot.appendingPathComponent(sandbox.fileURL.lastPathComponent).path
        let record = try prepareTrashRecord(sourceURL: sandbox.fileURL, trashRoot: trashRoot)

        let store = EntryOperationsTestSupport.makeStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.undoRecords = [record]
            return state
        }()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder, trashRoot: trashRoot)
        }

        await store.dependencies.trashMetadataStoreClient.save(TrashMetadata(
            trashPath: trashPath,
            originalPath: sourcePath,
            deletedDate: Date(timeIntervalSince1970: 0),
        ))

        // store.exhaustivity = .off: undo replay emits a chained async effect; final state and filesystem are enough.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.undoRedo(.undoEntryAction(record)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.movedPaths.first?.source.path, trashPath)
        XCTAssertEqual(recorder.movedPaths.first?.destination.path, sourcePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashPath))
        XCTAssertEqual(store.state.undoRecords.count, 0)
        XCTAssertEqual(store.state.redoRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-003-undo_entry_action: filesystem replay 실패 후에도 선행된 stack 전이를 되돌리지 않는다.
    /// 사용자가 Trash 이동을 undo할 때 put-back이 실패하면 현재 production의 비원자적 실패 상태를 유지하는지 검증한다.
    /// - 검증 내용: 실제 `.undoEntryAction` replay가 lifecycle failure를 남기고 stack rollback이나 filesystem 보상을 수행하지 않는다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 fake Trash로 옮긴 undo record가 하나 있고 putBack dependency는 실패한다.
    /// - 기대 결과: undo stack은 비고 redo stack은 record를 유지하며, Trash 경로의 작업 상태는 오류와 함께 종료되고 파일은 Trash에 남는다.
    func testUndoEntryAction_replayFailureKeepsStackTransitionAndLifecycleError() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let trashRoot = sandbox.root.appendingPathComponent(".Trash")
        let sourcePath = sandbox.fileURL.path
        let trashPath = trashRoot.appendingPathComponent(sandbox.fileURL.lastPathComponent).path
        let record = try prepareTrashRecord(sourceURL: sandbox.fileURL, trashRoot: trashRoot)
        let expectedError = FileOpError.system(message: "put back unavailable")
        var entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder, trashRoot: trashRoot)
        entryFileOpsClient.putBackFromTrash = { _, _ in
            throw expectedError
        }

        let store = EntryOperationsTestSupport.makeStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.undoRecords = [record]
            return state
        }()) {
            $0.entryFileOpsClient = entryFileOpsClient
        }

        // store.exhaustivity = .off: undo replay의 비동기 lifecycle chain 이후 최종 실패 상태와 stack 의미를 검증한다.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.undoRedo(.undoEntryAction(record)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertEqual(store.state.redoRecords, [record])
        XCTAssertEqual(store.state.itemStates[trashPath]?.isBusy, false)
        XCTAssertEqual(store.state.itemStates[trashPath]?.lastError, expectedError)
        XCTAssertTrue(recorder.movedPaths.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-003-redo_entry_action

    /// EOP-003-redo_entry_action: undo된 move-to-trash 기록을 redo 하면 다시 Trash로 이동하는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 다시 Trash로 보낼 때 redo stack 복원과 실제 trash 이동이 함께 일어나는지 확인한다.
    /// - 검증 내용: `.undoRedo(.redoEntryAction)`가 moveToTrash replay와 undo record 복원을 수행한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 샌드박스에 둔 뒤 redo record를 주입하고 fake Trash 디렉터리를 준비한다.
    /// - 기대 결과: source가 Trash로 이동하고, undo stack이 복원되며 redo stack은 비워진다.
    func testRedoEntryAction_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let trashRoot = sandbox.root.appendingPathComponent(".Trash")
        let sourcePath = sandbox.fileURL.path
        let trashPath = trashRoot.appendingPathComponent(sandbox.fileURL.lastPathComponent).path
        let record = EntryActionRecord(
            operationKind: .moveToTrash,
            targets: [.init(beforePath: sourcePath, afterPath: trashPath)],
        )

        let store = EntryOperationsTestSupport.makeStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.redoRecords = [record]
            return state
        }()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder, trashRoot: trashRoot)
        }

        // store.exhaustivity = .off: redo replay is async and the final state/file mutation is the contract we need.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.undoRedo(.redoEntryAction(record)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.trashedPaths, [URL(fileURLWithPath: trashPath)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashPath))
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertEqual(store.state.redoRecords.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-003-undo_entry_action

    /// EOP-003-undo_entry_action: 새 action 완료 시 undo stack에 push되고 redo stack이 clear된다
    /// `entryActionCompleted`가 isUndoable 작업으로 들어오면 undoRecords에 append하고 redoRecords를 비운다.
    /// - 검증 내용: `entryActionCompleted`가 undo stack에 record를 추가하고 redo stack을 clear한다.
    /// - 사전 조건: undoRecords와 redoRecords 모두 기존 record를 가진 상태.
    /// - 기대 결과: 새 record가 undoRecords에 추가되고 redoRecords가 비워진다.
    func testUndoStack_pushClearsRedo() async {
        let existingUndo = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/a/old.txt", afterPath: "/a/new.txt")],
        )
        let existingRedo = EntryActionRecord(
            operationKind: .pasteFileCopy,
            targets: [.init(beforePath: "/b/src.txt", afterPath: "/b/dst.txt")],
        )
        let newRecord = EntryActionRecord(
            operationKind: .createFolder,
            targets: [.init(beforePath: nil, afterPath: "/c/new_folder")],
        )

        var initialState = EntryOperationsState()
        initialState.undoRecords = [existingUndo]
        initialState.redoRecords = [existingRedo]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState)

        await store.send(.lifecycle(.entryActionCompleted(newRecord))) {
            $0.undoRecords = [existingUndo, newRecord]
            $0.redoRecords = []
        }

        await store.finish()

        XCTAssertEqual(store.state.undoRecords.count, 2)
        XCTAssertEqual(store.state.undoRecords.last?.operationKind, .createFolder)
        XCTAssertTrue(store.state.redoRecords.isEmpty)
    }

    /// EOP-003-undo_entry_action: undoEntryAction이 undo stack에서 pop하고 redo stack에 push한다
    /// `undoEntryAction`이 latestUndoRecord를 pop하고 redoRecords에 append한 후 replay를 트리거한다.
    /// - 검증 내용: `undoEntryAction`이 undo stack에서 pop하고 redo stack에 push한다.
    /// - 사전 조건: undoRecords에 하나의 record가 있고 redoRecords가 비어있다.
    /// - 기대 결과: undoRecords가 비워지고 redoRecords에 record가 들어간다.
    func testUndoStack_undoEntryActionPopsAndPushes() async {
        let sourcePath = "/a/old.txt"
        let destPath = "/a/new.txt"
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: sourcePath, afterPath: destPath)],
        )

        var initialState = EntryOperationsState()
        initialState.undoRecords = [record]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState)

        store.exhaustivity = .off

        await store.send(.undoRedo(.undoEntryAction(record)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertEqual(store.state.redoRecords.count, 1)
        XCTAssertEqual(store.state.redoRecords.first?.id, record.id)
    }

    /// EOP-003-undo_entry_action: undoRecords가 비어있으면 requestUndo가 no-op이다
    /// 되돌릴 수 있는 action history가 없으면 아무 작업도 수행하지 않는다.
    /// - 검증 내용: `requestUndo`가 undoRecords가 비어있을 때 상태를 변경하지 않는다.
    /// - 사전 조건: undoRecords가 빈 배열이다.
    /// - 기대 결과: 상태 변화 없음.
    func testUndoStack_requestUndoEmptyIsNoop() async {
        let store = EntryOperationsTestSupport.makeStore()

        await store.send(.undoRedo(.requestUndo))
        await store.finish()

        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertTrue(store.state.redoRecords.isEmpty)
    }

    /// EOP-003-undo_entry_action: 대상 record의 path가 busy 상태면 undo를 건너뛴다
    /// `requestUndo` 단계에서 isBusy 확인 후 busy면 no-op이다.
    /// - 검증 내용: `requestUndo`가 target path가 busy 상태일 때 상태를 변경하지 않는다.
    /// - 사전 조건: undoRecords에 record가 있고 해당 path의 itemStates가 isBusy=true.
    /// - 기대 결과: 상태 변화 없음.
    func testUndoStack_busyTargetSkipsUndo() async {
        let sourcePath = "/a/old.txt"
        let destPath = "/a/new.txt"
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: sourcePath, afterPath: destPath)],
        )

        var initialState = EntryOperationsState()
        initialState.undoRecords = [record]
        initialState.itemStates[sourcePath] = ItemOperationState(isBusy: true)

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState)

        await store.send(.undoRedo(.requestUndo))
        await store.finish()

        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertTrue(store.state.redoRecords.isEmpty)
    }

    /// EOP-003-undo_entry_action: record ID가 불일치하면 undo가 무시된다
    /// UndoManager 콜백으로 들어온 record의 ID가 latestUndoRecord와 다르면 무시한다.
    /// - 검증 내용: `undoEntryAction`이 ID 불일치 record에 대해 상태를 변경하지 않는다.
    /// - 사전 조건: undoRecords에 record가 있고, 들어오는 record의 ID가 다르다.
    /// - 기대 결과: undoRecords와 redoRecords가 그대로 유지된다.
    func testUndoStack_recordIdMismatchIgnored() async {
        let correctRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/a/old.txt", afterPath: "/a/new.txt")],
        )
        let wrongRecord = EntryActionRecord(
            operationKind: .pasteFileCopy,
            targets: [.init(beforePath: "/b/src.txt", afterPath: "/b/dst.txt")],
        )

        var initialState = EntryOperationsState()
        initialState.undoRecords = [correctRecord]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState)

        await store.send(.undoRedo(.undoEntryAction(wrongRecord)))
        await store.finish()

        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertEqual(store.state.undoRecords.first?.id, correctRecord.id)
        XCTAssertTrue(store.state.redoRecords.isEmpty)
    }

    /// EOP-003-redo_entry_action: redoEntryAction이 redo stack에서 pop하고 undo stack에 push한다
    /// `redoEntryAction`이 latestRedoRecord를 pop하고 undoRecords에 append한 후 replay를 트리거한다.
    /// - 검증 내용: `redoEntryAction`이 redo stack에서 pop하고 undo stack에 push한다.
    /// - 사전 조건: redoRecords에 하나의 record가 있고 undoRecords가 비어있다.
    /// - 기대 결과: redoRecords가 비워지고 undoRecords에 record가 들어간다.
    func testRedoStack_redoEntryActionPopsAndPushes() async {
        let sourcePath = "/a/old.txt"
        let destPath = "/a/new.txt"
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: sourcePath, afterPath: destPath)],
        )

        var initialState = EntryOperationsState()
        initialState.redoRecords = [record]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState)

        store.exhaustivity = .off

        await store.send(.undoRedo(.redoEntryAction(record)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(store.state.redoRecords.isEmpty)
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertEqual(store.state.undoRecords.first?.id, record.id)
    }

    /// EOP-003-redo_entry_action: redoRecords가 비어있으면 requestRedo가 no-op이다
    /// redo 가능한 action history가 없으면 아무 작업도 수행하지 않는다.
    /// - 검증 내용: `requestRedo`가 redoRecords가 비어있을 때 상태를 변경하지 않는다.
    /// - 사전 조건: redoRecords가 빈 배열이다.
    /// - 기대 결과: 상태 변화 없음.
    func testRedoStack_requestRedoEmptyIsNoop() async {
        let store = EntryOperationsTestSupport.makeStore()

        await store.send(.undoRedo(.requestRedo))
        await store.finish()

        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertTrue(store.state.redoRecords.isEmpty)
    }

    // MARK: - EOP-003-redo_entry_action

    // AC: EOP-003-redo_entry_action Edge Case #8
    /// EOP-003-redo_entry_action: 대상 record의 path가 busy 상태면 redo를 건너뛴다
    /// `requestRedo` 단계에서 isBusy 확인 후 busy면 no-op이다.
    /// - 검증 내용: `requestRedo`가 target path가 busy 상태일 때 상태를 변경하지 않는다.
    /// - 사전 조건: redoRecords에 record가 있고 해당 path의 itemStates가 isBusy=true.
    /// - 기대 결과: 상태 변화 없음, redo 시도도 하지 않음.
    func testRedo_busyTarget_skipsRedo() async {
        let sourcePath = "/a/old.txt"
        let destPath = "/a/new.txt"
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: sourcePath, afterPath: destPath)],
        )

        var initialState = EntryOperationsState()
        initialState.redoRecords = [record]
        initialState.itemStates[sourcePath] = ItemOperationState(isBusy: true)

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState)

        await store.send(.undoRedo(.requestRedo))
        await store.finish()

        // AC: EOP-003-redo_entry_action Edge Case #8 — busy guard가 redo를 차단한다
        XCTAssertEqual(store.state.redoRecords.count, 1)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
    }

    // AC: EOP-003-redo_entry_action Edge Case #10
    /// EOP-003-redo_entry_action: record ID가 불일치하면 redo가 무시된다
    /// UndoManager 콜백으로 들어온 record의 ID가 latestRedoRecord와 다르면 무시한다.
    /// - 검증 내용: `redoEntryAction`이 ID 불일치 record에 대해 상태를 변경하지 않는다.
    /// - 사전 조건: redoRecords에 record가 있고, 들어오는 record의 ID가 다르다.
    /// - 기대 결과: redoRecords와 undoRecords가 그대로 유지된다.
    func testRedo_recordIdMismatch_ignoresAndPreservesState() async {
        let correctRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/a/old.txt", afterPath: "/a/new.txt")],
        )
        let wrongRecord = EntryActionRecord(
            operationKind: .pasteFileCopy,
            targets: [.init(beforePath: "/b/src.txt", afterPath: "/b/dst.txt")],
        )

        var initialState = EntryOperationsState()
        initialState.redoRecords = [correctRecord]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState)

        await store.send(.undoRedo(.redoEntryAction(wrongRecord)))
        await store.finish()

        // AC: EOP-003-redo_entry_action Edge Case #10 — ID 불일치로 redo 무시
        XCTAssertEqual(store.state.redoRecords.count, 1)
        XCTAssertEqual(store.state.redoRecords.first?.id, correctRecord.id)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
    }

    // MARK: - EOP-003-undo_entry_action

    /// EOP-003-undo_entry_action: activate되지 않은 explicit scope의 register와 undo는 fail-closed된다.
    /// native manager가 없는 탭 scope에 요청해도 manager를 암묵 생성하거나 다른 scope로 fallback하지 않는지 검증한다.
    /// - 검증 내용: `FileOperationUndoManagerClient`의 registerUndo/requestUndo가 false를 반환하고 manager lookup이 nil이다.
    /// - 사전 조건: 새 registry와 activate하지 않은 `(windowID, contentTabID)` scope가 있다.
    /// - 기대 결과: 등록과 undo 요청이 모두 거부되고 registry에는 manager가 생성되지 않는다.
    func testFileOperationClientMissingScopeFailsClosedForRegisterAndUndo() async {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let scope = UndoManagerScope(windowID: UUID(), contentTabID: "missing-tab")
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/a/old.txt", afterPath: "/a/new.txt")],
        )

        let didRegister = await client.registerUndo(scope, 0, record, { _ in }, { _ in })
        let didRequestUndo = await client.requestUndo(scope)
        let manager = await client.undoManager(scope)

        XCTAssertFalse(didRegister)
        XCTAssertFalse(didRequestUndo)
        XCTAssertNil(manager)
    }

    // MARK: - EOP-003-redo_entry_action

    /// EOP-003-redo_entry_action: activate되지 않은 explicit scope의 redo는 fail-closed된다.
    /// native manager가 없는 탭 scope의 redo가 key window나 responder manager로 fallback하지 않는지 검증한다.
    /// - 검증 내용: `FileOperationUndoManagerClient.requestRedo`가 false를 반환하고 manager lookup이 nil이다.
    /// - 사전 조건: 새 registry와 activate하지 않은 `(windowID, contentTabID)` scope가 있다.
    /// - 기대 결과: redo 요청이 거부되고 registry에는 manager가 생성되지 않는다.
    func testFileOperationClientMissingScopeFailsClosedForRedo() async {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let scope = UndoManagerScope(windowID: UUID(), contentTabID: "missing-tab")

        let didRequestRedo = await client.requestRedo(scope)
        let manager = await client.undoManager(scope)

        XCTAssertFalse(didRequestRedo)
        XCTAssertNil(manager)
    }

    // MARK: - EOP-003-load_entry_items

    /// EOP-003-load_entry_items (VOY-578): Directory 실패와 성공한 빈 결과를 별도 completion으로 처리함
    /// 일반 Directory load 실패 후 retry가 빈 Directory로 성공하는 lifecycle 계약을 검증한다.
    /// - 검증 내용: 실패는 itemsLoadFailed로 transient state를 정리하고 retry 성공은 itemsLoaded([])를 방출함
    /// - 사전 조건: 기존 item과 reload/rename state가 있고 loader는 continuation으로 실패 후 빈 배열을 반환함
    /// - 기대 결과: 실패 직후 item/loading/reloading/rename state가 비고, retry의 빈 성공은 정상 completion으로 종료됨
    func testDirectoryLoadFailureClearsTransientStateThenEmptyRetrySucceeds() async {
        await verifyLoadFailureRetry()
    }

    /// EOP-003-load_entry_items (VOY-578): 취소된 Recents 응답은 최신 항목을 덮어쓰지 않음
    /// 취소를 무시하는 Recents loader가 늦게 완료돼도 stale itemsLoaded를 방출하지 않는지 검증한다.
    /// - 검증 내용: Recents load 보류 후 replacement Directory load 완료, Recents 재개 뒤 최신 항목 유지
    /// - 사전 조건: Recents dependency가 continuation에서 대기하고 같은 cancellation ID의 Directory load가 뒤따름
    /// - 기대 결과: 취소된 Recents 응답은 itemsLoaded를 보내지 않고 replacement 항목이 유지됨
    func testCancelledRecentItemsResponseDoesNotOverwriteLatestItems() async {
        let preservedLatest = await EntryOperationsTestSupport.cancelledLoadPreservesLatest(.recents)
        XCTAssertTrue(preservedLatest)
    }

    /// EOP-003-load_entry_items (VOY-578): 취소된 Tag 응답은 최신 항목을 덮어쓰지 않음
    /// 취소를 무시하는 Tag loader가 늦게 완료돼도 stale itemsLoaded를 방출하지 않는지 검증한다.
    /// - 검증 내용: Tag load 보류 후 replacement Directory load 완료, Tag 재개 뒤 최신 항목 유지
    /// - 사전 조건: Tag dependency가 continuation에서 대기하고 같은 cancellation ID의 Directory load가 뒤따름
    /// - 기대 결과: 취소된 Tag 응답은 itemsLoaded를 보내지 않고 replacement 항목이 유지됨
    func testCancelledTagItemsResponseDoesNotOverwriteLatestItems() async {
        let preservedLatest = await EntryOperationsTestSupport.cancelledLoadPreservesLatest(.tag)
        XCTAssertTrue(preservedLatest)
    }

    /// EOP-003-load_entry_items (VOY-578): 취소된 Computer 성공 응답은 최신 항목을 덮어쓰지 않음
    /// 취소를 무시하는 Computer loader가 성공으로 늦게 완료돼도 stale itemsLoaded를 방출하지 않는지 검증한다.
    /// - 검증 내용: Computer load 보류 후 replacement Directory load 완료, 성공 재개 뒤 최신 항목 유지
    /// - 사전 조건: Computer dependency가 continuation에서 대기하고 같은 cancellation ID의 Directory load가 뒤따름
    /// - 기대 결과: 취소된 Computer 성공 응답은 itemsLoaded를 보내지 않고 replacement 항목이 유지됨
    func testCancelledComputerItemsSuccessDoesNotOverwriteLatestItems() async {
        let preservedLatest = await EntryOperationsTestSupport.cancelledLoadPreservesLatest(.computerSuccess)
        XCTAssertTrue(preservedLatest)
    }

    /// EOP-003-load_entry_items (VOY-578): 취소된 Computer 오류 응답은 빈 항목 fallback을 방출하지 않음
    /// 취소를 무시하는 Computer loader가 오류로 늦게 완료돼도 stale 빈 itemsLoaded를 방출하지 않는지 검증한다.
    /// - 검증 내용: Computer load 보류 후 replacement Directory load 완료, 오류 재개 뒤 최신 항목 유지
    /// - 사전 조건: Computer dependency가 continuation에서 대기하고 같은 cancellation ID의 Directory load가 뒤따름
    /// - 기대 결과: 취소된 Computer 오류 fallback은 itemsLoaded를 보내지 않고 replacement 항목이 유지됨
    func testCancelledComputerItemsFailureDoesNotClearLatestItems() async {
        let preservedLatest = await EntryOperationsTestSupport.cancelledLoadPreservesLatest(.computerFailure)
        XCTAssertTrue(preservedLatest)
    }
}

extension EOP003ManageEntryLifecycleTests {
    // MARK: - EOP-003-load_entry_items

    /// EOP-003-load_entry_items: 모든 loaded list는 Trash metadata projection을 새로 읽는다.
    /// - 검증 내용: itemsLoaded 후 저장된 trash path가 restorableTrashPaths로 투영된다.
    /// - 사전 조건: metadata store에 하나의 Trash record가 있고 loaded item 목록은 비어 있다.
    /// - 기대 결과: lifecycle load completion이 해당 Trash path만 state에 저장한다.
    func testItemsLoadedRefreshesRestorableTrashPaths() async {
        let trashPath = "/tmp/.Trash/entry.txt"
        let store = EntryOperationsTestSupport.makeStore(initialState: .init())
        await store.dependencies.trashMetadataStoreClient.save(TrashMetadata(
            trashPath: trashPath,
            originalPath: "/tmp/entry.txt",
            deletedDate: .distantPast,
        ))
        // RED: itemsLoaded never refreshed the menu eligibility projection.
        await store.send(.loading(.itemsLoaded([])))
        await store.receive(\.lifecycle.restorableTrashPathsLoaded) {
            $0.restorableTrashPaths = [trashPath]
        }
        // GREEN: every successful list load refreshes the restorable Trash-path projection.
        XCTAssertEqual(store.state.restorableTrashPaths, [trashPath])
    }

    // MARK: - EOP-003-move_entries_to_trash

    /// EOP-003-move_entries_to_trash: 성공한 Put Back은 metadata와 capability projection을 함께 제거한다.
    /// - 검증 내용: putBack 성공 뒤 restorableTrashPaths와 metadata store가 비어 있다.
    /// - 사전 조건: fake Trash의 실제 파일과 일치하는 metadata 및 restorable path가 있다.
    /// - 기대 결과: 원래 경로로 파일이 돌아오고 metadata와 eligibility가 제거된다.
    func testPutBackSuccessRemovesRestorableMetadata() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let recorder = FileOpsRecorder()
        let trashRoot = sandbox.root.appendingPathComponent(".Trash")
        let sourcePath = sandbox.fileURL.path
        let record = try prepareTrashRecord(sourceURL: sandbox.fileURL, trashRoot: trashRoot)
        guard let trashPath = record.targets.first?.afterPath else {
            XCTFail("Expected a Trash path")
            return
        }
        var initialState = EntryOperationsState()
        initialState.restorableTrashPaths = [trashPath]
        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder, trashRoot: trashRoot)
        }
        await store.dependencies.trashMetadataStoreClient.save(TrashMetadata(
            trashPath: trashPath,
            originalPath: sourcePath,
            deletedDate: .distantPast,
        ))
        // RED: a successful restore left the metadata eligibility path stale.
        // store.exhaustivity = .off: put-back emits per-path lifecycle actions before the final action record.
        store.exhaustivity = .off
        await store.send(.trash(.putBackFromTrash(paths: [trashPath])))
        await store.finish()
        await store.skipReceivedActions()
        // GREEN: reducer removal and lifecycle projection removal agree after restore.
        let remainingMetadata = await store.dependencies.trashMetadataStoreClient.find(trashPath)
        XCTAssertNil(remainingMetadata)
        XCTAssertFalse(store.state.restorableTrashPaths.contains(trashPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashPath))
    }
}

private extension EOP003ManageEntryLifecycleTests {
    func verifyLoadFailureRetry() async {
        let staleEntry = EntryModelFixtures.makeFileEntry(id: "/tmp/stale.txt", name: "stale.txt")
        let gate = EntryLoadSuspensionGate()
        var initialState = EntryOperationsState()
        initialState.items = [staleEntry]
        initialState.isReloading = true
        initialState.renamingItemId = staleEntry.id
        initialState.renamingText = staleEntry.name
        initialState.renamingItem = staleEntry
        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryLoadingClient.loadItems = { _, _ in try await gate.wait() }
        }
        await store.send(.loading(.loadItems(path: "/tmp", showHidden: false))) { $0.isLoading = true }
        await gate.waitUntilWaiting()
        await gate.resume(with: .failure)
        await store.receive(\.loading.itemsLoadFailed) {
            $0.items = []
            $0.isLoading = false
            $0.isReloading = false
            $0.renamingItemId = nil
            $0.renamingText = ""
            $0.renamingItem = nil
        }
        await store.send(.loading(.loadItems(path: "/tmp", showHidden: false))) { $0.isLoading = true }
        await gate.waitUntilWaiting()
        await gate.resume(with: .entries([]))
        await store.receive(\.loading.itemsLoaded, []) {
            $0.isLoading = false
        }
        await store.receive(\.lifecycle.restorableTrashPathsLoaded)
    }
}

// MARK: - VOY-610-entry-sound

private actor SoundRecorder {
    var playedSounds: [EntryOperationSound] = []

    func record(_ sound: EntryOperationSound) {
        playedSounds.append(sound)
    }
}

extension EOP003ManageEntryLifecycleTests {
    /// VOY-610-entry-sound: moveToTrash batch completion이 EntryOperationSound.moveToTrash를 정확히 한 번 요청한다.
    /// 사용자가 하나 이상의 Entry를 Trash로 이동한 후 batch가 완료되면 drag-to-trash 사운드가 재생된다.
    /// - 검증 내용: entryActionCompleted(.moveToTrash) → .moveToTrash sound
    /// - 사전 조건: recorder가 주입된 TestStore
    /// - 기대 결과: recorder.playedSounds에 [.moveToTrash]가 기록된다
    func testMoveToTrashBatchPlaysFinderTrashSoundOnce() async {
        let recorder = SoundRecorder()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOperationSoundClient = EntryOperationSoundClient(play: { sound in
                await recorder.record(sound)
            })
        }
        let record = EntryActionRecord(
            operationKind: .moveToTrash,
            targets: [.init(beforePath: "/a/file.txt", afterPath: "/.Trash/file.txt")],
        )

        // store.exhaustivity = .off: sound play is a fire-and-forget .run effect
        store.exhaustivity = .off

        await store.send(.lifecycle(.entryActionCompleted(record)))
        await store.finish()

        let sounds = await recorder.playedSounds
        XCTAssertEqual(sounds, [.moveToTrash])
    }

    /// VOY-610-entry-sound: emptyTrashCompleted가 EntryOperationSound.emptyTrash를 정확히 한 번 요청한다.
    /// 사용자가 Trash 비우기를 완료하면 empty-trash 사운드가 재생된다.
    /// - 검증 내용: emptyTrashCompleted → .emptyTrash sound
    /// - 사전 조건: recorder가 주입된 TestStore
    /// - 기대 결과: recorder.playedSounds에 [.emptyTrash]가 기록된다
    func testEmptyTrashCompletedPlaysFinderEmptyTrashSoundOnce() async {
        let recorder = SoundRecorder()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOperationSoundClient = EntryOperationSoundClient(play: { sound in
                await recorder.record(sound)
            })
        }

        // store.exhaustivity = .off: sound play is a fire-and-forget .run effect
        store.exhaustivity = .off

        await store.send(.lifecycle(.emptyTrashCompleted))
        await store.finish()

        let sounds = await recorder.playedSounds
        XCTAssertEqual(sounds, [.emptyTrash])
    }

    /// VOY-610-entry-sound: pasteFileCopy/pasteFileMove/pasteFileDuplicate/putBack batch 완료가
    /// EntryOperationSound.operationCompleted를 batch당 정확히 1회 요청한다.
    /// 다중 파일 복사/이동에서도 사운드는 batch 완료 시 1회만 재생된다.
    /// - 검증 내용: entryActionCompleted for pasteFileCopy/pasteFileMove/pasteFileDuplicate/putBack →
    /// .operationCompleted sound (batch당 1회)
    /// - 사전 조건: recorder가 주입된 TestStore
    /// - 기대 결과: 각 batch마다 recorder.playedSounds에 .operationCompleted가 1회 기록된다
    func testBatchCompletionsPlayOperationCompletedSound() async {
        let recorder = SoundRecorder()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOperationSoundClient = EntryOperationSoundClient(play: { sound in
                await recorder.record(sound)
            })
        }

        store.exhaustivity = .off

        let copyRecord = EntryActionRecord(
            operationKind: .pasteFileCopy,
            targets: [
                .init(beforePath: "/a/src1.txt", afterPath: "/b/dst1.txt"),
                .init(beforePath: "/a/src2.txt", afterPath: "/b/dst2.txt"),
            ],
        )
        await store.send(.lifecycle(.entryActionCompleted(copyRecord)))
        await store.finish()

        var sounds = await recorder.playedSounds
        XCTAssertEqual(sounds, [.operationCompleted], "pasteFileCopy batch should play operationCompleted once")

        let moveRecord = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: "/a/src.txt", afterPath: "/b/dst.txt")],
        )
        await store.send(.lifecycle(.entryActionCompleted(moveRecord)))
        await store.finish()
        sounds = await recorder.playedSounds
        XCTAssertEqual(sounds, [.operationCompleted, .operationCompleted])

        let duplicateRecord = EntryActionRecord(
            operationKind: .pasteFileDuplicate,
            targets: [.init(beforePath: "/a/src.txt", afterPath: "/a/src copy.txt")],
        )
        await store.send(.lifecycle(.entryActionCompleted(duplicateRecord)))
        await store.finish()
        sounds = await recorder.playedSounds
        XCTAssertEqual(sounds, [.operationCompleted, .operationCompleted, .operationCompleted])

        let putBackRecord = EntryActionRecord(
            operationKind: .putBack,
            targets: [.init(beforePath: "/.Trash/file.txt", afterPath: "/original/file.txt")],
        )
        await store.send(.lifecycle(.entryActionCompleted(putBackRecord)))
        await store.finish()
        sounds = await recorder.playedSounds
        XCTAssertEqual(
            sounds,
            [.operationCompleted, .operationCompleted, .operationCompleted, .operationCompleted],
        )
    }

    /// VOY-610-entry-sound: non-cancel 오류는 .error 사운드를 요청하고 .cancelled는 무음이다.
    /// 사용자의 파일 작업이 실패하면 preferred alert 사운드가 재생되지만, 취소는 무음이다.
    /// - 검증 내용: operationFinished(.failure(.system)) → .error sound, operationFinished(.failure(.cancelled)) → 무음
    /// - 사전 조건: recorder가 주입된 TestStore
    /// - 기대 결과: .system 오류 사운드가 기록되고 .cancelled는 기록되지 않는다
    func testFailuresPlayPreferredAlertExceptCancellation() async {
        let recorder = SoundRecorder()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOperationSoundClient = EntryOperationSoundClient(play: { sound in
                await recorder.record(sound)
            })
        }

        // store.exhaustivity = .off: sound play is a fire-and-forget .run effect
        store.exhaustivity = .off

        // system error → .error sound
        await store.send(.lifecycle(.operationFinished(
            "/a/file.txt",
            .pasteFileCopy,
            .failure(.system(message: "disk full")),
        )))
        await store.finish()

        var sounds = await recorder.playedSounds
        XCTAssertEqual(sounds, [.error], "system error should play error sound")

        // cancelled → no sound
        await store.send(.lifecycle(.operationFinished("/a/file.txt", .pasteFileCopy, .failure(.cancelled))))
        await store.finish()

        sounds = await recorder.playedSounds
        XCTAssertEqual(sounds, [.error], "cancelled should NOT produce sound")
    }

    /// VOY-610-entry-sound: 두 개의 연속 entryActionCompleted batch가 각각 sound client에 도달한다.
    /// reducer는 모든 batch 완료를 sound client에 전달하며, throttle은 SoundPlayer live value에서만 적용된다.
    /// - 검증 내용: 연속 entryActionCompleted 2회 → recorder에 2개의 sound
    /// - 사전 조건: recorder가 주입된 TestStore
    /// - 기대 결과: recorder.playedSounds.count가 2 (reducer는 throttle 없이 모든 요청을 전달)
    func testRapidBatchCompletionsReachSoundClient() async {
        let recorder = SoundRecorder()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOperationSoundClient = EntryOperationSoundClient(play: { sound in
                await recorder.record(sound)
            })
        }

        store.exhaustivity = .off

        let batch1 = EntryActionRecord(
            operationKind: .pasteFileCopy,
            targets: [.init(beforePath: "/a/src.txt", afterPath: "/b/dst.txt")],
        )
        await store.send(.lifecycle(.entryActionCompleted(batch1)))
        await store.finish()

        let batch2 = EntryActionRecord(
            operationKind: .pasteFileCopy,
            targets: [.init(beforePath: "/c/src.txt", afterPath: "/d/dst.txt")],
        )
        await store.send(.lifecycle(.entryActionCompleted(batch2)))
        await store.finish()

        let sounds = await recorder.playedSounds
        XCTAssertEqual(sounds.count, 2, "Both batches should request sound; throttle is in live value only")
    }

    /// VOY-610-entry-sound: operationFinished(.success)는 모든 종류에서 무음이며,
    /// entryActionCompleted에서도 createFolder/createAlias/rename/setTags는 사운드를 생성하지 않는다.
    /// 완료 사운드는 pasteFileCopy/Move/Duplicate/putBack batch에서만 재생된다.
    /// - 검증 내용: operationFinished(.success) for excluded kinds → 0 sound,
    ///   entryActionCompleted for createFolder/createAlias/rename/setTags → 0 sound
    /// - 사전 조건: recorder가 주입된 TestStore
    /// - 기대 결과: recorder.playedSounds가 비어 있다
    func testExcludedOperationKindsProduceNoSound() async {
        let recorder = SoundRecorder()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOperationSoundClient = EntryOperationSoundClient(play: { sound in
                await recorder.record(sound)
            })
        }

        store.exhaustivity = .off

        let excludedKinds: [OperationKind] = [
            .createFolder,
            .rename,
            .setTags,
            .compress,
            .extract,
            .openDefault,
            .revealInFinder,
        ]
        for kind in excludedKinds {
            await store.send(.lifecycle(.operationFinished("/a/file.txt", kind, .success(()))))
            await store.finish()
        }

        let undoableNonSoundableKinds: [OperationKind] = [
            .createFolder,
            .createAlias,
            .rename,
            .setTags,
        ]
        for kind in undoableNonSoundableKinds {
            let record = EntryActionRecord(
                operationKind: kind,
                targets: [.init(beforePath: nil, afterPath: "/a/file.txt")],
            )
            await store.send(.lifecycle(.entryActionCompleted(record)))
            await store.finish()
        }

        let sounds = await recorder.playedSounds
        XCTAssertTrue(sounds.isEmpty, "Excluded operation kinds should produce no sound")
    }

    /// VOY-610-entry-sound: moveToTrash batch completion이 정확히 한 번 요청하고
    /// entryActionCompleted의 기존 상태 업데이트(restorableTrashPaths)는 유지된다.
    /// - 검증 내용: sound 요청과 state 업데이트가 모두 정상 동작
    /// - 사전 조건: recorder가 주입된 TestStore
    /// - 기대 결과: recorder.playedSounds에 [.moveToTrash]가 있고, state.restorableTrashPaths가 갱신된다
    func testMoveToTrashSoundPreservesStateUpdate() async {
        let recorder = SoundRecorder()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOperationSoundClient = EntryOperationSoundClient(play: { sound in
                await recorder.record(sound)
            })
        }

        let record = EntryActionRecord(
            operationKind: .moveToTrash,
            targets: [.init(beforePath: "/a/file.txt", afterPath: "/.Trash/file.txt")],
        )

        // store.exhaustivity = .off: sound play is a fire-and-forget .run effect
        store.exhaustivity = .off

        await store.send(.lifecycle(.entryActionCompleted(record)))
        await store.finish()

        let sounds = await recorder.playedSounds
        XCTAssertEqual(sounds, [.moveToTrash])

        XCTAssertTrue(store.state.restorableTrashPaths.contains("/.Trash/file.txt"))
    }
}

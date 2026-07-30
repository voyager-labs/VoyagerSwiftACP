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

        let didRegister = client.registerUndo(scope, 0, record)
        let outcome = client.performUndoRedo(scope, 0, .undo, record.id)
        let manager = await client.undoManager(scope)

        XCTAssertFalse(didRegister)
        XCTAssertEqual(outcome, .rejected(.missingScope))
        XCTAssertNil(manager)
    }

    /// EOP-003-undo_entry_action: 같은 event turn의 파일 작업은 native Undo step을 각각 소유한다.
    /// 연속 등록된 두 logical record가 AppKit event grouping으로 한 번에 소비되지 않는지 검증한다.
    /// - 검증 내용: B Undo 후 A가 native undo top에 남고 B는 redo 가능하며 A Undo도 이어서 성공한다.
    /// - 사전 조건: 동일 scope와 generation에 A, B record를 동기적으로 연속 등록한다.
    /// - 기대 결과: 각 perform 요청이 정확히 한 record만 이동하고 scope가 invalidated되지 않는다.
    func testFileOperationRegistrySeparatesSameEventRegistrationsIntoNativeUndoSteps() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let scope = UndoManagerScope(windowID: UUID(), contentTabID: "same-event-tab")
        let recordA = EntryActionRecord(operationKind: .rename, targets: [])
        let recordB = EntryActionRecord(operationKind: .pasteFileCopy, targets: [])
        _ = client.activate(scope)
        let generation = try XCTUnwrap(client.generation(scope))

        XCTAssertTrue(client.registerUndo(scope, generation, recordA))
        XCTAssertTrue(client.registerUndo(scope, generation, recordB))

        let firstOutcome = client.performUndoRedo(scope, generation, .undo, recordB.id)
        let managerValue = await client.undoManager(scope)
        let manager = try XCTUnwrap(managerValue)
        XCTAssertEqual(firstOutcome, .applied)
        XCTAssertTrue(manager.canUndo)
        XCTAssertTrue(manager.canRedo)

        let secondOutcome = client.performUndoRedo(scope, generation, .undo, recordA.id)
        XCTAssertEqual(secondOutcome, .applied)
        XCTAssertFalse(manager.canUndo)
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

        let outcome = client.performUndoRedo(scope, 0, .redo, UUID())
        let manager = await client.undoManager(scope)

        XCTAssertEqual(outcome, .rejected(.missingScope))
        XCTAssertNil(manager)
    }

    // MARK: - EOP-003-load_entry_items

    /// EOP-003-load_entry_items: 대용량 디렉터리는 첫 core batch를 즉시 표시한다.
    /// 사용자가 65개 항목이 있는 디렉터리를 열 때 전체 변환 완료를 기다리지 않고 첫 32개를 볼 수 있어야 한다.
    /// - 검증 내용: directory load의 첫 observable completion은 32개 항목만 포함하고 blocking loading을 해제한다.
    /// - 사전 조건: EntryLoadingClient는 순서가 고정된 65개 항목을 반환한다.
    /// - 기대 결과: 첫 receive에서 32개 항목만 반영되고 남은 항목은 후속 lifecycle에서 추가된다.
    func testDirectoryLoadPublishesFirstCoreBatchBeforeRemainingItems() async {
        let entries = (0 ..< 65).map {
            EntryModelFixtures.makeFileEntry(id: "/tmp/entry-\($0).txt", name: "entry-\($0).txt")
        }
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.coreBatch(items: Array(entries.prefix(32)), batchIndex: 0))
                    continuation.yield(.coreBatch(items: Array(entries[32 ..< 64]), batchIndex: 1))
                    continuation.yield(.coreBatch(items: [entries[64]], batchIndex: 2))
                    continuation.yield(.coreFinished(batchCount: 3))
                    continuation.finish()
                }
            }
        }

        await store.send(.loading(.loadItems(path: "/tmp", showHidden: false))) {
            $0.isLoading = true
            $0.loadingContext.generation = 1
            $0.loadingContext.sourceKind = .directory
        }
        await store.receive(\.loading.streamEvent, .init(
            generation: 1,
            event: .coreBatch(items: Array(entries.prefix(32)), batchIndex: 0),
        )) {
            $0.items = IdentifiedArray(uniqueElements: entries.prefix(32))
            $0.isLoading = false
            $0.loadingContext.expectedCoreBatchIndex = 1
        }
        await store.receive(\.loading.streamEvent, .init(
            generation: 1,
            event: .coreBatch(items: Array(entries[32 ..< 64]), batchIndex: 1),
        )) {
            $0.items = IdentifiedArray(uniqueElements: entries.prefix(64))
            $0.loadingContext.expectedCoreBatchIndex = 2
        }
        await store.receive(\.loading.streamEvent, .init(
            generation: 1,
            event: .coreBatch(items: [entries[64]], batchIndex: 2),
        )) {
            $0.items = IdentifiedArray(uniqueElements: entries)
            $0.loadingContext.expectedCoreBatchIndex = 3
        }
        await store.receive(\.loading.streamEvent, .init(generation: 1, event: .coreFinished(batchCount: 3))) {
            $0.loadingContext.coreFinished = true
        }
        await store.receive(\.loading.streamFinished, 1) {
            $0.loadingContext.streamTerminal = true
        }
    }

    /// EOP-003-load_entry_items: stale 또는 잘못된 root stream event는 현재 항목을 변경하지 않는다.
    /// 새 navigation이 이전 request를 대체한 뒤 늦은 batch, 순서가 틀린 batch, 종료 후 batch가 도착할 수 있다.
    /// - 검증 내용: generation, batch index, core completion, terminal guard가 허용되지 않은 event를 모두 무시한다.
    /// - 사전 조건: generation 3의 directory request가 batch 0을 아직 기다리고 있다.
    /// - 기대 결과: 유효한 batch 0만 항목과 expected index를 갱신하고 나머지는 state를 변경하지 않는다.
    func testRootStreamIgnoresStaleMalformedAndPostFinishedEvents() async {
        let entry = EntryModelFixtures.makeFileEntry(id: "/tmp/current.txt", name: "current.txt")
        var state = EntryOperationsState()
        state.isLoading = true
        state.loadingContext.generation = 3
        state.loadingContext.sourceKind = .directory
        let store = EntryOperationsTestSupport.makeStore(initialState: state)

        await store.send(.loading(.streamEvent(.init(
            generation: 2,
            event: .coreBatch(items: [entry], batchIndex: 0),
        ))))
        await store.send(.loading(.streamEvent(.init(
            generation: 3,
            event: .coreBatch(items: [entry], batchIndex: 1),
        ))))
        await store.send(.loading(.streamEvent(.init(
            generation: 3,
            event: .coreBatch(items: [entry], batchIndex: 0),
        )))) {
            $0.items = [entry]
            $0.isLoading = false
            $0.loadingContext.expectedCoreBatchIndex = 1
        }
        await store.send(.loading(.streamEvent(.init(generation: 3, event: .coreFinished(batchCount: 1))))) {
            $0.loadingContext.coreFinished = true
        }
        await store.send(.loading(.streamFinished(generation: 3))) {
            $0.loadingContext.streamTerminal = true
        }
        await store.send(.loading(.streamEvent(.init(
            generation: 3,
            event: .coreBatch(items: [entry], batchIndex: 1),
        ))))
    }

    /// EOP-003-load_entry_items: route clear는 root load generation과 transient snapshot을 함께 무효화한다.
    /// Home·AI Chat 전환 뒤 이미 enqueue된 이전 stream event가 빈 목록을 다시 채우지 않는지 검증한다.
    /// - 검증 내용: cancelAndClearItems의 generation 증가와 stale batch 차단
    /// - 사전 조건: generation 4의 directory load가 항목 하나를 표시하며 진행 중임
    /// - 기대 결과: generation 5의 빈 idle context로 전환하고 generation 4 event를 무시함
    func testCancelAndClearItemsInvalidatesRootStreamGeneration() async {
        let currentEntry = EntryModelFixtures.makeFileEntry(id: "/tmp/current.txt", name: "current.txt")
        let staleEntry = EntryModelFixtures.makeFileEntry(id: "/tmp/stale.txt", name: "stale.txt")
        var state = EntryOperationsState()
        state.items = [currentEntry]
        state.isLoading = true
        state.isReloading = true
        state.loadingContext.generation = 4
        state.loadingContext.sourceKind = .directory
        let store = EntryOperationsTestSupport.makeStore(initialState: state)

        await store.send(.loading(.cancelAndClearItems)) {
            $0.items = []
            $0.isLoading = false
            $0.isReloading = false
            $0.loadingContext.generation = 5
            $0.loadingContext.sourceKind = nil
        }
        await store.send(.loading(.streamEvent(.init(
            generation: 4,
            event: .coreBatch(items: [staleEntry], batchIndex: 0),
        ))))
    }

    /// EOP-003-load_entry_items: empty core completion은 blocking loading을 해제한다.
    /// 빈 Recents 또는 Tags 결과도 stream terminal을 기다리지 않고 입력 가능한 상태가 되어야 한다.
    /// - 검증 내용: `.coreFinished(batchCount: 0)`가 isLoading과 isReloading을 해제하고 core completion을 기록한다.
    /// - 사전 조건: generation 4의 Recents request가 loading 중이며 이전 snapshot은 없다.
    /// - 기대 결과: 항목은 비어 있고 loading은 false이며 후속 stream terminal은 정상 수용된다.
    func testEmptyCoreFinishReleasesBlockingLoading() async {
        var state = EntryOperationsState()
        state.isLoading = true
        state.isReloading = true
        state.loadingContext.generation = 4
        state.loadingContext.sourceKind = .recents
        let store = EntryOperationsTestSupport.makeStore(initialState: state)

        await store.send(.loading(.streamEvent(.init(generation: 4, event: .coreFinished(batchCount: 0))))) {
            $0.isLoading = false
            $0.isReloading = false
            $0.loadingContext.coreFinished = true
        }
        await store.send(.loading(.streamFinished(generation: 4))) {
            $0.loadingContext.streamTerminal = true
        }
    }

    /// EOP-003-load_entry_items: 첫 batch 뒤 stream failure는 부분 rows를 유지한다.
    /// source acquisition이 enrichment 전에 실패해도 이미 보여 준 항목을 빈 목록으로 바꾸면 안 된다.
    /// - 검증 내용: post-first failure가 incomplete/terminal을 기록하고 rows와 nonblocking presentation을 보존한다.
    /// - 사전 조건: generation 5의 Tags request가 하나의 accepted core batch를 이미 수신했다.
    /// - 기대 결과: existing ID는 유지되고 isLoading은 false, isIncomplete과 streamTerminal은 true가 된다.
    func testPostFirstBatchFailureRetainsPartialRowsAndMarksIncomplete() async {
        let entry = EntryModelFixtures.makeFileEntry(id: "/tmp/partial.txt", name: "partial.txt")
        var state = EntryOperationsState()
        state.isLoading = false
        state.loadingContext.generation = 5
        state.loadingContext.expectedCoreBatchIndex = 1
        state.loadingContext.sourceKind = .tags
        state.items = [entry]
        let store = EntryOperationsTestSupport.makeStore(initialState: state)

        await store.send(.loading(.streamFailed(generation: 5))) {
            $0.loadingContext.streamTerminal = true
            $0.loadingContext.isIncomplete = true
        }
        XCTAssertEqual(store.state.items, [entry])
    }

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

    // MARK: - EOP-003-load_folder_items

    /// EOP-003-load_folder_items: folder stream은 Feature가 request identity와 staged 순서를 검증한 뒤 delegate로 전달한다.
    /// 중첩 directory 로드가 Widget의 client effect가 아니라 EntryOperations의 취소 가능한 수명주기에서 처리되는지 검증한다.
    /// - 검증 내용: request별 context가 core order를 기록하고 stale request 및 core 이전 metadata를 거부한다.
    /// - 사전 조건: root generation 4, folder generation 2의 `/tmp/folder` request와 하나의 core entry가 있다.
    /// - 기대 결과: 유효한 core event만 expected index를 전진시키며 stale/early metadata는 context를 변경하지 않는다.
    func testFolderLoadLifecycleRejectsStaleAndEarlyMetadata() {
        let request = EntryFolderLoadRequest(
            rootContextGeneration: 4,
            folderID: "/tmp/folder",
            folderGeneration: 2,
            path: "/tmp/folder",
            showHidden: false,
            priority: .active([]),
        )
        let staleRequest = EntryFolderLoadRequest(
            rootContextGeneration: 4,
            folderID: "/tmp/folder",
            folderGeneration: 1,
            path: "/tmp/folder",
            showHidden: false,
            priority: .active([]),
        )
        let entry = EntryModelFixtures.makeFileEntry(id: "/tmp/folder/a.txt", name: "a.txt")
        var state = EntryOperationsState()
        let reducer = EntryOperationsFolderLoadingReducer()

        _ = reducer.reduce(into: &state, action: .loading(.loadFolderItems(request)))
        XCTAssertEqual(state.folderLoadingContexts[request.id]?.request, request)

        _ = reducer.reduce(into: &state, action: .loading(.folderStreamEvent(
            request: staleRequest,
            event: .coreBatch(items: [entry], batchIndex: 0),
        )))
        _ = reducer.reduce(into: &state, action: .loading(.folderStreamEvent(
            request: request,
            event: .metadataPatches([]),
        )))
        XCTAssertEqual(state.folderLoadingContexts[request.id]?.expectedCoreBatchIndex, 0)

        _ = reducer.reduce(into: &state, action: .loading(.folderStreamEvent(
            request: request,
            event: .coreBatch(items: [entry], batchIndex: 0),
        )))
        XCTAssertEqual(state.folderLoadingContexts[request.id]?.expectedCoreBatchIndex, 1)
    }

    /// EOP-003-load_folder_items: staged folder stream의 Cocoa permission error는 typed permission-denied delegate로 전달된다.
    /// filesystem failure가 localized string으로 축소되지 않고 hierarchy presentation이 구별 가능한 failure를 받는지 검증한다.
    /// - 검증 내용: throwing stream이 `.folderStreamFailed(..., .permissionDenied)`와 matching delegate를 순서대로 방출한다.
    /// - 사전 조건: EntryLoadingClient의 staged folder stream이 `NSFileReadNoPermissionError`로 즉시 종료된다.
    /// - 기대 결과: request context는 terminal이 되고 delegate failure는 `.permissionDenied`다.
    func testFolderLoadPermissionDeniedStreamEmitsTypedFailureDelegate() async {
        let request = EntryFolderLoadRequest(
            rootContextGeneration: 4,
            folderID: "/tmp/protected",
            folderGeneration: 2,
            path: "/tmp/protected",
            showHidden: false,
            priority: .active([]),
        )
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: NSError(
                        domain: NSCocoaErrorDomain,
                        code: NSFileReadNoPermissionError,
                    ))
                }
            }
        }

        await store.send(.loading(.loadFolderItems(request))) {
            $0.folderLoadingContexts[request.id] = .init(request: request)
        }
        await store.receive { action in
            guard case let .loading(.folderStreamFailed(receivedRequest, failure)) = action else { return false }
            return receivedRequest == request && failure == .permissionDenied
        } assert: {
            $0.folderLoadingContexts[request.id]?.terminal = true
        }
        await store.receive { action in
            guard case let .delegate(.folderLoadFailed(receivedRequest, failure)) = action else { return false }
            return receivedRequest == request && failure == .permissionDenied
        }
        await store.finish()
    }

    /// EOP-003-load_folder_items: 동일 window의 다른 tab folder stream은 서로 취소하지 않는다.
    /// 같은 request identity를 사용하는 두 content tab이 각각 독립된 cancellation owner를 유지하는지 검증한다.
    /// - 검증 내용: 두 번째 folder load 시작 후 첫 번째 stream의 cancellation recorder 상태
    /// - 사전 조건: 같은 windowID와 request, 서로 다른 loadingCancellationOwnerID를 가진 두 Store
    /// - 기대 결과: 두 번째 load가 시작되어도 첫 번째 stream은 취소되지 않음
    func testFolderLoadsWithDifferentOwnersDoNotCancelEachOther() async throws {
        let windowID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let request = EntryFolderLoadRequest(
            rootContextGeneration: 1,
            folderID: "/tmp/shared-folder",
            folderGeneration: 1,
            path: "/tmp/shared-folder",
            showHidden: false,
            priority: .none,
        )
        var firstState = try EntryOperationsState(
            loadingCancellationOwnerID: XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
        )
        firstState.windowID = windowID
        var secondState = try EntryOperationsState(
            loadingCancellationOwnerID: XCTUnwrap(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")),
        )
        secondState.windowID = windowID
        let streamFactory = FolderStreamFactory()
        let store = TestStore(initialState: FolderLoadOwnerHarness.State(
            first: firstState,
            second: secondState,
        )) {
            FolderLoadOwnerHarness()
        } withDependencies: {
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                streamFactory.makeStream()
            }
        }
        // store.exhaustivity = .off: stream 완료 액션은 정리 경로이며 cancellation 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.first(.loading(.loadFolderItems(request)))) {
            $0.first.folderLoadingContexts[request.id] = .init(request: request)
        }
        await streamFactory.firstGate.waitUntilWaiting()
        await store.send(.second(.loading(.loadFolderItems(request)))) {
            $0.second.folderLoadingContexts[request.id] = .init(request: request)
        }
        await streamFactory.secondGate.waitUntilWaiting()

        XCTAssertFalse(streamFactory.firstCancellation.wasCancelled)

        await streamFactory.firstGate.resume(with: .entries([]))
        await streamFactory.secondGate.resume(with: .entries([]))
        await store.finish()
    }

    /// EOP-003-load_folder_items: owner teardown은 실행 중인 모든 folder stream을 취소한다.
    /// 상위 tab lifecycle이 owner-scoped action 하나로 request context와 filesystem I/O를 함께 정리하는지 검증한다.
    /// - 검증 내용: cancelAllFolderItems 이후 context 제거와 stream cancellation
    /// - 사전 조건: 하나의 folder stream이 suspension gate에서 대기 중임
    /// - 기대 결과: 모든 context가 제거되고 해당 stream이 취소됨
    func testCancelAllFolderItemsCancelsOwnerStreams() async {
        let request = EntryFolderLoadRequest(
            rootContextGeneration: 1,
            folderID: "/tmp/folder",
            folderGeneration: 1,
            path: "/tmp/folder",
            showHidden: false,
            priority: .none,
        )
        let streamFactory = FolderStreamFactory()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in streamFactory.makeStream() }
        }

        await store.send(.loading(.loadFolderItems(request))) {
            $0.folderLoadingContexts[request.id] = .init(request: request)
        }
        await streamFactory.firstGate.waitUntilWaiting()
        await store.send(.loading(.cancelAllFolderItems)) {
            $0.folderLoadingContexts = [:]
        }
        await store.finish()

        XCTAssertTrue(streamFactory.firstCancellation.wasCancelled)
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
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                failingOrEmptyStagedStream(gate: gate)
            }
        }
        await store.send(.loading(.loadItems(path: "/tmp", showHidden: false))) {
            $0.isLoading = true
            $0.loadingContext.generation = 1
            $0.loadingContext.sourceKind = .directory
        }
        await gate.waitUntilWaiting()
        await gate.resume(with: .failure)
        await store.receive(\.loading.streamFailed, 1) {
            $0.items = []
            $0.isLoading = false
            $0.isReloading = false
            $0.renamingItemId = nil
            $0.renamingText = ""
            $0.renamingItem = nil
            $0.loadingContext.streamTerminal = true
            $0.loadingContext.isIncomplete = true
        }
        await store.send(.loading(.loadItems(path: "/tmp", showHidden: false))) {
            $0.isLoading = true
            $0.loadingContext.generation = 2
            $0.loadingContext.expectedCoreBatchIndex = 0
            $0.loadingContext.coreFinished = false
            $0.loadingContext.streamTerminal = false
            $0.loadingContext.isIncomplete = false
            $0.loadingContext.sourceKind = .directory
        }
        await gate.waitUntilWaiting()
        await gate.resume(with: .entries([]))
        await store.receive(\.loading.streamEvent, .init(generation: 2, event: .coreFinished(batchCount: 0))) {
            $0.isLoading = false
            $0.loadingContext.coreFinished = true
        }
        await store.receive(\.loading.streamFinished, 2) {
            $0.loadingContext.streamTerminal = true
        }
    }
}

private func failingOrEmptyStagedStream(
    gate: EntryLoadSuspensionGate,
) -> AsyncThrowingStream<EntryLoadEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                let entries = try await gate.wait()
                continuation.yield(.coreFinished(batchCount: entries.isEmpty ? 0 : 1))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

@Reducer
private struct FolderLoadOwnerHarness {
    @ObservableState
    struct State: Equatable {
        var first: EntryOperationsState
        var second: EntryOperationsState
    }

    enum Action {
        case first(EntryOperationsAction)
        case second(EntryOperationsAction)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.first, action: \.first) {
            EntryOperationsFolderLoadingReducer()
        }
        Scope(state: \.second, action: \.second) {
            EntryOperationsFolderLoadingReducer()
        }
    }
}

private final class FolderStreamCancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var wasCancelled: Bool {
        lock.withLock { cancelled }
    }

    func recordCancellation() {
        lock.withLock { cancelled = true }
    }
}

private final class FolderStreamFactory: @unchecked Sendable {
    let firstGate = EntryLoadSuspensionGate()
    let secondGate = EntryLoadSuspensionGate()
    let firstCancellation = FolderStreamCancellationRecorder()

    private let lock = NSLock()
    private var invocationCount = 0

    func makeStream() -> AsyncThrowingStream<EntryLoadEvent, Error> {
        let invocation = lock.withLock {
            invocationCount += 1
            return invocationCount
        }
        if invocation == 1 {
            return suspendedFolderStream(gate: firstGate, cancellationRecorder: firstCancellation)
        }
        return suspendedFolderStream(gate: secondGate)
    }
}

private func suspendedFolderStream(
    gate: EntryLoadSuspensionGate,
    cancellationRecorder: FolderStreamCancellationRecorder? = nil,
) -> AsyncThrowingStream<EntryLoadEvent, Error> {
    AsyncThrowingStream { continuation in
        continuation.onTermination = { termination in
            guard case .cancelled = termination else { return }
            cancellationRecorder?.recordCancellation()
        }
        Task {
            do {
                let entries = try await gate.wait()
                if !entries.isEmpty {
                    continuation.yield(.coreBatch(items: entries, batchIndex: 0))
                }
                continuation.yield(.coreFinished(batchCount: entries.isEmpty ? 0 : 1))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
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

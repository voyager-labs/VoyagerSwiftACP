import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import XCTest

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
        initialState.windowID = UUID()
        initialState.undoRecords = [existingUndo]
        initialState.redoRecords = [existingRedo]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState)

        await store.send(.lifecycle(.entryActionCompleted(newRecord))) {
            $0.undoRecords = [existingUndo, newRecord]
            $0.redoRecords = []
        }
        await store.receive { action in
            guard case let .outcome(.undoManagerAvailabilityChanged(availability)) = action else { return false }
            return availability == .init()
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
        await store.receive { action in
            guard case let .outcome(.entryActionReplayFinished(.undo, terminal)) = action else { return false }
            return terminal == .failure(reason: .ownerRecordMismatch, appliedTargets: [])
        }
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

        let spy = UndoManagerSpy()
        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.undoManagerClient = spy.client
        }

        await store.send(.undoRedo(.requestRedo))
        await store.finish()

        // AC: EOP-003-redo_entry_action Edge Case #8 — busy guard가 redo를 차단한다
        XCTAssertEqual(store.state.redoRecords.count, 1)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertEqual(spy.redoCalls.count, 0)
    }

    // AC: EOP-003-redo_entry_action Edge Case #9
    /// EOP-003-redo_entry_action: requestRedo가 UndoManagerClient.redo를 호출한다
    /// `requestRedo`가 들어오면 reducer가 `undoManagerClient.redo(windowID)`를 호출하는지 검증한다.
    /// - 검증 내용: `requestRedo` 전송 시 spy.redoCalls가 1 이상 증가한다.
    /// - 사전 조건: redoRecords에 record가 있고, target path가 busy가 아니다.
    /// - 기대 결과: UndoManagerClient.redo가 호출된다.
    func testRedo_undoManagerResolved_callsRedo() async {
        let sourcePath = "/a/old.txt"
        let destPath = "/a/new.txt"
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: sourcePath, afterPath: destPath)],
        )

        var initialState = EntryOperationsState()
        initialState.redoRecords = [record]

        let spy = UndoManagerSpy()
        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.undoManagerClient = spy.client
        }

        store.exhaustivity = .off

        // requestRedo는 .run 이펙트로 undoManagerClient.redo만 호출하고 store로 action을 돌려보내지 않는다.
        await store.send(.undoRedo(.requestRedo))
        await store.finish()

        // AC: EOP-003-redo_entry_action Edge Case #9 — UndoManagerClient.redo가 호출되었다
        XCTAssertGreaterThanOrEqual(spy.redoCalls.count, 1)
    }

    // AC: EOP-003-redo_entry_action Edge Case #9
    /// EOP-003-redo_entry_action: UndoManager가 콜백을 실행하지 않으면 상태가 유지된다
    /// `requestRedo` 전송 후 UndoManagerClient.redo가 onRedo 콜백을 실행하지 않으면
    /// (해결되지 않은 UndoManager) redoRecords와 undoRecords가 그대로 유지된다.
    /// - 검증 내용: spy가 redo 호출만 기록하고 onRedo 콜백을 실행하지 않으면 상태 불변.
    /// - 사전 조건: redoRecords에 record가 있고, spy.client를 주입한다.
    /// - 기대 결과: redoRecords가 유지되고 undoRecords는 비어있다.
    func testRedo_undoManagerUnresolved_ignoresRedo() async {
        let sourcePath = "/a/old.txt"
        let destPath = "/a/new.txt"
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: sourcePath, afterPath: destPath)],
        )

        var initialState = EntryOperationsState()
        initialState.redoRecords = [record]

        let spy = UndoManagerSpy()
        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.undoManagerClient = spy.client
        }

        store.exhaustivity = .off

        // requestRedo는 .run 이펙트로 undoManagerClient.redo만 호출하고 store로 action을 돌려보내지 않는다.
        await store.send(.undoRedo(.requestRedo))
        await store.finish()

        // AC: EOP-003-redo_entry_action Edge Case #9 — UndoManager 미해결 시 상태 유지
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
        await store.receive { action in
            guard case let .outcome(.entryActionReplayFinished(.redo, terminal)) = action else { return false }
            return terminal == .failure(reason: .ownerRecordMismatch, appliedTargets: [])
        }
        await store.finish()

        // AC: EOP-003-redo_entry_action Edge Case #10 — ID 불일치로 redo 무시
        XCTAssertEqual(store.state.redoRecords.count, 1)
        XCTAssertEqual(store.state.redoRecords.first?.id, correctRecord.id)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
    }

    // AC: EOP-003-undo_entry_action Edge Case #9

    /// EOP-003-undo_entry_action: UndoManager가 resolve되면 registerUndo 핸들러가 등록된다
    /// `entryActionCompleted`가 isUndoable 작업으로 들어오면 `undoManagerClient.registerUndo`를 호출한다.
    /// - 검증 내용: `entryActionCompleted` 이후 spy에 registerUndo 호출이 기록되고, record가 일치한다.
    /// - 사전 조건: UndoManagerSpy를 주입하고 undoRecords가 비어있다.
    /// - 기대 결과: spy.registerUndoCalls에 1개의 호출이 기록되며, record가 전송한 것과 일치한다.
    func testUndo_undoManagerResolved_registersUndoHandler() async throws {
        let spy = UndoManagerSpy()
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/a/old.txt", afterPath: "/a/new.txt")],
        )

        let windowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000568"))
        let ownerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000567"))
        var initialState = EntryOperationsState(undoOwnerID: ownerID)
        initialState.windowID = windowID
        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.undoManagerClient = spy.client
        }

        await store.send(.lifecycle(.entryActionCompleted(record))) {
            $0.undoRecords = [record]
            $0.redoRecords = []
        }
        await store.receive { action in
            guard case let .outcome(.undoManagerAvailabilityChanged(availability)) = action else { return false }
            return availability == .init()
        }

        await store.finish()

        // AC: EOP-003-undo_entry_action Edge Case #9 — registerUndo 핸들러가 등록되었다
        XCTAssertEqual(spy.registerUndoCalls.count, 1)
        XCTAssertEqual(spy.registerUndoCalls.first?.windowID, windowID)
        XCTAssertEqual(spy.registerUndoCalls.first?.ownerID, ownerID)
        XCTAssertEqual(spy.registeredRecords.first, record)
    }

    /// EOP-003-undo_entry_action: UndoManager가 resolve되지 않으면 undo 요청이 무시된다
    /// `requestUndo`가 `undoManagerClient.undo`를 호출하지만 spy가 onUndo 핸들러를 실행하지 않으면
    /// (실제 UndoManager가 resolve되지 않은 상황), 상태가 그대로 유지된다.
    /// - 검증 내용: `requestUndo` 이후 spy.undoCalls에 기록은 남지만, state의 undoRecords/redoRecords는 변하지 않는다.
    /// - 사전 조건: undoRecords에 record가 있고 UndoManagerSpy를 주입한다.
    /// - 기대 결과: spy.undoCalls에 1개의 호출이 기록되며, undoRecords와 redoRecords는 그대로 유지된다.
    func testUndo_undoManagerUnresolved_ignoresUndo() async {
        let spy = UndoManagerSpy()
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/a/old.txt", afterPath: "/a/new.txt")],
        )

        var initialState = EntryOperationsState()
        initialState.undoRecords = [record]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.undoManagerClient = spy.client
        }

        await store.send(.undoRedo(.requestUndo))
        await store.finish()

        // AC: EOP-003-undo_entry_action Edge Case #9 — UndoManager 미해결 시 상태 유지
        XCTAssertEqual(spy.undoCalls.count, 1)
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertEqual(store.state.undoRecords.first?.id, record.id)
        XCTAssertTrue(store.state.redoRecords.isEmpty)
    }

    /// EOP-003-undo_entry_action: 공유 UndoManager가 owner와 무관하게 전역 등록 역순으로 callback을 실행함
    /// - 검증 내용: content와 Sidebar owner를 교차 등록해도 마지막 등록 owner부터 undo됨
    /// - 사전 조건: 같은 windowID와 같은 live UndoManagerClient를 두 논리 owner가 공유함
    /// - 기대 결과: Sidebar callback 후 content callback 순서이며 availability도 단일 manager 상태를 반영함
    func testUndoManager_sharedOwnersFollowGlobalRegistrationOrder() async throws {
        let undoManager = UndoManager()
        let client = UndoManagerClient.live(undoManager: undoManager)
        let windowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000569"))
        let contentOwnerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let sidebarOwnerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let contentRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/content/old", afterPath: "/content/new")],
        )
        let sidebarRecord = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: "/sidebar/source", afterPath: "/sidebar/destination")],
        )
        let events = client.events(windowID)
        let receivedEvents = Task {
            var iterator = events.makeAsyncIterator()
            return await [iterator.next(), iterator.next()].compactMap(\.self)
        }

        await client.registerUndo(windowID, contentOwnerID, contentRecord)
        await client.registerUndo(windowID, sidebarOwnerID, sidebarRecord)

        let registeredAvailability = await client.availability(windowID)
        XCTAssertEqual(registeredAvailability, .init(canUndo: true, canRedo: false))
        _ = await client.undo(windowID)
        _ = await client.undo(windowID)

        let values = await receivedEvents.value
        XCTAssertEqual(values.map(\.ownerID), [sidebarOwnerID, contentOwnerID])
        XCTAssertEqual(values.map(\.record), [sidebarRecord, contentRecord])
        XCTAssertEqual(values.map(\.direction), [.undo, .undo])
        let fullyUndoneAvailability = await client.availability(windowID)
        XCTAssertEqual(fullyUndoneAvailability, .init(canUndo: false, canRedo: true))
    }

    /// EOP-003-redo_entry_action: 새 owner 등록이 반대 owner의 stale global redo를 양방향으로 제거함
    /// - 검증 내용: content undo 뒤 Sidebar 등록, Sidebar undo 뒤 content 등록 모두 canRedo=false
    /// - 사전 조건: 같은 live UndoManagerClient에서 undo로 redo availability를 만든 상태
    /// - 기대 결과: 어느 owner가 새 등록을 만들든 NSUndoManager의 redo stack이 제거됨
    func testUndoManager_crossOwnerRegistrationClearsGlobalRedoInBothDirections() async throws {
        let undoManager = UndoManager()
        let client = UndoManagerClient.live(undoManager: undoManager)
        let windowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000570"))
        let contentOwnerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let sidebarOwnerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        let contentRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/content/old", afterPath: "/content/new")],
        )
        let sidebarRecord = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: "/sidebar/source", afterPath: "/sidebar/destination")],
        )

        await client.registerUndo(windowID, contentOwnerID, contentRecord)
        _ = await client.undo(windowID)
        let contentRedoAvailability = await client.availability(windowID)
        XCTAssertTrue(contentRedoAvailability.canRedo)
        await client.registerUndo(windowID, sidebarOwnerID, sidebarRecord)
        let afterSidebarRegistration = await client.availability(windowID)
        XCTAssertFalse(afterSidebarRegistration.canRedo)

        undoManager.removeAllActions()
        await client.registerUndo(windowID, sidebarOwnerID, sidebarRecord)
        _ = await client.undo(windowID)
        let sidebarRedoAvailability = await client.availability(windowID)
        XCTAssertTrue(sidebarRedoAvailability.canRedo)
        await client.registerUndo(windowID, contentOwnerID, contentRecord)
        let afterContentRegistration = await client.availability(windowID)
        XCTAssertFalse(afterContentRegistration.canRedo)
    }

    /// EOP-003-undo_entry_action: owner invalidation은 해당 owner action만 제거함
    func testUndoManager_ownerInvalidationRemovesOnlyMatchingActions() async {
        let undoManager = UndoManager()
        let client = UndoManagerClient.live(undoManager: undoManager)
        let windowID = UUID()
        let contentOwnerID = UUID()
        let sidebarOwnerID = UUID()
        let contentRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/content/old", afterPath: "/content/new")],
        )
        let sidebarRecord = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: "/sidebar/source", afterPath: "/sidebar/destination")],
        )
        let events = client.events(windowID)
        let receivedEvent = Task {
            var iterator = events.makeAsyncIterator()
            return await iterator.next()
        }

        await client.registerUndo(windowID, contentOwnerID, contentRecord)
        await client.registerUndo(windowID, sidebarOwnerID, sidebarRecord)
        _ = await client.invalidateOwner(windowID, sidebarOwnerID)
        _ = await client.undo(windowID)

        let event = await receivedEvent.value
        XCTAssertEqual(event?.ownerID, contentOwnerID)
        XCTAssertEqual(event?.record, contentRecord)
        let availability = await client.availability(windowID)
        XCTAssertFalse(availability.canUndo)
    }

    /// EOP-003-undo_entry_action: window invalidation은 stream을 종료하고 action을 제거함
    func testUndoManager_windowInvalidationFinishesStreamAndRemovesActions() async {
        let undoManager = UndoManager()
        let client = UndoManagerClient.live(undoManager: undoManager)
        let windowID = UUID()
        let ownerID = UUID()
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/content/old", afterPath: "/content/new")],
        )
        let events = client.events(windowID)
        let streamCompletion = Task {
            var iterator = events.makeAsyncIterator()
            return await iterator.next()
        }

        await client.registerUndo(windowID, ownerID, record)
        _ = await client.invalidateWindow(windowID)

        let nextEvent = await streamCompletion.value
        let availability = await client.availability(windowID)
        XCTAssertNil(nextEvent)
        XCTAssertEqual(availability, .init())
    }

    /// EOP-003-undo_entry_action: target가 비어 replay가 실패하면 stack 이동 없이 양쪽 history를 폐기한다.
    /// - 검증 내용: undo callback 직후 source stack이 유지되고 replayFailed commit에서 undo/redo stack이 함께 비워진다.
    /// - 사전 조건: 빈 target undo record와 기존 redo record
    /// - 기대 결과: operationFailed terminal의 appliedTargets는 빈 배열이고 두 stack은 비어 있다.
    func testUndoReplay_emptyTargetsClearsBothStacksWithoutPrecommit() async {
        let record = EntryActionRecord(operationKind: .rename, targets: [])
        let staleRedo = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/stale/before", afterPath: "/stale/after")],
        )
        var state = EntryOperationsState()
        state.undoRecords = [record]
        state.redoRecords = [staleRedo]
        let store = EntryOperationsTestSupport.makeStore(initialState: state)
        // store.exhaustivity = .off: replay 내부 lifecycle action을 건너뛰고 stack commit/terminal 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.undoRedo(.undoEntryAction(record)))
        XCTAssertEqual(store.state.undoRecords, [record])
        XCTAssertEqual(store.state.redoRecords, [staleRedo])
        await store.receive { action in
            guard case .undoRedo(.replayFailed(direction: .undo, appliedTargets: [])) = action else { return false }
            return true
        } assert: {
            $0.undoRecords = []
            $0.redoRecords = []
        }
        await store.receive { action in
            guard case let .outcome(.entryActionReplayFinished(direction: .undo, terminal: terminal)) = action else {
                return false
            }
            return terminal == .failure(reason: .operationFailed, appliedTargets: [])
        }
        await store.finish()
    }

    /// EOP-003-undo_entry_action: 두 번째 target 실패 시 적용 prefix만 보고하고 local history는 모두 폐기한다.
    /// - 검증 내용: 첫 target 성공/두 번째 target 실패 후 pre-commit 없이 replayFailed가 양 stack을 clear한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 독립 sandbox 두 개와 두 target setTags record
    /// - 기대 결과: appliedTargets는 첫 target 하나이며 undo/redo stack은 모두 빈 배열이다.
    func testUndoReplay_partialFailureReportsAppliedPrefixAndClearsBothStacks() async throws {
        let firstSandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        let secondSandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer {
            firstSandbox.cleanup()
            secondSandbox.cleanup()
        }
        let firstTarget = EntryActionRecord.Target(
            beforePath: firstSandbox.fileURL.path,
            afterPath: firstSandbox.fileURL.path,
            beforeTags: ["before"],
            afterTags: ["after"],
        )
        let secondTarget = EntryActionRecord.Target(
            beforePath: secondSandbox.fileURL.path,
            afterPath: secondSandbox.fileURL.path,
            beforeTags: ["before"],
            afterTags: ["after"],
        )
        let record = EntryActionRecord(operationKind: .setTags, targets: [firstTarget, secondTarget])
        let staleRedo = EntryActionRecord(operationKind: .createFolder, targets: [])
        let callCount = LockIsolated(0)
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.setTags = { _, _ in
            let invocation = callCount.withValue { value in
                value += 1
                return value
            }
            if invocation == 2 {
                throw FileOpError.system(message: "second target failed")
            }
        }
        var state = EntryOperationsState()
        state.undoRecords = [record]
        state.redoRecords = [staleRedo]
        let store = EntryOperationsTestSupport.makeStore(initialState: state) {
            $0.entryFileOpsClient = fileOps
        }
        // store.exhaustivity = .off: per-target lifecycle action 대신 partial terminal과 stack 원자성에 집중한다.
        store.exhaustivity = .off

        await store.send(.undoRedo(.undoEntryAction(record)))
        XCTAssertEqual(store.state.undoRecords, [record])
        XCTAssertEqual(store.state.redoRecords, [staleRedo])
        await store.receive { action in
            guard case let .undoRedo(.replayFailed(direction: .undo, appliedTargets: targets)) = action else {
                return false
            }
            return targets == [firstTarget]
        } assert: {
            $0.undoRecords = []
            $0.redoRecords = []
        }
        await store.receive { action in
            guard case let .outcome(.entryActionReplayFinished(direction: .undo, terminal: terminal)) = action else {
                return false
            }
            return terminal == .failure(reason: .operationFailed, appliedTargets: [firstTarget])
        }
        XCTAssertEqual(callCount.value, 2)
        await store.finish()
    }

    /// EOP-003-redo_entry_action: 동적 Trash destination은 replay refresh와 committed record에 반영된다.
    /// - 검증 내용: moveToTrash client가 반환한 실제 경로를 pathsMutated와 replaySucceeded target이 공유한다.
    /// - 사전 조건: record의 stale Trash 경로와 서로 다른 deterministic client 반환 경로
    /// - 기대 결과: stale 경로가 아닌 실제 반환 경로만 refresh 및 redo→undo commit에 사용됨
    func testRedoReplay_moveToTrashRefreshesUpdatedDestination() async {
        let originalPath = "/source/item.txt"
        let staleTrashPath = "/trash/stale-item.txt"
        let actualTrashPath = "/trash/actual-item.txt"
        let record = EntryActionRecord(
            operationKind: .moveToTrash,
            targets: [.init(beforePath: originalPath, afterPath: staleTrashPath)],
        )
        let updatedTarget = EntryActionRecord.Target(
            beforePath: originalPath,
            afterPath: actualTrashPath,
        )
        let updatedRecord = EntryActionRecord(
            operationKind: .moveToTrash,
            targets: [updatedTarget],
            id: record.id,
            timestamp: record.timestamp,
        )
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.moveToTrashAndReturnURL = { url in
            XCTAssertEqual(url.path, originalPath)
            return URL(fileURLWithPath: actualTrashPath)
        }
        var state = EntryOperationsState()
        state.redoRecords = [record]
        let store = EntryOperationsTestSupport.makeStore(initialState: state) {
            $0.entryFileOpsClient = fileOps
        }
        // store.exhaustivity = .off: lifecycle 중 updated path와 stack commit 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.undoRedo(.redoEntryAction(record)))
        await store.receive { action in
            guard case let .lifecycle(.pathsMutated(paths)) = action else { return false }
            return paths == [originalPath, actualTrashPath]
        }
        await store.receive { action in
            guard case let .undoRedo(.replaySucceeded(
                direction: .redo,
                sourceRecordID: sourceRecordID,
                updatedRecord: committedRecord,
            )) = action else {
                return false
            }
            return sourceRecordID == record.id && committedRecord == updatedRecord
        } assert: {
            $0.redoRecords = []
            $0.undoRecords = [updatedRecord]
        }
        await store.finish()
    }
}

private func makeFailingDeleteClient(error: FileOpError) -> EntryFileOpsClient {
    let live = EntryFileOpsClient.liveValue
    return EntryFileOpsClient(
        createFolder: { parentURL, folderName in try await live.createFolder(parentURL, folderName) },
        pasteFile: { sourceURL, destinationURL in try await live.pasteFile(sourceURL, destinationURL) },
        moveFile: { sourceURL, destinationURL in try await live.moveFile(sourceURL, destinationURL) },
        renameFile: { sourceURL, destinationURL in try await live.renameFile(sourceURL, destinationURL) },
        createAlias: { sourceURL, aliasURL in try await live.createAlias(sourceURL, aliasURL) },
        moveToTrashAndReturnURL: { url in try await live.moveToTrashAndReturnURL(url) },
        deleteImmediately: { _ in throw error },
        putBackFromTrash: { trashURL, originalPath in try await live.putBackFromTrash(trashURL, originalPath) },
        compressItems: { urls in try await live.compressItems(urls) },
        extractCompressedFile: { url in try await live.extractCompressedFile(url) },
        getTags: { url in try await live.getTags(url) },
        setTags: { url, tags in try await live.setTags(url, tags) },
        toggleTag: { url, tag in try await live.toggleTag(url, tag) },
        fileExists: { path in live.fileExists(path) },
        saveDragPaths: { _ in },
        loadDragPaths: { [] },
        saveDragWithOption: { _ in },
        loadDragWithOption: { false },
        clipboardChangeCount: { 0 },
        loadClipboardCutSessionId: { nil },
        saveClipboardCutSessionId: { _ in },
        loadClipboardPaths: { ([], .copy) },
        postFileSystemChanged: { _ in },
    )
}

private func makeFailingTrashClient(recorder: FileOpsRecorder) -> EntryFileOpsClient {
    let live = EntryFileOpsClient.liveValue
    return EntryFileOpsClient(
        createFolder: { parentURL, folderName in try await live.createFolder(parentURL, folderName) },
        pasteFile: { sourceURL, destinationURL in try await live.pasteFile(sourceURL, destinationURL) },
        moveFile: { sourceURL, destinationURL in try await live.moveFile(sourceURL, destinationURL) },
        renameFile: { sourceURL, destinationURL in try await live.renameFile(sourceURL, destinationURL) },
        createAlias: { sourceURL, aliasURL in try await live.createAlias(sourceURL, aliasURL) },
        moveToTrashAndReturnURL: { _ in
            throw FileOpError.system(message: "trash unavailable")
        },
        deleteImmediately: { url in
            try await live.deleteImmediately(url)
            recorder.recordDelete(path: url)
        },
        putBackFromTrash: { trashURL, originalPath in try await live.putBackFromTrash(trashURL, originalPath) },
        compressItems: { urls in try await live.compressItems(urls) },
        extractCompressedFile: { url in try await live.extractCompressedFile(url) },
        getTags: { url in try await live.getTags(url) },
        setTags: { url, tags in try await live.setTags(url, tags) },
        toggleTag: { url, tag in try await live.toggleTag(url, tag) },
        fileExists: { path in live.fileExists(path) },
        saveDragPaths: { _ in },
        loadDragPaths: { [] },
        saveDragWithOption: { _ in },
        loadDragWithOption: { false },
        clipboardChangeCount: { 0 },
        loadClipboardCutSessionId: { nil },
        saveClipboardCutSessionId: { _ in },
        loadClipboardPaths: { ([], .copy) },
        postFileSystemChanged: { _ in },
    )
}

private func prepareTrashRecord(sourceURL: URL, trashRoot: URL) throws -> EntryActionRecord {
    try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
    let trashURL = trashRoot.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: trashURL)
    return EntryActionRecord(
        operationKind: .moveToTrash,
        targets: [.init(beforePath: sourceURL.path, afterPath: trashURL.path)],
    )
}

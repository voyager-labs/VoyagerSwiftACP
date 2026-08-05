import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
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

    /// EOP-003-move_entries_to_trash: Sidebar provider batch는 전용 Trash mutation과 Put Back 계약을 보존함
    /// `fixtures/fixtures/texts/plain/11.txt` 두 복사본의 provider를 all-or-none 해석해 generic move/paste 없이 처리한다.
    /// - 검증 내용: provider 두 개 trash 이동, metadata 저장, Undo 등록, Put Back 원위치 복구
    /// - 사전 조건: fixture-backed sandbox 두 개, source별 fake Trash, Window/owner identity와 UndoManager spy
    /// - 기대 결과: moveToTrash만 두 번 호출되고 metadata/Undo가 생성되며 두 파일 모두 원래 위치로 복구됨
    func testHandleDropToTrash_successPreservesMetadataUndoAndPutBack() async throws {
        let firstSandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        let secondSandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer {
            firstSandbox.cleanup()
            secondSandbox.cleanup()
        }
        let sourceURLs = [firstSandbox.fileURL, secondSandbox.fileURL]
        let providers = sourceURLs.map {
            NSItemProvider(item: $0 as NSURL, typeIdentifier: UTType.fileURL.identifier)
        }
        let trashCalls = LockIsolated<[URL]>([])
        let genericCalls = LockIsolated(0)
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.pasteFile = { _, _ in
            genericCalls.withValue { $0 += 1 }
            throw FileOpError.system(message: "generic paste must not run")
        }
        fileOps.moveFile = { _, _ in
            genericCalls.withValue { $0 += 1 }
            throw FileOpError.system(message: "generic move must not run")
        }
        fileOps.moveToTrashAndReturnURL = { sourceURL in
            let trashRoot = sourceURL.deletingLastPathComponent().appendingPathComponent(".Trash")
            try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
            let trashURL = trashRoot.appendingPathComponent(sourceURL.lastPathComponent)
            try FileManager.default.moveItem(at: sourceURL, to: trashURL)
            trashCalls.withValue { $0.append(trashURL) }
            return trashURL
        }
        fileOps.putBackFromTrash = { trashURL, originalPath in
            try FileManager.default.moveItem(at: trashURL, to: URL(fileURLWithPath: originalPath))
        }
        let windowID = UUID()
        let ownerID = UUID()
        var state = EntryOperationsState(undoOwnerID: ownerID)
        state.windowID = windowID
        let undoSpy = UndoManagerSpy()
        let store = EntryOperationsTestSupport.makeStore(initialState: state) {
            $0.entryFileOpsClient = fileOps
            $0.undoManagerClient = undoSpy.client
        }
        // store.exhaustivity = .off: provider decode부터 Trash/Undo lifecycle까지 최종 불변식으로 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.handleDropToTrash(providers: providers)))
        await store.finish()
        await store.skipReceivedActions()

        let trashURLs = trashCalls.value
        XCTAssertEqual(Set(trashURLs.map(\.path)), Set(sourceURLs.map {
            $0.deletingLastPathComponent().appendingPathComponent(".Trash/\($0.lastPathComponent)").path
        }))
        XCTAssertEqual(genericCalls.value, 0)
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertEqual(undoSpy.registerUndoCalls.count, 1)
        XCTAssertEqual(undoSpy.registerUndoCalls.first?.windowID, windowID)
        XCTAssertEqual(undoSpy.registerUndoCalls.first?.ownerID, ownerID)
        for sourceURL in sourceURLs {
            let trashURL = sourceURL.deletingLastPathComponent()
                .appendingPathComponent(".Trash/\(sourceURL.lastPathComponent)")
            let metadata = await store.dependencies.trashMetadataStoreClient.find(trashURL.path)
            XCTAssertEqual(metadata?.originalPath, sourceURL.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: trashURL.path))
        }

        await store.send(.trash(.putBackFromTrash(paths: trashURLs.map(\.path))))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(sourceURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(trashURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstSandbox.originalFixture.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondSandbox.originalFixture.path))
    }

    /// EOP-003-move_entries_to_trash: provider 하나라도 decode 실패하면 batch 전체를 변경하지 않음
    /// all-or-none resolver가 일부 성공 path를 Trash mutation으로 흘리지 않는 회귀를 검증한다.
    /// - 검증 내용: valid + invalid provider batch의 moveToTrash/generic move/paste 호출 0회, metadata/Undo 없음
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt` temp copy provider와 fileURL payload가 없는 provider
    /// - 기대 결과: fixture copy와 원본이 유지되고 EntryOperations state가 변경되지 않음
    func testHandleDropToTrash_decodeFailureMutatesNothing() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let validProvider = NSItemProvider(
            item: sandbox.fileURL as NSURL,
            typeIdentifier: UTType.fileURL.identifier,
        )
        let mutationCalls = LockIsolated(0)
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.pasteFile = { _, _ in
            mutationCalls.withValue { $0 += 1 }
            throw FileOpError.system(message: "generic paste must not run")
        }
        fileOps.moveFile = { _, _ in
            mutationCalls.withValue { $0 += 1 }
            throw FileOpError.system(message: "generic move must not run")
        }
        fileOps.moveToTrashAndReturnURL = { _ in
            mutationCalls.withValue { $0 += 1 }
            throw FileOpError.system(message: "trash mutation must not run")
        }
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = fileOps
        }
        // store.exhaustivity = .off: decode failure의 action 부재와 filesystem 불변만 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.handleDropToTrash(providers: [validProvider, NSItemProvider()])))
        await store.finish()

        XCTAssertEqual(mutationCalls.value, 0)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertTrue(store.state.itemStates.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
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

    /// EOP-003-undo_entry_action: undo owner 회전은 로컬 history만 초기화한다.
    /// - 검증 내용: owner ID와 undo/redo history 외 모든 EntryOperationsState 필드 보존
    /// - 사전 조건: loading/rename/clipboard/counter 상태와 undo/redo record가 함께 존재함
    /// - 기대 결과: 새 owner ID, 빈 history, 그 외 상태 동일
    func testUndoOwnerRotation_preservesOperationStateAndClearsLocalHistory() {
        let oldOwnerID = UUID()
        let newOwnerID = UUID()
        let undoRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/a/old.txt", afterPath: "/a/new.txt")],
        )
        let redoRecord = EntryActionRecord(
            operationKind: .createFolder,
            targets: [.init(beforePath: nil, afterPath: "/b/new-folder")],
        )
        var state = EntryOperationsState(undoOwnerID: oldOwnerID)
        state.windowID = UUID()
        state.isLoading = true
        state.isReloading = true
        state.renamingText = "preserved-name"
        state.clipboardItems = ["/preserved/item"]
        state.pendingEmptyTrashItemCount = 3
        state.emptyTrashCompletedCount = 2
        state.undoRecords = [undoRecord]
        state.redoRecords = [redoRecord]
        var expected = state
        expected.undoOwnerID = newOwnerID
        expected.undoRecords = []
        expected.redoRecords = []

        state.rotateUndoOwner(to: newOwnerID)

        XCTAssertEqual(state, expected)
    }

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

    // MARK: - EOP-003-undo_entry_action

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

    /// EOP-003-undo_entry_action: scope 이동은 기존 native UndoManager와 history를 보존한다.
    /// 창 간 Content Tab 이동 뒤에도 logical record와 연결된 native callback이 새 scope에서 실행되는지 검증한다.
    /// - 검증 내용: manager identity와 generation이 유지되고 target scope의 Undo와 Redo가 성공한다.
    /// - 사전 조건: source scope에 하나의 undo record가 등록되어 있고 target scope는 비어 있다.
    /// - 기대 결과: source lookup은 nil이고 target에서 동일 manager로 Undo와 Redo가 각각 적용된다.
    func testFileOperationRegistryMoveScopePreservesNativeUndoAndRedoHistory() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let source = UndoManagerScope(windowID: UUID(), contentTabID: "moved-tab")
        let target = UndoManagerScope(windowID: UUID(), contentTabID: "moved-tab")
        let record = EntryActionRecord(operationKind: .rename, targets: [])
        let sourceManager = try XCTUnwrap(client.activate(source))
        let generation = try XCTUnwrap(client.generation(source))
        XCTAssertTrue(client.registerUndo(source, generation, record))

        XCTAssertEqual(client.moveScope(source, target, .requireVacant), .moved)

        let removedSourceManager = await client.undoManager(source)
        let targetManagerValue = await client.undoManager(target)
        let targetManager = try XCTUnwrap(targetManagerValue)
        XCTAssertNil(removedSourceManager)
        XCTAssertIdentical(sourceManager, targetManager)
        XCTAssertEqual(client.generation(target), generation)
        XCTAssertEqual(client.performUndoRedo(target, generation, .undo, record.id), .applied)
        XCTAssertEqual(client.performUndoRedo(target, generation, .redo, record.id), .applied)
    }

    /// EOP-003-undo_entry_action: passive pinned projection의 빈 target scope는 source history로 교체된다.
    /// target manager에 history가 없을 때만 기존 projection scope를 버리고 source native stack을 보존하는지 검증한다.
    /// - 검증 내용: 빈 target 교체 outcome, manager identity, generation, source record의 Undo 성공을 비교한다.
    /// - 사전 조건: source에는 undo record가 있고 target은 activate만 되어 history가 없다.
    /// - 기대 결과: target의 빈 manager는 제거되고 source manager와 history가 target scope로 이동한다.
    func testFileOperationRegistryMoveScopeReplacesEmptyTargetForPinnedProjection() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let source = UndoManagerScope(windowID: UUID(), contentTabID: "pinned-tab")
        let target = UndoManagerScope(windowID: UUID(), contentTabID: "pinned-tab")
        let record = EntryActionRecord(operationKind: .rename, targets: [])
        let sourceManager = try XCTUnwrap(client.activate(source))
        let targetManager = try XCTUnwrap(client.activate(target))
        let sourceGeneration = try XCTUnwrap(client.generation(source))
        XCTAssertTrue(client.registerUndo(source, sourceGeneration, record))

        XCTAssertEqual(client.moveScope(source, target, .replaceEmpty), .moved)

        let removedSourceManager = await client.undoManager(source)
        let movedTargetManagerValue = await client.undoManager(target)
        let movedTargetManager = try XCTUnwrap(movedTargetManagerValue)
        XCTAssertNil(removedSourceManager)
        XCTAssertIdentical(sourceManager, movedTargetManager)
        XCTAssertNotIdentical(targetManager, movedTargetManager)
        XCTAssertEqual(client.generation(target), sourceGeneration)
        XCTAssertEqual(client.performUndoRedo(target, sourceGeneration, .undo, record.id), .applied)
    }

    /// EOP-003-undo_entry_action: scope 이동 precondition 실패는 양쪽 registry entry를 변경하지 않는다.
    /// target 충돌과 source 누락이 기존 manager identity와 generation을 훼손하지 않는지 검증한다.
    /// - 검증 내용: 각 실패 outcome과 source/target manager identity 및 generation을 비교한다.
    /// - 사전 조건: source와 target이 모두 활성화되어 있고 별도의 missing source가 존재한다.
    /// - 기대 결과: 충돌과 누락 요청이 거부되며 모든 기존 scope가 원래 manager를 유지한다.
    func testFileOperationRegistryMoveScopeFailureLeavesEntriesUnchanged() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let source = UndoManagerScope(windowID: UUID(), contentTabID: "source-tab")
        let target = UndoManagerScope(windowID: UUID(), contentTabID: "target-tab")
        let missing = UndoManagerScope(windowID: UUID(), contentTabID: "missing-tab")
        let sourceManager = try XCTUnwrap(client.activate(source))
        let targetManager = try XCTUnwrap(client.activate(target))
        let sourceGeneration = try XCTUnwrap(client.generation(source))
        let targetGeneration = try XCTUnwrap(client.generation(target))
        let sourceRecord = EntryActionRecord(operationKind: .rename, targets: [])
        let targetRecord = EntryActionRecord(operationKind: .pasteFileCopy, targets: [])
        XCTAssertTrue(client.registerUndo(source, sourceGeneration, sourceRecord))
        XCTAssertTrue(client.registerUndo(target, targetGeneration, targetRecord))

        XCTAssertEqual(client.moveScope(source, target, .requireVacant), .targetOccupied)
        XCTAssertEqual(client.moveScope(source, target, .replaceEmpty), .targetOccupied)
        XCTAssertEqual(client.moveScope(missing, target, .requireVacant), .sourceMissing)
        XCTAssertEqual(client.moveScope(source, source, .requireVacant), .targetOccupied)

        let unchangedSourceManagerValue = await client.undoManager(source)
        let unchangedTargetManagerValue = await client.undoManager(target)
        let unchangedSourceManager = try XCTUnwrap(unchangedSourceManagerValue)
        let unchangedTargetManager = try XCTUnwrap(unchangedTargetManagerValue)
        XCTAssertIdentical(sourceManager, unchangedSourceManager)
        XCTAssertIdentical(targetManager, unchangedTargetManager)
        XCTAssertEqual(client.generation(source), sourceGeneration)
        XCTAssertEqual(client.generation(target), targetGeneration)
        XCTAssertEqual(client.performUndoRedo(source, sourceGeneration, .undo, sourceRecord.id), .applied)
        XCTAssertEqual(client.performUndoRedo(target, targetGeneration, .undo, targetRecord.id), .applied)
    }

    /// EOP-003-undo_entry_action: 여러 scope를 한 번에 이동하면 모든 native history와 handler scope가 보존된다.
    /// 창 간 다중 Content Tab 이동이 frozen descriptor 순서대로 하나의 registry commit으로 반영되는지 검증한다.
    /// - 검증 내용: `moveScopes` 성공 outcome, manager identity, generation, target scope의 Undo/Redo를 비교한다.
    /// - 사전 조건: 서로 다른 두 source scope에 각각 undo record가 있고 두 target scope는 비어 있다.
    /// - 기대 결과: 두 source가 사라지고 각 target이 동일 manager와 history를 소유하며 callback이 새 scope에서 실행된다.
    func testFileOperationRegistryMoveScopesMovesMultipleManagersAtomically() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let firstSource = UndoManagerScope(windowID: UUID(), contentTabID: "first-tab")
        let secondSource = UndoManagerScope(windowID: UUID(), contentTabID: "second-tab")
        let firstTarget = UndoManagerScope(windowID: UUID(), contentTabID: "first-tab")
        let secondTarget = UndoManagerScope(windowID: UUID(), contentTabID: "second-tab")
        let firstRecord = EntryActionRecord(operationKind: .rename, targets: [])
        let secondRecord = EntryActionRecord(operationKind: .pasteFileCopy, targets: [])
        let firstManager = try XCTUnwrap(client.activate(firstSource))
        let secondManager = try XCTUnwrap(client.activate(secondSource))
        let firstGeneration = try XCTUnwrap(client.generation(firstSource))
        let secondGeneration = try XCTUnwrap(client.generation(secondSource))
        XCTAssertTrue(client.registerUndo(firstSource, firstGeneration, firstRecord))
        XCTAssertTrue(client.registerUndo(secondSource, secondGeneration, secondRecord))

        let outcome = client.moveScopes([
            .init(source: firstSource, target: firstTarget),
            .init(source: secondSource, target: secondTarget),
        ])

        let removedFirstManager = await client.undoManager(firstSource)
        let removedSecondManager = await client.undoManager(secondSource)
        let movedFirstManager = await client.undoManager(firstTarget)
        let movedSecondManager = await client.undoManager(secondTarget)
        XCTAssertEqual(outcome, .moved)
        XCTAssertNil(removedFirstManager)
        XCTAssertNil(removedSecondManager)
        XCTAssertIdentical(firstManager, movedFirstManager)
        XCTAssertIdentical(secondManager, movedSecondManager)
        XCTAssertEqual(client.generation(firstTarget), firstGeneration)
        XCTAssertEqual(client.generation(secondTarget), secondGeneration)
        XCTAssertEqual(client.performUndoRedo(firstTarget, firstGeneration, .undo, firstRecord.id), .applied)
        XCTAssertEqual(client.performUndoRedo(secondTarget, secondGeneration, .undo, secondRecord.id), .applied)
        XCTAssertEqual(client.performUndoRedo(firstTarget, firstGeneration, .redo, firstRecord.id), .applied)
        XCTAssertEqual(client.performUndoRedo(secondTarget, secondGeneration, .redo, secondRecord.id), .applied)
    }

    /// EOP-003-undo_entry_action: duplicate 및 교차 source/target은 batch 전체를 거절한다.
    /// 중복 descriptor와 source로 이동 중인 target이 manager identity 변경 전에 검출되는지 검증한다.
    /// - 검증 내용: duplicate/overlap outcome과 기존 source manager identity를 비교한다.
    /// - 사전 조건: 서로 다른 두 source manager가 활성화되어 있고 target은 비어 있다.
    /// - 기대 결과: 각 중복 batch가 거절되고 두 source manager가 원래 scope에 남는다.
    func testFileOperationRegistryMoveScopesRejectsDuplicateAndOverlappingScopes() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let firstSource = UndoManagerScope(windowID: UUID(), contentTabID: "first-source")
        let secondSource = UndoManagerScope(windowID: UUID(), contentTabID: "second-source")
        let firstTarget = UndoManagerScope(windowID: UUID(), contentTabID: "first-target")
        let secondTarget = UndoManagerScope(windowID: UUID(), contentTabID: "second-target")
        let firstManager = try XCTUnwrap(client.activate(firstSource))
        let secondManager = try XCTUnwrap(client.activate(secondSource))

        XCTAssertEqual(client.moveScopes([
            .init(source: firstSource, target: firstTarget),
            .init(source: firstSource, target: secondTarget),
        ]), .duplicateSource(firstSource))
        XCTAssertEqual(client.moveScopes([
            .init(source: firstSource, target: firstTarget),
            .init(source: secondSource, target: firstTarget),
        ]), .duplicateTarget(firstTarget))
        XCTAssertEqual(client.moveScopes([
            .init(source: firstSource, target: secondSource, targetPolicy: .replaceEmpty),
            .init(source: secondSource, target: secondTarget),
        ]), .targetOccupied(secondSource))

        let unchangedFirstManager = await client.undoManager(firstSource)
        let unchangedSecondManager = await client.undoManager(secondSource)
        XCTAssertIdentical(firstManager, unchangedFirstManager)
        XCTAssertIdentical(secondManager, unchangedSecondManager)
        let absentFirstTarget = await client.undoManager(firstTarget)
        let absentSecondTarget = await client.undoManager(secondTarget)
        XCTAssertNil(absentFirstTarget)
        XCTAssertNil(absentSecondTarget)
    }

    /// EOP-003-undo_entry_action: missing/occupied/nonempty validation 실패는 원본 registry를 변경하지 않는다.
    /// source 누락과 target history 정책이 모두 side effect 전에 거절되는지 검증한다.
    /// - 검증 내용: rejection outcome 뒤 manager identity, generation, native history를 비교한다.
    /// - 사전 조건: source와 history가 있는 occupied target이 활성화되어 있다.
    /// - 기대 결과: 모든 실패 뒤 각 scope와 handler가 원래 위치에 남고 기존 Undo가 정상 실행된다.
    func testFileOperationRegistryMoveScopesRejectsInvalidEntriesWithoutMutation() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let source = UndoManagerScope(windowID: UUID(), contentTabID: "source")
        let target = UndoManagerScope(windowID: UUID(), contentTabID: "target")
        let occupiedTarget = UndoManagerScope(windowID: UUID(), contentTabID: "occupied-target")
        let missingSource = UndoManagerScope(windowID: UUID(), contentTabID: "missing-source")
        let sourceRecord = EntryActionRecord(operationKind: .rename, targets: [])
        let occupiedRecord = EntryActionRecord(operationKind: .createFolder, targets: [])
        let sourceManager = try XCTUnwrap(client.activate(source))
        let occupiedManager = try XCTUnwrap(client.activate(occupiedTarget))
        let sourceGeneration = try XCTUnwrap(client.generation(source))
        let occupiedGeneration = try XCTUnwrap(client.generation(occupiedTarget))
        XCTAssertTrue(client.registerUndo(source, sourceGeneration, sourceRecord))
        XCTAssertTrue(client.registerUndo(occupiedTarget, occupiedGeneration, occupiedRecord))

        XCTAssertEqual(client.moveScopes([]), .emptyBatch)
        XCTAssertEqual(client.moveScopes([
            .init(source: source, target: target),
            .init(source: missingSource, target: UndoManagerScope(windowID: UUID(), contentTabID: "other")),
        ]), .sourceMissing(missingSource))
        XCTAssertEqual(client.moveScopes([
            .init(source: source, target: occupiedTarget),
        ]), .targetOccupied(occupiedTarget))
        XCTAssertEqual(client.moveScopes([
            .init(source: source, target: occupiedTarget, targetPolicy: .replaceEmpty),
        ]), .targetOccupied(occupiedTarget))

        let unchangedSourceManager = await client.undoManager(source)
        let unchangedOccupiedManager = await client.undoManager(occupiedTarget)
        XCTAssertIdentical(sourceManager, unchangedSourceManager)
        XCTAssertIdentical(occupiedManager, unchangedOccupiedManager)
        XCTAssertEqual(client.generation(source), sourceGeneration)
        XCTAssertEqual(client.generation(occupiedTarget), occupiedGeneration)
        XCTAssertEqual(client.performUndoRedo(source, sourceGeneration, .undo, sourceRecord.id), .applied)
        XCTAssertEqual(
            client.performUndoRedo(occupiedTarget, occupiedGeneration, .undo, occupiedRecord.id),
            .applied,
        )
    }

    /// EOP-003-undo_entry_action: 마지막 descriptor 실패도 앞선 move의 registry와 handler를 변경하지 않는다.
    /// batch validation이 live registry mutation보다 완전히 선행하는지 late failure로 검증한다.
    /// - 검증 내용: 세 번째 occupied target rejection 뒤 앞선 두 source의 manager와 callback scope를 비교한다.
    /// - 사전 조건: 세 source에 history가 있고 마지막 target만 별도 history로 점유되어 있다.
    /// - 기대 결과: 새 target은 모두 비어 있고 세 source의 manager/history가 원래 scope에서 그대로 동작한다.
    func testFileOperationRegistryMoveScopesLastDescriptorFailureLeavesEarlierMovesUntouched() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let sources = (0 ..< 3).map {
            UndoManagerScope(windowID: UUID(), contentTabID: "source-\($0)")
        }
        let targets = (0 ..< 3).map {
            UndoManagerScope(windowID: UUID(), contentTabID: "target-\($0)")
        }
        let records = [
            EntryActionRecord(operationKind: .rename, targets: []),
            EntryActionRecord(operationKind: .pasteFileCopy, targets: []),
            EntryActionRecord(operationKind: .createFolder, targets: []),
        ]
        var managers: [UndoManager] = []
        var generations: [FileOperationUndoManagerClient.Generation] = []
        for (scope, record) in zip(sources, records) {
            try managers.append(XCTUnwrap(client.activate(scope)))
            let generation = try XCTUnwrap(client.generation(scope))
            generations.append(generation)
            XCTAssertTrue(client.registerUndo(scope, generation, record))
        }
        let occupiedManager = try XCTUnwrap(client.activate(targets[2]))
        let occupiedGeneration = try XCTUnwrap(client.generation(targets[2]))
        let occupiedRecord = EntryActionRecord(operationKind: .pasteFileMove, targets: [])
        XCTAssertTrue(client.registerUndo(targets[2], occupiedGeneration, occupiedRecord))

        let outcome = client.moveScopes(zip(sources, targets).map {
            .init(source: $0, target: $1)
        })

        XCTAssertEqual(outcome, .targetOccupied(targets[2]))
        for index in sources.indices {
            let unchangedManager = await client.undoManager(sources[index])
            XCTAssertIdentical(managers[index], unchangedManager)
            if index < 2 {
                let absentTargetManager = await client.undoManager(targets[index])
                XCTAssertNil(absentTargetManager)
            }
            XCTAssertEqual(
                client.performUndoRedo(sources[index], generations[index], .undo, records[index].id),
                .applied,
            )
        }
        let unchangedOccupiedManager = await client.undoManager(targets[2])
        XCTAssertIdentical(occupiedManager, unchangedOccupiedManager)
        XCTAssertEqual(
            client.performUndoRedo(targets[2], occupiedGeneration, .undo, occupiedRecord.id),
            .applied,
        )
    }

    /// EOP-003-undo_entry_action: 성공한 replaceEmpty batch만 빈 target manager를 정리하고 source handler를 rebind한다.
    /// passive pinned projection target 교체가 전체 validation 이후 한 번만 commit되는지 검증한다.
    /// - 검증 내용: 교체된 manager 제거, source manager identity/history 보존, target callback 실행을 비교한다.
    /// - 사전 조건: source에는 undo record가 있고 target은 native/logical history 없이 activate만 되어 있다.
    /// - 기대 결과: 빈 target manager는 registry에서 교체되고 moved manager의 Undo/Redo가 새 target에서 성공한다.
    func testFileOperationRegistryMoveScopesReplaceEmptyCommitsCleanupAndRebind() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let source = UndoManagerScope(windowID: UUID(), contentTabID: "pinned-source")
        let target = UndoManagerScope(windowID: UUID(), contentTabID: "pinned-target")
        let record = EntryActionRecord(operationKind: .rename, targets: [])
        let sourceManager = try XCTUnwrap(client.activate(source))
        let replacedManager = try XCTUnwrap(client.activate(target))
        let generation = try XCTUnwrap(client.generation(source))
        XCTAssertTrue(client.registerUndo(source, generation, record))

        let outcome = client.moveScopes([
            .init(source: source, target: target, targetPolicy: .replaceEmpty),
        ])

        let removedSourceManager = await client.undoManager(source)
        let movedTargetManager = await client.undoManager(target)
        XCTAssertEqual(outcome, .moved)
        XCTAssertNil(removedSourceManager)
        XCTAssertIdentical(sourceManager, movedTargetManager)
        XCTAssertNotIdentical(replacedManager, movedTargetManager)
        XCTAssertFalse(replacedManager.canUndo)
        XCTAssertFalse(replacedManager.canRedo)
        XCTAssertEqual(client.performUndoRedo(target, generation, .undo, record.id), .applied)
        XCTAssertEqual(client.performUndoRedo(target, generation, .redo, record.id), .applied)
    }

    /// EOP-003-undo_entry_action: legacy moveScope는 singleton batch와 동일한 결과를 반환한다.
    /// 기존 호출자가 batch API 도입 뒤에도 manager identity와 history 의미를 그대로 유지하는지 검증한다.
    /// - 검증 내용: legacy outcome mapping과 singleton batch의 registry 결과 및 Undo 실행을 비교한다.
    /// - 사전 조건: 동일한 source/target/history 구성을 가진 두 독립 registry가 있다.
    /// - 기대 결과: legacy는 moved, batch는 moved이며 두 경로 모두 원래 manager를 target으로 이동시킨다.
    func testFileOperationRegistryMoveScopeMatchesSingletonBatch() async throws {
        let legacyRegistry = FileOperationUndoManagerRegistry()
        let batchRegistry = FileOperationUndoManagerRegistry()
        let legacyClient = FileOperationUndoManagerClient.live(registry: legacyRegistry)
        let batchClient = FileOperationUndoManagerClient.live(registry: batchRegistry)
        let legacySource = UndoManagerScope(windowID: UUID(), contentTabID: "singleton")
        let legacyTarget = UndoManagerScope(windowID: UUID(), contentTabID: "singleton")
        let batchSource = UndoManagerScope(windowID: UUID(), contentTabID: "singleton")
        let batchTarget = UndoManagerScope(windowID: UUID(), contentTabID: "singleton")
        let legacyRecord = EntryActionRecord(operationKind: .rename, targets: [])
        let batchRecord = EntryActionRecord(operationKind: .rename, targets: [])
        let legacyManager = try XCTUnwrap(legacyClient.activate(legacySource))
        let batchManager = try XCTUnwrap(batchClient.activate(batchSource))
        let legacyGeneration = try XCTUnwrap(legacyClient.generation(legacySource))
        let batchGeneration = try XCTUnwrap(batchClient.generation(batchSource))
        XCTAssertTrue(legacyClient.registerUndo(legacySource, legacyGeneration, legacyRecord))
        XCTAssertTrue(batchClient.registerUndo(batchSource, batchGeneration, batchRecord))

        let legacyOutcome = legacyClient.moveScope(legacySource, legacyTarget, .requireVacant)
        let batchOutcome = batchClient.moveScopes([
            .init(source: batchSource, target: batchTarget),
        ])

        let movedLegacyManager = await legacyClient.undoManager(legacyTarget)
        let movedBatchManager = await batchClient.undoManager(batchTarget)
        XCTAssertEqual(legacyOutcome, .moved)
        XCTAssertEqual(batchOutcome, .moved)
        XCTAssertIdentical(legacyManager, movedLegacyManager)
        XCTAssertIdentical(batchManager, movedBatchManager)
        XCTAssertEqual(
            legacyClient.performUndoRedo(legacyTarget, legacyGeneration, .undo, legacyRecord.id),
            .applied,
        )
        XCTAssertEqual(
            batchClient.performUndoRedo(batchTarget, batchGeneration, .undo, batchRecord.id),
            .applied,
        )
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
        XCTAssertEqual(registeredAvailability, .init(
            canUndo: true,
            canRedo: false,
            undoTarget: .init(ownerID: sidebarOwnerID, recordID: sidebarRecord.id),
        ))
        _ = await client.undo(
            windowID,
            expectedTarget: .init(ownerID: sidebarOwnerID, recordID: sidebarRecord.id),
        )
        let afterSidebarUndo = await client.availability(windowID)
        XCTAssertEqual(afterSidebarUndo.undoTarget, .init(ownerID: contentOwnerID, recordID: contentRecord.id))
        XCTAssertEqual(afterSidebarUndo.redoTarget, .init(ownerID: sidebarOwnerID, recordID: sidebarRecord.id))
        _ = await client.undo(
            windowID,
            expectedTarget: .init(ownerID: contentOwnerID, recordID: contentRecord.id),
        )

        let values = await receivedEvents.value
        XCTAssertEqual(values.map(\.ownerID), [sidebarOwnerID, contentOwnerID])
        XCTAssertEqual(values.map(\.record), [sidebarRecord, contentRecord])
        XCTAssertEqual(values.map(\.direction), [.undo, .undo])
        let fullyUndoneAvailability = await client.availability(windowID)
        XCTAssertEqual(fullyUndoneAvailability, .init(
            canUndo: false,
            canRedo: true,
            redoTarget: .init(ownerID: contentOwnerID, recordID: contentRecord.id),
        ))
        _ = await client.redo(
            windowID,
            expectedTarget: .init(ownerID: contentOwnerID, recordID: contentRecord.id),
        )
        let afterContentRedo = await client.availability(windowID)
        XCTAssertEqual(afterContentRedo.undoTarget, .init(ownerID: contentOwnerID, recordID: contentRecord.id))
        XCTAssertEqual(afterContentRedo.redoTarget, .init(ownerID: sidebarOwnerID, recordID: sidebarRecord.id))
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
        _ = await client.undo(
            windowID,
            expectedTarget: .init(ownerID: contentOwnerID, recordID: contentRecord.id),
        )
        let contentRedoAvailability = await client.availability(windowID)
        XCTAssertTrue(contentRedoAvailability.canRedo)
        await client.registerUndo(windowID, sidebarOwnerID, sidebarRecord)
        let afterSidebarRegistration = await client.availability(windowID)
        XCTAssertFalse(afterSidebarRegistration.canRedo)

        undoManager.removeAllActions()
        await client.registerUndo(windowID, sidebarOwnerID, sidebarRecord)
        _ = await client.undo(
            windowID,
            expectedTarget: .init(ownerID: sidebarOwnerID, recordID: sidebarRecord.id),
        )
        let sidebarRedoAvailability = await client.availability(windowID)
        XCTAssertTrue(sidebarRedoAvailability.canRedo)
        await client.registerUndo(windowID, contentOwnerID, contentRecord)
        let afterContentRegistration = await client.availability(windowID)
        XCTAssertFalse(afterContentRegistration.canRedo)
    }

    /// EOP-003-undo_entry_action: expected target mismatch는 native manager를 호출하지 않는다.
    /// Window preflight 이후 top이 바뀌는 경쟁에서도 live client가 마지막 원자 검증을 수행하는지 확인한다.
    /// - 검증 내용: nil/wrong expected target은 didInvoke=false이고 올바른 target만 native undo를 실행한다.
    /// - 사전 조건: 단일 owner/record가 shared UndoManager undo top으로 등록되어 있다.
    /// - 기대 결과: mismatch 동안 canUndo와 top identity가 유지되고 matching 호출에서만 redo로 이동한다.
    func testUndoManager_expectedTargetMismatchDoesNotInvokeNativeManager() async {
        let undoManager = UndoManager()
        let client = UndoManagerClient.live(undoManager: undoManager)
        let windowID = UUID()
        let ownerID = UUID()
        let record = makeUndoManagerRecord(pathStem: "expected-target")
        let expectedTarget = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
        await client.registerUndo(windowID, ownerID, record)

        let missingResult = await client.undo(windowID)
        let mismatchResult = await client.undo(
            windowID,
            expectedTarget: .init(ownerID: ownerID, recordID: UUID()),
        )

        XCTAssertFalse(missingResult.didInvoke)
        XCTAssertFalse(mismatchResult.didInvoke)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(mismatchResult.availability.undoTarget, expectedTarget)

        let matchingResult = await client.undo(windowID, expectedTarget: expectedTarget)
        XCTAssertTrue(matchingResult.didInvoke)
        XCTAssertFalse(matchingResult.availability.canUndo)
        XCTAssertEqual(matchingResult.availability.redoTarget, expectedTarget)
    }

    // AC: EOP-003-undo_entry_action — owner invalidation은 이미 등록된 action을 제거함
    /// EOP-003-undo_entry_action: owner 무효화가 기존 undo action을 제거하고 identity를 폐기함
    func testUndoManager_registerThenInvalidateOwnerRemovesUndo() async {
        let undoManager = UndoManager()
        let client = UndoManagerClient.live(undoManager: undoManager)
        let windowID = UUID()
        let ownerID = UUID()

        await client.registerUndo(windowID, ownerID, makeUndoManagerRecord(pathStem: "registered-owner"))
        XCTAssertTrue(undoManager.canUndo)

        let result = await client.invalidateOwner(windowID, ownerID)

        XCTAssertEqual(result, .init(succeeded: true, availability: .init()))
        XCTAssertFalse(undoManager.canUndo)
    }

    // AC: EOP-003-undo_entry_action — owner invalidation이 resolver 대기 중인 late registration보다 먼저 선형화됨
    /// EOP-003-undo_entry_action: register resolve가 늦게 끝나도 이미 무효화된 owner에는 action을 등록하지 않음
    func testUndoManager_ownerInvalidationRejectsRegistrationAfterBlockedResolverResumes() async {
        let undoManager = UndoManager()
        let windowID = UUID()
        let ownerID = UUID()
        let resolverCallCount = LockIsolated(0)
        let (registrationStarted, registrationStartedContinuation) = AsyncStream<Bool>.makeStream()
        let (registrationResolution, registrationResolutionContinuation) = AsyncStream<UndoManager>.makeStream()
        let client = UndoManagerClient.live { _ in
            let call = resolverCallCount.withValue { count in
                count += 1
                return count
            }
            guard call == 1 else {
                return undoManager
            }
            registrationStartedContinuation.yield(true)
            registrationStartedContinuation.finish()
            for await resolvedUndoManager in registrationResolution {
                return resolvedUndoManager
            }
            return nil
        }
        var registrationStartedIterator = registrationStarted.makeAsyncIterator()
        let registrationTask = Task {
            await client.registerUndo(windowID, ownerID, makeUndoManagerRecord(pathStem: "late-owner"))
        }

        let didStartRegistration = await registrationStartedIterator.next()
        XCTAssertEqual(didStartRegistration, true)
        let invalidation = await client.invalidateOwner(windowID, ownerID)
        XCTAssertTrue(invalidation.succeeded)

        registrationResolutionContinuation.yield(undoManager)
        registrationResolutionContinuation.finish()
        await registrationTask.value

        XCTAssertFalse(undoManager.canUndo)
    }

    // AC: EOP-003-undo_entry_action — owner tombstone은 같은 window의 다른 owner를 차단하지 않음
    /// EOP-003-undo_entry_action: owner A 무효화 후에도 같은 window의 owner B는 undo를 등록할 수 있음
    func testUndoManager_ownerTombstoneDoesNotBlockDifferentOwner() async {
        let undoManager = UndoManager()
        let client = UndoManagerClient.live(undoManager: undoManager)
        let windowID = UUID()
        let invalidatedOwnerID = UUID()
        let activeOwnerID = UUID()

        let invalidation = await client.invalidateOwner(windowID, invalidatedOwnerID)
        XCTAssertTrue(invalidation.succeeded)
        await client.registerUndo(windowID, invalidatedOwnerID, makeUndoManagerRecord(pathStem: "invalidated-owner"))
        XCTAssertFalse(undoManager.canUndo)

        let activeRecord = makeUndoManagerRecord(pathStem: "active-owner")
        await client.registerUndo(windowID, activeOwnerID, activeRecord)

        XCTAssertTrue(undoManager.canUndo)
        let activeAvailability = await client.availability(windowID)
        XCTAssertEqual(
            activeAvailability.undoTarget,
            .init(ownerID: activeOwnerID, recordID: activeRecord.id),
        )
    }

    // AC: EOP-003-undo_entry_action — window invalidation은 모든 owner의 late registration을 영구 차단하고 stream을 종료함
    /// EOP-003-undo_entry_action: window 무효화 뒤 어떤 owner도 undo를 등록할 수 없고 event stream이 종료됨
    func testUndoManager_windowInvalidationRejectsLateRegistrationsAndFinishesStream() async {
        let undoManager = UndoManager()
        let client = UndoManagerClient.live(undoManager: undoManager)
        let windowID = UUID()
        let events = client.events(windowID)
        let streamCompletion = Task {
            var iterator = events.makeAsyncIterator()
            return await iterator.next()
        }

        let invalidation = await client.invalidateWindow(windowID)
        XCTAssertTrue(invalidation.succeeded)
        await client.registerUndo(windowID, UUID(), makeUndoManagerRecord(pathStem: "late-window-owner-a"))
        await client.registerUndo(windowID, UUID(), makeUndoManagerRecord(pathStem: "late-window-owner-b"))

        let nextEvent = await streamCompletion.value
        XCTAssertNil(nextEvent)
        XCTAssertFalse(undoManager.canUndo)
    }

    // AC: EOP-003-undo_entry_action — manager resolution 실패는 tombstone을 만들지 않음
    /// EOP-003-undo_entry_action: 무효화 resolve 실패 뒤 manager가 복구되면 같은 identity의 등록을 허용함
    func testUndoManager_failedInvalidationResolutionDoesNotCreateTombstone() async {
        let undoManager = UndoManager()
        let resolverCallCount = LockIsolated(0)
        let client = UndoManagerClient.live { _ in
            let call = resolverCallCount.withValue { count in
                count += 1
                return count
            }
            return call == 1 ? nil : undoManager
        }
        let windowID = UUID()
        let ownerID = UUID()

        let invalidation = await client.invalidateOwner(windowID, ownerID)
        XCTAssertEqual(invalidation, .init(succeeded: false, availability: .init()))

        await client.registerUndo(windowID, ownerID, makeUndoManagerRecord(pathStem: "resolution-recovered"))

        XCTAssertTrue(undoManager.canUndo)
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
        _ = await client.undo(
            windowID,
            expectedTarget: .init(ownerID: contentOwnerID, recordID: contentRecord.id),
        )

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

private func makeUndoManagerRecord(pathStem: String) -> EntryActionRecord {
    EntryActionRecord(
        operationKind: .rename,
        targets: [.init(beforePath: "/\(pathStem)/old", afterPath: "/\(pathStem)/new")],
    )
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

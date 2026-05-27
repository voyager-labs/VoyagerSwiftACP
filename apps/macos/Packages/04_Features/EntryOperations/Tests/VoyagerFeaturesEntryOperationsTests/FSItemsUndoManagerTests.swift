import ComposableArchitecture
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class FSItemsUndoManagerTests: XCTestCase {
    /// 완료된 작업이 등록되면 undo가 쌓이고 redo는 비워지는지 검증
    func testEntryActionCompletedRegistersUndoAndClearsRedo() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let redoRecordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 0),
        )
        let redoRecord = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: "/tmp/c.txt", afterPath: "/tmp/d.txt")],
            id: redoRecordId,
            timestamp: Date(timeIntervalSince1970: 1),
        )

        let registered = RegisteredRecords()

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.redoRecords = [redoRecord]
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.undoManagerClient.registerUndo = { _, record, _, _ in
                await registered.append(record)
            }
        }

        await store.send(.lifecycle(.entryActionCompleted(record))) {
            $0.undoRecords = [record]
            $0.redoRecords = []
        }
        await store.finish()

        let recorded = await registered.snapshot()
        XCTAssertEqual(recorded, [record])
    }

    /// undo 요청이 실제 undoManager 호출로 이어지는지 검증
    func testRequestUndoTriggersUndoManager() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 10),
        )

        let undoCalls = CallCounter()

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.undoRecords = [record]
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.undoManagerClient.undo = { _ in
                await undoCalls.increment()
            }
        }

        await store.send(.undoRedo(.requestUndo))
        await store.finish()

        let count = await undoCalls.value()
        XCTAssertEqual(count, 1)
    }

    /// busy 상태의 항목은 undo 대상이 아니므로 요청을 무시하는지 검증
    func testRequestUndoSkipsWhenBusy() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 11),
        )

        let undoCalls = CallCounter()

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.undoRecords = [record]
            state.itemStates["/tmp/a.txt"] = ItemOperationState(isBusy: true)
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.undoManagerClient.undo = { _ in
                await undoCalls.increment()
            }
        }

        await store.send(.undoRedo(.requestUndo))
        await store.finish()

        let count = await undoCalls.value()
        XCTAssertEqual(count, 0)
    }

    /// undo 시 실제 파일명이 되돌아가고 redo 기록이 쌓이는지 검증
    func testUndoEntryActionRenamesAndRegistersRedo() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 12),
        )

        let renameCalls = RenameRecorder()

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.undoRecords = [record]
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient.renameFile = { source, destination in
                await renameCalls.append(source.path, destination.path)
            }
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        // 핵심 상태 변화만 확인하고 중간 액션은 생략해 테스트 의도를 명확히 유지한다.
        store.exhaustivity = .off

        await store.send(.undoRedo(.undoEntryAction(record)))
        await store.finish()

        let calls = await renameCalls.snapshot()
        XCTAssertEqual(calls, [RenameCall(source: "/tmp/b.txt", destination: "/tmp/a.txt")])
        XCTAssertEqual(store.state.undoRecords, [])
        XCTAssertEqual(store.state.redoRecords, [record])
    }

    /// redo 시 원래 방향으로 다시 이름이 바뀌고 undo 기록이 복원되는지 검증
    func testRedoEntryActionRenamesAndRegistersUndo() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000013"))
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 13),
        )

        let renameCalls = RenameRecorder()

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.redoRecords = [record]
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient.renameFile = { source, destination in
                await renameCalls.append(source.path, destination.path)
            }
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        // 핵심 상태 변화만 확인하고 중간 액션은 생략해 테스트 의도를 명확히 유지한다.
        store.exhaustivity = .off

        await store.send(.undoRedo(.redoEntryAction(record)))
        await store.finish()

        let calls = await renameCalls.snapshot()
        XCTAssertEqual(calls, [RenameCall(source: "/tmp/a.txt", destination: "/tmp/b.txt")])
        XCTAssertEqual(store.state.undoRecords, [record])
        XCTAssertEqual(store.state.redoRecords, [])
    }

    /// windowID에 맞는 UndoManager가 해석되어 실제 undo 가능 상태가 되는지 검증
    func testResolverBackedUndoManagerClientRegistersUndoForWindowID() async throws {
        let windowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000014"))
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000015"))
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 14),
        )

        let undoManager = UndoManager()

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.windowID = windowID
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.undoManagerClient = .live(resolveUndoManager: { requestedWindowID in
                requestedWindowID == windowID ? undoManager : nil
            })
        }

        await store.send(.lifecycle(.entryActionCompleted(record))) {
            $0.undoRecords = [record]
            $0.redoRecords = []
        }
        await store.finish()

        XCTAssertTrue(undoManager.canUndo)
    }
}

private actor RegisteredRecords {
    private var records: [EntryActionRecord] = []

    func append(_ record: EntryActionRecord) {
        records.append(record)
    }

    func snapshot() -> [EntryActionRecord] {
        records
    }
}

private actor CallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private struct RenameCall: Equatable {
    let source: String
    let destination: String
}

private actor RenameRecorder {
    private var calls: [RenameCall] = []

    func append(_ source: String, _ destination: String) {
        calls.append(RenameCall(source: source, destination: destination))
    }

    func snapshot() -> [RenameCall] {
        calls
    }
}

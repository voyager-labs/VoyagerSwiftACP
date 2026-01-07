import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class FSItemsUndoManagerTests: XCTestCase {
    func testEntryActionCompletedRegistersUndoAndClearsRedo() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let redoRecordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let record = EntryActionRecord(
            actionKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 0),
        )
        let redoRecord = EntryActionRecord(
            actionKind: .move,
            targets: [.init(beforePath: "/tmp/c.txt", afterPath: "/tmp/d.txt")],
            id: redoRecordId,
            timestamp: Date(timeIntervalSince1970: 1),
        )

        let registered = RegisteredRecords()

        let store = TestStore(initialState: {
            var state = FSItemsFeature.State()
            state.redoRecords = [redoRecord]
            return state
        }()) {
            FSItemsFeature()
        } withDependencies: {
            $0.undoManagerClient.registerUndo = { record, _, _ in
                await registered.append(record)
            }
        }

        await store.send(.operations(.entryActionCompleted(record))) {
            $0.undoRecords = [record]
            $0.redoRecords = []
        }
        await store.finish()

        let recorded = await registered.snapshot()
        XCTAssertEqual(recorded, [record])
    }

    func testRequestUndoTriggersUndoManager() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let record = EntryActionRecord(
            actionKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 10),
        )

        let undoCalls = CallCounter()

        let store = TestStore(initialState: {
            var state = FSItemsFeature.State()
            state.undoRecords = [record]
            return state
        }()) {
            FSItemsFeature()
        } withDependencies: {
            $0.undoManagerClient.undo = {
                await undoCalls.increment()
            }
        }

        await store.send(.requestUndo)
        await store.finish()

        let count = await undoCalls.value()
        XCTAssertEqual(count, 1)
    }

    func testRequestUndoSkipsWhenBusy() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let record = EntryActionRecord(
            actionKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 11),
        )

        let undoCalls = CallCounter()

        let store = TestStore(initialState: {
            var state = FSItemsFeature.State()
            state.undoRecords = [record]
            state.operations.itemStates["/tmp/a.txt"] = FSItemsOperationsFeature.ItemOperationState(isBusy: true)
            return state
        }()) {
            FSItemsFeature()
        } withDependencies: {
            $0.undoManagerClient.undo = {
                await undoCalls.increment()
            }
        }

        await store.send(.requestUndo)
        await store.finish()

        let count = await undoCalls.value()
        XCTAssertEqual(count, 0)
    }

    func testUndoEntryActionRenamesAndRegistersRedo() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
        let record = EntryActionRecord(
            actionKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 12),
        )

        let renameCalls = RenameRecorder()

        let store = TestStore(initialState: {
            var state = FSItemsFeature.State()
            state.undoRecords = [record]
            return state
        }()) {
            FSItemsFeature()
        } withDependencies: {
            $0.fsItemClient.renameFile = { source, destination in
                await renameCalls.append(source.path, destination.path)
            }
        }

        store.exhaustivity = .off

        await store.send(.undoEntryAction(record))
        await store.finish()

        let calls = await renameCalls.snapshot()
        XCTAssertEqual(calls, [RenameCall(source: "/tmp/b.txt", destination: "/tmp/a.txt")])
        XCTAssertEqual(store.state.undoRecords, [])
        XCTAssertEqual(store.state.redoRecords, [record])
    }

    func testRedoEntryActionRenamesAndRegistersUndo() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000013"))
        let record = EntryActionRecord(
            actionKind: .rename,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 13),
        )

        let renameCalls = RenameRecorder()

        let store = TestStore(initialState: {
            var state = FSItemsFeature.State()
            state.redoRecords = [record]
            return state
        }()) {
            FSItemsFeature()
        } withDependencies: {
            $0.fsItemClient.renameFile = { source, destination in
                await renameCalls.append(source.path, destination.path)
            }
        }

        store.exhaustivity = .off

        await store.send(.redoEntryAction(record))
        await store.finish()

        let calls = await renameCalls.snapshot()
        XCTAssertEqual(calls, [RenameCall(source: "/tmp/a.txt", destination: "/tmp/b.txt")])
        XCTAssertEqual(store.state.undoRecords, [record])
        XCTAssertEqual(store.state.redoRecords, [])
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

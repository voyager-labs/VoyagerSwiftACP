import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class EntryThumbnailCacheEvictionTests: XCTestCase {
    func testUndoRenameEvictsOldAndNewThumbnailPaths() async throws {
        let recordId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000099"))
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/tmp/old.txt", afterPath: "/tmp/new.txt")],
            id: recordId,
            timestamp: Date(timeIntervalSince1970: 99),
        )
        let removedPaths = RemovedPathsRecorder()

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.undoRecords = [record]
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient.renameFile = { _, _ in }
            $0.entryThumbnailCacheClient.removeThumbnails = { paths in
                removedPaths.append(paths)
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.undoRedo(.undoEntryAction(record)))
        await store.finish()

        let snapshot = removedPaths.snapshot().map { Set($0) }
        XCTAssertTrue(snapshot.contains(["/tmp/old.txt", "/tmp/new.txt"]))
    }
}

private final class RemovedPathsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[String]] = []

    func append(_ paths: [String]) {
        lock.lock()
        values.append(paths)
        lock.unlock()
    }

    func snapshot() -> [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

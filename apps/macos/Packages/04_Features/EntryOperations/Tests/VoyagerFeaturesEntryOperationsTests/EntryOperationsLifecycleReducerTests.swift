import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryOperationsLifecycleReducerTests: XCTestCase {
    private func makeStore(
        initialState: EntryOperationsFeature.State = .init(),
    ) -> TestStore<EntryOperationsFeature.State, EntryOperationsFeature.Action> {
        TestStore(initialState: initialState) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }
    }

    func testOperationStartedSetsIsBusyTrue() async {
        let store = makeStore()

        await store.send(.lifecycle(.operationStarted("/tmp/file.txt", .rename))) {
            $0.itemStates["/tmp/file.txt"] = ItemOperationState(isBusy: true)
        }

        await store.finish()
    }

    func testOperationFinishedSetsIsBusyFalseOnSuccess() async {
        let store = makeStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.itemStates["/tmp/file.txt"] = ItemOperationState(isBusy: true)
            return state
        }())

        await store.send(.lifecycle(.operationFinished(
            "/tmp/file.txt",
            .rename,
            .success(()),
        ))) {
            $0.itemStates["/tmp/file.txt"]?.isBusy = false
            $0.itemStates["/tmp/file.txt"]?.lastError = nil
            $0.renamingItemId = nil
            $0.renamingText = ""
        }

        await store.finish()
    }

    func testOperationFinishedSetsErrorOnFailure() async {
        let store = makeStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.itemStates["/tmp/file.txt"] = ItemOperationState(isBusy: true)
            return state
        }())

        await store.send(.lifecycle(.operationFinished(
            "/tmp/file.txt",
            .rename,
            .failure(.notFound),
        ))) {
            $0.itemStates["/tmp/file.txt"]?.isBusy = false
            $0.itemStates["/tmp/file.txt"]?.lastError = .notFound
            $0.renamingItemId = nil
            $0.renamingText = ""
        }

        await store.finish()
    }

    func testPathsMutatedTriggersThumbnailInvalidation() async {
        let removedPaths = RemovedPathsRecorder()

        let store = makeStore()
        store.dependencies.entryThumbnailCacheClient.removeThumbnails = { paths in
            removedPaths.append(paths)
        }

        await store.send(.lifecycle(.pathsMutated(["/tmp/a.txt", "/tmp/b.txt"])))

        await store.finish()

        let snapshot = removedPaths.snapshot()
        XCTAssertEqual(snapshot.count, 1, "thumbnail eviction should fire once")
        if let paths = snapshot.first {
            XCTAssertEqual(Set(paths), Set(["/tmp/a.txt", "/tmp/b.txt"]))
        }
    }

    func testEntryActionCompletedAppendsUndoRecord() async {
        let store = makeStore()

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/tmp/old.txt", afterPath: "/tmp/new.txt")],
        )

        await store.send(.lifecycle(.entryActionCompleted(record))) {
            $0.undoRecords = [record]
            $0.redoRecords = []
        }

        await store.finish()
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

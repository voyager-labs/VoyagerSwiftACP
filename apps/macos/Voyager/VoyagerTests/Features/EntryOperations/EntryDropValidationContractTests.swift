import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class EntryDropValidationContractTests: XCTestCase {
    func testValidateDropReturnsNoOpForSameParentInternalMove() async {
        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        }

        let context = EntryDropValidationContext(
            sourcePaths: ["/tmp/voyager/source.txt"],
            destinationPath: "/tmp/voyager",
            allowedOperationsRawValue: NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = .init(
                destinationPath: "/tmp/voyager",
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        await store.finish()
    }

    func testValidateDropReturnsNoOpForDescendantInternalMove() async {
        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        }

        let context = EntryDropValidationContext(
            sourcePaths: ["/tmp/voyager/folder"],
            destinationPath: "/tmp/voyager/folder/child",
            allowedOperationsRawValue: NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = .init(
                destinationPath: "/tmp/voyager/folder/child",
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        await store.finish()
    }

    // MARK: - Bug 2: VoyagerDragOption never written

    func testDragOptionIsCapturedAtSessionStart() async {
        // DESIRED: When a drag session begins, the Option-key state should be
        // captured via saveDragWithOption so it can be read deterministically
        // during drop handling.
        //
        // WILL FAIL: The current reducer does not call saveDragWithOption from
        // any action. loadDragWithOption returns stale/empty values.
        let recorder = DragOptionRecorder()

        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient.saveDragPaths = { _ in }
            $0.entryFileOpsClient.loadDragPaths = { ["/tmp/file.txt"] }
            $0.entryFileOpsClient.saveDragWithOption = { [recorder] isOption in
                recorder.record(isOption)
            }
            $0.entryFileOpsClient.loadDragWithOption = { false }
        }

        await store.send(.routing(.saveDragPaths(["/tmp/file.txt"])))
        await store.finish()

        XCTAssertEqual(
            recorder.savedOptions.count,
            1,
            "saveDragWithOption should be called when a drag session begins",
        )
        XCTAssertEqual(
            recorder.savedOptions.first,
            false,
            "Option-key state should be captured as false (not pressed)",
        )
    }

    func testDragOptionDoesNotLeakBetweenSessions() async {
        // DESIRED: Each drag session starts with fresh option state. The
        // saveDragWithOption call at session start means loadDragWithOption
        // returns the current session's value, not stale state from a prior drag.
        //
        // WILL FAIL: Since saveDragWithOption is never called, loadDragWithOption
        // returns whatever was left from a prior session.
        let recorder = DragOptionRecorder()

        let store1 = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient.saveDragPaths = { _ in }
            $0.entryFileOpsClient.loadDragPaths = { ["/tmp/file1.txt"] }
            $0.entryFileOpsClient.saveDragWithOption = { [recorder] isOption in
                recorder.record(isOption)
            }
            $0.entryFileOpsClient.loadDragWithOption = { false }
        }

        await store1.send(.routing(.saveDragPaths(["/tmp/file1.txt"])))
        await store1.finish()

        let store2 = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient.saveDragPaths = { _ in }
            $0.entryFileOpsClient.loadDragPaths = { ["/tmp/file2.txt"] }
            $0.entryFileOpsClient.saveDragWithOption = { [recorder] isOption in
                recorder.record(isOption)
            }
            $0.entryFileOpsClient.loadDragWithOption = { true }
        }

        await store2.send(.routing(.saveDragPaths(["/tmp/file2.txt"])))
        await store2.finish()

        XCTAssertEqual(
            recorder.savedOptions.count,
            2,
            "Each drag session should independently call saveDragWithOption",
        )
        XCTAssertEqual(
            recorder.savedOptions.last,
            true,
            "Second session should capture its own option state, not inherit from first",
        )
    }
}

private final class DragOptionRecorder: @unchecked Sendable {
    private(set) var savedOptions: [Bool] = []
    func record(_ isOption: Bool) {
        savedOptions.append(isOption)
    }
}

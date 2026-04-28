import ComposableArchitecture
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryMutationContractTests: XCTestCase {
    func testCutPasteIntoSameParentKeepsClipboardState() async {
        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.clipboardItems = ["/tmp/voyager/source.txt"]
            state.clipboardOperation = .cut
            state.cutClearSession = EntryOperationsCutClearHeuristic().makeInitialSession(
                cutSessionId: "cut-session",
                pasteboardChangeCount: 1,
                sourcePaths: ["/tmp/voyager/source.txt"],
                now: Date(timeIntervalSince1970: 1_700_000_000),
            )
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.clipboard(.pasteItems(
            sourcePaths: ["/tmp/voyager/source.txt"],
            destinationPath: "/tmp/voyager",
            operation: .cut,
            operationKind: .pasteFileMove,
        )))
        await store.finish()

        XCTAssertEqual(store.state.clipboardItems, ["/tmp/voyager/source.txt"])
        XCTAssertEqual(store.state.clipboardOperation, .cut)
        XCTAssertNotNil(store.state.cutClearSession)
    }

    func testCutPasteMoveSuccessRemovesOnlyMovedPathFromClipboard() async {
        let session = EntryOperationsCutClearHeuristic().makeInitialSession(
            cutSessionId: "cut-session",
            pasteboardChangeCount: 1,
            sourcePaths: ["/tmp/voyager/a.txt", "/tmp/other/b.txt"],
            now: Date(timeIntervalSince1970: 1_700_000_000),
        )

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.clipboardItems = ["/tmp/voyager/a.txt", "/tmp/other/b.txt"]
            state.clipboardOperation = .cut
            state.cutClearSession = session
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        await store.send(.lifecycle(.operationFinished("/tmp/voyager/a.txt", .pasteFileMove, .success(())))) {
            $0.clipboardItems = ["/tmp/other/b.txt"]
            $0.clipboardOperation = .cut
            $0.cutClearSession?.sourcePaths = ["/tmp/other/b.txt"]
        }

        await store.finish()
    }

    func testCutPasteMoveSuccessClearsClipboardWhenLastPathMoves() async {
        let session = EntryOperationsCutClearHeuristic().makeInitialSession(
            cutSessionId: "cut-session",
            pasteboardChangeCount: 1,
            sourcePaths: ["/tmp/voyager/a.txt"],
            now: Date(timeIntervalSince1970: 1_700_000_000),
        )

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.clipboardItems = ["/tmp/voyager/a.txt"]
            state.clipboardOperation = .cut
            state.cutClearSession = session
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        await store.send(.lifecycle(.operationFinished("/tmp/voyager/a.txt", .pasteFileMove, .success(())))) {
            $0.clipboardItems = []
            $0.clipboardOperation = .copy
            $0.cutClearSession = nil
        }
        await store.receive(\.clipboard.setClipboardOperation)

        await store.finish()
    }
}

import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class EntryMutationContractTests: XCTestCase {
    func testCutPasteIntoSameParentIsNoOpAndKeepsClipboardState() async {
        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.clipboardItems = ["/tmp/voyager/source.txt"]
            state.clipboardOperation = .cut
            state.cutClearSession = EntryViewLayoutCutClearHeuristic().makeInitialSession(
                cutSessionId: "cut-session",
                pasteboardChangeCount: 1,
                sourcePaths: ["/tmp/voyager/source.txt"],
                now: Date(timeIntervalSince1970: 1_700_000_000),
            )
            return state
        }()) {
            EntryOperationsFeature()
        }

        await store.send(.pasteItems(
            sourcePaths: ["/tmp/voyager/source.txt"],
            destinationPath: "/tmp/voyager",
            operation: .cut,
            operationKind: .pasteFileMove,
        ))

        XCTAssertEqual(store.state.clipboardItems, ["/tmp/voyager/source.txt"])
        XCTAssertEqual(store.state.clipboardOperation, .cut)
        XCTAssertNotNil(store.state.cutClearSession)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertTrue(store.state.redoRecords.isEmpty)

        await store.finish()
    }

    func testCutPasteMoveSuccessRemovesOnlyMovedPathFromClipboard() async {
        let session = EntryViewLayoutCutClearHeuristic().makeInitialSession(
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
        }

        await store.send(.operationFinished("/tmp/voyager/a.txt", .pasteFileMove, .success(()))) {
            $0.clipboardItems = ["/tmp/other/b.txt"]
            $0.clipboardOperation = .cut
            $0.cutClearSession?.sourcePaths = ["/tmp/other/b.txt"]
        }

        await store.finish()
    }

    func testCutPasteMoveSuccessClearsClipboardWhenLastPathMoves() async {
        let session = EntryViewLayoutCutClearHeuristic().makeInitialSession(
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
        }

        await store.send(.operationFinished("/tmp/voyager/a.txt", .pasteFileMove, .success(()))) {
            $0.clipboardItems = []
            $0.clipboardOperation = .copy
            $0.cutClearSession = nil
        }
        await store.receive(.setClipboardOperation(operation: .copy)) {
            $0.clipboardOperation = .copy
            $0.cutClearSession = nil
        }

        await store.finish()
    }
}

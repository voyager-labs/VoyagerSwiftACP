import ComposableArchitecture
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryMutationContractTests: XCTestCase {
    /// cut-paste가 같은 부모에서 수행되더라도 클립보드 상태가 유지되는지 검증
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

    /// 이동 성공 후 클립보드에서 이동된 경로만 제거되는지 검증
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

    /// 마지막 경로가 이동되면 cut 클립보드를 비우고 copy로 전환하는지 검증
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

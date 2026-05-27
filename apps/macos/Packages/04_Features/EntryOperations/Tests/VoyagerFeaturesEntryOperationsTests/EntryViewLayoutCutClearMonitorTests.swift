import ComposableArchitecture
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryViewLayoutCutClearMonitorTests: XCTestCase {
    /// 앱 활성화 시 source path 중 하나라도 없으면 cut 클립보드를 지워야 하는지 검증
    func testAppActiveClearsCutWhenAnySourcePathIsMissing() {
        let heuristic = EntryOperationsCutClearHeuristic(backoffSchedule: [0.5, 1, 2])
        let monitor = EntryClipboardOperationsCutClearMonitor(heuristic: heuristic)
        let startedAt = Date(timeIntervalSinceReferenceDate: 0)
        let session = heuristic.makeInitialSession(
            cutSessionId: "cut-1",
            pasteboardChangeCount: 10,
            sourcePaths: ["/tmp/existing", "/tmp/missing"],
            now: startedAt,
        )

        let decision = monitor.evaluateOnAppDidBecomeActive(
            clipboardOperation: .cut,
            clipboardItems: session.sourcePaths,
            session: session,
            makeSession: { _, _ in nil },
            context: .init(
                now: Date(timeIntervalSinceReferenceDate: 1),
                readPasteboardChangeCount: { 10 },
                readPasteboardCutSessionId: { "cut-1" },
                fileExists: { path in
                    path != "/tmp/missing"
                },
            ),
        )

        XCTAssertEqual(decision, .clear)
    }

    /// 활성화 이벤트가 오면 cut 상태를 copy로 되돌리고 세션을 초기화하는지 검증
    func testAppDidBecomeActiveActionClearsClipboardOperationToCopy() async {
        let heuristic = EntryOperationsCutClearHeuristic(backoffSchedule: [0.5, 1, 2])
        let session = heuristic.makeInitialSession(
            cutSessionId: "cut-1",
            pasteboardChangeCount: 10,
            sourcePaths: ["/tmp/missing"],
            now: Date(timeIntervalSinceReferenceDate: 0),
        )

        let store = TestStore(initialState: {
            var state = EntryOperationsFeature.State()
            state.clipboardItems = ["/tmp/missing"]
            state.clipboardOperation = .cut
            state.cutClearSession = session
            return state
        }()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient.fileExists = { _ in false }
            $0.entryFileOpsClient.clipboardChangeCount = { 10 }
            $0.entryFileOpsClient.loadClipboardCutSessionId = { "cut-1" }
            $0.entryFileOpsClient.saveClipboardCutSessionId = { _ in }
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        await store.send(.lifecycle(.appDidBecomeActive))
        await store.receive(\.clipboard.setClipboardOperation) {
            $0.clipboardOperation = .copy
            $0.cutClearSession = nil
        }
        await store.finish()
    }
}

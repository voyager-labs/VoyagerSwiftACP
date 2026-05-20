@testable import Voyager
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
/// 드래그/클립보드 상태 정리 회귀를 검증하는 테스트 모음이다.
final class EntryOperationsCutClearHeuristicTests: XCTestCase {
    /// 잘라내기 상태 정리 회귀를 방지한다.
    func testKeepsCutWhenPasteboardChangeCountChangedButCutSessionIdStillMatches() {
        let heuristic = EntryOperationsCutClearHeuristic()
        let now = Date(timeIntervalSinceReferenceDate: 0)

        let session = heuristic.makeInitialSession(
            cutSessionId: "cut-1",
            pasteboardChangeCount: 10,
            sourcePaths: ["/tmp/a"],
            now: now,
        )

        let decision = heuristic.evaluate(
            session: session,
            now: now,
            readPasteboardChangeCount: { 11 },
            readPasteboardCutSessionId: { "cut-1" },
            fileExists: { _ in true },
        )

        switch decision {
        case let .keep(updated):
            XCTAssertEqual(updated.cutSessionId, "cut-1")
            XCTAssertEqual(updated.pasteboard.changeCount, 11)
        case .clear:
            XCTFail("Expected to keep cut session")
        }
    }

    /// 잘라내기 상태 정리 회귀를 방지한다.
    func testClearsCutWhenPasteboardChangeCountChangedAndCutSessionIdIsDifferentOrMissing() {
        let heuristic = EntryOperationsCutClearHeuristic()
        let now = Date(timeIntervalSinceReferenceDate: 0)

        let session = heuristic.makeInitialSession(
            cutSessionId: "cut-1",
            pasteboardChangeCount: 10,
            sourcePaths: ["/tmp/a"],
            now: now,
        )

        let decision = heuristic.evaluate(
            session: session,
            now: now,
            readPasteboardChangeCount: { 11 },
            readPasteboardCutSessionId: { nil },
            fileExists: { _ in true },
        )

        XCTAssertEqual(decision, .clear)
    }

    /// 잘라내기 상태 정리 회귀를 방지한다.
    func testClearsCutWhenBackoffDueAndAnySourcePathIsMissing() {
        let heuristic = EntryOperationsCutClearHeuristic(backoffSchedule: [0.5, 1, 2])
        let start = Date(timeIntervalSinceReferenceDate: 0)

        let missingPath = "/missing"
        let session = heuristic.makeInitialSession(
            cutSessionId: "cut-1",
            pasteboardChangeCount: 10,
            sourcePaths: ["/tmp/a", missingPath],
            now: start,
        )

        let afterBackoff = Date(timeIntervalSinceReferenceDate: 1.0)
        let decision = heuristic.evaluate(
            session: session,
            now: afterBackoff,
            readPasteboardChangeCount: { 10 },
            readPasteboardCutSessionId: { "cut-1" },
            fileExists: { path in path != missingPath },
        )

        XCTAssertEqual(decision, .clear)
    }
}

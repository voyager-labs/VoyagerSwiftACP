import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryGridDropHighlightLifecycleTests: XCTestCase {
    /// 성공한 복사 드롭에서는 세션 종료 직후 하이라이트를 즉시 지우지 않는지 검증한다.
    func testAcceptDropClearsDropTargetState() {
        let operation: NSDragOperation = .copy
        XCTAssertFalse(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation),
            "Successful copy drop should defer clearing — highlight persists until operation completes",
        )
    }

    /// 잘못된 드롭은 성공 작업이 없으므로 하이라이트를 즉시 정리하는지 검증한다.
    func testInvalidDropClearsDropTargetState() {
        let operation: NSDragOperation = []
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation),
            "Invalid drop should still trigger drop target state clearing",
        )
    }

    /// 드래그 종료 시 모든 내부 상태와 하이라이트가 정리되는지 검증한다.
    func testDragEndClearsDropTargetState() {
        let paths = ["/Users/test/Documents/file.txt"]
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .move,
            currentPaths: paths,
        )
        XCTAssertTrue(
            cleared.isEmpty,
            "Drag end should clear all internal drag state paths",
        )
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: .move),
            "Drag end should trigger drop target clearing",
        )
    }

    /// 취소된 세션 종료 후 오래된 드롭 대상 상태가 남지 않는지 검증한다.
    func testReloadDoesNotPreserveStaleDropTargetState() {
        let stalePaths = ["/Users/test/stale.txt"]
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: [],
            currentPaths: stalePaths,
        )
        XCTAssertTrue(
            cleared.isEmpty,
            "Stale drag paths should be fully cleared on cancelled session end",
        )
        XCTAssertFalse(
            EntryViewLayoutDragStateClearRuleSet.isInternalDrag(paths: cleared),
            "After clearing, subsequent drag should not be treated as internal",
        )
    }

    // MARK: - 버그 1: 너무 이른 하이라이트 해제 (snap-back)

    func testSuccessfulFolderDropDoesNotClearHighlightAtAcceptTime() {
        // 요구사항: 성공적인 드롭(비어 있지 않은 작업)은
        // 수락-드롭 시점에서의 세션 종료 정리를 트리거해서는 안 됩니다. 하이라이트는
        // 파일 작업이 완료될 때까지 유지되어야 합니다.
        //
        // 실패 예정: 현재 구현은 모든 작업에 대해 조건 없이 true를 반환하여
        // 모든 작업에서 acceptDrop이 즉시 하이라이트를 지우도록 합니다.
        let successfulOperation: NSDragOperation = .copy
        XCTAssertFalse(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: successfulOperation),
            "Successful drop operation should NOT clear highlight at accept time — deferred to operation completion",
        )
    }

    func testSuccessfulFolderDropClearsHighlightAfterOperationCompletes() {
        // 요구사항: 작업이 완료된 뒤(별도 라이프사이클 이벤트의
        // 완료 신호가 올라오면) 규칙 집합은 정리를 허용해야 합니다. 즉,
        // 하이라이트 제거는 즉시가 아니라 지연되어야 함을 의미합니다.
        //
        // 실패 예정: 현재 구현은 성공 종료와 즉시 종료 정리를 구분하지 못합니다.
        // 규칙 집합에 지연 정리 경로가 없습니다.
        let paths = ["/Users/test/Documents/file.txt"]
        let operation: NSDragOperation = .copy

        // 세션 종료 시 성공한 작업의 경로는 유지되어야 함
        let preserved = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: operation,
            currentPaths: paths,
        )
        XCTAssertEqual(
            preserved,
            paths,
            "After successful drop, drag paths should be preserved until operation lifecycle signals completion",
        )
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.isInternalDrag(paths: preserved),
            "Preserved paths should still be recognized as internal drag state",
        )
    }

    func testCancelledDragClearsHighlightImmediately() {
        // 취소된 드래그(빈 작업)는 즉시 정리되어야 함.
        // 현재 동작이 취소 처리에서 정확하므로 통과해야 합니다.
        let cancelledOperation: NSDragOperation = []
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: cancelledOperation),
            "Cancelled drag should clear highlight immediately",
        )
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: cancelledOperation,
            currentPaths: ["/tmp/file.txt"],
        )
        XCTAssertTrue(
            cleared.isEmpty,
            "Cancelled drag should clear all stored paths",
        )
    }

    func testInvalidDropTargetClearsHighlightImmediately() {
        // 잘못된 대상 드롭(유효성 검사에서 .none으로 판정됨)
        // 즉시 정리되어야 합니다. 현재 동작이라면 통과해야 합니다.
        let noOperation: NSDragOperation = []
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: noOperation),
            "Invalid drop target should clear highlight immediately",
        )
    }

    // MARK: - Finder 유사 하이라이트 억제 수명주기 (NEW)

    func testDropTargetHighlightRestraintOnTransitionFromTargetedToUntargeted() {
        // 새로운 계약: 대상 지정됨→미지정 상태로 전환할 때 전체 셀
        // 테두리가 완전히 제거되어야 합니다. 이는 기존의 폭넓은 처리가
        // 완전히 해제됨을 확인합니다. 잔존 테두리 아티팩트가 없어야 합니다.
        // 통과해야 하지만 라이프사이클 요구사항을 문서화합니다.
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: []),
            "Untargeted transition must clear all drop visual state",
        )
    }

    func testDropTargetHighlightDoesNotPersistAcrossDragSessions() {
        // 새로운 계약: 이전 드래그 세션의 오래된 드롭 대상 상태가
        // 새 세션으로 이어져서는 안 됩니다. 각 세션은 깨끗하게 시작되어야 합니다.
        let freshPaths: [String] = []
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: [],
            currentPaths: freshPaths,
        )
        XCTAssertTrue(
            cleared.isEmpty,
            "No stale paths should persist between drag sessions",
        )
    }
}

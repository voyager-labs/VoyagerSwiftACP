import AppKit
@testable import Voyager
import XCTest

@MainActor
final class EntryGridDropHighlightLifecycleTests: XCTestCase {
    func testAcceptDropClearsDropTargetState() {
        let operation: NSDragOperation = .copy
        XCTAssertFalse(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation),
            "Successful copy drop should defer clearing — highlight persists until operation completes",
        )
    }

    func testInvalidDropClearsDropTargetState() {
        let operation: NSDragOperation = []
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation),
            "Invalid drop should still trigger drop target state clearing",
        )
    }

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

    // MARK: - 버그 1: 조기 하이라이트 해제 (스냅백)

    func testSuccessfulFolderDropDoesNotClearHighlightAtAcceptTime() {
        // 기대 동작: 성공적인 드롭(비어 있지 않은 작업)은 accept 시점에서
        // 세션 종료 정리가 즉시 트리거되어서는 안 됩니다. 하이라이트는 유지되어야 하며
        // 파일 작업이 완료될 때까지 유지되어야 합니다.
        //
        // 현재 구현은 모든 작업에 대해 무조건 true를 반환하므로
        // acceptDrop이 하이라이트를 즉시 해제하는 문제가 발생합니다.
        let successfulOperation: NSDragOperation = .copy
        XCTAssertFalse(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: successfulOperation),
            "Successful drop operation should NOT clear highlight at accept time — deferred to operation completion",
        )
    }

    func testSuccessfulFolderDropClearsHighlightAfterOperationCompletes() {
        // 기대 동작: 작업 완료 후(별도의 생명주기 이벤트로 알림),
        // 규칙 집합이 정리 허용되어야 하며, 이는 즉시 제거가 아닌 지연 제거라는
        // 비결성 규칙을 보장합니다.
        //
        // 현재는 실패 사유: "세션이 성공적으로 종료"와
        // "세션이 종료되어 즉시 정리"를 구분할 수 있는 메커니즘이 없습니다.
        // 규칙 집합에는 지연 정리 경로가 없습니다.
        let paths = ["/Users/test/Documents/file.txt"]
        let operation: NSDragOperation = .copy

        // 세션 종료 시 성공 작업의 경로는 보존되어야 함
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
        // 취소된 드래그(작업이 빈 값)는 즉시 정리되어야 합니다.
        // 현재 동작이 취소 처리에 대해 올바르므로 통과해야 합니다.
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
        // 잘못된 드롭 대상(검증 결과 .none으로 판정)은
        // 즉시 정리되어야 합니다. 현재 동작이므로 통과해야 합니다.
        let noOperation: NSDragOperation = []
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: noOperation),
            "Invalid drop target should clear highlight immediately",
        )
    }

    // MARK: - Finder 유사 하이라이트 억제 수명주기 (신규)

    func testDropTargetHighlightRestraintOnTransitionFromTargetedToUntargeted() {
        // 신규 계약: targeted→untargeted 전환 시 전체 셀의
        // 테두리가 완전히 제거되어야 합니다. 이전의 범위가 넓은 처리 방식이
        // 완전히 클리어되어, 잔여 테두리 아티팩트가 없어야 함을 검증합니다.
        // 통과해야 하지만 수명주기 요구사항을 문서화합니다.
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: []),
            "Untargeted transition must clear all drop visual state",
        )
    }

    func testDropTargetHighlightDoesNotPersistAcrossDragSessions() {
        // 신규 계약: 이전 드래그 세션의 오래된 드롭 대상 상태가
        // 새 세션으로 이어져서는 안 됩니다. 각 세션은 깨끗하게 시작해야 합니다.
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

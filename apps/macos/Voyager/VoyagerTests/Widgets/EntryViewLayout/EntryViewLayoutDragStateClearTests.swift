import AppKit
@testable import Voyager
import XCTest

@MainActor
/// 드래그/클립보드 상태 정리 회귀를 검증하는 테스트 모음이다.
final class EntryViewLayoutDragStateClearTests: XCTestCase {
    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testClearsInternalDragStateWhenSessionEndsWithNonEmptyOperation() {
        let after = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .copy,
            currentPaths: ["/tmp/a.txt"],
        )

        XCTAssertTrue(after.isEmpty)
    }

    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testClearsInternalDragStateWhenSessionEndsWithEmptyOperation() {
        let after = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: [],
            currentPaths: ["/tmp/a.txt"],
        )

        XCTAssertTrue(after.isEmpty)
    }

    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testNextDragIsNotTreatedAsInternalAfterStateCleared() {
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .move,
            currentPaths: ["/tmp/a.txt"],
        )

        XCTAssertFalse(EntryViewLayoutDragStateClearRuleSet.isInternalDrag(paths: cleared))
    }
}

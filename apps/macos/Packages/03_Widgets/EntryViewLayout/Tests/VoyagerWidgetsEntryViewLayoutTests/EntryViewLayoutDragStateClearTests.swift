import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryViewLayoutDragStateClearTests: XCTestCase {
    /// 비복사 작업이 끝나면 내부 드래그 경로를 즉시 비우는지 검증한다.
    func testClearsInternalDragStateWhenSessionEndsWithNonEmptyOperation() {
        // .copy와 달리 move는 완료 시점에 경로를 남길 이유가 없으므로 즉시 정리되어야 한다.
        let after = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .move,
            currentPaths: ["/tmp/a.txt"],
        )

        XCTAssertTrue(after.isEmpty)
    }

    /// 복사 작업은 완료 전까지 드래그 하이라이트를 유지하기 위해 경로를 보존하는지 검증한다.
    func testCopyOperationPreservesDragPathsUntilCompletion() {
        // 복사는 비동기 파일 작업이 끝날 때까지 내부 상태를 유지해야 시각적 하이라이트가 지속된다.
        let after = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .copy,
            currentPaths: ["/tmp/a.txt"],
        )

        XCTAssertFalse(after.isEmpty, "Copy operations should preserve drag paths for highlight persistence")
    }

    /// 빈 작업 종료 시 내부 드래그 상태를 비우는지 검증한다.
    func testClearsInternalDragStateWhenSessionEndsWithEmptyOperation() {
        let after = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: [],
            currentPaths: ["/tmp/a.txt"],
        )

        XCTAssertTrue(after.isEmpty)
    }

    /// 세션 종료 후 정리된 경로가 다음 드래그에서 내부 상태로 오인되지 않는지 검증한다.
    func testNextDragIsNotTreatedAsInternalAfterStateCleared() {
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .move,
            currentPaths: ["/tmp/a.txt"],
        )

        XCTAssertFalse(EntryViewLayoutDragStateClearRuleSet.isInternalDrag(paths: cleared))
    }
}

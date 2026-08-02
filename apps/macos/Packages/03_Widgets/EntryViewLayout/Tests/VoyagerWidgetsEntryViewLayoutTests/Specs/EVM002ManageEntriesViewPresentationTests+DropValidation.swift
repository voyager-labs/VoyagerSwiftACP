import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    /// EVM-002-manage_entries_view: move 선호 drag가 copy-only mask를 따르면 copy로 fallback한다.
    /// - 검증 내용: AppKit source operation mask가 canonical drop validation에 전달된다.
    /// - 사전 조건: Option 키 없이 copy만 허용된 drag source다.
    /// - 기대 결과: resolved operation이 copy이고 isOptionDrag가 true다.
    func testDropValidationPreservesCopyOnlySourceMask() {
        let result = EntryViewLayoutDropValidationAdapter.resolve(
            sourcePaths: ["/source/file.txt"],
            destinationPath: "/destination",
            allowedOperations: .copy,
            prefersCopy: false,
        )

        XCTAssertEqual(result.resolvedOperation, .copy)
        XCTAssertTrue(result.isOptionDrag)
    }

    /// EVM-002-manage_entries_view: source folder 하위 destination drop을 거부한다.
    /// - 검증 내용: coordinator adapter가 canonical descendant rejection을 재사용한다.
    /// - 사전 조건: source folder를 자신의 하위 경로로 move하려 한다.
    /// - 기대 결과: resolved operation이 none이다.
    func testDropValidationRejectsDescendantDestination() {
        let result = EntryViewLayoutDropValidationAdapter.resolve(
            sourcePaths: ["/source/folder"],
            destinationPath: "/source/folder/child",
            allowedOperations: [.copy, .move],
            prefersCopy: false,
        )

        XCTAssertEqual(result.resolvedOperation, .none)
    }
}

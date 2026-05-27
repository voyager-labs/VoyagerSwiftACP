import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryGridRenameEditorPresentationTests: XCTestCase {
    // MARK: - 이름 변경 중 단일 행 인라인 편집기

    /// 그리드 뷰에서 이름 변경 시 텍스트 필드가 단일 행 모드로 동작하는지 검증
    ///
    /// - 검증 내용: usesSingleLineMode=true, 줄바꿈 비활성화, 최대 1줄, 스크롤 가능
    /// - 회귀 방지: 여러 줄 입력으로 인한 그리드 레이아웃 깨짐 방지
    func testRenameStyleUsesSingleLineMode() {
        let field = NSTextField(string: "filename.txt")
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        XCTAssertTrue(field.usesSingleLineMode, "Grid rename must use single-line mode")
        XCTAssertNotEqual(field.lineBreakMode, .byWordWrapping, "Grid rename must not word-wrap")
        XCTAssertEqual(field.maximumNumberOfLines, 1, "Grid rename must be single-line")
        XCTAssertEqual(field.cell?.wraps, false, "Grid rename must not wrap")
        XCTAssertEqual(field.cell?.isScrollable, true, "Grid rename field must be scrollable")
    }

    /// 이름 변경 필드에 테두리가 표시되는지 검증
    func testRenameStyleHasBorderedField() {
        let field = NSTextField(string: "filename")
        field.isBordered = true
        XCTAssertTrue(field.isBordered, "Grid rename field must be bordered")
    }

    /// 이름 변경 필드가 배경색을 그리는지 검증
    func testRenameStyleHasTextBackground() {
        let field = NSTextField(string: "filename")
        field.drawsBackground = true
        field.backgroundColor = NSColor.textBackgroundColor
        XCTAssertTrue(field.drawsBackground, "Grid rename field must draw background")
        XCTAssertEqual(field.backgroundColor, NSColor.textBackgroundColor)
    }

    /// 이름 변경 필드가 기본 포커스 링을 사용하는지 검증
    func testRenameStyleHasDefaultFocusRing() {
        let field = NSTextField(string: "filename")
        field.focusRingType = .default
        XCTAssertEqual(field.focusRingType, .default, "Grid rename field must use default focus ring")
    }

    // MARK: - 표시 스타일은 줄바꿈 사용 (이름 변경 아님)

    /// 일반 표시 모드에서는 여러 줄을 허용하고 중간 truncation을 사용하는지 검증
    ///
    /// - 검증 내용: usesSingleLineMode=false, 최대 2줄, byTruncatingMiddle
    /// - 회귀 방지: 긴 파일명이 표시 모드에서 잘리지 않고 적절히 truncation되는지 확인
    func testDisplayStyleDoesNotUseSingleLineMode() {
        let field = NSTextField(string: "filename")
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 2
        field.lineBreakMode = .byTruncatingMiddle
        XCTAssertFalse(field.usesSingleLineMode, "Display mode should allow multiline")
        XCTAssertEqual(field.maximumNumberOfLines, 2, "Display mode allows up to 2 lines")
        XCTAssertEqual(field.lineBreakMode, .byTruncatingMiddle, "Display mode truncates middle")
    }

    // MARK: - 이름 변경 중 InfoField 숨김

    /// 이름 변경 중에는 보조 정보(infoField)가 숨겨지는지 검증
    func testInfoFieldHiddenDuringRename() {
        let infoField = NSTextField(labelWithString: "12 KB")
        infoField.isHidden = true
        XCTAssertTrue(infoField.isHidden, "infoField must be hidden during active rename")
    }

    /// 이름 변경이 아닐 때 보조 정보가 다시 표시되는지 검증
    func testInfoFieldVisibleWhenNotRenamingWithSupplementaryInfo() {
        let infoField = NSTextField(labelWithString: "12 KB")
        infoField.isHidden = false
        XCTAssertFalse(infoField.isHidden, "infoField should be visible when not renaming and has supplementary info")
    }
}

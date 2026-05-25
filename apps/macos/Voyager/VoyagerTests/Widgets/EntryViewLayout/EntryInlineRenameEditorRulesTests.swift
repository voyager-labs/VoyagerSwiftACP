import AppKit
@testable import Voyager
import XCTest

@MainActor
/// 이름 변경(리네임) 동작 회귀를 검증하는 테스트 모음이다.
final class EntryInlineRenameEditorRulesTests: XCTestCase {
    /// 리네임/선택 전환 경계를 검증해 회귀를 방지한다.
    func testRenameEditorWrappingStyleIsConfigured() {
        let textField = NSTextField(string: "filename")
        EntryInlineRenameEditorRules.applyWrappingStyle(to: textField)
        XCTAssertFalse(textField.usesSingleLineMode)
        XCTAssertEqual(textField.lineBreakMode, .byWordWrapping)
        XCTAssertGreaterThanOrEqual(textField.maximumNumberOfLines, 2)
        XCTAssertTrue(textField.cell?.wraps ?? false)
        XCTAssertFalse(textField.cell?.isScrollable ?? true)
    }

    /// 리네임 입력/커밋 경로 회귀를 방지한다.
    func testSanitizeInputRemovesNewlineCharacters() {
        let sanitized = EntryInlineRenameEditorRules.sanitizeInput("line1\nline2\rline3\r\nline4")
        XCTAssertEqual(sanitized, "line1line2line3line4")
    }

    /// 리네임 입력/커밋 경로 회귀를 방지한다.
    func testCommandActionMapsEnterAndTabToCommitAndEscToCancel() {
        let newlineAction = EntryInlineRenameEditorRules.commandAction(for: #selector(NSResponder.insertNewline(_:)))
        let tabAction = EntryInlineRenameEditorRules.commandAction(for: #selector(NSResponder.insertTab(_:)))
        let cancelAction = EntryInlineRenameEditorRules.commandAction(for: #selector(NSResponder.cancelOperation(_:)))
        let noopAction = EntryInlineRenameEditorRules.commandAction(for: #selector(NSResponder.moveRight(_:)))
        XCTAssertEqual(newlineAction, .commit)
        XCTAssertEqual(tabAction, .commit)
        XCTAssertEqual(cancelAction, .cancel)
        XCTAssertEqual(noopAction, .none)
    }
}

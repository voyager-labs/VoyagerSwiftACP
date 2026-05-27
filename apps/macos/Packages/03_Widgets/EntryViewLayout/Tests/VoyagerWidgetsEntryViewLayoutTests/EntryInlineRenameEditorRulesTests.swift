import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryInlineRenameEditorRulesTests: XCTestCase {
    /// 이름 변경 편집기가 여러 줄 입력을 허용하도록 스타일을 설정하는지 검증
    func testRenameEditorWrappingStyleIsConfigured() {
        let textField = NSTextField(string: "filename")
        EntryInlineRenameEditorRules.applyWrappingStyle(to: textField)
        XCTAssertFalse(textField.usesSingleLineMode)
        XCTAssertEqual(textField.lineBreakMode, .byWordWrapping)
        XCTAssertGreaterThanOrEqual(textField.maximumNumberOfLines, 2)
        XCTAssertTrue(textField.cell?.wraps ?? false)
        XCTAssertFalse(textField.cell?.isScrollable ?? true)
    }

    /// 개행 문자가 입력값에서 제거되어 단일 줄 이름 변경이 안전하게 처리되는지 검증
    func testSanitizeInputRemovesNewlineCharacters() {
        let sanitized = EntryInlineRenameEditorRules.sanitizeInput("line1\nline2\rline3\r\nline4")
        XCTAssertEqual(sanitized, "line1line2line3line4")
    }

    /// 리턴/탭/ESC 명령이 각각 commit 또는 cancel 동작으로 매핑되는지 검증
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

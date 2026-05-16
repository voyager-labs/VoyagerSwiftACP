import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryInlineRenameEditorRulesTests: XCTestCase {
    func testRenameEditorWrappingStyleIsConfigured() {
        let textField = NSTextField(string: "filename")
        EntryInlineRenameEditorRules.applyWrappingStyle(to: textField)
        XCTAssertFalse(textField.usesSingleLineMode)
        XCTAssertEqual(textField.lineBreakMode, .byWordWrapping)
        XCTAssertGreaterThanOrEqual(textField.maximumNumberOfLines, 2)
        XCTAssertTrue(textField.cell?.wraps ?? false)
        XCTAssertFalse(textField.cell?.isScrollable ?? true)
    }

    func testSanitizeInputRemovesNewlineCharacters() {
        let sanitized = EntryInlineRenameEditorRules.sanitizeInput("line1\nline2\rline3\r\nline4")
        XCTAssertEqual(sanitized, "line1line2line3line4")
    }

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

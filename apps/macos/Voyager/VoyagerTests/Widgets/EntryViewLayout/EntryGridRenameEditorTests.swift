import AppKit
@testable import Voyager
import XCTest

@MainActor
final class EntryGridRenameEditorTests: XCTestCase {
    func testRenameEditorWrappingStyleIsConfigured() {
        let textField = NSTextField(string: "filename")

        EntryGridRenameEditorRules.applyWrappingStyle(to: textField)

        XCTAssertFalse(textField.usesSingleLineMode)
        XCTAssertEqual(textField.lineBreakMode, .byWordWrapping)
        XCTAssertGreaterThanOrEqual(textField.maximumNumberOfLines, 2)
        XCTAssertTrue(textField.cell?.wraps ?? false)
        XCTAssertFalse(textField.cell?.isScrollable ?? true)
    }

    func testSanitizeInputRemovesNewlineCharacters() {
        let sanitized = EntryGridRenameEditorRules.sanitizeInput("line1\nline2\rline3\r\nline4")

        XCTAssertEqual(sanitized, "line1line2line3line4")
    }

    func testCommandActionMapsEnterAndTabToCommitAndEscToCancel() {
        let newlineAction = EntryGridRenameEditorRules.commandAction(
            for: #selector(NSResponder.insertNewline(_:)),
        )
        let tabAction = EntryGridRenameEditorRules.commandAction(
            for: #selector(NSResponder.insertTab(_:)),
        )
        let cancelAction = EntryGridRenameEditorRules.commandAction(
            for: #selector(NSResponder.cancelOperation(_:)),
        )
        let noopAction = EntryGridRenameEditorRules.commandAction(
            for: #selector(NSResponder.moveRight(_:)),
        )

        XCTAssertEqual(newlineAction, .commit)
        XCTAssertEqual(tabAction, .commit)
        XCTAssertEqual(cancelAction, .cancel)
        XCTAssertEqual(noopAction, .none)
    }
}

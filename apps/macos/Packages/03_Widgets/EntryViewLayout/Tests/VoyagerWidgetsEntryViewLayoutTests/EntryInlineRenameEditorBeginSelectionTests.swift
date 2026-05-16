import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryInlineRenameBeginSelectionTests: XCTestCase {
    // MARK: - initialSelectionRange tests

    func testRegularFileSelectsBasenameOnly() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "report.txt", isFolder: false)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 6)
    }

    func testExtensionlessFileSelectsAll() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "README", isFolder: false)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 6)
    }

    func testMultiDotFileSelectsBeforeFinalExtension() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "archive.tar.gz", isFolder: false)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 11)
    }

    func testFolderSelectsAll() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "MyFolder", isFolder: true)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 8)
    }

    func testHiddenFolderSelectsAll() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: ".git", isFolder: true)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 4)
    }

    func testDotfileIsTreatedAsExtensionless() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: ".env", isFolder: false)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 4)
    }

    func testDotfileWithExtensionSelectsBeforeFinalDot() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: ".env.backup", isFolder: false)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 4)
    }

    func testUnicodeFilenameUsesUtf16BasenameLength() {
        let displayName = "📄report.txt"
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: displayName, isFolder: false)

        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, ("📄report" as NSString).length)
    }

    // MARK: - selectedRange application tests

    private func makeWindowWithTextField(_ text: String) -> (NSWindow, NSTextField) {
        let textField = NSTextField(string: text)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 24),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(textField)
        return (window, textField)
    }

    func testBasenameSelectionAppliedToTextField() {
        let (_, textField) = makeWindowWithTextField("report.txt")
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "report.txt", isFolder: false)
        textField.selectText(nil)
        if let editor = textField.currentEditor() as? NSTextView {
            editor.setSelectedRange(range)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 6))
        } else {
            XCTFail("Field editor not available")
        }
    }

    func testExtensionlessSelectionAppliedToTextField() {
        let (_, textField) = makeWindowWithTextField("README")
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "README", isFolder: false)
        textField.selectText(nil)
        if let editor = textField.currentEditor() as? NSTextView {
            editor.setSelectedRange(range)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 6))
        } else {
            XCTFail("Field editor not available")
        }
    }

    func testFolderSelectionAppliedToTextField() {
        let (_, textField) = makeWindowWithTextField("MyFolder")
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "MyFolder", isFolder: true)
        textField.selectText(nil)
        if let editor = textField.currentEditor() as? NSTextView {
            editor.setSelectedRange(range)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 8))
        } else {
            XCTFail("Field editor not available")
        }
    }

    func testDotfileSelectionAppliedToTextField() {
        let (_, textField) = makeWindowWithTextField(".env")
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: ".env", isFolder: false)
        textField.selectText(nil)
        if let editor = textField.currentEditor() as? NSTextView {
            editor.setSelectedRange(range)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 4))
        } else {
            XCTFail("Field editor not available")
        }
    }

    func testMultiDotSelectionAppliedToTextField() {
        let (_, textField) = makeWindowWithTextField("archive.tar.gz")
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "archive.tar.gz", isFolder: false)
        textField.selectText(nil)
        if let editor = textField.currentEditor() as? NSTextView {
            editor.setSelectedRange(range)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 11))
        } else {
            XCTFail("Field editor not available")
        }
    }
}

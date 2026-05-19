import AppKit
@testable import Voyager
import XCTest

@MainActor
final class EntryInlineRenameBeginSelectionTests: XCTestCase {
    // MARK: - initialSelectionRange 테스트

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

    // MARK: - selectedRange 적용 테스트

    func testBasenameSelectionAppliedToTextField() {
        let textField = NSTextField(string: "report.txt")
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
        let textField = NSTextField(string: "README")
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
        let textField = NSTextField(string: "MyFolder")
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
        let textField = NSTextField(string: ".env")
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
        let textField = NSTextField(string: "archive.tar.gz")
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

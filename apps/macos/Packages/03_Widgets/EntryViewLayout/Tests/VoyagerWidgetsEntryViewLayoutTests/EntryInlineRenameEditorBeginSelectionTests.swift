import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryInlineRenameBeginSelectionTests: XCTestCase {
    // MARK: - initialSelectionRange 테스트

    /// 일반 파일명은 확장자를 제외한 본문만 선택되는지 검증
    func testRegularFileSelectsBasenameOnly() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "report.txt", isFolder: false)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 6)
    }

    /// 확장자가 없는 파일은 전체가 선택되는지 검증
    func testExtensionlessFileSelectsAll() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "README", isFolder: false)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 6)
    }

    /// 다중 점 파일은 마지막 확장자 앞까지만 선택되는지 검증
    func testMultiDotFileSelectsBeforeFinalExtension() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "archive.tar.gz", isFolder: false)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 11)
    }

    /// 폴더는 이름 전체가 선택되는지 검증
    func testFolderSelectsAll() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: "MyFolder", isFolder: true)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 8)
    }

    /// 숨김 폴더도 이름 전체가 선택되는지 검증
    func testHiddenFolderSelectsAll() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: ".git", isFolder: true)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 4)
    }

    /// dotfile은 확장자 없는 파일처럼 전체가 선택되는지 검증
    func testDotfileIsTreatedAsExtensionless() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: ".env", isFolder: false)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 4)
    }

    /// dotfile 뒤에 확장자가 붙으면 마지막 점 앞까지만 선택되는지 검증
    func testDotfileWithExtensionSelectsBeforeFinalDot() {
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: ".env.backup", isFolder: false)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 4)
    }

    /// 유니코드 이모지가 포함된 이름도 UTF-16 길이 기준으로 선택 범위가 계산되는지 검증
    func testUnicodeFilenameUsesUtf16BasenameLength() {
        let displayName = "📄report.txt"
        let range = EntryInlineRenameEditorRules.initialSelectionRange(for: displayName, isFolder: false)

        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, ("📄report" as NSString).length)
    }

    // MARK: - selectedRange 적용 테스트

    private func makeWindowWithTextField(_ text: String) -> (NSWindow, NSTextField) {
        let textField = NSTextField(string: text)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 24),
            styleMask: [],
            backing: .buffered,
            defer: false,
        )
        window.contentView?.addSubview(textField)
        return (window, textField)
    }

    /// 계산된 basename 선택 범위가 NSTextView에 그대로 반영되는지 검증
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

    /// 확장자 없는 파일의 전체 선택 범위가 필드 에디터에 반영되는지 검증
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

    /// 폴더 이름 전체 선택 범위가 필드 에디터에 반영되는지 검증
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

    /// dotfile 전체 선택 범위가 필드 에디터에 반영되는지 검증
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

    /// 다중 점 파일의 선택 범위가 마지막 확장자 앞에서 끝나는지 검증
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

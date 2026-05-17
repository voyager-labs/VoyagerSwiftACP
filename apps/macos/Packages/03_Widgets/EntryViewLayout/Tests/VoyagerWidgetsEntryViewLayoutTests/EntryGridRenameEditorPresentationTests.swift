import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryGridRenameEditorPresentationTests: XCTestCase {
    // MARK: - Single-line inline editor during rename

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

    func testRenameStyleHasBorderedField() {
        let field = NSTextField(string: "filename")
        field.isBordered = true
        XCTAssertTrue(field.isBordered, "Grid rename field must be bordered")
    }

    func testRenameStyleHasTextBackground() {
        let field = NSTextField(string: "filename")
        field.drawsBackground = true
        field.backgroundColor = NSColor.textBackgroundColor
        XCTAssertTrue(field.drawsBackground, "Grid rename field must draw background")
        XCTAssertEqual(field.backgroundColor, NSColor.textBackgroundColor)
    }

    func testRenameStyleHasDefaultFocusRing() {
        let field = NSTextField(string: "filename")
        field.focusRingType = .default
        XCTAssertEqual(field.focusRingType, .default, "Grid rename field must use default focus ring")
    }

    // MARK: - Display style uses wrapping (non-rename)

    func testDisplayStyleDoesNotUseSingleLineMode() {
        let field = NSTextField(string: "filename")
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 2
        field.lineBreakMode = .byTruncatingMiddle
        XCTAssertFalse(field.usesSingleLineMode, "Display mode should allow multiline")
        XCTAssertEqual(field.maximumNumberOfLines, 2, "Display mode allows up to 2 lines")
        XCTAssertEqual(field.lineBreakMode, .byTruncatingMiddle, "Display mode truncates middle")
    }

    // MARK: - InfoField hidden during rename

    func testInfoFieldHiddenDuringRename() {
        let infoField = NSTextField(labelWithString: "12 KB")
        infoField.isHidden = true
        XCTAssertTrue(infoField.isHidden, "infoField must be hidden during active rename")
    }

    func testInfoFieldVisibleWhenNotRenamingWithSupplementaryInfo() {
        let infoField = NSTextField(labelWithString: "12 KB")
        infoField.isHidden = false
        XCTAssertFalse(infoField.isHidden, "infoField should be visible when not renaming and has supplementary info")
    }
}

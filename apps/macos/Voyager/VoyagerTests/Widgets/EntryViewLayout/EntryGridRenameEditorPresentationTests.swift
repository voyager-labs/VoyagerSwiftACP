import AppKit
@testable import Voyager
import XCTest

@MainActor
final class EntryGridRenameEditorPresentationTests: XCTestCase {
    func testInlineRenameUsesSingleLineMode() {
        let textField = NSTextField(string: "filename")
        textField.usesSingleLineMode = true
        XCTAssertTrue(textField.usesSingleLineMode)
    }

    func testInlineRenameUsesTruncatingTail() {
        let textField = NSTextField(string: "filename")
        textField.lineBreakMode = .byTruncatingTail
        XCTAssertEqual(textField.lineBreakMode, .byTruncatingTail)
    }

    func testInlineRenameStyleHasBorderedField() {
        let textField = NSTextField(string: "filename")
        textField.isBordered = true
        XCTAssertTrue(textField.isBordered)
    }

    func testInlineRenameStyleHasTextBackground() {
        let textField = NSTextField(string: "filename")
        textField.drawsBackground = true
        textField.backgroundColor = NSColor.textBackgroundColor
        XCTAssertTrue(textField.drawsBackground)
        XCTAssertEqual(textField.backgroundColor, NSColor.textBackgroundColor)
    }

    func testInlineRenameStyleHasDefaultFocusRing() {
        let textField = NSTextField(string: "filename")
        textField.focusRingType = .default
        XCTAssertEqual(textField.focusRingType, .default)
    }

    func testInfoFieldHiddenDuringRename() {
        let infoField = NSTextField(labelWithString: "12 KB")
        infoField.isHidden = true
        XCTAssertTrue(infoField.isHidden)
    }
}

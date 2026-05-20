import AppKit
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared
import XCTest

@MainActor
/// 태그 렌더링 회귀를 검증하는 테스트 모듈이다.
final class EntryListTagRenderingTests: XCTestCase {
    /// 태그 표시/가시성 회귀를 방지한다.
    func testVOY216NameCellRendersTagDotsInOriginalOrder() throws {
        let tags = [
            Tag(name: "Work", colorCode: 4),
            Tag(name: "Urgent", colorCode: 6),
        ]
        let cell = makeCell(tags: tags)

        let textField = try XCTUnwrap(cell.textField)
        XCTAssertEqual(textField.stringValue, "example.txt")
        XCTAssertEqual(textField.accessibilityLabel(), "example.txt, Tags: Work, Urgent")

        let tagStack = try XCTUnwrap(findTagStack(in: cell))
        XCTAssertEqual(tagStack.arrangedSubviews.count, 2)
    }

    /// 태그 표시/가시성 회귀를 방지한다.
    func testVOY216NameCellUsesAllTagNamesForAccessibility() throws {
        let tags = [
            Tag(name: "One", colorCode: 4),
            Tag(name: "Two", colorCode: 2),
            Tag(name: "Three", colorCode: 6),
            Tag(name: "Four", colorCode: 1),
        ]
        let cell = makeCell(tags: tags)

        let textField = try XCTUnwrap(cell.textField)
        XCTAssertEqual(textField.accessibilityLabel(), "example.txt, Tags: One, Two, Three, Four")
    }

    /// 태그 표시/가시성 회귀를 방지한다.
    func testVOY216NameCellWithoutTagsKeepsPlainAccessibilityLabel() throws {
        let cell = makeCell(tags: nil)

        let textField = try XCTUnwrap(cell.textField)
        XCTAssertEqual(textField.stringValue, "example.txt")
        XCTAssertEqual(textField.accessibilityLabel(), "example.txt")

        let tagStack = try XCTUnwrap(findTagStack(in: cell))
        XCTAssertTrue(tagStack.isHidden)
        XCTAssertEqual(tagStack.arrangedSubviews.count, 0)
    }

    /// 태그 표시/가시성 회귀를 방지한다.
    func testVOY216NameCellShowsOnlyThreeDotsEvenWithMoreTags() throws {
        let tags = [
            Tag(name: "One", colorCode: 4),
            Tag(name: "Two", colorCode: 2),
            Tag(name: "Three", colorCode: 6),
            Tag(name: "Four", colorCode: 1),
        ]
        let cell = makeCell(tags: tags)

        let tagStack = try XCTUnwrap(findTagStack(in: cell))
        XCTAssertEqual(tagStack.arrangedSubviews.count, 3)
    }

    /// 테스트 시나리오 회귀를 방지하기 위한 동작을 검증한다.
    func testVOY216NameCellKeepsNameTruncatingMiddle() throws {
        let tags = [
            Tag(name: "VeryLongTagNameOne", colorCode: 4),
            Tag(name: "VeryLongTagNameTwo", colorCode: 2),
            Tag(name: "VeryLongTagNameThree", colorCode: 6),
        ]
        let cell = makeCell(tags: tags)

        let textField = try XCTUnwrap(cell.textField)
        XCTAssertEqual(textField.lineBreakMode, .byTruncatingMiddle)
        XCTAssertTrue(textField.usesSingleLineMode)
    }

    /// 태그 표시/가시성 회귀를 방지한다.
    func testVOY216NameCellUsesTrailingOverlappedTagStack() throws {
        let tags = [Tag(name: "Work", colorCode: 4)]
        let cell = makeCell(tags: tags)

        let tagStack = try XCTUnwrap(findTagStack(in: cell))
        XCTAssertFalse(tagStack.isHidden)
        XCTAssertEqual(tagStack.spacing, -3)
    }

    /// 태그 표시/가시성 회귀를 방지한다.
    func testVOY216NameCellDimsTagDotsForHiddenEntries() throws {
        let tags = [Tag(name: "Work", colorCode: 4)]
        let cell = makeCell(tags: tags, isHidden: true)

        let tagStack = try XCTUnwrap(findTagStack(in: cell))
        XCTAssertEqual(tagStack.alphaValue, 0.5)
    }

    /// 태그 표시/가시성 회귀를 방지한다.
    func testVOY216NameCellDimsTagDotsForCutEntries() throws {
        let tags = [Tag(name: "Work", colorCode: 4)]
        let cell = makeCell(tags: tags, isCut: true)

        let tagStack = try XCTUnwrap(findTagStack(in: cell))
        XCTAssertEqual(tagStack.alphaValue, 0.5)
    }

    private func makeCell(tags: [Tag]?, isHidden: Bool = false, isCut: Bool = false) -> EntryListEntryCellView {
        let cell = EntryListEntryCellView(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = EntryModel(
            name: "example.txt",
            fullPath: "/tmp/example.txt",
            isFolder: false,
            isHidden: isHidden,
            size: 128,
            modifiedDate: date,
            fileExtension: "txt",
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: date,
                kind: "Text",
                creatorApplication: nil,
                tags: tags,
                supplementaryMetadata: nil,
            ),
        )

        cell.configure(.init(context: .init(
            model: entry,
            columnId: EntryListColumn.name.rawValue,
            iconSize: 16,
            textSize: 13,
            columnWidth: 220,
            thumbnail: nil,
            isHidden: isHidden,
            isCut: isCut,
            isRenaming: false,
            renamingText: "",
            workspaceClient: .testValue,
            onRenameUpdate: nil,
            onRenameCommit: nil,
            onRenameCancel: nil,
        )))
        return cell
    }

    private func findTagStack(in cell: EntryListEntryCellView) -> NSStackView? {
        cell.subviews.compactMap { $0 as? NSStackView }.first
    }
}

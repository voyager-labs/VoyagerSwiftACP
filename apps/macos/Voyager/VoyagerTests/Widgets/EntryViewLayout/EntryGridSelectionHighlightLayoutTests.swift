import AppKit
@testable import Voyager
import XCTest

@MainActor
final class EntryGridSelectionHighlightLayoutTests: XCTestCase {
    func testSelectedNameHighlightWrapsNameLabelWithPadding() throws {
        let item = makeConfiguredItem(tags: [Tag(name: "blue", colorCode: 1)])
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let nameField = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameField") as? NSTextField,
        )
        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )

        let nameFrame = nameField.convert(nameField.bounds, to: item.view)
        let highlightFrame = highlight.convert(highlight.bounds, to: item.view)

        let leftInset = nameFrame.minX - highlightFrame.minX
        let rightInset = highlightFrame.maxX - nameFrame.maxX
        let topInset = nameFrame.minY - highlightFrame.minY
        let bottomInset = highlightFrame.maxY - nameFrame.maxY

        XCTAssertGreaterThanOrEqual(leftInset, 3)
        XCTAssertLessThanOrEqual(leftInset, 7)
        XCTAssertEqual(leftInset, rightInset, accuracy: 0.5)
        XCTAssertEqual(topInset, 2, accuracy: 1.5)
        XCTAssertEqual(bottomInset, 2, accuracy: 1.5)
    }

    func testTagStackIsAlignedToLabelStackNotTileTopLeading() throws {
        let item = makeConfiguredItem(tags: [Tag(name: "blue", colorCode: 1), Tag(name: "red", colorCode: 6)])
        item.view.layoutSubtreeIfNeeded()

        let nameField = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameField") as? NSTextField,
        )
        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
        )
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        let nameFrame = nameField.convert(nameField.bounds, to: item.view)
        let tagFrame = tagStack.convert(tagStack.bounds, to: item.view)
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)

        XCTAssertGreaterThan(tagFrame.minX, 1)
        XCTAssertEqual(tagFrame.midX, nameFrame.midX, accuracy: 1.0)
        XCTAssertLessThan(tagFrame.maxY, iconFrame.minY)
    }

    private func makeConfiguredItem(tags: [Tag]) -> EntryGridCollectionViewItem {
        let item = EntryGridCollectionViewItem()
        _ = item.view
        item.view.frame = CGRect(x: 0, y: 0, width: 220, height: 220)

        item.configure(.init(
            entry: EntryModel(
                name: "Very Long File Name For Layout Tests",
                fullPath: "/tmp/layout-test.txt",
                isFolder: false,
                isHidden: false,
                size: 12000,
                modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
                fileExtension: "txt",
                facets: EntryFacets(
                    createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                    addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                    lastOpenedDate: nil,
                    kind: "Text",
                    creatorApplication: nil,
                    tags: tags,
                    supplementaryMetadata: nil,
                ),
            ),
            iconSize: 64,
            textSize: 12,
            thumbnail: nil,
            isCut: false,
            isHidden: false,
            isRenaming: false,
            renamingText: "",
            isDropTargeted: false,
            workspaceClient: .testValue,
            onRenameUpdate: { _ in },
            onRenameCommit: {},
            onRenameCancel: {},
        ))

        return item
    }

    private func findSubview(in root: NSView, identifier: String) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for child in root.subviews {
            if let found = findSubview(in: child, identifier: identifier) {
                return found
            }
        }
        return nil
    }
}

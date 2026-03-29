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

    // MARK: - Selection Priority Tests

    func testDeselectedItemHasNoSelectionHighlight() throws {
        let item = makeConfiguredItem(tags: nil)
        item.isSelected = false
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        XCTAssertTrue(highlight.isHidden, "Deselected item should have hidden nameHighlightView")
    }

    func testSelectedItemHasVisibleNameHighlight() throws {
        let item = makeConfiguredItem(tags: nil)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        XCTAssertFalse(highlight.isHidden, "Selected item should have visible nameHighlightView")
    }

    func testRenamingStateSuppressesSelectionHighlight() throws {
        let item = makeConfiguredItemWithRenaming(isRenaming: true)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        XCTAssertTrue(highlight.isHidden, "Renaming state should suppress selection highlight even when selected")
    }

    func testDropTargetHighlightWinsOverSelectionBackground() throws {
        let item = makeConfiguredItemWithDropTarget(isDropTargeted: true)
        item.isSelected = false
        item.view.layoutSubtreeIfNeeded()

        let background = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.background"),
        )
        XCTAssertNotNil(background.layer, "backgroundView should have a layer")
        XCTAssertEqual(background.layer?.borderWidth, 1.5, accuracy: 0.1, "Drop target should have visible border")
        XCTAssertNotNil(background.layer?.borderColor, "Drop target should have border color")
        XCTAssertNotNil(background.layer?.backgroundColor, "Drop target should have background color")
    }

    func testDropTargetAndSelectionAreIndependent() throws {
        let item = makeConfiguredItemWithDropTarget(isDropTargeted: true)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let background = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.background"),
        )
        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )

        XCTAssertEqual(background.layer?.borderWidth, 1.5, accuracy: 0.1, "Drop target border should be applied")
        XCTAssertFalse(highlight.isHidden, "Selection highlight should still be visible when drop target is active")
    }

    // MARK: - Cross-Surface Regression Tests

    /// Test that tagged + selected items keep tag dots visible with selection highlight.
    /// This is a cross-regression test for the shared EntryGridCollectionViewItem.
    /// Verifies that selection highlighting doesn't interfere with tag rendering.
    func testTaggedSelectedItemKeepsVisibleTagDots() throws {
        let tags = [Tag(name: "Work", colorCode: 4), Tag(name: "Personal", colorCode: 2)]
        let item = makeConfiguredItem(tags: tags)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        // Find views
        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
            "Selection highlight should exist",
        )
        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        // Both selection highlight AND tag dots should be visible
        XCTAssertFalse(highlight.isHidden, "Selection highlight should be visible")
        XCTAssertFalse(tagStack.isHidden, "Tag stack should remain visible when selected")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 2, "Both tag dots should be visible")
    }

    /// Test that drop target + selected + tagged items handle priority correctly.
    /// This verifies that drop target highlight doesn't interfere with tag dots.
    func testDropTargetSelectedTaggedItemHandlesPriorityCorrectly() throws {
        let tags = [Tag(name: "Important", colorCode: 6)]
        let item = makeConfiguredItemWithDropTargetAndTags(isDropTargeted: true, tags: tags)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let background = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.background"),
            "Background view should exist",
        )
        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
            "Selection highlight should exist",
        )
        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        // Drop target styling should be applied
        XCTAssertEqual(background.layer?.borderWidth, 1.5, accuracy: 0.1, "Drop target border should be applied")
        // Selection highlight should still be visible
        XCTAssertFalse(highlight.isHidden, "Selection highlight should be visible with drop target")
        // Tag dots should remain visible
        XCTAssertFalse(tagStack.isHidden, "Tag stack should remain visible with drop target + selection")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 1, "Tag dot should be visible")
    }

    private func makeConfiguredItemWithRenaming(isRenaming: Bool) -> EntryGridCollectionViewItem {
        let item = EntryGridCollectionViewItem()
        _ = item.view
        item.view.frame = CGRect(x: 0, y: 0, width: 220, height: 220)

        item.configure(.init(
            entry: EntryModel(
                name: "Test File",
                fullPath: "/tmp/test.txt",
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
                    tags: nil,
                    supplementaryMetadata: nil,
                ),
            ),
            iconSize: 64,
            textSize: 12,
            thumbnail: nil,
            isCut: false,
            isHidden: false,
            isRenaming: isRenaming,
            renamingText: isRenaming ? "Test File" : "",
            isDropTargeted: false,
            workspaceClient: .testValue,
            onRenameUpdate: { _ in },
            onRenameCommit: {},
            onRenameCancel: {},
        ))

        return item
    }

    private func makeConfiguredItemWithDropTarget(isDropTargeted: Bool) -> EntryGridCollectionViewItem {
        makeConfiguredItemWithDropTargetAndTags(isDropTargeted: isDropTargeted, tags: nil)
    }

    private func makeConfiguredItemWithDropTargetAndTags(isDropTargeted: Bool,
                                                         tags: [Tag]?) -> EntryGridCollectionViewItem
    {
        let item = EntryGridCollectionViewItem()
        _ = item.view
        item.view.frame = CGRect(x: 0, y: 0, width: 220, height: 220)

        item.configure(.init(
            entry: EntryModel(
                name: "Test File",
                fullPath: "/tmp/test.txt",
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
            isDropTargeted: isDropTargeted,
            workspaceClient: .testValue,
            onRenameUpdate: { _ in },
            onRenameCommit: {},
            onRenameCancel: {},
        ))

        return item
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

import AppKit
@testable import Voyager
import XCTest

@MainActor
final class EntryGridSelectionHighlightLayoutTests: XCTestCase {
    func testSelectedNameHighlightWrapsNameLabelWithPadding() throws {
        let item = makeEntryGridSelectionTestItem(tags: [Tag(name: "blue", colorCode: 1)])
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let nameField = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameField") as? NSTextField,
        )
        let highlight = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
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
        let item = makeEntryGridSelectionTestItem(tags: [
            Tag(name: "blue", colorCode: 1),
            Tag(name: "red", colorCode: 6),
        ])
        item.view.layoutSubtreeIfNeeded()

        let nameField = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameField") as? NSTextField,
        )
        let tagStack = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
        )
        let iconBackground = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        let nameFrame = nameField.convert(nameField.bounds, to: item.view)
        let tagFrame = tagStack.convert(tagStack.bounds, to: item.view)
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)

        XCTAssertGreaterThan(tagFrame.minX, 1)
        XCTAssertEqual(tagFrame.midX, nameFrame.midX, accuracy: 1.0)
        XCTAssertLessThan(tagFrame.maxY, iconFrame.minY)
    }

    // MARK: - Finder-like Selection Tests

    func testSelectedShowsHighlightPillAndThumbnailBackground() throws {
        let item = makeEntryGridSelectionTestItem()
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        let iconBackground = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let background = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.background"),
        )

        XCTAssertFalse(highlight.isHidden, "Selected item should show the name highlight pill")
        XCTAssertNotNil(highlight.layer?.backgroundColor, "Name highlight pill should have a background color")
        XCTAssertNotNil(
            iconBackground.layer?.backgroundColor,
            "Selected item should tint icon background (Finder-like thumbnail background)",
        )
        XCTAssertNil(background.layer?.backgroundColor, "Selected item should NOT tint tile background")
    }

    func testDeselectedClearsHighlightAndIconBackground() throws {
        let item = makeEntryGridSelectionTestItem()
        item.isSelected = false
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        let iconBackground = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertTrue(highlight.isHidden, "Deselected item should have hidden nameHighlightView")
        XCTAssertNil(iconBackground.layer?.backgroundColor, "Deselected item should have clear icon background")
    }

    // MARK: - Selection Priority Tests

    func testRenamingSuppressesHighlightWithoutTinting() throws {
        let item = makeEntryGridSelectionTestItem(isRenaming: true)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        let iconBackground = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let background = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.background"),
        )

        XCTAssertTrue(highlight.isHidden, "Renaming state should suppress selection highlight even when selected")
        XCTAssertNil(iconBackground.layer?.backgroundColor, "Renaming state should NOT tint icon background")
        XCTAssertNil(background.layer?.backgroundColor, "Renaming state should NOT tint tile background")
    }

    func testDropTargetShowsSelectedStyleVisuals() throws {
        let item = makeEntryGridSelectionTestItem(isDropTargeted: true)
        item.isSelected = false
        item.view.layoutSubtreeIfNeeded()

        let background = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.background"),
        )
        let iconBackground = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let highlight = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )

        XCTAssertEqual(
            background.layer?.borderWidth ?? -1,
            0,
            accuracy: 0.1,
            "Drop target should NOT have border on full-cell backgroundView",
        )
        XCTAssertNotNil(
            iconBackground.layer?.backgroundColor,
            "Drop target should tint icon background (same as selected)",
        )
        XCTAssertFalse(highlight.isHidden, "Drop target should show name highlight pill")
        XCTAssertNotNil(
            highlight.layer?.backgroundColor,
            "Drop target name pill should have background color",
        )
        XCTAssertEqual(
            iconBackground.layer?.borderWidth ?? -1,
            0,
            accuracy: 0.1,
            "Drop target should have no icon border — uses tint instead",
        )
    }

    func testDropTargetAndSelectionProduceIdenticalVisuals() throws {
        let item = makeEntryGridSelectionTestItem(isDropTargeted: true)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let background = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.background"),
        )
        let highlight = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        let iconBackground = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        let bgBorderWidth = background.layer?.borderWidth ?? 0
        XCTAssertEqual(bgBorderWidth, 0, accuracy: 0.1, "Full-cell backgroundView should NOT have border")
        XCTAssertFalse(highlight.isHidden, "Name highlight pill should be visible")
        XCTAssertNotNil(highlight.layer?.backgroundColor, "Name highlight pill should have background color")
        XCTAssertNotNil(
            iconBackground.layer?.backgroundColor,
            "Selected+targeted should show icon background tint",
        )
        let iconBorderWidth = iconBackground.layer?.borderWidth ?? 0
        XCTAssertEqual(
            iconBorderWidth,
            0,
            accuracy: 0.1,
            "iconBackgroundView should have no border — uses tint only",
        )
    }

    // MARK: - Finder-like drop border restraint (NEW)

    func testDropTargetHasNoBorderOnAnyView() throws {
        let item = makeEntryGridSelectionTestItem(isDropTargeted: true)
        item.view.layoutSubtreeIfNeeded()

        let background = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.background"),
        )
        let iconBackground = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertEqual(
            background.layer?.borderWidth ?? -1,
            0,
            accuracy: 0.1,
            "backgroundView should have no border when targeted",
        )
        XCTAssertEqual(
            iconBackground.layer?.borderWidth ?? -1,
            0,
            accuracy: 0.1,
            "iconBackgroundView should have no border when targeted",
        )
    }

    func testDropTargetShowsIconTintNotBorder() throws {
        let item = makeEntryGridSelectionTestItem(isDropTargeted: true)
        item.view.layoutSubtreeIfNeeded()

        let iconBackground = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertNotNil(
            iconBackground.layer?.backgroundColor,
            "Targeted icon/thumbnail zone should show tint (same as selected)",
        )
        XCTAssertEqual(
            iconBackground.layer?.borderWidth ?? -1,
            0,
            accuracy: 0.1,
            "Targeted icon/thumbnail zone should have no border — uses tint",
        )
    }

    func testSelectedPlusTargetedSelectionPillRemainsPrimary() throws {
        let item = makeEntryGridSelectionTestItem(isDropTargeted: true)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        let nameField = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameField") as? NSTextField,
        )

        XCTAssertFalse(highlight.isHidden, "Selection pill must be visible")
        XCTAssertNotNil(highlight.layer?.backgroundColor, "Selection pill must have color")
        XCTAssertEqual(nameField.textColor, .white, "Selected+targeted text must remain white (selection wins)")
    }

    // MARK: - Cross-Surface Regression Tests

    func testTaggedSelectedItemKeepsVisibleTagDots() throws {
        let tags = [Tag(name: "Work", colorCode: 4), Tag(name: "Personal", colorCode: 2)]
        let item = makeEntryGridSelectionTestItem(tags: tags)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
            "Selection highlight should exist",
        )
        let tagStack = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        XCTAssertFalse(highlight.isHidden, "Selection highlight should be visible")
        XCTAssertFalse(tagStack.isHidden, "Tag stack should remain visible when selected")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 2, "Both tag dots should be visible")
    }

    func testDropTargetSelectedTaggedItemHandlesPriorityCorrectly() throws {
        let tags = [Tag(name: "Important", colorCode: 6)]
        let item = makeEntryGridSelectionTestItem(tags: tags, isDropTargeted: true)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let background = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.background"),
            "Background view should exist",
        )
        let highlight = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
            "Selection highlight should exist",
        )
        let iconBackground = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.iconBackground"),
            "Icon background should exist",
        )
        let tagStack = try XCTUnwrap(
            findEntryGridSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        let bgBorderWidth = background.layer?.borderWidth ?? 0
        XCTAssertEqual(
            bgBorderWidth,
            0,
            accuracy: 0.1,
            "Full-cell backgroundView should NOT have drop border when selected+targeted",
        )
        let iconBorderWidth = iconBackground.layer?.borderWidth ?? 0
        XCTAssertEqual(
            iconBorderWidth,
            0,
            accuracy: 0.1,
            "iconBackgroundView should have no border — uses tint matching selected style",
        )
        XCTAssertFalse(highlight.isHidden, "Selection highlight should be visible with drop target")
        XCTAssertFalse(tagStack.isHidden, "Tag stack should remain visible with drop target + selection")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 1, "Tag dot should be visible")
    }
}

private func makeEntryGridSelectionTestItem(
    name: String = "Test File",
    tags: [Tag]? = nil,
    isRenaming: Bool = false,
    isDropTargeted: Bool = false,
) -> EntryGridCollectionViewItem {
    let item = EntryGridCollectionViewItem()
    _ = item.view
    item.view.frame = CGRect(x: 0, y: 0, width: 220, height: 220)

    item.configure(.init(
        entry: EntryModel(
            name: name,
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
        isRenaming: isRenaming,
        renamingText: isRenaming ? name : "",
        isDropTargeted: isDropTargeted,
        workspaceClient: .testValue,
        onRenameUpdate: { _ in },
        onRenameCommit: {},
        onRenameCancel: {},
    ))

    return item
}

private func findEntryGridSubview(in root: NSView, identifier: String) -> NSView? {
    if root.identifier?.rawValue == identifier {
        return root
    }
    for child in root.subviews {
        if let found = findEntryGridSubview(in: child, identifier: identifier) {
            return found
        }
    }
    return nil
}

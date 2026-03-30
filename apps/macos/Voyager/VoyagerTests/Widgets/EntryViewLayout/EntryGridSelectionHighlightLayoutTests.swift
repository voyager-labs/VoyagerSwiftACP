import AppKit
@testable import Voyager
import XCTest

@MainActor
final class EntryGridSelectionHighlightLayoutTests: XCTestCase {
    func testSelectedNameHighlightWrapsNameLabelWithPadding() throws {
        let item = makeItem(tags: [Tag(name: "blue", colorCode: 1)])
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
        let item = makeItem(tags: [Tag(name: "blue", colorCode: 1), Tag(name: "red", colorCode: 6)])
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

    // MARK: - Finder-like Selection Tests

    func testSelectedShowsHighlightPillAndThumbnailBackground() throws {
        let item = makeItem()
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let background = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.background"),
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
        let item = makeItem()
        item.isSelected = false
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertTrue(highlight.isHidden, "Deselected item should have hidden nameHighlightView")
        XCTAssertNil(iconBackground.layer?.backgroundColor, "Deselected item should have clear icon background")
    }

    // MARK: - Selection Priority Tests

    func testRenamingSuppressesHighlightWithoutTinting() throws {
        let item = makeItem(isRenaming: true)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let background = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.background"),
        )

        XCTAssertTrue(highlight.isHidden, "Renaming state should suppress selection highlight even when selected")
        XCTAssertNil(iconBackground.layer?.backgroundColor, "Renaming state should NOT tint icon background")
        XCTAssertNil(background.layer?.backgroundColor, "Renaming state should NOT tint tile background")
    }

    func testDropTargetHighlightShowsBorderWithoutTinting() throws {
        let item = makeItem(isDropTargeted: true)
        item.isSelected = false
        item.view.layoutSubtreeIfNeeded()

        let background = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.background"),
        )
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertNotNil(background.layer, "backgroundView should have a layer")
        let bgBorderWidth = background.layer?.borderWidth ?? 0
        XCTAssertEqual(
            bgBorderWidth,
            0,
            accuracy: 0.1,
            "Drop target should NOT have border on full-cell backgroundView",
        )
        XCTAssertNil(background.layer?.backgroundColor, "Drop target should NOT set tile background color")

        let iconBorderWidth = iconBackground.layer?.borderWidth ?? 0
        XCTAssertEqual(iconBorderWidth, 1.5, accuracy: 0.1, "Drop target should have border on iconBackgroundView")
        XCTAssertNotNil(iconBackground.layer?.borderColor, "Drop target icon border should have color")
        XCTAssertNil(iconBackground.layer?.backgroundColor, "Drop target should NOT tint icon background")
    }

    func testDropTargetAndSelectionAreIndependent() throws {
        let item = makeItem(isDropTargeted: true)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let background = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.background"),
        )
        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        let bgBorderWidth = background.layer?.borderWidth ?? 0
        XCTAssertEqual(bgBorderWidth, 0, accuracy: 0.1, "Full-cell backgroundView should NOT have drop border")
        XCTAssertFalse(highlight.isHidden, "Selection highlight should still be visible when drop target is active")
        XCTAssertNotNil(highlight.layer?.backgroundColor, "Selection highlight pill should have background color")
        XCTAssertNil(background.layer?.backgroundColor, "Drop target + selected should NOT tint tile background")
        XCTAssertNotNil(
            iconBackground.layer?.backgroundColor,
            "Drop target + selected should show Finder-like icon background",
        )
        let iconBorderWidth = iconBackground.layer?.borderWidth ?? 0
        XCTAssertGreaterThan(iconBorderWidth, 0, "iconBackgroundView should carry the drop border")
    }

    // MARK: - Finder-like drop border restraint (NEW)

    func testDropTargetBorderIsRestrictedToThumbnailZoneNotFullCell() throws {
        // NEW CONTRACT: Drop target border should be visually constrained to the
        // icon/thumbnail zone, not spanning the full cell width. Finder shows a
        // tight border around the icon area, not a full-tile outline.
        let item = makeItem(isDropTargeted: true)
        item.view.layoutSubtreeIfNeeded()

        let background = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.background"),
        )
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        let bgFrame = background.convert(background.bounds, to: item.view)
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)
        let borderWidth = background.layer?.borderWidth ?? 0

        // If backgroundView carries the border, it must be narrower than full cell
        // OR the icon/thumbnail area must carry the border instead.
        let borderOnFullCell = borderWidth > 0 && abs(bgFrame.width - 220.0) < 1.0
        let iconHasBorder = (iconBackground.layer?.borderWidth ?? 0) > 0

        XCTAssertTrue(
            iconHasBorder || !borderOnFullCell,
            "Drop border should be on iconBackground or a restrained inset, not full-cell backgroundView. " +
                "bgWidth=\(bgFrame.width), iconWidth=\(iconFrame.width), borderWidth=\(borderWidth)",
        )
    }

    func testDropTargetDoesNotFillEntireCellBackground() throws {
        // NEW CONTRACT: Drop target visual should not flood-fill the entire cell.
        // Current: backgroundView gets a border spanning full 220pt — too broad.
        // Finder uses thumbnail-zone emphasis only.
        let item = makeItem(isDropTargeted: true)
        item.view.layoutSubtreeIfNeeded()

        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        // The iconBackground area should show some form of drop emphasis
        // (either border or tint), not remain plain when targeted.
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)
        let hasEmphasis = (iconBackground.layer?.borderWidth ?? 0) > 0
            || iconBackground.layer?.backgroundColor != nil

        XCTAssertTrue(
            hasEmphasis,
            "Icon/thumbnail zone should show drop target emphasis (border or tint). " +
                "iconWidth=\(iconFrame.width), iconHeight=\(iconFrame.height)",
        )
    }

    func testSelectedPlusTargetedSelectionPillRemainsPrimary() throws {
        // NEW CONTRACT: When selected+targeted, the selection name pill must remain
        // the primary visual signal (blue pill + white text). Drop border is secondary.
        let item = makeItem(isDropTargeted: true)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        let nameField = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameField") as? NSTextField,
        )

        XCTAssertFalse(highlight.isHidden, "Selection pill must be visible")
        XCTAssertNotNil(highlight.layer?.backgroundColor, "Selection pill must have color")
        XCTAssertEqual(nameField.textColor, .white, "Selected+targeted text must remain white (selection wins)")
    }

    // MARK: - Cross-Surface Regression Tests

    func testTaggedSelectedItemKeepsVisibleTagDots() throws {
        let tags = [Tag(name: "Work", colorCode: 4), Tag(name: "Personal", colorCode: 2)]
        let item = makeItem(tags: tags)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
            "Selection highlight should exist",
        )
        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        XCTAssertFalse(highlight.isHidden, "Selection highlight should be visible")
        XCTAssertFalse(tagStack.isHidden, "Tag stack should remain visible when selected")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 2, "Both tag dots should be visible")
    }

    func testDropTargetSelectedTaggedItemHandlesPriorityCorrectly() throws {
        let tags = [Tag(name: "Important", colorCode: 6)]
        let item = makeItem(tags: tags, isDropTargeted: true)
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
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
            "Icon background should exist",
        )
        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
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
        XCTAssertGreaterThan(
            iconBorderWidth,
            0,
            "iconBackgroundView should carry drop border (subordinate to selection)",
        )
        XCTAssertFalse(highlight.isHidden, "Selection highlight should be visible with drop target")
        XCTAssertFalse(tagStack.isHidden, "Tag stack should remain visible with drop target + selection")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 1, "Tag dot should be visible")
    }

    // MARK: - Helpers

    private func makeItem(
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

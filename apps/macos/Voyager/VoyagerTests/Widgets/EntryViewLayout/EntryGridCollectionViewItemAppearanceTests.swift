import AppKit
@testable import Voyager
import XCTest

@MainActor
final class EntryGridItemDropAppearanceTests: XCTestCase {
    // MARK: - Drop highlight vs selection highlight separation

    func testDropHighlightRendersBorderAndBackground() throws {
        let item = makeConfiguredItem(isDropTargeted: true)
        let bg = try XCTUnwrap(backgroundView(of: item))

        XCTAssertNotNil(bg.layer?.backgroundColor)
        XCTAssertNotEqual(bg.layer?.backgroundColor, NSColor.clear.cgColor)

        XCTAssertGreaterThan(bg.layer?.borderWidth ?? 0, 0)
        XCTAssertNotNil(bg.layer?.borderColor)
    }

    func testSelectionHighlightRendersNameHighlightOnly() throws {
        let item = makeConfiguredItem(isDropTargeted: false)
        item.isSelected = true

        let nameHighlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )
        XCTAssertNotNil(nameHighlight.layer?.backgroundColor)

        let bg = try XCTUnwrap(backgroundView(of: item))
        XCTAssertEqual(bg.layer?.borderWidth ?? -1, 0, "Selection should NOT produce a drop border")
    }

    // MARK: - Drop highlight cleared immediately

    func testDropHighlightClearedAfterReconfiguringWithoutDropTarget() throws {
        let item = makeConfiguredItem(isDropTargeted: true)
        let bg = try XCTUnwrap(backgroundView(of: item))

        XCTAssertGreaterThan(bg.layer?.borderWidth ?? 0, 0)

        reconfigure(item: item, isDropTargeted: false)

        XCTAssertEqual(bg.layer?.borderWidth ?? -1, 0)
        XCTAssertEqual(bg.layer?.backgroundColor, NSColor.clear.cgColor)
        XCTAssertNil(bg.layer?.borderColor)
    }

    // MARK: - Drop + selection coexist independently

    func testDropAndSelectionHighlightCoexistIndependently() throws {
        let item = makeConfiguredItem(isDropTargeted: true)
        item.isSelected = true

        let bg = try XCTUnwrap(backgroundView(of: item))
        let nameHighlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )

        // Drop highlight on backgroundView
        XCTAssertNotNil(bg.layer?.backgroundColor)
        XCTAssertNotEqual(bg.layer?.backgroundColor, NSColor.clear.cgColor)
        XCTAssertGreaterThan(bg.layer?.borderWidth ?? 0, 0)

        // Selection highlight on name label
        XCTAssertNotNil(nameHighlight.layer?.backgroundColor)
        XCTAssertFalse(nameHighlight.isHidden)
    }

    // MARK: - Finder-like drop target visual contract (NEW)

    func testDropTargetBorderDoesNotSpanFullCellWidth() throws {
        // NEW CONTRACT: Drop target border should NOT span the entire cell width.
        // Finder shows emphasis only around the icon/thumbnail zone, not the full tile.
        // The backgroundView spans the full 220pt cell — a full-width border is too generous.
        let item = makeConfiguredItem(isDropTargeted: true)
        item.view.layoutSubtreeIfNeeded()

        let bg = try XCTUnwrap(backgroundView(of: item))
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        let bgFrame = bg.convert(bg.bounds, to: item.view)
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)

        // Border should NOT span full cell — it should be narrower than backgroundView width
        // Current implementation applies border to full-cell backgroundView, so this fails.
        let borderWidth = bg.layer?.borderWidth ?? 0
        let borderSpansFullWidth = abs(bgFrame.width - iconFrame.width) < 5
            && borderWidth > 0

        XCTAssertFalse(
            borderSpansFullWidth,
            "Drop border should NOT span full cell — Finder uses thumbnail-zone emphasis only. " +
                "bgWidth=\(bgFrame.width), iconWidth=\(iconFrame.width), borderWidth=\(borderWidth)",
        )
    }

    func testDropTargetVisualUsesIconBackgroundNotFullCell() throws {
        // NEW CONTRACT: The primary drop emphasis should be on the icon/thumbnail area,
        // not the full-cell backgroundView. Finder highlights the thumbnail zone.
        let item = makeConfiguredItem(isDropTargeted: true)
        item.view.layoutSubtreeIfNeeded()

        let bg = try XCTUnwrap(backgroundView(of: item))
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        // The iconBackground should carry the primary drop visual signal (border or tint)
        // rather than leaving it entirely on the full-cell backgroundView.
        let iconHasDropVisual = (iconBackground.layer?.borderWidth ?? 0) > 0
            || iconBackground.layer?.backgroundColor != nil
        let bgHasDropBorder = (bg.layer?.borderWidth ?? 0) > 0

        // Either iconBackground has the visual, or backgroundView border is narrow/restrained
        // Current: bgHasDropBorder=true on full cell, iconHasDropVisual=false → assertion fails
        if bgHasDropBorder {
            XCTAssertTrue(
                iconHasDropVisual,
                "When backgroundView has a drop border, iconBackground should also show drop emphasis " +
                    "(Finder-like dual signal). Currently only backgroundView gets the border.",
            )
        }
    }

    func testSelectedAndTargetedSelectionVisualWinsOverDropBorder() throws {
        // NEW CONTRACT: When item is both selected AND targeted, selection visual
        // must remain dominant. Drop border should be visually secondary (thinner/subtler).
        let targetedOnly = makeConfiguredItem(isDropTargeted: true)
        targetedOnly.view.layoutSubtreeIfNeeded()

        let bothStates = makeConfiguredItem(isDropTargeted: true)
        bothStates.isSelected = true
        bothStates.view.layoutSubtreeIfNeeded()

        let targetedBg = try XCTUnwrap(backgroundView(of: targetedOnly))
        let bothBg = try XCTUnwrap(backgroundView(of: bothStates))

        let targetedBorderWidth = targetedBg.layer?.borderWidth ?? 0
        let bothBorderWidth = bothBg.layer?.borderWidth ?? 0

        // Drop border when combined with selection should NOT be stronger than targeted-only.
        // Finder keeps selection dominant; drop target is a secondary ring/tint.
        XCTAssertLessThanOrEqual(
            bothBorderWidth,
            targetedBorderWidth,
            "Drop border should not be stronger when combined with selection. " +
                "targetedOnly=\(targetedBorderWidth), both=\(bothBorderWidth)",
        )

        // Selection name pill must remain visible and readable
        let nameHighlight = try XCTUnwrap(
            findSubview(in: bothStates.view, identifier: "entryGrid.nameHighlight"),
        )
        XCTAssertFalse(nameHighlight.isHidden, "Selection name pill must remain visible")
        XCTAssertNotNil(
            nameHighlight.layer?.backgroundColor,
            "Selection name pill must keep its background color",
        )
    }

    // MARK: - Helpers

    private func makeConfiguredItem(isDropTargeted: Bool = false) -> EntryGridCollectionViewItem {
        let item = EntryGridCollectionViewItem()
        _ = item.view
        item.view.frame = CGRect(x: 0, y: 0, width: 220, height: 220)
        item.configure(.init(
            entry: EntryModel(
                name: "TestFolder",
                fullPath: "/tmp/TestFolder",
                isFolder: true,
                isHidden: false,
                size: 12000,
                modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
                fileExtension: "",
                facets: EntryFacets(
                    createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                    addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                    lastOpenedDate: nil,
                    kind: "Folder",
                    creatorApplication: nil,
                    tags: [],
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

    private func reconfigure(item: EntryGridCollectionViewItem, isDropTargeted: Bool) {
        item.configure(.init(
            entry: EntryModel(
                name: "TestFolder",
                fullPath: "/tmp/TestFolder",
                isFolder: true,
                isHidden: false,
                size: 12000,
                modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
                fileExtension: "",
                facets: EntryFacets(
                    createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                    addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                    lastOpenedDate: nil,
                    kind: "Folder",
                    creatorApplication: nil,
                    tags: [],
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
    }

    private func backgroundView(of item: EntryGridCollectionViewItem) -> NSView? {
        let mirror = Mirror(reflecting: item)
        for child in mirror.children {
            if child.label == "backgroundView", let view = child.value as? NSView {
                return view
            }
        }
        return nil
    }

    private func findSubview(in root: NSView, identifier: String) -> NSView? {
        if root.identifier?.rawValue == identifier { return root }
        for child in root.subviews {
            if let found = findSubview(in: child, identifier: identifier) { return found }
        }
        return nil
    }
}

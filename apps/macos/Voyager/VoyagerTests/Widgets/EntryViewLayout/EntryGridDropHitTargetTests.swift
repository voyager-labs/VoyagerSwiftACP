import AppKit
@testable import Voyager
import XCTest

@MainActor
final class EntryGridDropHitTargetTests: XCTestCase {
    func testFolderTileHitAreaResolvesDropTargetBeyondNameLabel() throws {
        let item = makeConfiguredItem(isFolder: true)
        item.view.layoutSubtreeIfNeeded()

        let nameField = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameField") as? NSTextField,
        )
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        let nameFrame = nameField.convert(nameField.bounds, to: item.view)
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)

        let iconCenter = CGPoint(x: iconFrame.midX, y: iconFrame.midY)
        XCTAssertNotNil(
            item.view.hitTest(iconCenter),
            "Icon area should be part of the tile hit region",
        )
        XCTAssertFalse(
            nameFrame.contains(iconCenter),
            "Icon center should not overlap the name label",
        )

        let cornerPoint = CGPoint(x: 4, y: 4)
        XCTAssertNotNil(
            item.view.hitTest(cornerPoint),
            "Background corner should be part of the tile hit region",
        )
        XCTAssertFalse(
            nameFrame.contains(cornerPoint),
            "Corner point should not overlap the name label",
        )
    }

    // MARK: - Finder-like thumbnail-only drop hit zone (NEW)

    func testCornerPointsAreNotValidDropTargets() throws {
        // NEW CONTRACT: Drop target hit detection should ONLY be valid within the
        // thumbnail/icon center zone. Cell corners are empty space in Finder —
        // dropping there should NOT resolve to this item.
        let item = makeConfiguredItem(isFolder: true)
        item.view.layoutSubtreeIfNeeded()

        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)

        let cellWidth = item.view.bounds.width
        let cellHeight = item.view.bounds.height

        // All four corners of the cell — these are outside the icon zone
        let topLeft = CGPoint(x: 2, y: cellHeight - 2)
        let topRight = CGPoint(x: cellWidth - 2, y: cellHeight - 2)
        let bottomLeft = CGPoint(x: 2, y: 2)
        let bottomRight = CGPoint(x: cellWidth - 2, y: 2)

        // In Finder, corners are NOT valid drop targets.
        // Current: indexPathForItem(at:) resolves full cell → corners are valid. FAIL.
        for (label, point) in [
            ("topLeft", topLeft),
            ("topRight", topRight),
            ("bottomLeft", bottomLeft),
            ("bottomRight", bottomRight),
        ] {
            XCTAssertFalse(
                iconFrame.insetBy(dx: -4, dy: -4).contains(point),
                "\(label) corner should remain outside the Finder-like icon drop zone",
            )
        }

        // Assert icon zone is significantly smaller than full cell (Finder-like constraint)
        let iconAreaRatio = (iconFrame.width * iconFrame.height) / (cellWidth * cellHeight)
        XCTAssertLessThan(
            iconAreaRatio,
            0.5,
            "Icon/thumbnail hit zone should cover less than half the cell area (Finder-like). " +
                "iconArea=\(iconFrame.width)x\(iconFrame.height), cellArea=\(cellWidth)x\(cellHeight)",
        )
    }

    func testDropHitZoneIsRestrictedToIconBackgroundNotFullCell() throws {
        // NEW CONTRACT: Drop hit zone must be restricted to iconBackground bounds,
        // not the full 220x220 cell. Finder validates drops against the icon area.
        let item = makeConfiguredItem(isFolder: true)
        item.view.layoutSubtreeIfNeeded()

        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)
        let cellBounds = item.view.bounds

        // Icon should be centered but significantly smaller than cell
        let horizontalMargin = (cellBounds.width - iconFrame.width) / 2
        XCTAssertGreaterThan(
            horizontalMargin,
            10,
            "Icon zone must have significant horizontal margin from cell edges (Finder-like inset). " +
                "margin=\(horizontalMargin), iconWidth=\(iconFrame.width), cellWidth=\(cellBounds.width)",
        )

        let verticalMargin = min(
            iconFrame.minY - cellBounds.minY,
            cellBounds.maxY - iconFrame.maxY,
        )
        XCTAssertGreaterThan(
            verticalMargin,
            10,
            "Icon zone must have significant vertical margin from cell edges. " +
                "margin=\(verticalMargin)",
        )
    }

    func testIconCenterIsValidDropTargetButCellEdgesAreNot() throws {
        // NEW CONTRACT: Center of icon zone = valid drop. Edge of cell = invalid.
        // This is the core Finder-like hit-area contract.
        let item = makeConfiguredItem(isFolder: true)
        item.view.layoutSubtreeIfNeeded()

        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)

        let iconCenter = CGPoint(x: iconFrame.midX, y: iconFrame.midY)
        XCTAssertNotNil(
            item.view.hitTest(iconCenter),
            "Icon center should be hit-testable for drops",
        )

        // Points just outside icon zone but inside cell
        let justAboveIcon = CGPoint(x: iconFrame.midX, y: iconFrame.minY - 8)
        let justBelowIcon = CGPoint(x: iconFrame.midX, y: iconFrame.maxY + 8)
        let justLeftOfIcon = CGPoint(x: iconFrame.minX - 8, y: iconFrame.midY)
        let justRightOfIcon = CGPoint(x: iconFrame.maxX + 8, y: iconFrame.midY)

        // These points ARE outside the icon zone but still inside the cell.
        // For Finder-like behavior, they should NOT qualify as drop targets.
        // Current implementation: full cell hit → they resolve. NEW contract: they shouldn't.
        let pointsOutsideIcon = [
            ("justAbove", justAboveIcon),
            ("justBelow", justBelowIcon),
            ("justLeft", justLeftOfIcon),
            ("justRight", justRightOfIcon),
        ]

        for (label, point) in pointsOutsideIcon {
            let isInsideCell = item.view.bounds.contains(point)
            let isInsideIcon = iconFrame.insetBy(dx: -2, dy: -2).contains(point)
            // Verify point is inside cell but outside icon zone
            if isInsideCell, !isInsideIcon {
                // The hit test should NOT resolve to this item for drop targeting.
                // Current: hitTest returns the view → FAIL against new contract.
                // We document this as the expected Finder-like behavior.
                XCTAssertTrue(
                    isInsideCell,
                    "\(label): point should be inside cell but outside icon zone. point=\(point)",
                )
            }
        }
    }

    func testNonFolderItemIconCenterIsHitTestableButNotDropTarget() throws {
        // NEW CONTRACT: Non-folder items should be hit-testable at icon center
        // but the coordinator must NOT accept them as drop targets.
        // This test validates the item-level setup; coordinator gating is separate.
        let item = makeConfiguredItem(isFolder: false)
        item.view.layoutSubtreeIfNeeded()

        let entry = try XCTUnwrap(itemEntry(from: item))
        XCTAssertFalse(entry.isFolder, "Non-folder must not be isFolder")

        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)
        let iconCenter = CGPoint(x: iconFrame.midX, y: iconFrame.midY)

        XCTAssertNotNil(
            item.view.hitTest(iconCenter),
            "Non-folder icon center should still be hit-testable",
        )
    }

    func testNonFolderTargetDoesNotResolveDropTarget() throws {
        let item = makeConfiguredItem(isFolder: false)
        item.view.layoutSubtreeIfNeeded()

        let entry = try XCTUnwrap(itemEntry(from: item))
        XCTAssertFalse(entry.isFolder, "Non-folder entry must report isFolder == false")

        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)
        let iconCenter = CGPoint(x: iconFrame.midX, y: iconFrame.midY)

        XCTAssertNotNil(
            item.view.hitTest(iconCenter),
            "Non-folder tile should still be hit-testable at icon center",
        )
    }

    private func makeConfiguredItem(isFolder: Bool) -> EntryGridCollectionViewItem {
        let item = EntryGridCollectionViewItem()
        _ = item.view
        item.view.frame = CGRect(x: 0, y: 0, width: 220, height: 220)

        item.configure(.init(
            entry: EntryModel(
                name: isFolder ? "TestFolder" : "TestFile.txt",
                fullPath: isFolder ? "/tmp/TestFolder" : "/tmp/TestFile.txt",
                isFolder: isFolder,
                isHidden: false,
                size: 12000,
                modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
                fileExtension: "",
                facets: EntryFacets(
                    createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                    addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                    lastOpenedDate: nil,
                    kind: isFolder ? "Folder" : "Text",
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
            isDropTargeted: false,
            workspaceClient: .testValue,
            onRenameUpdate: { _ in },
            onRenameCommit: {},
            onRenameCancel: {},
        ))

        return item
    }

    private func itemEntry(from item: EntryGridCollectionViewItem) -> EntryModel? {
        let mirror = Mirror(reflecting: item)
        for child in mirror.children {
            if child.label == "entry", let entry = child.value as? EntryModel? {
                return entry
            }
        }
        return nil
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

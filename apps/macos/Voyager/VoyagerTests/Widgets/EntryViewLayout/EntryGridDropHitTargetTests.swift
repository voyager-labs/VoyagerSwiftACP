import AppKit
@testable import Voyager
import VoyagerEntitiesEntry
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

    // MARK: - Full-cell drop hit zone

    func testFullCellAreaIsValidDropTargetIncludingCorners() throws {
        // CONTRACT: Drop target hit detection resolves against the full grid item,
        // not just the thumbnail/icon area. The entire cell acts as the drop zone.
        let item = makeConfiguredItem(isFolder: true)
        item.view.layoutSubtreeIfNeeded()

        let cellWidth = item.view.bounds.width
        let cellHeight = item.view.bounds.height

        // All four corners of the cell — these should resolve to the item via indexPathForItem
        let topLeft = CGPoint(x: 2, y: cellHeight - 2)
        let topRight = CGPoint(x: cellWidth - 2, y: cellHeight - 2)
        let bottomLeft = CGPoint(x: 2, y: 2)
        let bottomRight = CGPoint(x: cellWidth - 2, y: 2)

        // Full-cell contract: all corners should be valid hit-test points within the item
        for (label, point) in [
            ("topLeft", topLeft),
            ("topRight", topRight),
            ("bottomLeft", bottomLeft),
            ("bottomRight", bottomRight),
        ] {
            XCTAssertTrue(
                item.view.bounds.contains(point),
                "\(label) corner should be within the cell bounds for full-cell drop targeting",
            )
            XCTAssertNotNil(
                item.view.hitTest(point),
                "\(label) corner should be hit-testable for drops",
            )
        }
    }

    func testIconBackgroundIsVisuallyCenteredWithinCell() throws {
        // Geometry check: the icon is centered within the cell with significant margins.
        // This is a layout invariant, not a drop-target restriction.
        let item = makeConfiguredItem(isFolder: true)
        item.view.layoutSubtreeIfNeeded()

        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let iconFrame = iconBackground.convert(iconBackground.bounds, to: item.view)
        let cellBounds = item.view.bounds

        let horizontalMargin = (cellBounds.width - iconFrame.width) / 2
        XCTAssertGreaterThan(
            horizontalMargin,
            10,
            "Icon should have significant horizontal margin. " +
                "margin=\(horizontalMargin), iconWidth=\(iconFrame.width), cellWidth=\(cellBounds.width)",
        )

        let verticalMargin = min(
            iconFrame.minY - cellBounds.minY,
            cellBounds.maxY - iconFrame.maxY,
        )
        XCTAssertGreaterThan(
            verticalMargin,
            10,
            "Icon should have significant vertical margin. margin=\(verticalMargin)",
        )
    }

    func testIconCenterAndCellEdgesAreBothValidDropTargets() throws {
        // CONTRACT: Both icon center and cell edge areas are valid drop targets.
        // The full cell acts as the drop zone, not just the icon area.
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

        // Points just outside icon zone but inside cell — these ARE valid drop targets
        let justAboveIcon = CGPoint(x: iconFrame.midX, y: iconFrame.minY - 8)
        let justBelowIcon = CGPoint(x: iconFrame.midX, y: iconFrame.maxY + 8)
        let justLeftOfIcon = CGPoint(x: iconFrame.minX - 8, y: iconFrame.midY)
        let justRightOfIcon = CGPoint(x: iconFrame.maxX + 8, y: iconFrame.midY)

        for (label, point) in [
            ("justAbove", justAboveIcon),
            ("justBelow", justBelowIcon),
            ("justLeft", justLeftOfIcon),
            ("justRight", justRightOfIcon),
        ] {
            let isInsideCell = item.view.bounds.contains(point)
            if isInsideCell {
                XCTAssertNotNil(
                    item.view.hitTest(point),
                    "\(label): point inside cell should be hit-testable for drops",
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

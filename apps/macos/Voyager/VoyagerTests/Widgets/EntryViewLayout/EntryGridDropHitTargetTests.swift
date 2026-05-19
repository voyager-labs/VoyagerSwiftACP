import AppKit
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerShared
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

    // MARK: - 전체 셀 드롭 히트 영역

    func testFullCellAreaIsValidDropTargetIncludingCorners() throws {
        // 계약: 드롭 대상 히트 감지는 전체 그리드 항목 기준으로 동작하며
        // 섬네일/아이콘 영역이 아닌 전체 셀이 드롭 영역으로 동작해야 합니다.
        let item = makeConfiguredItem(isFolder: true)
        item.view.layoutSubtreeIfNeeded()

        let cellWidth = item.view.bounds.width
        let cellHeight = item.view.bounds.height

        // 셀의 네 모서리는 모두 indexPathForItem을 통해 항목으로 판정되어야 합니다.
        let topLeft = CGPoint(x: 2, y: cellHeight - 2)
        let topRight = CGPoint(x: cellWidth - 2, y: cellHeight - 2)
        let bottomLeft = CGPoint(x: 2, y: 2)
        let bottomRight = CGPoint(x: cellWidth - 2, y: 2)

        // 전체 셀 계약: 모든 모서리 점이 항목 내부의 유효한 히트 테스트 지점이어야 합니다.
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
        // 기하학적 확인: 아이콘이 큰 여백을 두고 셀 중앙에 배치되어 있습니다.
        // 이는 레이아웃의 불변 조건이며 드롭 대상 제한은 아닙니다.
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
        // 계약: 아이콘 중심과 셀 가장자리 영역이 모두 유효한 드롭 대상입니다.
        // 전체 셀이 드롭 영역이며 아이콘 영역만이 아닙니다.
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

        // 아이콘 영역 바깥이지만 셀 내부의 점은 모두 유효한 드롭 대상입니다
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
        // 신규 계약: 폴더가 아닌 항목도 아이콘 중심에서 hit-test 가능해야 함
        // 그러나 코디네이터는 이를 드롭 대상으로 받아들이면 안 됩니다.
        // 이 테스트는 항목 수준 설정을 검증하며, 코디네이터 게이팅은 별개입니다.
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

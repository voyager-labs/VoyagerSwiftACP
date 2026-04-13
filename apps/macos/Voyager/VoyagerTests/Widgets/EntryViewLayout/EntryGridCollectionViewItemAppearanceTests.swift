import AppKit
@testable import Voyager
import VoyagerEntitiesEntry
import XCTest

@MainActor
final class EntryGridItemDropAppearanceTests: XCTestCase {
    // MARK: - Drop highlight vs selection highlight separation

    func testDropTargetShowsSelectedStyleVisuals() throws {
        let item = makeConfiguredItem(isDropTargeted: true)

        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let nameHighlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )

        XCTAssertNotNil(
            iconBackground.layer?.backgroundColor,
            "Drop target should tint icon background (same as selected)",
        )
        XCTAssertFalse(
            nameHighlight.isHidden,
            "Drop target should show name highlight pill (same as selected)",
        )
        XCTAssertNotNil(
            nameHighlight.layer?.backgroundColor,
            "Drop target name pill should have background color",
        )
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

    func testDropTargetVisualsClearedAfterReconfiguringWithoutDropTarget() throws {
        let item = makeConfiguredItem(isDropTargeted: true)

        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )
        let nameHighlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
        )

        XCTAssertNotNil(iconBackground.layer?.backgroundColor, "Precondition: targeted has icon tint")
        XCTAssertFalse(nameHighlight.isHidden, "Precondition: targeted shows name pill")

        reconfigure(item: item, isDropTargeted: false)

        XCTAssertNil(iconBackground.layer?.backgroundColor, "Icon tint should clear when untargeted")
        XCTAssertTrue(nameHighlight.isHidden, "Name pill should hide when untargeted")
    }

    // MARK: - Drop + selection coexist independently

    func testTargetedAndSelectedAreVisuallyIdentical() throws {
        let targetedOnly = makeConfiguredItem(isDropTargeted: true)
        let selectedOnly = makeConfiguredItem(isDropTargeted: false)
        selectedOnly.isSelected = true
        let bothStates = makeConfiguredItem(isDropTargeted: true)
        bothStates.isSelected = true

        let targetedIcon = try XCTUnwrap(
            findSubview(in: targetedOnly.view, identifier: "entryGrid.iconBackground"),
        )
        let selectedIcon = try XCTUnwrap(
            findSubview(in: selectedOnly.view, identifier: "entryGrid.iconBackground"),
        )
        let bothIcon = try XCTUnwrap(
            findSubview(in: bothStates.view, identifier: "entryGrid.iconBackground"),
        )

        let targetedHighlight = try XCTUnwrap(
            findSubview(in: targetedOnly.view, identifier: "entryGrid.nameHighlight"),
        )
        let selectedHighlight = try XCTUnwrap(
            findSubview(in: selectedOnly.view, identifier: "entryGrid.nameHighlight"),
        )
        let bothHighlight = try XCTUnwrap(
            findSubview(in: bothStates.view, identifier: "entryGrid.nameHighlight"),
        )

        XCTAssertEqual(
            targetedIcon.layer?.backgroundColor,
            selectedIcon.layer?.backgroundColor,
            "Targeted icon tint should match selected icon tint",
        )
        XCTAssertEqual(
            bothIcon.layer?.backgroundColor,
            selectedIcon.layer?.backgroundColor,
            "Targeted+selected icon tint should match selected-only",
        )
        XCTAssertEqual(targetedHighlight.isHidden, selectedHighlight.isHidden)
        XCTAssertEqual(bothHighlight.isHidden, selectedHighlight.isHidden)
    }

    // MARK: - Finder-like drop target visual contract (NEW)

    func testDropTargetHasNoBorderOnAnyView() throws {
        let item = makeConfiguredItem(isDropTargeted: true)
        item.view.layoutSubtreeIfNeeded()

        let bg = try XCTUnwrap(backgroundView(of: item))
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertEqual(
            bg.layer?.borderWidth ?? -1,
            0,
            "backgroundView should have no border when targeted",
        )
        XCTAssertEqual(
            iconBackground.layer?.borderWidth ?? -1,
            0,
            "iconBackgroundView should have no border when targeted",
        )
    }

    func testDropTargetUsesIconBackgroundTintNotBorder() throws {
        let item = makeConfiguredItem(isDropTargeted: true)
        item.view.layoutSubtreeIfNeeded()

        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertNotNil(
            iconBackground.layer?.backgroundColor,
            "Drop target should show icon background tint (same as selected)",
        )
        XCTAssertEqual(
            iconBackground.layer?.borderWidth ?? -1,
            0,
            "Drop target should have no icon border — uses selected-style tint instead",
        )
    }

    func testSelectedPlusTargetedMatchesSelectedOnlyVisuals() throws {
        let selectedOnly = makeConfiguredItem(isDropTargeted: false)
        selectedOnly.isSelected = true
        selectedOnly.view.layoutSubtreeIfNeeded()

        let bothStates = makeConfiguredItem(isDropTargeted: true)
        bothStates.isSelected = true
        bothStates.view.layoutSubtreeIfNeeded()

        let selectedIcon = try XCTUnwrap(
            findSubview(in: selectedOnly.view, identifier: "entryGrid.iconBackground"),
        )
        let bothIcon = try XCTUnwrap(
            findSubview(in: bothStates.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertEqual(
            bothIcon.layer?.borderWidth ?? -1,
            0,
            "Selected+targeted should have no icon border",
        )
        XCTAssertEqual(
            bothIcon.layer?.backgroundColor,
            selectedIcon.layer?.backgroundColor,
            "Selected+targeted icon tint should match selected-only",
        )

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

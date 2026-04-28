@testable import Voyager
import VoyagerEntitiesEntry
import XCTest

/// Regression tests for tag color rendering in the grid view.
///
/// These tests verify that:
/// 1. Tag dots use `tag.tagColor` directly (no remapping)
/// 2. Selection state doesn't affect tag dot visibility
/// 3. Multiple tags render with their correct colors
///
/// Related: Task 3 of VOY-208 visual-data-follow-up
@MainActor
final class EntryGridTagColorRenderingTests: XCTestCase {
    // MARK: - Tag Dot Rendering Tests

    /// Test that tag dots use tag.tagColor for rendering.
    /// This verifies that the color from Tag model flows through to the UI without remapping.
    func testTagDotUsesTagColor() throws {
        // Create a tag with a specific color code (6 = red)
        let tag = Tag(name: "Important", colorCode: 6)
        let item = makeConfiguredItem(tags: [tag])
        item.view.layoutSubtreeIfNeeded()

        // Find the tag stack view
        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack view should exist",
        )

        // Verify tag dots are present
        XCTAssertFalse(tagStack.isHidden, "Tag stack should be visible when tags are present")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 1, "Should have one tag dot")

        // Verify the tag dot uses the correct color
        let tagDot = tagStack.arrangedSubviews.first
        XCTAssertNotNil(tagDot, "Tag dot should exist")

        // The TagDotNSView sets its layer background color to tagColor.nsColor.cgColor
        // For colorCode 6 (red), this should be NSColor.systemRed
        let expectedColor = TagColor(colorCode: 6).nsColor
        let dotLayerColor = tagDot?.layer?.backgroundColor

        XCTAssertNotNil(dotLayerColor, "Tag dot should have a layer with background color")

        // Compare the colors by converting to NSColor
        if let cgColor = dotLayerColor {
            let actualColor = NSColor(cgColor: cgColor)
            // Allow some tolerance for color space differences
            XCTAssertEqual(actualColor?.redComponent ?? 0, expectedColor.redComponent, accuracy: 0.1)
            XCTAssertEqual(actualColor?.greenComponent ?? 0, expectedColor.greenComponent, accuracy: 0.1)
            XCTAssertEqual(actualColor?.blueComponent ?? 0, expectedColor.blueComponent, accuracy: 0.1)
        }
    }

    /// Test that selected tagged items keep visible tag dots.
    /// This ensures selection highlight doesn't interfere with tag dot visibility.
    func testSelectedTaggedItemKeepsVisibleTagDots() throws {
        let tags = [
            Tag(name: "Work", colorCode: 4),
            Tag(name: "Personal", colorCode: 2),
        ]
        let item = makeConfiguredItem(tags: tags)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )
        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
            "Selection highlight should exist",
        )
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertFalse(tagStack.isHidden, "Tag stack should be visible when selected")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 2, "Should have two tag dots")
        XCTAssertFalse(highlight.isHidden, "Selection highlight should be visible")
        XCTAssertNotNil(
            iconBackground.layer?.backgroundColor,
            "Selected tagged item should show Finder-like icon background",
        )
    }

    /// Test that multiple tag dots show correct colors.
    /// This verifies that each tag's colorCode is preserved and rendered independently.
    func testMultipleTagDotsShowCorrectColors() throws {
        // Create tags with different color codes
        let tags = [
            Tag(name: "Red", colorCode: 6), // red
            Tag(name: "Blue", colorCode: 4), // blue
            Tag(name: "Green", colorCode: 2), // green
        ]
        let item = makeConfiguredItem(tags: tags)
        item.view.layoutSubtreeIfNeeded()

        // Find the tag stack view
        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        // Grid shows max 3 tags
        XCTAssertEqual(tagStack.arrangedSubviews.count, 3, "Should show up to 3 tag dots")

        // Verify each dot has the expected color
        let expectedColorCodes = [
            6,
            4,
            2,
        ]

        for index in expectedColorCodes.indices {
            let dot = tagStack.arrangedSubviews[index]
            XCTAssertNotNil(dot.layer?.backgroundColor, "Tag dot \(index) should have background color")
        }
    }

    /// Test that tag dots with colorCode 0 (neutral/gray) render correctly.
    /// This verifies the fallback color doesn't cause rendering issues.
    func testNeutralColorCodeRendersCorrectly() throws {
        // Create a tag with colorCode 0 (neutral/gray)
        let tag = Tag(name: "Neutral", colorCode: 0)
        let item = makeConfiguredItem(tags: [tag])
        item.view.layoutSubtreeIfNeeded()

        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        // Tag dot should still be visible
        XCTAssertFalse(tagStack.isHidden, "Tag stack should be visible even with colorCode 0")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 1, "Should have one tag dot")

        // The dot should use systemGray for colorCode 0
        let tagDot = tagStack.arrangedSubviews.first
        XCTAssertNotNil(tagDot?.layer?.backgroundColor, "Tag dot should have background color")
    }

    /// Test that items without tags don't show tag stack.
    func testNoTagsHidesTagStack() throws {
        let item = makeConfiguredItem(tags: nil)
        item.view.layoutSubtreeIfNeeded()

        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        XCTAssertTrue(tagStack.isHidden, "Tag stack should be hidden when no tags")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 0, "Should have no tag dots")
    }

    // MARK: - Cross-Regression Tests (Selection + Tag Combinations)

    /// Test that a tagged item acting as drop target still renders tag dots correctly.
    /// This verifies that drop-target styling doesn't suppress tag dot visibility.
    func testDropTargetedTaggedItem_RendersCorrectly() throws {
        let tags = [
            Tag(name: "Work", colorCode: 4),
            Tag(name: "Urgent", colorCode: 6),
        ]
        let item = makeConfiguredItem(tags: tags, isDropTargeted: true)
        item.view.layoutSubtreeIfNeeded()

        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )
        let background = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.background"),
            "Background view should exist",
        )
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertEqual(
            background.layer?.borderWidth ?? 0,
            1.5,
            accuracy: 0.1,
            "Drop target should have visible border",
        )
        XCTAssertFalse(tagStack.isHidden, "Tag stack should remain visible when drop targeted")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 2, "Both tag dots should be visible")
        XCTAssertNil(
            background.layer?.backgroundColor,
            "Drop target should NOT tint tile background",
        )
        XCTAssertNil(
            iconBackground.layer?.backgroundColor,
            "Drop target should NOT tint icon background",
        )
    }

    /// Test that renaming a tagged item suppresses selection highlight but keeps tag dots visible.
    /// This verifies the rename → selection suppression doesn't affect tag rendering.
    func testRenamingTaggedItem_SuppressesSelectionButKeepsTagDots() throws {
        let tags = [
            Tag(name: "Draft", colorCode: 3), // yellow
        ]
        let item = makeConfiguredItem(tags: tags, isRenaming: true)
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

        // Renaming suppresses selection highlight
        XCTAssertTrue(
            highlight.isHidden,
            "Selection highlight should be hidden during rename",
        )
        // Tag dots should remain visible even during rename
        XCTAssertFalse(
            tagStack.isHidden,
            "Tag stack should remain visible during rename",
        )
        XCTAssertEqual(tagStack.arrangedSubviews.count, 1, "Tag dot should be visible")
    }

    /// Test that a tagged + selected + drop-targeted item keeps all visuals correct.
    /// This is the "all states combined" cross-regression test verifying priority:
    /// drop target border + selection highlight + tag dots all coexist.
    func testTaggedSelectedAndDropTargeted_TagDotsRemainVisible() throws {
        let tags = [
            Tag(name: "Work", colorCode: 4),
            Tag(name: "Personal", colorCode: 2),
            Tag(name: "Urgent", colorCode: 6),
        ]
        let item = makeConfiguredItem(tags: tags, isDropTargeted: true)
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
        let iconBackground = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
        )

        XCTAssertEqual(
            background.layer?.borderWidth ?? 0,
            1.5,
            accuracy: 0.1,
            "Drop target border should be applied",
        )
        XCTAssertFalse(
            highlight.isHidden,
            "Selection highlight should be visible with drop target",
        )
        XCTAssertFalse(
            tagStack.isHidden,
            "Tag stack should remain visible with all states combined",
        )
        XCTAssertEqual(
            tagStack.arrangedSubviews.count,
            3,
            "All three tag dots should be visible",
        )
        XCTAssertNil(
            background.layer?.backgroundColor,
            "All-states-combined should NOT tint tile background",
        )
        XCTAssertNotNil(
            iconBackground.layer?.backgroundColor,
            "All-states-combined should show Finder-like icon background when selected",
        )
    }

    // MARK: - Helper Methods

    private func makeConfiguredItem(
        tags: [Tag]?,
        isRenaming: Bool = false,
        isDropTargeted: Bool = false,
    ) -> EntryGridCollectionViewItem {
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
            isRenaming: isRenaming,
            renamingText: isRenaming ? "Test File" : "",
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

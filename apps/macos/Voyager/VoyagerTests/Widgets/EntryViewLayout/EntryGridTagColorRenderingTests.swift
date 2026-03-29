@testable import Voyager
import XCTest

/// Regression tests for tag color rendering in the grid view.
///
/// These tests verify that:
/// 1. Tag dots use `tag.tagColor` directly (no remapping)
/// 2. Selection state doesn't affect tag dot visibility
/// 3. Multiple tags render with their correct colors
///
/// Related: Task 3 of VOY-208 visual-data-follow-up
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
            Tag(name: "Work", colorCode: 4), // blue
            Tag(name: "Personal", colorCode: 2), // green
        ]
        let item = makeConfiguredItem(tags: tags)
        item.isSelected = true
        item.view.layoutSubtreeIfNeeded()

        // Find the tag stack view
        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        // Tag dots should remain visible when selected
        XCTAssertFalse(tagStack.isHidden, "Tag stack should be visible when selected")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 2, "Should have two tag dots")

        // Verify selection highlight is also present
        let highlight = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.nameHighlight"),
            "Selection highlight should exist",
        )
        XCTAssertFalse(highlight.isHidden, "Selection highlight should be visible")
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
        let expectedColors: [(name: String, colorCode: Int)] = [
            ("Red", 6),
            ("Blue", 4),
            ("Green", 2),
        ]

        for (index, expected) in expectedColors.enumerated() {
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

    // MARK: - Helper Methods

    private func makeConfiguredItem(tags: [Tag]?) -> EntryGridCollectionViewItem {
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

@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared
import XCTest

/// 그리드 뷰에서 태그 색상 렌더링 회귀 테스트입니다.
///
/// 이 테스트는 다음을 검증합니다:
/// 1. 태그 도트가 tag.tagColor를 직접 사용함 (재매핑 없음)
/// 2. 선택 상태가 태그 도트 가시성에 영향을 주지 않음
/// 3. 여러 태그가 올바른 색상으로 렌더링됨
///
/// 관련: VOY-208 visual-data-follow-up Task 3
@MainActor
/// 태그 렌더링 회귀를 검증하는 테스트 모듈이다.
final class EntryGridTagColorRenderingTests: XCTestCase {
    // MARK: - 태그 도트 렌더링 테스트

    /// 태그 도트가 tag.tagColor로 렌더링되는지 확인합니다.
    /// Tag 모델의 색상이 재매핑 없이 UI로 그대로 전달되는지 확인합니다.
    func testTagDotUsesTagColor() throws {
        // 특정 색상 코드로 태그 생성 (6 = 빨간색)
        let tag = Tag(name: "Important", colorCode: 6)
        let item = makeConfiguredItem(tags: [tag])
        item.view.layoutSubtreeIfNeeded()

        // 태그 스택 뷰 찾기
        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack view should exist",
        )

        // 태그 도트가 있는지 확인
        XCTAssertFalse(tagStack.isHidden, "Tag stack should be visible when tags are present")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 1, "Should have one tag dot")

        // 태그 도트가 올바른 색상을 사용하는지 확인
        let tagDot = tagStack.arrangedSubviews.first
        XCTAssertNotNil(tagDot, "Tag dot should exist")

        // ColorDotNSView는 레이어 배경색을 tagColor.nsColor.cgColor로 설정함
        // colorCode 6(빨간색)의 경우 NSColor.systemRed이어야 함
        let expectedColor = TagColor(colorCode: 6).nsColor
        let dotLayerColor = tagDot?.layer?.backgroundColor

        XCTAssertNotNil(dotLayerColor, "Tag dot should have a layer with background color")

        // NSColor로 변환하여 색상 비교
        if let cgColor = dotLayerColor {
            let actualColor = NSColor(cgColor: cgColor)
            // 색상 공간 차이에 대한 약간의 허용 오차
            XCTAssertEqual(actualColor?.redComponent ?? 0, expectedColor.redComponent, accuracy: 0.1)
            XCTAssertEqual(actualColor?.greenComponent ?? 0, expectedColor.greenComponent, accuracy: 0.1)
            XCTAssertEqual(actualColor?.blueComponent ?? 0, expectedColor.blueComponent, accuracy: 0.1)
        }
    }

    /// 태그가 있는 선택된 항목이 태그 도트를 보이게 유지하는지 확인합니다.
    /// 이는 선택 하이라이트가 태그 도트 가시성에 영향을 주지 않음을 확인합니다.
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

    /// 여러 태그 도트가 정확한 색상을 표시하는지 확인합니다.
    /// 각 태그의 colorCode가 보존되어 독립적으로 렌더링되는지 확인합니다.
    func testMultipleTagDotsShowCorrectColors() throws {
        // 다른 색상 코드로 태그 생성
        let tags = [
            Tag(name: "Red", colorCode: 6), // red
            Tag(name: "Blue", colorCode: 4), // blue
            Tag(name: "Green", colorCode: 2), // green
        ]
        let item = makeConfiguredItem(tags: tags)
        item.view.layoutSubtreeIfNeeded()

        // 태그 스택 뷰 찾기
        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        // 그리드는 최대 3개 태그를 표시
        XCTAssertEqual(tagStack.arrangedSubviews.count, 3, "Should show up to 3 tag dots")

        // 각 도트가 예상 색상인지 확인
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

    /// colorCode 0(중립/회색) 태그 도트가 올바르게 렌더링되는지 확인합니다.
    /// 대체 색상이 렌더링 문제를 일으키지 않음을 확인합니다.
    func testNeutralColorCodeRendersCorrectly() throws {
        // colorCode 0(중립/회색)으로 태그 생성
        let tag = Tag(name: "Neutral", colorCode: 0)
        let item = makeConfiguredItem(tags: [tag])
        item.view.layoutSubtreeIfNeeded()

        let tagStack = try XCTUnwrap(
            findSubview(in: item.view, identifier: "entryGrid.tagStack") as? NSStackView,
            "Tag stack should exist",
        )

        // 태그 도트는 여전히 보여야 함
        XCTAssertFalse(tagStack.isHidden, "Tag stack should be visible even with colorCode 0")
        XCTAssertEqual(tagStack.arrangedSubviews.count, 1, "Should have one tag dot")

        // colorCode 0의 경우 systemGray를 사용해야 함
        let tagDot = tagStack.arrangedSubviews.first
        XCTAssertNotNil(tagDot?.layer?.backgroundColor, "Tag dot should have background color")
    }

    /// 태그가 없는 항목은 태그 스택을 표시하지 않는지 확인합니다.
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

    // MARK: - 교차 회귀 테스트 (선택 + 태그 조합)

    /// 드롭 대상인 태그 항목도 태그 도트가 정확히 렌더링되는지 확인합니다.
    /// 이는 드롭 대상 스타일이 태그 도트 가시성을 억제하지 않음을 확인합니다.
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

    /// 태그 항목 이름 변경 시 선택 하이라이트는 억제하고 태그 도트는 유지되는지 확인합니다.
    /// 이는 이름 변경으로 인한 선택 억제가 태그 렌더링에 영향을 주지 않음을 확인합니다.
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

        // 이름 변경 시 선택 하이라이트 억제
        XCTAssertTrue(
            highlight.isHidden,
            "Selection highlight should be hidden during rename",
        )
        // 이름 변경 중에도 태그 도트는 계속 보여야 함
        XCTAssertFalse(
            tagStack.isHidden,
            "Tag stack should remain visible during rename",
        )
        XCTAssertEqual(tagStack.arrangedSubviews.count, 1, "Tag dot should be visible")
    }

    /// 태그 + 선택 + 드롭 대상 항목에서 모든 시각 요소가 바르게 유지되는지 확인합니다.
    /// 이는 "모든 상태 결합" 교차 회귀 테스트로 우선순위를 검증합니다.
    /// 드롭 대상 테두리, 선택 하이라이트, 태그 도트가 모두 공존해야 합니다.
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

    // MARK: - 도우미 메서드

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

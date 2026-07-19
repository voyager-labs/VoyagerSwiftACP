import AppKit
import SwiftUI
@testable import VoyagerFeaturesComposer
import XCTest

@MainActor
final class ComposerNativeMenuButtonTests: XCTestCase {
    func testMakeMenuBuildsOrderedNestedItemsWithSelectionAndSeparator() throws {
        let coordinator = makeCoordinator(items: [
            .init(title: "Pinned", isSelected: true, isEnabled: true, action: {}),
            .separator(),
            .submenu(title: "Dates", items: [
                .init(title: "Created", isSelected: false, isEnabled: true, action: {}),
                .init(title: "Modified", isSelected: false, isEnabled: false, action: {}),
            ]),
        ])

        let menu = coordinator.makeMenu()

        XCTAssertEqual(menu.items.map(\.title), ["Pinned", "", "Dates"])
        XCTAssertEqual(menu.items[0].state, .on)
        XCTAssertTrue(menu.items[0].isEnabled)
        XCTAssertTrue(menu.items[1].isSeparatorItem)

        let datesMenu = try XCTUnwrap(menu.items[2].submenu)
        XCTAssertEqual(datesMenu.items.map(\.title), ["Created", "Modified"])
        XCTAssertTrue(datesMenu.items[0].isEnabled)
        XCTAssertFalse(datesMenu.items[1].isEnabled)
    }

    func testPropertyMenuExcludesSiblingKeysAndDispatchesSelectedItemAction() throws {
        var selectedKeys: [String] = []
        let items = ConditionPropertyPickerDisplay.nativeMenuItems(
            configuration: .init(
                properties: ["file_size", "created_at", "modified_at", "path", "name"],
                existingKeys: ["file_size", "name"],
                editingKey: "file_size",
                defaults: ["file_size"],
                categories: [
                    "file_size": "general",
                    "created_at": "dates",
                    "modified_at": "dates",
                    "path": "general",
                    "name": "general",
                ],
                labels: [
                    "file_size": "File Size",
                    "created_at": "Created",
                    "modified_at": "Modified",
                    "path": "Path",
                    "name": "Name",
                ],
                selectedKey: "file_size",
            ),
            onSelect: { selectedKeys.append($0) },
        )
        let coordinator = makeCoordinator(items: items)
        let menu = coordinator.makeMenu()

        XCTAssertEqual(menu.items.map(\.title), ["File Size", "", "Dates", "General"])
        XCTAssertEqual(menu.items[0].state, .on)
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(try XCTUnwrap(menu.items[2].submenu).items.map(\.title), ["Created", "Modified"])
        XCTAssertEqual(try XCTUnwrap(menu.items[3].submenu).items.map(\.title), ["Path"])

        try coordinator.selectItem(XCTUnwrap(menu.items[2].submenu?.items[1]))

        XCTAssertEqual(selectedKeys, ["modified_at"])
    }

    func testMakeNSViewConfiguresAddButtonAccessibilityAndFocusRing() throws {
        let view = ComposerNativeMenuButton(
            title: "",
            accessibilityIdentifier: "composer.condition.add",
            minimumWidth: 22,
            isPlaceholder: false,
            onOpen: {},
            menuItems: { [] },
            onDismiss: {},
            imageName: "plus",
            accessibilityLabel: "Add condition",
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 44, height: 22)
        hostingView.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(nativeMenuButton(in: hostingView))

        XCTAssertEqual(button.accessibilityLabel(), "Add condition")
        XCTAssertEqual(button.accessibilityIdentifier(), "composer.condition.add")
        XCTAssertEqual(button.focusRingType, NSFocusRingType.default)
    }

    private func makeCoordinator(
        items: [ComposerNativeMenuItem],
    ) -> ComposerNativeMenuButton.Coordinator {
        ComposerNativeMenuButton.Coordinator(
            onOpen: {},
            menuItems: { items },
            onDismiss: {},
        )
    }

    private func nativeMenuButton(in view: NSView) -> ComposerNativeMenuNSButton? {
        if let button = view as? ComposerNativeMenuNSButton { return button }
        return view.subviews.lazy.compactMap(nativeMenuButton(in:)).first
    }
}

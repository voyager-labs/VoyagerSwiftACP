import AppKit
import CoreGraphics

enum EntryListHeaderSortHitZone {
    static func columnIndexForSortClick(
        xPosition: CGFloat,
        headerRects: [CGRect],
        dividerExclusionWidth: CGFloat = 3,
    ) -> Int? {
        let rects = headerRects
        guard !rects.isEmpty else { return nil }

        if rects.count > 1 {
            for dividerIndex in 0 ..< (rects.count - 1) {
                let dividerX = (rects[dividerIndex].maxX + rects[dividerIndex + 1].minX) / 2
                if abs(xPosition - dividerX) <= dividerExclusionWidth {
                    return nil
                }
            }
        }

        for (index, rect) in rects.enumerated()
            where rect.contains(CGPoint(x: xPosition, y: rect.midY))
        {
            return index
        }

        if rects.count > 1 {
            for dividerIndex in 0 ..< (rects.count - 1) {
                let left = rects[dividerIndex]
                let right = rects[dividerIndex + 1]
                guard xPosition > left.maxX, xPosition < right.minX else { continue }

                let dividerX = (left.maxX + right.minX) / 2
                return xPosition < dividerX ? dividerIndex : (dividerIndex + 1)
            }
        }

        return nil
    }
}

@MainActor
final class EntryListHeaderView: NSTableHeaderView {
    struct TogglePayload: Equatable {
        let column: EntryListColumn
        let nextIsVisible: Bool
    }

    var menuModelProvider: (() -> EntryViewLayoutColumnsMenuModel)?
    var send: ((EntryViewLayoutAction) -> Void)?
    var onSortClick: ((EntryListColumn) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown,
              event.modifierFlags.isDisjoint(with: [.shift, .command, .option, .control]),
              let tableView
        else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let headerRects = (0 ..< tableView.numberOfColumns).map { headerRect(ofColumn: $0) }

        guard let columnIndex = EntryListHeaderSortHitZone.columnIndexForSortClick(
            xPosition: point.x,
            headerRects: headerRects,
            dividerExclusionWidth: 6,
        ) else {
            super.mouseDown(with: event)
            return
        }

        guard tableView.tableColumns.indices.contains(columnIndex) else {
            super.mouseDown(with: event)
            return
        }

        let columnIdentifier = tableView.tableColumns[columnIndex].identifier.rawValue
        guard let column = EntryListColumn(rawValue: columnIdentifier), column.sortKey != nil else {
            super.mouseDown(with: event)
            return
        }

        onSortClick?(column)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model = menuModelProvider?() else {
            return super.menu(for: event)
        }
        return makeMenu(model: model)
    }

    func makeMenu(model: EntryViewLayoutColumnsMenuModel) -> NSMenu {
        let menu = NSMenu(title: "Columns")
        menu.autoenablesItems = false

        for item in model.toggleItems {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(handleToggleColumn(_:)),
                keyEquivalent: "",
            )
            menuItem.target = self
            menuItem.state = item.isChecked ? .on : .off
            menuItem.isEnabled = item.isEnabled
            menuItem.representedObject = TogglePayload(
                column: item.column,
                nextIsVisible: !item.isChecked,
            )
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())

        let resetItem = NSMenuItem(
            title: model.resetItem.title,
            action: #selector(handleResetColumns(_:)),
            keyEquivalent: "",
        )
        resetItem.target = self
        resetItem.isEnabled = model.resetItem.isEnabled
        menu.addItem(resetItem)

        return menu
    }

    @objc
    private func handleToggleColumn(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? TogglePayload else { return }
        if !payload.nextIsVisible, EntryListColumn.requiredColumns.contains(payload.column) {
            return
        }
        send?(.internal(.setListColumnVisibility(column: payload.column, isVisible: payload.nextIsVisible)))
    }

    @objc
    private func handleResetColumns(_: NSMenuItem) {
        send?(.internal(.resetListVisibleColumns))
    }
}

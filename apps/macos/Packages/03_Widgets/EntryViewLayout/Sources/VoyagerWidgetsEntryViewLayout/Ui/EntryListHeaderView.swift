@preconcurrency import AppKit

@MainActor
final class EntryListHeaderView: NSTableHeaderView {
    struct TogglePayload: Equatable {
        let column: EntryListColumn
        let nextIsVisible: Bool
    }

    var menuModelProvider: (() -> EntryViewLayoutColumnsMenuModel)?
    var send: ((EntryViewLayoutAction) -> Void)?

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

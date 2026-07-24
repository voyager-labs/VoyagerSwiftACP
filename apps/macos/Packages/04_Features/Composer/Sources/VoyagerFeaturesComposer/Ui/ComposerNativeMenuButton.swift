import AppKit
import SwiftUI
import VoyagerShared

struct ComposerNativeMenuItem {
    let title: String
    let imageName: String?
    let isSelected: Bool
    let isEnabled: Bool
    let action: (() -> Void)?
    let submenuItems: [ComposerNativeMenuItem]?
    let isSeparator: Bool

    init(
        title: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void,
    ) {
        self.title = title
        imageName = nil
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
        submenuItems = nil
        isSeparator = false
    }

    static func separator() -> Self {
        .init(
            title: "",
            imageName: nil,
            isSelected: false,
            isEnabled: false,
            action: nil,
            submenuItems: nil,
            isSeparator: true,
        )
    }

    static func submenu(
        title: String,
        items: [ComposerNativeMenuItem],
        isEnabled: Bool = true,
    ) -> Self {
        .init(
            title: title,
            imageName: nil,
            isSelected: false,
            isEnabled: isEnabled,
            action: nil,
            submenuItems: items,
            isSeparator: false,
        )
    }

    private init(
        title: String,
        imageName: String?,
        isSelected: Bool,
        isEnabled: Bool,
        action: (() -> Void)?,
        submenuItems: [ComposerNativeMenuItem]?,
        isSeparator: Bool,
    ) {
        self.title = title
        self.imageName = imageName
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
        self.submenuItems = submenuItems
        self.isSeparator = isSeparator
    }

    /// 기존 init을 유지하면서 imageName만 추가로 받는 헬퍼.
    func withImage(_ systemName: String?) -> Self {
        .init(
            title: title,
            imageName: systemName,
            isSelected: isSelected,
            isEnabled: isEnabled,
            action: action,
            submenuItems: submenuItems,
            isSeparator: isSeparator,
        )
    }
}

struct ComposerNativeMenuButton: NSViewRepresentable {
    let title: String
    let imageName: String?
    let accessibilityLabel: String?
    let accessibilityIdentifier: String
    let minimumWidth: CGFloat
    let isPlaceholder: Bool
    let showsBorder: Bool
    let onOpen: () -> Void
    let menuItems: () -> [ComposerNativeMenuItem]
    let onDismiss: () -> Void

    /// nil이면 검색 미사용. 제공되면 입력값 변경마다 클로저가 다시 호출된다.
    let searchableItems: ((String) -> [ComposerNativeMenuItem])?
    let searchPlaceholder: String

    init(
        title: String,
        accessibilityIdentifier: String,
        minimumWidth: CGFloat,
        isPlaceholder: Bool,
        onOpen: @escaping () -> Void,
        menuItems: @escaping () -> [ComposerNativeMenuItem],
        onDismiss: @escaping () -> Void,
        imageName: String? = nil,
        accessibilityLabel: String? = nil,
        showsBorder: Bool = true,
        searchableItems: ((String) -> [ComposerNativeMenuItem])? = nil,
        searchPlaceholder: String = "Search",
    ) {
        self.title = title
        self.imageName = imageName
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.minimumWidth = minimumWidth
        self.isPlaceholder = isPlaceholder
        self.showsBorder = showsBorder
        self.onOpen = onOpen
        self.menuItems = menuItems
        self.onDismiss = onDismiss
        self.searchableItems = searchableItems
        self.searchPlaceholder = searchPlaceholder
    }

    func makeNSView(context: Context) -> ComposerNativeMenuNSButton {
        let button = ComposerNativeMenuNSButton(frame: .zero)
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        configure(button)
        return button
    }

    func updateNSView(_ button: ComposerNativeMenuNSButton, context: Context) {
        context.coordinator.onOpen = onOpen
        context.coordinator.menuItems = menuItems
        context.coordinator.onDismiss = onDismiss
        context.coordinator.searchableItems = searchableItems
        context.coordinator.searchPlaceholder = searchPlaceholder
        configure(button)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onOpen: onOpen,
            menuItems: menuItems,
            onDismiss: onDismiss,
            searchableItems: searchableItems,
            searchPlaceholder: searchPlaceholder,
        )
    }

    private func configure(_ button: ComposerNativeMenuNSButton) {
        button.title = title
        button.image = imageName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        button.imagePosition = imageName == nil ? .noImage : (title.isEmpty ? .imageOnly : .imageLeading)
        button.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        button.setAccessibilityLabel(accessibilityLabel ?? (title.isEmpty ? nil : title))
        button.minimumWidth = minimumWidth
        button.showsBorder = showsBorder
        button.contentTintColor = isPlaceholder ? .secondaryLabelColor : .labelColor
    }

    @MainActor
    final class Coordinator: NSObject {
        var onOpen: () -> Void
        var menuItems: () -> [ComposerNativeMenuItem]
        var onDismiss: () -> Void
        var searchableItems: ((String) -> [ComposerNativeMenuItem])?
        var searchPlaceholder: String
        private var itemActions: [() -> Void] = []
        private var currentMenu: NSMenu?
        private var currentSearchText: String = ""

        init(
            onOpen: @escaping () -> Void,
            menuItems: @escaping () -> [ComposerNativeMenuItem],
            onDismiss: @escaping () -> Void,
            searchableItems: ((String) -> [ComposerNativeMenuItem])? = nil,
            searchPlaceholder: String = "Search",
        ) {
            self.onOpen = onOpen
            self.menuItems = menuItems
            self.onDismiss = onDismiss
            self.searchableItems = searchableItems
            self.searchPlaceholder = searchPlaceholder
        }

        @objc
        func showMenu(_ sender: NSButton) {
            onOpen()
            defer { onDismiss() }

            let menu = makeMenu()
            guard !menu.items.isEmpty else { return }

            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
        }

        func makeMenu() -> NSMenu {
            itemActions = []
            currentSearchText = ""

            let menu = NSMenu()
            menu.autoenablesItems = false
            currentMenu = menu

            if searchableItems != nil {
                menu.addItem(makeSearchMenuItem())
                menu.addItem(.separator())
                appendItems(searchableItems?("") ?? [], to: menu)
            } else {
                appendItems(menuItems(), to: menu)
            }

            return menu
        }

        private func makeSearchMenuItem() -> NSMenuItem {
            let searchItem = NSMenuItem()
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            let searchField = ComposerNativeMenuSearchField()
            searchField.placeholderString = searchPlaceholder
            searchField.target = self
            searchField.action = #selector(searchChanged(_:))
            searchField.font = NSFont.systemFont(ofSize: 12)
            searchField.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(searchField)
            NSLayoutConstraint.activate([
                searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                searchField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            searchItem.view = container
            DispatchQueue.main.async {
                searchField.becomeFirstResponder()
            }
            return searchItem
        }

        @objc
        func searchChanged(_ sender: NSSearchField) {
            currentSearchText = sender.stringValue
            rebuildFilteredItems()
        }

        private func rebuildFilteredItems() {
            guard let menu = currentMenu, searchableItems != nil else { return }
            itemActions = []
            while menu.items.count > 2 {
                menu.removeItem(at: 2)
            }
            let items = searchableItems?(currentSearchText) ?? []
            appendItems(items, to: menu)
        }

        private func appendItems(_ items: [ComposerNativeMenuItem], to menu: NSMenu) {
            for item in items {
                if item.isSeparator {
                    menu.addItem(.separator())
                    continue
                }

                let menuItem = NSMenuItem(
                    title: item.title,
                    action: item.submenuItems == nil ? #selector(selectItem(_:)) : nil,
                    keyEquivalent: "",
                )
                menuItem.state = item.isSelected ? .on : .off
                menuItem.isEnabled = item.isEnabled

                if let imageName = item.imageName {
                    menuItem.image = NSImage(
                        systemSymbolName: imageName,
                        accessibilityDescription: nil,
                    )
                }

                if let submenuItems = item.submenuItems {
                    menuItem.submenu = makeSubmenu(from: submenuItems)
                } else if let action = item.action {
                    menuItem.target = self
                    menuItem.representedObject = itemActions.count
                    itemActions.append(action)
                }

                menu.addItem(menuItem)
            }
        }

        private func makeSubmenu(from items: [ComposerNativeMenuItem]) -> NSMenu {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            appendItems(items, to: submenu)
            return submenu
        }

        @objc
        func selectItem(_ sender: NSMenuItem) {
            guard let index = sender.representedObject as? Int,
                  itemActions.indices.contains(index)
            else {
                return
            }
            itemActions[index]()
        }
    }
}

private final class ComposerNativeMenuSearchField: NSSearchField {
    override var acceptsFirstResponder: Bool {
        true
    }
}

final class ComposerNativeMenuNSButton: NSButton {
    var minimumWidth: CGFloat = 0 {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    var showsBorder = true {
        didSet {
            layer?.borderWidth = showsBorder ? 1 : 0
        }
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(size.width + 12, minimumWidth), height: size.height + 8)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .inline
        isBordered = false
        focusRingType = .default
        font = NSFont.systemFont(ofSize: 11, weight: .medium)
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = VoyagerDS.Radius.chipItem
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.25).cgColor
        setButtonType(.momentaryPushIn)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

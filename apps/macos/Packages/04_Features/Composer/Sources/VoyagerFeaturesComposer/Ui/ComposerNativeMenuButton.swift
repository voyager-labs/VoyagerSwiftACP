import AppKit
import SwiftUI
import VoyagerShared

struct ComposerNativeMenuItem {
    let title: String
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
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
        submenuItems = nil
        isSeparator = false
    }

    static func separator() -> Self {
        .init(
            title: "",
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
            isSelected: false,
            isEnabled: isEnabled,
            action: nil,
            submenuItems: items,
            isSeparator: false,
        )
    }

    private init(
        title: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: (() -> Void)?,
        submenuItems: [ComposerNativeMenuItem]?,
        isSeparator: Bool,
    ) {
        self.title = title
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
        self.submenuItems = submenuItems
        self.isSeparator = isSeparator
    }
}

struct ComposerNativeMenuButton: NSViewRepresentable {
    let title: String
    let imageName: String?
    let accessibilityLabel: String?
    let accessibilityIdentifier: String
    let minimumWidth: CGFloat
    let isPlaceholder: Bool
    let onOpen: () -> Void
    let menuItems: () -> [ComposerNativeMenuItem]
    let onDismiss: () -> Void

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
    ) {
        self.title = title
        self.imageName = imageName
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.minimumWidth = minimumWidth
        self.isPlaceholder = isPlaceholder
        self.onOpen = onOpen
        self.menuItems = menuItems
        self.onDismiss = onDismiss
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
        configure(button)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen, menuItems: menuItems, onDismiss: onDismiss)
    }

    private func configure(_ button: ComposerNativeMenuNSButton) {
        button.title = title
        button.image = imageName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        button.imagePosition = imageName == nil ? .noImage : (title.isEmpty ? .imageOnly : .imageLeading)
        button.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        button.setAccessibilityLabel(accessibilityLabel ?? (title.isEmpty ? nil : title))
        button.minimumWidth = minimumWidth
        button.contentTintColor = isPlaceholder ? .secondaryLabelColor : .labelColor
    }

    @MainActor
    final class Coordinator: NSObject {
        var onOpen: () -> Void
        var menuItems: () -> [ComposerNativeMenuItem]
        var onDismiss: () -> Void
        private var itemActions: [() -> Void] = []

        init(
            onOpen: @escaping () -> Void,
            menuItems: @escaping () -> [ComposerNativeMenuItem],
            onDismiss: @escaping () -> Void,
        ) {
            self.onOpen = onOpen
            self.menuItems = menuItems
            self.onDismiss = onDismiss
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
            return makeMenu(items: menuItems())
        }

        private func makeMenu(items: [ComposerNativeMenuItem]) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

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

                if let submenuItems = item.submenuItems {
                    menuItem.submenu = makeMenu(items: submenuItems)
                } else if let action = item.action {
                    menuItem.target = self
                    menuItem.representedObject = itemActions.count
                    itemActions.append(action)
                }

                menu.addItem(menuItem)
            }

            return menu
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

final class ComposerNativeMenuNSButton: NSButton {
    var minimumWidth: CGFloat = 0 {
        didSet {
            invalidateIntrinsicContentSize()
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

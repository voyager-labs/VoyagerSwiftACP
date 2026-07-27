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
    let isCaption: Bool

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
        isCaption = false
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
            isCaption: false,
        )
    }

    static func caption(_ title: String) -> Self {
        .init(
            title: title,
            imageName: nil,
            isSelected: false,
            isEnabled: false,
            action: nil,
            submenuItems: nil,
            isSeparator: false,
            isCaption: true,
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
            isCaption: false,
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
        isCaption: Bool,
    ) {
        self.title = title
        self.imageName = imageName
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
        self.submenuItems = submenuItems
        self.isSeparator = isSeparator
        self.isCaption = isCaption
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
            isCaption: isCaption,
        )
    }
}

struct ComposerNativeMenuButton: NSViewRepresentable {
    let title: String
    let imageName: String?
    let accessibilityLabel: String?
    let accessibilityIdentifier: String
    let minimumWidth: CGFloat
    let size: CGSize?
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
        size: CGSize? = nil,
        searchableItems: ((String) -> [ComposerNativeMenuItem])? = nil,
        searchPlaceholder: String = "Search",
    ) {
        self.title = title
        self.imageName = imageName
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.minimumWidth = minimumWidth
        self.size = size
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
        button.fixedSize = size
        button.showsBorder = showsBorder
        button.contentTintColor = isPlaceholder ? .secondaryLabelColor : .labelColor
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var onOpen: () -> Void
        var menuItems: () -> [ComposerNativeMenuItem]
        var onDismiss: () -> Void
        var searchableItems: ((String) -> [ComposerNativeMenuItem])?
        var searchPlaceholder: String
        private var itemActions: [() -> Void] = []
        private var currentMenu: NSMenu?
        private var currentSearchText: String = ""
        private var currentSearchRow: ComposerNativeMenuSearchRow?
        private let searchableMenuWidth: CGFloat = 320

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

            let menu = ComposerNativeMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            currentMenu = menu

            if searchableItems != nil {
                menu.addItem(makeSearchMenuItem())
                menu.searchField = currentSearchRow?.searchField
                menu.addItem(.separator())
                appendItems(searchableItems?("") ?? [], to: menu)

                menu.update()
                menu.minimumWidth = searchableMenuWidth
                if let searchView = menu.item(at: 0)?.view {
                    var frame = searchView.frame
                    frame.size.width = searchableMenuWidth
                    searchView.frame = frame
                }
            } else {
                appendItems(menuItems(), to: menu)
            }

            return menu
        }

        private func makeSearchMenuItem() -> NSMenuItem {
            let searchItem = NSMenuItem()
            let searchRow = ComposerNativeMenuSearchRow(
                placeholder: searchPlaceholder,
                target: self,
                action: #selector(searchChanged(_:)),
            )
            currentSearchRow = searchRow
            searchItem.view = searchRow
            return searchItem
        }

        func menuWillOpen(_: NSMenu) {
            guard let searchRow = currentSearchRow else { return }
            searchRow.focusSearchField(in: searchRow.window)
        }

        func menuDidClose(_ menu: NSMenu) {
            guard menu === currentMenu else { return }
            currentSearchRow = nil
            currentMenu = nil
        }

        @objc
        func searchChanged(_ sender: NSTextField) {
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

                if item.isCaption {
                    let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                    menuItem.isEnabled = false
                    menuItem.attributedTitle = NSAttributedString(
                        string: item.title,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                            .foregroundColor: NSColor.secondaryLabelColor,
                        ],
                    )
                    menu.addItem(menuItem)
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

final class ComposerNativeMenuNSButton: NSButton {
    private let hoverLayer = CALayer()
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { updateHoverAppearance() }
    }

    var minimumWidth: CGFloat = 0 {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    var fixedSize: CGSize? {
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
        if let fixedSize {
            return fixedSize
        }
        let titleWidth = title.isEmpty
            ? 0
            : (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 11)]).width
        let imageWidth = image?.size.width ?? 0
        let imageTitleSpacing: CGFloat = imageWidth > 0 && titleWidth > 0 ? 4 : 0
        let contentWidth = imageWidth + imageTitleSpacing + titleWidth
        return NSSize(
            width: max(
                contentWidth + ComposerUIMetrics.compactControlHorizontalPadding * 2,
                minimumWidth,
            ),
            height: ComposerUIMetrics.compactControlHeight,
        )
    }

    override func layout() {
        super.layout()
        hoverLayer.frame = bounds
    }

    override var isEnabled: Bool {
        didSet { updateHoverAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .inline
        isBordered = false
        (cell as? NSButtonCell)?.highlightsBy = []
        focusRingType = .default
        font = NSFont.systemFont(ofSize: 11, weight: .medium)
        contentTintColor = .labelColor
        wantsLayer = true
        hoverLayer.cornerRadius = VoyagerDS.Radius.chipItem
        layer?.insertSublayer(hoverLayer, at: 0)
        layer?.cornerRadius = VoyagerDS.Radius.chipItem
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.25).cgColor
        setButtonType(.momentaryPushIn)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil,
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHoverAppearance()
    }

    private func updateHoverAppearance() {
        let colorScheme: ColorScheme = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light
        hoverLayer.backgroundColor = isEnabled && isHovering
            ? NSColor(VoyagerDS.Interaction.controlHoverFill(for: colorScheme)).cgColor
            : NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class ComposerNativeMenu: NSMenu {
    private let searchFieldBox = WeakSearchFieldBox()

    var searchField: NSTextField? {
        get { searchFieldBox.value }
        set { searchFieldBox.value = newValue }
    }

    override nonisolated func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard Self.shouldForwardToSearchField(event) else {
            return super.performKeyEquivalent(with: event)
        }

        let keyEvent = KeyEventData(event)
        let searchFieldBox = searchFieldBox
        return MainActor.assumeIsolated {
            guard let searchField = searchFieldBox.value,
                  let window = searchField.window,
                  let forwardedEvent = keyEvent.makeEvent()
            else {
                return false
            }
            window.makeFirstResponder(searchField)
            searchField.currentEditor()?.keyDown(with: forwardedEvent)
            return true
        }
    }

    nonisolated private static func shouldForwardToSearchField(_ event: NSEvent) -> Bool {
        let deleteKeyCodes: Set<UInt16> = [51, 117]
        if deleteKeyCodes.contains(event.keyCode) { return true }

        let menuNavigationKeyCodes: Set<UInt16> = [48, 49, 53, 123, 124, 125, 126]
        if menuNavigationKeyCodes.contains(event.keyCode) { return false }
        if event.modifierFlags.contains(.command) { return false }

        return !(event.characters?.isEmpty ?? true)
    }
}

private final class WeakSearchFieldBox: @unchecked Sendable {
    @MainActor weak var value: NSTextField?
}

private struct KeyEventData {
    let modifierFlags: UInt
    let timestamp: TimeInterval
    let windowNumber: Int
    let characters: String
    let charactersIgnoringModifiers: String
    let isARepeat: Bool
    let keyCode: UInt16

    init(_ event: NSEvent) {
        modifierFlags = event.modifierFlags.rawValue
        timestamp = event.timestamp
        windowNumber = event.windowNumber
        characters = event.characters ?? ""
        charactersIgnoringModifiers = event.charactersIgnoringModifiers ?? ""
        isARepeat = event.isARepeat
        keyCode = event.keyCode
    }

    @MainActor
    func makeEvent() -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlags),
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: isARepeat,
            keyCode: keyCode,
        )
    }
}

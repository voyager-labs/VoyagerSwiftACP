@preconcurrency import AppKit
import VoyagerEntitiesTag
import VoyagerShared

final class EntryFavoriteTagsPaletteView: NSView {
    private let tags: [EntryContextMenuTagSpec]
    private let onSelect: @MainActor (EntryContextMenuTagSpec) -> Void
    private let itemSize = NSSize(width: 28, height: 28)
    private let itemSpacing: CGFloat = 2

    init(
        tags: [EntryContextMenuTagSpec],
        isEnabled: Bool,
        onSelect: @escaping @MainActor (EntryContextMenuTagSpec) -> Void,
    ) {
        self.tags = tags
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: tags.count * 30 + 8, height: 36))
        autoresizesSubviews = false
        toolTip = "Favorite Tags"
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Favorite Tags")
        for tag in tags {
            let button = FavoriteTagButton(tag: tag) { [weak self] selectedTag in
                guard let self else { return }
                self.onSelect(selectedTag)
                enclosingMenuItem?.menu?.cancelTracking()
            }
            button.autoresizingMask = []
            button.isEnabled = isEnabled
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let contentWidth = CGFloat(tags.count) * itemSize.width
            + CGFloat(max(0, tags.count - 1)) * itemSpacing
        let leadingInset = max(4, (bounds.width - contentWidth) / 2)
        for (index, button) in subviews.enumerated() {
            button.frame = itemRect(at: index, leadingInset: leadingInset)
        }
    }

    private func itemRect(at index: Int, leadingInset: CGFloat) -> NSRect {
        NSRect(
            x: leadingInset + CGFloat(index) * (itemSize.width + itemSpacing),
            y: 4,
            width: itemSize.width,
            height: itemSize.height,
        )
    }
}

private final class FavoriteTagButton: NSButton {
    let tagSpec: EntryContextMenuTagSpec
    private let onPress: @MainActor (EntryContextMenuTagSpec) -> Void
    private let dotLayer = CALayer()
    private let dotSize: CGFloat = 12
    private var pressedInside = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(
        tag: EntryContextMenuTagSpec,
        onPress: @escaping @MainActor (EntryContextMenuTagSpec) -> Void,
    ) {
        tagSpec = tag
        self.onPress = onPress
        super.init(frame: .zero)
        isBordered = false
        title = ""
        toolTip = tag.name
        setAccessibilityLabel(tag.name)
        setAccessibilityValue(tag.selection.accessibilityValue)
        wantsLayer = true
        dotLayer.backgroundColor = TagColor(colorCode: tag.colorCode).nsColor.cgColor
        layer?.addSublayer(dotLayer)
        updateDotAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        dotLayer.frame = NSRect(
            x: (bounds.width - dotSize) / 2,
            y: (bounds.height - dotSize) / 2,
            width: dotSize,
            height: dotSize,
        )
        dotLayer.cornerRadius = dotSize / 2
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil,
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with _: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        updateDotAppearance()
        updateTagsMenuItemTitle("Tags: \(tagSpec.name)")
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        updateDotAppearance()
        updateTagsMenuItemTitle("Tags…")
    }

    override func mouseDown(with event: NSEvent) {
        pressedInside = isEnabled && bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedInside = false }
        guard pressedInside, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress(tagSpec)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress(tagSpec)
        return true
    }

    private func updateDotAppearance() {
        if isHovered {
            dotLayer.borderColor = NSColor.controlAccentColor.cgColor
            dotLayer.borderWidth = 2
        } else {
            dotLayer.borderColor = tagSpec.selection == .off
                ? NSColor.clear.cgColor
                : NSColor.labelColor.cgColor
            dotLayer.borderWidth = tagSpec.selection == .on
                ? 2
                : (tagSpec.selection == .mixed ? 1 : 0)
        }
    }

    private func updateTagsMenuItemTitle(_ title: String) {
        let tagsMenuItem = enclosingMenuItem?.menu?.items.first {
            $0.action == #selector(EntryContextMenuCoordinator.contextMenuShowTags(_:))
        }
        tagsMenuItem?.title = title
    }
}

final class EntryTagsPopoverViewController: NSViewController, NSSearchFieldDelegate, NSTableViewDataSource,
    NSTableViewDelegate
{
    private let targetTitle: String
    private let tags: [EntryContextMenuTagSpec]
    private let onSelect: (String, EntryContextMenuTagSelection) -> Void
    private let onClose: () -> Void
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var filteredTags: [EntryContextMenuTagSpec] = []

    init(
        title: String,
        tags: [EntryContextMenuTagSpec],
        onSelect: @escaping (String, EntryContextMenuTagSelection) -> Void,
        onClose: @escaping () -> Void,
    ) {
        targetTitle = title
        self.tags = tags
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        filteredTags = tags
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 244))
        let title = NSTextField(labelWithString: targetTitle.isEmpty ? "Tags" : targetTitle)
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 12, y: 216, width: 236, height: 16)
        root.addSubview(title)

        searchField.placeholderString = "Search Tags"
        searchField.setAccessibilityLabel("Search tags")
        searchField.delegate = self
        searchField.frame = NSRect(x: 12, y: 184, width: 236, height: 24)
        root.addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tag"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 28
        let scrollView = NSScrollView(frame: NSRect(x: 12, y: 12, width: 236, height: 164))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        root.addSubview(scrollView)
        view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.makeFirstResponder(searchField)
    }

    func controlTextDidChange(_: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredTags = query.isEmpty ? tags : tags.filter { $0.name.localizedCaseInsensitiveContains(query) }
        if !query.isEmpty, !tags.contains(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) {
            filteredTags.append(.init(name: query, colorCode: 0, selection: .off))
        }
        tableView.reloadData()
    }

    func numberOfRows(in _: NSTableView) -> Int {
        filteredTags.count
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let tag = filteredTags[row]
        let label = NSTextField(labelWithString: tag.name)
        label.frame = NSRect(x: 40, y: 5, width: 180, height: 18)
        let rowView = NSView()
        let dot = NSView(frame: NSRect(x: 4, y: 9, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = TagColor(colorCode: tag.colorCode).nsColor.cgColor
        let selection = NSTextField(labelWithString: tag.selection == .on ? "✓" : tag.selection == .mixed ? "—" : "")
        selection.alignment = .center
        selection.frame = NSRect(x: 20, y: 5, width: 16, height: 18)
        selection.textColor = .secondaryLabelColor
        rowView.addSubview(dot)
        rowView.addSubview(selection)
        rowView.addSubview(label)
        rowView.setAccessibilityElement(true)
        rowView.setAccessibilityLabel(tag.name)
        rowView.setAccessibilityValue(tag.selection.accessibilityValue)
        return rowView
    }

    func tableViewSelectionDidChange(_: Notification) {
        let row = tableView.selectedRow
        guard filteredTags.indices.contains(row) else { return }
        let tag = filteredTags[row]
        onSelect(tag.name, tag.selection)
        onClose()
    }
}

private extension EntryContextMenuTagSelection {
    var accessibilityValue: String {
        switch self {
        case .on: "On"
        case .mixed: "Mixed"
        case .off: "Off"
        }
    }
}

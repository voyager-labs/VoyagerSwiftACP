@preconcurrency import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerShared

@MainActor
public struct EntryListViewRepresentable: NSViewRepresentable {
    public let store: StoreOf<EntryViewLayoutFeature>
    public let blankSpaceMenuProvider: (() -> NSMenu)?

    public init(
        store: StoreOf<EntryViewLayoutFeature>,
        blankSpaceMenuProvider: (() -> NSMenu)?,
    ) {
        self.store = store
        self.blankSpaceMenuProvider = blankSpaceMenuProvider
    }

    public func makeCoordinator() -> EntryListCoordinator {
        EntryListCoordinator(store: store)
    }

    public func makeNSView(context: Context) -> EntryListView {
        let view = EntryListView()
        context.coordinator.bind(to: view)
        view.tableView.blankSpaceContextMenuProvider = blankSpaceMenuProvider
        return view
    }

    public func updateNSView(_ view: EntryListView, context: Context) {
        context.coordinator.updateRootView(view)
        view.tableView.blankSpaceContextMenuProvider = blankSpaceMenuProvider
    }

    public static func dismantleNSView(_: EntryListView, coordinator: EntryListCoordinator) {
        coordinator.externalDropSessionController.cancel()
    }
}

final class EntryListSelectionRowView: NSTableRowView {
    private var isGroupRow = false

    func configure(isGroupRow: Bool) {
        self.isGroupRow = isGroupRow
    }

    override func accessibilityChildren() -> [Any]? {
        let nativeChildren = super.accessibilityChildren() ?? []
        let unrepresentedSubviews = subviews.filter { subview in
            !nativeChildren.contains { child in
                (child as? NSView) === subview
            }
        }
        return nativeChildren + unrepresentedSubviews
    }

    private var tableView: NSTableView? {
        var view: NSView? = self
        while let currentView = view {
            if let tableView = currentView as? NSTableView {
                return tableView
            }
            view = currentView.superview
        }
        return nil
    }

    override var isEmphasized: Bool {
        didSet {
            super.isEmphasized = true
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard !isSelected else {
            super.drawBackground(in: dirtyRect)
            return
        }

        // 불투명 색으로 덮으면 하위 NSVisualEffectView material 투과가 죽으므로 반투명 오버레이를 쓴다(VOY-598).
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isGroupRow {
            VoyagerDS.AppKitSurface.contentPaneOverlay(isDark: isDark).setFill()
            dirtyRect.fill()
            return
        }

        guard let tableView,
              tableView.row(for: self) % 2 == 1 else { return }

        let backgroundColor = isDark
            ? NSColor.white.withAlphaComponent(0.035)
            : NSColor.black.withAlphaComponent(0.055)
        backgroundColor.setFill()
        dirtyRect.fill()
    }
}

struct EntryListNativeSelectionContext {
    let destinationOccurrence: AnyObject
    let modifierFlags: NSEvent.ModifierFlags
}

final class EntryListScrollView: NSScrollView {
    override func tile() {
        super.tile()

        guard let headerClipView = subviews
            .compactMap({ $0 as? NSClipView })
            .first(where: { $0.documentView is NSTableHeaderView })
        else { return }

        installHeaderBackdrop(in: headerClipView)
        headerClipView.drawsBackground = false
        headerClipView.backgroundColor = .clear
        for subview in headerClipView.subviews
            where !(subview is NSTableHeaderView) && !(subview is NSVisualEffectView)
        {
            subview.isHidden = true
        }
    }

    /// 헤더 배경은 색 fill이 아니라 withinWindow material 백드롭으로 그려
    /// 아래 콘텐츠 표면이 블러로 비치게 한다(VOY-598).
    private func installHeaderBackdrop(in headerClipView: NSClipView) {
        if let existing = headerClipView.subviews
            .first(where: { $0 is NSVisualEffectView }) as? NSVisualEffectView
        {
            VoyagerDS.SurfaceMaterialRole.listHeaderSurface.apply(to: existing)
            return
        }
        guard let headerView = headerClipView.documentView as? NSTableHeaderView else { return }
        let backdrop = VoyagerDS.SurfaceMaterialRole.listHeaderSurface.makeBackgroundView()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        headerClipView.addSubview(backdrop, positioned: .below, relativeTo: headerView)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: headerClipView.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: headerClipView.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: headerClipView.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: headerClipView.bottomAnchor),
        ])
    }
}

public final class EntryListView: NSView {
    enum ContextMenuSelectionHandling {
        case native
        case prepared
        case suppressed
    }

    @MainActor
    protocol EntryListTableViewContextMenuProviding: AnyObject {
        func handleSelectionMouseDown(forRow row: Int, event: NSEvent, isDisclosureHit: Bool) -> Bool
        func handleSelectionKeyDown(forRow row: Int, event: NSEvent) -> Bool
        func prepareContextMenuSelection(
            forRow row: Int,
            event: NSEvent,
            isDisclosureHit: Bool,
        ) -> ContextMenuSelectionHandling
        func contextMenu(forRow row: Int?, event: NSEvent) -> NSMenu
    }

    final class EntryListTableView: NSOutlineView {
        weak var contextMenuProvider: EntryListTableViewContextMenuProviding?
        var blankSpaceContextMenuProvider: (() -> NSMenu)?
        private(set) var activeSelectionOccurrence: AnyObject?
        private(set) var rangeAnchorOccurrence: AnyObject?
        private(set) var selectionTransactionGeneration: UInt = 0
        private(set) var expectedSelectionSignature: IndexSet?
        private(set) var isApplyingDisclosureSelectionTransaction = false
        private var hasPendingDisclosureSelectionCallbacks = false
        private var didBeginNativeDrag = false
        private var pendingNativeSelectionContext: EntryListNativeSelectionContext?
        private var pendingNativeSelectionOwner: UInt?

        @discardableResult
        func applyCanonicalSelection(
            _ indexes: IndexSet,
            activeOccurrence: AnyObject?,
            anchorOccurrence: AnyObject?,
        ) -> Bool {
            let cursorUnchanged = activeSelectionOccurrence === activeOccurrence
                && rangeAnchorOccurrence === anchorOccurrence
            guard selectedRowIndexes != indexes
                || expectedSelectionSignature != indexes
                || !cursorUnchanged
            else { return false }

            selectionTransactionGeneration &+= 1
            expectedSelectionSignature = indexes
            hasPendingDisclosureSelectionCallbacks = false
            activeSelectionOccurrence = activeOccurrence
            rangeAnchorOccurrence = anchorOccurrence
            pendingNativeSelectionContext = nil
            selectRowIndexes(indexes, byExtendingSelection: false)
            return true
        }

        func invalidateSelectionProjection() {
            selectionTransactionGeneration &+= 1
            expectedSelectionSignature = nil
            activeSelectionOccurrence = nil
            rangeAnchorOccurrence = nil
            pendingNativeSelectionContext = nil
        }

        func invalidateSelectionProjectionIfNeeded() {
            let hasStaleActive = activeSelectionOccurrence != nil && liveRow(for: activeSelectionOccurrence) == nil
            let hasStaleAnchor = rangeAnchorOccurrence != nil && liveRow(for: rangeAnchorOccurrence) == nil
            if hasStaleActive || hasStaleAnchor {
                invalidateSelectionProjection()
            }
        }

        func liveRow(for occurrence: AnyObject?) -> Int? {
            guard let occurrence else { return nil }
            let row = row(forItem: occurrence)
            guard row >= 0,
                  let currentOccurrence = item(atRow: row) as AnyObject?,
                  currentOccurrence === occurrence
            else { return nil }
            return row
        }

        func shouldIgnoreSelectionCallback(_ signature: IndexSet) -> Bool {
            guard let expectedSelectionSignature else { return false }
            return signature == expectedSelectionSignature
        }

        @discardableResult
        func beginNativeSelection(atRow row: Int, modifierFlags: NSEvent.ModifierFlags = []) -> Bool {
            guard let occurrence = item(atRow: row) as AnyObject? else { return false }
            expectedSelectionSignature = nil
            hasPendingDisclosureSelectionCallbacks = false
            pendingNativeSelectionContext = EntryListNativeSelectionContext(
                destinationOccurrence: occurrence,
                modifierFlags: modifierFlags,
            )
            return true
        }

        func endNativeSelection() {
            pendingNativeSelectionContext = nil
        }

        func performDisclosureSelectionTransaction(_ operation: () -> Void) {
            isApplyingDisclosureSelectionTransaction = true
            prepareDisclosureSelectionCallbacks()
            defer {
                expectedSelectionSignature = selectedRowIndexes
                isApplyingDisclosureSelectionTransaction = false
            }
            operation()
        }

        func prepareDisclosureSelectionCallbacks() {
            hasPendingDisclosureSelectionCallbacks = true
        }

        var suppressesDisclosureSelectionCallback: Bool {
            isApplyingDisclosureSelectionTransaction || hasPendingDisclosureSelectionCallbacks
        }

        func finishDisclosureSelectionSynchronization() {
            hasPendingDisclosureSelectionCallbacks = false
        }

        func takeNativeSelectionContext() -> EntryListNativeSelectionContext? {
            defer { pendingNativeSelectionContext = nil }
            return pendingNativeSelectionContext
        }

        override func mouseDown(with event: NSEvent) {
            cancelPendingNativeSelection()
            guard let hit = pointerHit(for: event) else { return }
            if handleCustomSelectionMouseDown(event).boolValue {
                return
            }
            let isGroupRow = if let item = item(atRow: hit.row) as? EntryListOutlineItem,
                                case .group = item.kind
            {
                true
            } else {
                false
            }
            if hit.isDisclosure || isGroupRow {
                performDisclosureSelectionTransaction { super.mouseDown(with: event) }
                return
            }
            guard beginNativeSelection(atRow: hit.row, modifierFlags: event.modifierFlags) else {
                cancelPendingNativeSelection()
                return
            }
            let selectedRowsBeforeEvent = selectedRowIndexes
            let selectedGroupRepresentsDestination = if event.modifierFlags.contains(.command),
                                                        selectedRowsBeforeEvent.contains(hit.row),
                                                        let destination = item(atRow: hit.row) as? EntryListOutlineItem,
                                                        case let .entry(destinationEntry) = destination.kind
            {
                selectedRowsBeforeEvent.contains { selectedRow in
                    guard let group = item(atRow: selectedRow) as? EntryListOutlineItem,
                          case .group = group.kind
                    else { return false }
                    return group.orderedDistinctEntries().contains(where: { $0.id == destinationEntry.id })
                }
            } else {
                false
            }
            super.mouseDown(with: event)
            guard selectedGroupRepresentsDestination, selectedRowIndexes == selectedRowsBeforeEvent else {
                cancelPendingNativeSelection()
                return
            }
            let generation = selectionTransactionGeneration
            scheduleNativeCommandToggle(row: hit.row, selectedRows: selectedRowsBeforeEvent, generation: generation)
        }

        override func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            didBeginNativeDrag = true
            super.draggingSession(session, willBeginAt: screenPoint)
        }

        @objc
        func handleCustomSelectionMouseDown(_ event: NSEvent) -> NSNumber {
            guard let hit = pointerHit(for: event) else { return true }
            guard event.clickCount == 1,
                  let contextMenuProvider
            else {
                return false
            }
            return NSNumber(value: contextMenuProvider.handleSelectionMouseDown(
                forRow: hit.row,
                event: event,
                isDisclosureHit: hit.isDisclosure,
            ))
        }

        override func keyDown(with event: NSEvent) {
            cancelPendingNativeSelection()
            let row = liveRow(for: activeSelectionOccurrence) ?? selectedRow
            guard row >= 0, let specialKey = event.specialKey else {
                super.keyDown(with: event)
                return
            }

            switch specialKey {
            case .rightArrow:
                let item = item(atRow: row)
                if !isItemExpanded(item), isExpandable(item) {
                    performDisclosureSelectionTransaction { expandItem(item) }
                    return
                }
            case .leftArrow:
                let item = item(atRow: row)
                if isItemExpanded(item) {
                    performDisclosureSelectionTransaction { collapseItem(item) }
                    return
                }
            case .upArrow, .downArrow:
                let destinationRow = row + (specialKey == .upArrow ? -1 : 1)
                guard (0 ..< numberOfRows).contains(destinationRow) else { return }
                guard contextMenuProvider?.handleSelectionKeyDown(forRow: destinationRow, event: event) == true
                else { break }
                scrollRowToVisible(destinationRow)
                return
            default:
                break
            }
            super.keyDown(with: event)
        }

        override func rightMouseDown(with event: NSEvent) {
            cancelPendingNativeSelection()
            let location = convert(event.locationInWindow, from: nil)
            let row = row(at: location)

            if row == -1 {
                if let menu = blankSpaceContextMenuProvider?() {
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                }
                return
            }

            switch contextMenuSelectionHandling(for: event) {
            case .suppressed:
                return
            case .native where !selectedRowIndexes.contains(row):
                guard beginNativeSelection(atRow: row, modifierFlags: event.modifierFlags) else { return }
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                endNativeSelection()
            case .native, .prepared:
                break
            }

            guard let contextMenuProvider else {
                super.rightMouseDown(with: event)
                return
            }

            let menu = contextMenuProvider.contextMenu(forRow: row, event: event)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc
        func handleCustomSelectionRightMouseDown(_ event: NSEvent) -> NSNumber {
            NSNumber(value: contextMenuSelectionHandling(for: event) == .suppressed)
        }

        private func contextMenuSelectionHandling(for event: NSEvent) -> ContextMenuSelectionHandling {
            guard let contextMenuProvider,
                  let hit = pointerHit(for: event)
            else {
                return .native
            }
            return contextMenuProvider.prepareContextMenuSelection(
                forRow: hit.row,
                event: event,
                isDisclosureHit: hit.isDisclosure,
            )
        }

        private func pointerHit(for event: NSEvent) -> (row: Int, isDisclosure: Bool)? {
            let location = convert(event.locationInWindow, from: nil)
            let row = row(at: location)
            guard row >= 0 else { return nil }
            return (row, frameOfOutlineCell(atRow: row).contains(location))
        }
    }

    let scrollView = EntryListScrollView()
    let tableView = EntryListTableView()
    private var availableColumns: [EntryListColumn: NSTableColumn] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViewTree()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func accessibilityChildren() -> [Any]? {
        [tableView]
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    private func setupViewTree() {
        setAccessibilityElement(false)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = NSColor.clear
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        tableView.wantsLayer = true
        tableView.layer?.backgroundColor = NSColor.clear.cgColor
        tableView.setAccessibilityElement(true)
        tableView.setAccessibilityIdentifier("entry-list-outline")
        tableView.setAccessibilityLabel("File entries")
        tableView.setAccessibilityRole(.outline)
        tableView.backgroundColor = NSColor.clear
        tableView.headerView = NSTableHeaderView()
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.intercellSpacing = NSSize(width: 4, height: 0)
        tableView.registerForDraggedTypes(EntryViewLayoutDropValidationAdapter.registeredDraggedTypes)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy], forLocal: false)
        tableView.autoresizesOutlineColumn = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.autosaveName = "FileManager.EntryList.Columns"
        tableView.autosaveTableColumns = true
        applyColumns(EntryListColumn.defaultVisibleColumns)

        scrollView.documentView = tableView

        addSubview(scrollView)
        setAccessibilityChildren([tableView])
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    func applyColumns(_ visibleColumns: [EntryListColumn]) {
        let normalizedColumns = EntryListColumn.normalizeVisibleColumns(visibleColumns)
        let visibleIdentifiers = Set(normalizedColumns.map(\.rawValue))

        for tableColumn in tableView.tableColumns where !visibleIdentifiers.contains(tableColumn.identifier.rawValue) {
            tableView.removeTableColumn(tableColumn)
        }

        for column in normalizedColumns {
            let identifier = NSUserInterfaceItemIdentifier(column.rawValue)
            if tableView.tableColumn(withIdentifier: identifier) == nil {
                tableView.addTableColumn(resolvedTableColumn(for: column))
            }
        }

        for (targetIndex, column) in normalizedColumns.enumerated() {
            let identifier = NSUserInterfaceItemIdentifier(column.rawValue)
            let currentIndex = tableView.column(withIdentifier: identifier)
            guard currentIndex >= 0, currentIndex != targetIndex else { continue }
            tableView.moveColumn(currentIndex, toColumn: targetIndex)
        }

        if let outlineColumn = tableView.tableColumn(
            withIdentifier: NSUserInterfaceItemIdentifier(EntryListColumn.name.rawValue),
        ) {
            tableView.outlineTableColumn = outlineColumn
        }

        tableView.sortDescriptors = tableView.sortDescriptors.filter { descriptor in
            guard let key = descriptor.key else { return false }
            return visibleIdentifiers.contains(key)
        }
    }

    private func resolvedTableColumn(for column: EntryListColumn) -> NSTableColumn {
        if let cached = availableColumns[column] {
            return cached
        }

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
        tableColumn.title = column.title
        tableColumn.minWidth = column.minWidth
        tableColumn.maxWidth = column.maxWidth
        tableColumn.width = column.defaultWidth
        tableColumn.resizingMask = [.userResizingMask, .autoresizingMask]

        if let sortDescriptorKey = column.sortDescriptorKey {
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(
                key: sortDescriptorKey,
                ascending: column.defaultSortAscending,
            )
        } else {
            tableColumn.sortDescriptorPrototype = nil
        }

        availableColumns[column] = tableColumn
        return tableColumn
    }
}

private extension EntryListView.EntryListTableView {
    func cancelPendingNativeSelection(ownedBy owner: UInt? = nil) {
        if let owner, pendingNativeSelectionOwner != owner { return }
        didBeginNativeDrag = false
        pendingNativeSelectionOwner = nil
        guard pendingNativeSelectionContext != nil else { return }
        selectionTransactionGeneration &+= 1
        endNativeSelection()
    }

    func scheduleNativeCommandToggle(row: Int, selectedRows: IndexSet, generation: UInt) {
        pendingNativeSelectionOwner = generation
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.pendingNativeSelectionOwner == generation else { return }
                defer { self.cancelPendingNativeSelection(ownedBy: generation) }
                guard !self.didBeginNativeDrag,
                      self.selectionTransactionGeneration == generation,
                      self.selectedRowIndexes == selectedRows
                else { return }
                var toggledRows = selectedRows
                toggledRows.remove(row)
                self.selectRowIndexes(toggledRows, byExtendingSelection: false)
            }
        }
    }
}

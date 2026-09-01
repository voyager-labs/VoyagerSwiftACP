@preconcurrency import AppKit
import ComposableArchitecture
import SwiftUI

public struct EntryHistorySwipeProgress: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        case back
        case forward
    }

    public let direction: Direction
    public let progress: CGFloat
    public let isArmed: Bool

    public init(direction: Direction, progress: CGFloat, isArmed: Bool) {
        self.direction = direction
        self.progress = min(max(progress, 0), 1)
        self.isArmed = isArmed
    }
}

@MainActor
public struct EntryListViewRepresentable: NSViewRepresentable {
    public let store: StoreOf<EntryViewLayoutFeature>
    public let blankSpaceMenuProvider: (() -> NSMenu)?
    public let onGoBack: () -> Void
    public let onGoForward: () -> Void
    public let onSwipeProgress: (EntryHistorySwipeProgress?) -> Void

    public init(
        store: StoreOf<EntryViewLayoutFeature>,
        blankSpaceMenuProvider: (() -> NSMenu)?,
        onGoBack: @escaping () -> Void = {},
        onGoForward: @escaping () -> Void = {},
        onSwipeProgress: @escaping (EntryHistorySwipeProgress?) -> Void = { _ in },
    ) {
        self.store = store
        self.blankSpaceMenuProvider = blankSpaceMenuProvider
        self.onGoBack = onGoBack
        self.onGoForward = onGoForward
        self.onSwipeProgress = onSwipeProgress
    }

    public func makeCoordinator() -> EntryListCoordinator {
        EntryListCoordinator(store: store)
    }

    public func makeNSView(context: Context) -> EntryListView {
        let view = EntryListView()
        context.coordinator.bind(to: view)
        view.tableView.blankSpaceContextMenuProvider = blankSpaceMenuProvider
        view.scrollView.onGoBack = onGoBack
        view.scrollView.onGoForward = onGoForward
        view.scrollView.onSwipeProgress = onSwipeProgress
        return view
    }

    public func updateNSView(_ view: EntryListView, context: Context) {
        context.coordinator.updateRootView(view)
        view.tableView.blankSpaceContextMenuProvider = blankSpaceMenuProvider
        view.scrollView.onGoBack = onGoBack
        view.scrollView.onGoForward = onGoForward
        view.scrollView.onSwipeProgress = onSwipeProgress
    }

    public static func dismantleNSView(_ view: EntryListView, coordinator: EntryListCoordinator) {
        view.scrollView.onSwipeProgress(nil)
        view.scrollView.onGoBack = {}
        view.scrollView.onGoForward = {}
        view.scrollView.onSwipeProgress = { _ in }
        coordinator.externalDropSessionController.cancel()
    }
}

@MainActor
class EntryHistorySwipeScrollView: NSScrollView {
    private static let acceptanceGestureAmount: CGFloat = 0.25

    var onGoBack: () -> Void = {}
    var onGoForward: () -> Void = {}
    var onSwipeProgress: (EntryHistorySwipeProgress?) -> Void = { _ in }

    private var isTrackingSwipe = false
    private var hasCommittedNavigation = false
    private var swipeDirection: EntryHistorySwipeProgress.Direction?

    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        axis == .horizontal
    }

    override func scrollWheel(with event: NSEvent) {
        let deltaX = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaX : event.scrollingDeltaX
        guard event.phase == .began,
              event.hasPreciseScrollingDeltas,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
              deltaX != 0,
              isAtHorizontalEdge(for: deltaX),
              NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              !isTrackingSwipe
        else {
            super.scrollWheel(with: event)
            return
        }

        isTrackingSwipe = true
        hasCommittedNavigation = false
        swipeDirection = deltaX > 0 ? .forward : .back
        let isDirectionInverted = event.isDirectionInvertedFromDevice
        event.trackSwipeEvent(
            options: [.lockDirection],
            dampenAmountThresholdMin: -1,
            max: 1,
        ) { [weak self] amount, phase, isComplete, _ in
            self?.handleSwipeUpdate(
                amount: amount,
                phase: phase,
                isComplete: isComplete,
                isDirectionInverted: isDirectionInverted,
            )
        }
    }

    private func handleSwipeUpdate(
        amount: CGFloat,
        phase: NSEvent.Phase,
        isComplete: Bool,
        isDirectionInverted: Bool,
    ) {
        let normalizedAmount = isDirectionInverted ? -amount : amount
        let progress = min(abs(normalizedAmount) / Self.acceptanceGestureAmount, 1)
        let isArmed = progress >= 1

        if let swipeDirection, !isComplete {
            onSwipeProgress(
                EntryHistorySwipeProgress(
                    direction: swipeDirection,
                    progress: progress,
                    isArmed: isArmed,
                ),
            )
        }

        if phase == .ended,
           isArmed,
           !hasCommittedNavigation,
           let swipeDirection
        {
            hasCommittedNavigation = true
            switch swipeDirection {
            case .back:
                onGoBack()
            case .forward:
                onGoForward()
            }
        }

        if isComplete {
            guard isTrackingSwipe else { return }
            isTrackingSwipe = false
            hasCommittedNavigation = false
            swipeDirection = nil
            onSwipeProgress(nil)
        }
    }

    private func isAtHorizontalEdge(for deltaX: CGFloat) -> Bool {
        let documentRect = contentView.documentRect
        let minimumX = documentRect.minX
        let maximumX = max(minimumX, documentRect.maxX - contentView.bounds.width)
        let currentX = contentView.bounds.minX
        let tolerance: CGFloat = 1

        return deltaX > 0
            ? currentX >= maximumX - tolerance
            : currentX <= minimumX + tolerance
    }
}

final class EntryListSelectionRowView: NSTableRowView {
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

        guard let tableView,
              tableView.row(for: self) % 2 == 1 else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let backgroundColor = isDark
            ? NSColor.white.withAlphaComponent(0.035)
            : NSColor.black.withAlphaComponent(0.055)
        backgroundColor.setFill()
        dirtyRect.fill()
    }
}

public final class EntryListView: NSView {
    @MainActor
    protocol EntryListTableViewContextMenuProviding: AnyObject {
        func contextMenu(forRow row: Int?, event: NSEvent) -> NSMenu
    }

    final class EntryListTableView: NSOutlineView {
        weak var contextMenuProvider: EntryListTableViewContextMenuProviding?
        var blankSpaceContextMenuProvider: (() -> NSMenu)?

        override func mouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            if row(at: location) == -1 {
                deselectAll(nil)
            }
            super.mouseDown(with: event)
        }

        override func keyDown(with event: NSEvent) {
            let row = selectedRow
            guard row >= 0, let specialKey = event.specialKey else {
                super.keyDown(with: event)
                return
            }

            switch specialKey {
            case .rightArrow:
                let item = item(atRow: row)
                if !isItemExpanded(item), isExpandable(item) {
                    expandItem(item)
                    return
                }
            case .leftArrow:
                let item = item(atRow: row)
                if isItemExpanded(item) {
                    collapseItem(item)
                    return
                }
            case .upArrow where row > 0:
                let extending = event.modifierFlags.contains(.shift)
                selectRowIndexes(IndexSet(integer: row - 1), byExtendingSelection: extending)
                scrollRowToVisible(row - 1)
                return
            case .downArrow where row < numberOfRows - 1:
                let extending = event.modifierFlags.contains(.shift)
                selectRowIndexes(IndexSet(integer: row + 1), byExtendingSelection: extending)
                scrollRowToVisible(row + 1)
                return
            default:
                break
            }
            super.keyDown(with: event)
        }

        override func rightMouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            let row = row(at: location)

            if row == -1 {
                deselectAll(nil)
                if let menu = blankSpaceContextMenuProvider?() {
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                    return
                }
                super.rightMouseDown(with: event)
                return
            }

            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }

            guard let contextMenuProvider else {
                super.rightMouseDown(with: event)
                return
            }

            let menu = contextMenuProvider.contextMenu(forRow: row, event: event)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    final class EntryListScrollView: EntryHistorySwipeScrollView {
        override func tile() {
            super.tile()

            guard let headerClipView = subviews
                .compactMap({ $0 as? NSClipView })
                .first(where: { $0.documentView is NSTableHeaderView })
            else { return }

            headerClipView.drawsBackground = false
            headerClipView.backgroundColor = NSColor.clear
            for subview in headerClipView.subviews where !(subview is NSTableHeaderView) {
                subview.isHidden = true
            }
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

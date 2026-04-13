import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
public struct EntryGridViewRepresentable<ContentStore>: NSViewRepresentable {
    public typealias Coordinator = Void
    public let store: StoreOf<EntryViewLayoutFeature>
    public let contentStore: ContentStore

    public init(store: StoreOf<EntryViewLayoutFeature>, contentStore: ContentStore) {
        self.store = store
        self.contentStore = contentStore
    }

    public func makeCoordinator() {}

    public func makeNSView(context _: Context) -> EntryGridView {
        let view = EntryGridView()
        let coordinator = EntryGridCoordinator(store: store)
        view.coordinator = coordinator
        coordinator.bind(to: view)
        return view
    }

    public func updateNSView(_ view: EntryGridView, context _: Context) {
        if let coordinator = view.coordinator {
            coordinator.updateView(view)
        } else {
            let coordinator = EntryGridCoordinator(store: store)
            view.coordinator = coordinator
            coordinator.bind(to: view)
        }
    }
}

public final class EntryGridView: NSView {
    var coordinator: EntryGridCoordinator?

    public protocol EntryGridCollectionViewMenuProviding: AnyObject {
        func contextMenu(for indexPath: IndexPath?, event: NSEvent) -> NSMenu
    }

    public final class EntryGridCollectionView: NSCollectionView {
        public weak var contextMenuProvider: EntryGridCollectionViewMenuProviding?
        public var blankSpaceContextMenuProvider: (() -> NSMenu)?
        public var blankSpaceContextMenuCoordinator: AnyObject?
        public var onSelectionDrag: (() -> Void)?
        public var onLassoSelectionIndexPathsChanged: ((Set<IndexPath>, Bool) -> Void)?
        public var onLassoActiveChanged: ((Bool) -> Void)?

        private var lassoStartPoint: NSPoint?
        private var lassoInitialSelection: Set<IndexPath> = []
        private var lastReportedLassoSelection: Set<IndexPath> = []
        private var isLassoActive: Bool = false

        override public func mouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            if indexPathForItem(at: location) == nil {
                let isAdditive = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
                if !isAdditive {
                    deselectAll(nil)
                }

                lassoStartPoint = location
                lassoInitialSelection = selectionIndexPaths
                lastReportedLassoSelection = selectionIndexPaths
                isLassoActive = true
                onLassoActiveChanged?(true)
            }
            super.mouseDown(with: event)
        }

        override public func rightMouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            guard let indexPath = indexPathForItem(at: location) else {
                deselectAll(nil)
                if let menu = blankSpaceContextMenuProvider?() {
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                    return
                }
                super.rightMouseDown(with: event)
                return
            }

            if !selectionIndexPaths.contains(indexPath) {
                selectItems(at: [indexPath], scrollPosition: [])
            }
            super.rightMouseDown(with: event)
        }

        override public func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)

            guard isLassoActive else {
                onSelectionDrag?()
                return
            }

            let current = convert(event.locationInWindow, from: nil)
            applyLassoSelection(current: current, modifierFlags: event.modifierFlags, isFinal: false)

            onSelectionDrag?()
        }

        override public func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)

            guard isLassoActive else {
                return
            }

            let current = convert(event.locationInWindow, from: nil)
            applyLassoSelection(current: current, modifierFlags: event.modifierFlags, isFinal: true)
        }

        public func updateLassoSelectionFromAutoscroll(_ point: NSPoint) {
            guard isLassoActive else { return }
            applyLassoSelection(current: point, modifierFlags: NSEvent.modifierFlags, isFinal: false)
        }

        private func applyLassoSelection(
            current: NSPoint,
            modifierFlags: NSEvent.ModifierFlags,
            isFinal: Bool,
        ) {
            guard let start = lassoStartPoint,
                  let layout = collectionViewLayout
            else {
                if isFinal {
                    finishLassoSelection()
                }
                return
            }

            let selectionRect = NSRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y),
            )

            let attributes = layout.layoutAttributesForElements(in: selectionRect)
            var selection = Set(attributes.compactMap { attr -> IndexPath? in
                guard attr.representedElementCategory == .item else { return nil }
                return attr.indexPath
            })

            let isAdditive = modifierFlags.contains(.command) || modifierFlags.contains(.shift)
            if isAdditive {
                selection.formUnion(lassoInitialSelection)
            }

            if isFinal {
                onLassoSelectionIndexPathsChanged?(selection, true)
                finishLassoSelection()
                return
            }

            if selection != lastReportedLassoSelection {
                lastReportedLassoSelection = selection
                onLassoSelectionIndexPathsChanged?(selection, false)
            }
        }

        private func finishLassoSelection() {
            isLassoActive = false
            lassoStartPoint = nil
            lassoInitialSelection = []
            lastReportedLassoSelection = []
            onLassoActiveChanged?(false)
        }

        override public func menu(for event: NSEvent) -> NSMenu? {
            let location = convert(event.locationInWindow, from: nil)
            let indexPath = indexPathForItem(at: location)
            guard let indexPath else { return nil }
            return contextMenuProvider?.contextMenu(for: indexPath, event: event)
        }
    }

    public let scrollView = NSScrollView()
    public let collectionView = EntryGridCollectionView()
    public let flowLayout = NSCollectionViewFlowLayout()

    public var onLayout: ((CGFloat) -> Void)?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViewTree()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViewTree() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)

        collectionView.collectionViewLayout = flowLayout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            EntryGridCollectionViewItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("EntryGridCollectionViewItem"),
        )
        collectionView.register(
            EntryGridSectionHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: NSUserInterfaceItemIdentifier("EntryGridSectionHeaderView"),
        )
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.setDraggingSourceOperationMask([.copy], forLocal: false)
        collectionView.registerForDraggedTypes([.fileURL])

        scrollView.documentView = collectionView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override public func layout() {
        super.layout()
        onLayout?(bounds.width)
    }
}

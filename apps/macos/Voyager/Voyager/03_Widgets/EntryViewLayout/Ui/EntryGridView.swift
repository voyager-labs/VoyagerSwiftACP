import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
struct EntryGridViewRepresentable: NSViewRepresentable {
    let store: StoreOf<FileManagerContentFeature>

    func makeCoordinator() -> EntryGridCoordinator {
        EntryGridCoordinator(store: store)
    }

    func makeNSView(context: Context) -> EntryGridView {
        let view = EntryGridView()
        context.coordinator.bind(to: view)
        return view
    }

    func updateNSView(_ view: EntryGridView, context: Context) {
        context.coordinator.updateView(view)
    }
}

final class EntryGridView: NSView {
    protocol EntryGridCollectionViewMenuProviding: AnyObject {
        func contextMenu(for indexPath: IndexPath?, event: NSEvent) -> NSMenu
    }

    final class EntryGridCollectionView: NSCollectionView {
        weak var contextMenuProvider: EntryGridCollectionViewMenuProviding?
        var onSelectionDrag: (() -> Void)?
        var onLassoSelectionIndexPathsChanged: ((Set<IndexPath>, Bool) -> Void)?
        var onLassoActiveChanged: ((Bool) -> Void)?

        private var lassoStartPoint: NSPoint?
        private var lassoInitialSelection: Set<IndexPath> = []
        private var lastReportedLassoSelection: Set<IndexPath> = []
        private var isLassoActive: Bool = false

        override func mouseDown(with event: NSEvent) {
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

        override func rightMouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            if let indexPath = indexPathForItem(at: location),
               !selectionIndexPaths.contains(indexPath)
            {
                selectItems(at: [indexPath], scrollPosition: [])
            }
            super.rightMouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)

            guard isLassoActive, let start = lassoStartPoint, let layout = collectionViewLayout else {
                onSelectionDrag?()
                return
            }

            let current = convert(event.locationInWindow, from: nil)
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

            let isAdditive = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
            if isAdditive {
                selection.formUnion(lassoInitialSelection)
            }

            if selection != lastReportedLassoSelection {
                lastReportedLassoSelection = selection
                onLassoSelectionIndexPathsChanged?(selection, false)
            }

            onSelectionDrag?()
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)

            guard isLassoActive, let start = lassoStartPoint, let layout = collectionViewLayout else {
                return
            }

            let current = convert(event.locationInWindow, from: nil)
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

            let isAdditive = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
            if isAdditive {
                selection.formUnion(lassoInitialSelection)
            }

            onLassoSelectionIndexPathsChanged?(selection, true)

            isLassoActive = false
            lassoStartPoint = nil
            lassoInitialSelection = []
            lastReportedLassoSelection = []
            onLassoActiveChanged?(false)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let location = convert(event.locationInWindow, from: nil)
            let indexPath = indexPathForItem(at: location)
            return contextMenuProvider?.contextMenu(for: indexPath, event: event)
        }
    }

    let scrollView = NSScrollView()
    let collectionView = EntryGridCollectionView()
    let flowLayout = NSCollectionViewFlowLayout()

    var onLayout: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViewTree()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
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

    override func layout() {
        super.layout()
        onLayout?(bounds.width)
    }
}

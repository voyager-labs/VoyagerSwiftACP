@preconcurrency import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
public struct EntryGridViewRepresentable: NSViewRepresentable {
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

    public func makeCoordinator() -> EntryGridCoordinator {
        EntryGridCoordinator(store: store)
    }

    public func makeNSView(context: Context) -> EntryGridView {
        let view = EntryGridView()
        context.coordinator.bind(to: view)
        view.collectionView.blankSpaceContextMenuProvider = blankSpaceMenuProvider
        view.scrollView.onGoBack = onGoBack
        view.scrollView.onGoForward = onGoForward
        view.scrollView.onSwipeProgress = onSwipeProgress
        return view
    }

    public func updateNSView(_ view: EntryGridView, context: Context) {
        context.coordinator.updateView(view)
        view.collectionView.blankSpaceContextMenuProvider = blankSpaceMenuProvider
        view.scrollView.onGoBack = onGoBack
        view.scrollView.onGoForward = onGoForward
        view.scrollView.onSwipeProgress = onSwipeProgress
    }

    public static func dismantleNSView(_ view: EntryGridView, coordinator: EntryGridCoordinator) {
        view.scrollView.onSwipeProgress(nil)
        view.scrollView.onGoBack = {}
        view.scrollView.onGoForward = {}
        view.scrollView.onSwipeProgress = { _ in }
        coordinator.externalDropSessionController.cancel()
    }
}

public final class EntryGridView: NSView {
    @MainActor
    protocol EntryGridCollectionViewMenuProviding: AnyObject {
        func contextMenu(for indexPath: IndexPath?, event: NSEvent) -> NSMenu
    }

    final class EntryGridCollectionView: NSCollectionView {
        weak var contextMenuProvider: EntryGridCollectionViewMenuProviding?
        var blankSpaceContextMenuProvider: (() -> NSMenu)?
        var onSelectionDrag: (() -> Void)?
        var onLassoSelectionIndexPathsChanged: ((Set<IndexPath>, Bool) -> Void)?
        var onLassoActiveChanged: ((Bool) -> Void)?
        /// 빈 영역 클릭(좌/우, non-additive)이 시작될 때 호출된다. coordinator가 1회성 user-clear provenance를 표시한다.
        var onBlankSpaceSelectionClear: (() -> Void)?
        /// Command 클릭으로 item 선택 토글이 시작될 때 호출된다. 마지막 항목 해제 provenance에 사용된다.
        var onCommandItemClick: (() -> Void)?

        private var lassoStartPoint: NSPoint?
        private var lassoInitialSelection: Set<IndexPath> = []
        private var lastReportedLassoSelection: Set<IndexPath> = []
        private var isLassoActive: Bool = false

        override func mouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            if indexPathForItem(at: location) != nil {
                if event.modifierFlags.contains(.command) {
                    onCommandItemClick?()
                }
            } else {
                let isAdditive = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
                if !isAdditive {
                    onBlankSpaceSelectionClear?()
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
            guard let indexPath = indexPathForItem(at: location) else {
                onBlankSpaceSelectionClear?()
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

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)

            guard isLassoActive else {
                onSelectionDrag?()
                return
            }

            let current = convert(event.locationInWindow, from: nil)
            applyLassoSelection(current: current, modifierFlags: event.modifierFlags, isFinal: false)

            onSelectionDrag?()
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)

            guard isLassoActive else {
                return
            }

            let current = convert(event.locationInWindow, from: nil)
            applyLassoSelection(current: current, modifierFlags: event.modifierFlags, isFinal: true)
        }

        func updateLassoSelectionFromAutoscroll(_ point: NSPoint) {
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

        override func menu(for event: NSEvent) -> NSMenu? {
            let location = convert(event.locationInWindow, from: nil)
            let indexPath = indexPathForItem(at: location)
            guard let indexPath else { return nil }
            return contextMenuProvider?.contextMenu(for: indexPath, event: event)
        }
    }

    let scrollView = EntryHistorySwipeScrollView()
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
        collectionView.registerForDraggedTypes(EntryViewLayoutDropValidationAdapter.registeredDraggedTypes)

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

import AppKit
import SwiftUI

struct FixedLocationSidebarButtonHost: NSViewRepresentable {
    let rootView: AnyView
    let accessibilityLabel: String
    let isEnabled: Bool
    let reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
    let onActivate: () -> Void

    func makeNSView(context _: Context) -> FixedLocationSidebarButton {
        let button = FixedLocationSidebarButton(frame: .zero)
        update(button)
        return button
    }

    func updateNSView(
        _ button: FixedLocationSidebarButton,
        context _: Context,
    ) {
        update(button)
    }

    static func dismantleNSView(_ button: FixedLocationSidebarButton, coordinator _: ()) {
        button.dismantle()
    }

    private func update(_ button: FixedLocationSidebarButton) {
        button.update(
            rootView: rootView,
            accessibilityLabel: accessibilityLabel,
            isEnabled: isEnabled,
            reorderDragSource: reorderDragSource,
            onActivate: onActivate,
        )
    }
}

@MainActor
final class FixedLocationSidebarButton: NSButton, NSDraggingSource {
    private struct PointerTracking {
        let localOrigin: NSPoint
        let dragSource: FileManagerTopNavigationReorderDragSourceConfiguration
    }

    private enum PointerState {
        case idle
        case tracking(PointerTracking)
        case dragging(FileManagerTopNavigationReorderPasteboardWriter)
    }

    private static let reorderDragThreshold: CGFloat = 4

    private let presentationView = FixedLocationSidebarPresentationHostingView(rootView: AnyView(EmptyView()))
    private var pointerState = PointerState.idle
    private var reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
    private var onActivate: () -> Void = {}

    var dragSessionStartOverride: (([NSDraggingItem], NSEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureControl()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        presentationView.fittingSize
    }

    func update(
        rootView: AnyView,
        accessibilityLabel: String,
        isEnabled: Bool,
        reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?,
        onActivate: @escaping () -> Void,
    ) {
        self.reorderDragSource = reorderDragSource
        self.onActivate = onActivate
        self.isEnabled = isEnabled
        presentationView.rootView = rootView
        setAccessibilityLabel(accessibilityLabel)
        presentationView.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        presentationView.needsLayout = true
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0, isEnabled, let reorderDragSource else {
            super.mouseDown(with: event)
            return
        }

        trackPointer(from: PointerTracking(
            localOrigin: convert(event.locationInWindow, from: nil),
            dragSource: reorderDragSource,
        ))
    }

    func draggingSession(
        _: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext,
    ) -> NSDragOperation {
        switch context {
        case .withinApplication:
            .move
        case .outsideApplication:
            []
        @unknown default:
            []
        }
    }

    func draggingSession(
        _: NSDraggingSession,
        endedAt _: NSPoint,
        operation _: NSDragOperation,
    ) {
        cleanupDragging()
    }

    func ignoreModifierKeys(for _: NSDraggingSession) -> Bool {
        true
    }

    func dismantle() {
        cleanupDragging()
        cancelPointerTracking()
    }

    private func configureControl() {
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        target = self
        action = #selector(handlePrimaryAction)
        sendAction(on: .leftMouseUp)
        setAccessibilityElement(true)

        presentationView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(presentationView)
        NSLayoutConstraint.activate([
            presentationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            presentationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            presentationView.topAnchor.constraint(equalTo: topAnchor),
            presentationView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func trackPointer(from tracking: PointerTracking) {
        pointerState = .tracking(tracking)
        isHighlighted = true
        guard let window else {
            cancelPointerTracking()
            return
        }

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        while case .tracking = pointerState {
            guard let event = window.nextEvent(
                matching: eventMask,
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true,
            ) else {
                cancelPointerTracking()
                return
            }

            let localLocation = convert(event.locationInWindow, from: nil)
            switch event.type {
            case .leftMouseDragged:
                isHighlighted = bounds.contains(localLocation)
                if hypot(
                    localLocation.x - tracking.localOrigin.x,
                    localLocation.y - tracking.localOrigin.y,
                ) >= Self.reorderDragThreshold {
                    startDragging(from: tracking, event: event)
                    return
                }
            case .leftMouseUp:
                finishPointerTracking(mouseUpLocation: localLocation)
                return
            default:
                break
            }
        }
    }

    private func finishPointerTracking(mouseUpLocation: NSPoint) {
        pointerState = .idle
        isHighlighted = false
        guard isEnabled, bounds.contains(mouseUpLocation) else { return }
        onActivate()
    }

    private func startDragging(
        from tracking: PointerTracking,
        event: NSEvent,
    ) {
        do {
            let writer = try FileManagerTopNavigationReorderPasteboardWriter(
                payload: tracking.dragSource.payload,
                sessionStore: tracking.dragSource.sessionStore,
            )
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            draggingItem.setDraggingFrame(bounds, contents: draggingImage())
            pointerState = .dragging(writer)
            isHighlighted = false

            if let dragSessionStartOverride {
                dragSessionStartOverride([draggingItem], event)
            } else {
                beginDraggingSession(
                    with: [draggingItem],
                    event: event,
                    source: self,
                )
            }
        } catch {
            cancelPointerTracking()
        }
    }

    private func draggingImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
            return image
        }
        cacheDisplay(in: bounds, to: representation)
        image.addRepresentation(representation)
        return image
    }

    private func cleanupDragging() {
        guard case let .dragging(writer) = pointerState else { return }
        writer.cleanupOwnedToken()
        pointerState = .idle
        isHighlighted = false
    }

    private func cancelPointerTracking() {
        if case .tracking = pointerState {
            pointerState = .idle
        }
        isHighlighted = false
    }

    @objc
    private func handlePrimaryAction() {
        onActivate()
    }
}

@MainActor
private final class FixedLocationSidebarPresentationHostingView: NSHostingView<AnyView> {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

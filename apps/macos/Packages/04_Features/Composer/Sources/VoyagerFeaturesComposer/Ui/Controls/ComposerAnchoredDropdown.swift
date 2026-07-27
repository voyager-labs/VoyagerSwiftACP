import AppKit
import SwiftUI
import VoyagerShared

struct ComposerAnchoredDropdown<Label: View, Content: View>: View {
    @Binding private var isPresented: Bool
    private let dropdownAccessibilityIdentifier: String
    private let label: Label
    private let content: Content

    init(
        isPresented: Binding<Bool>,
        dropdownAccessibilityIdentifier: String = "composer.property.dropdown",
        @ViewBuilder label: () -> Label,
        @ViewBuilder content: () -> Content,
    ) {
        _isPresented = isPresented
        self.dropdownAccessibilityIdentifier = dropdownAccessibilityIdentifier
        self.label = label()
        self.content = content()
    }

    var body: some View {
        label.background(
            ComposerAnchoredDropdownPresenter(
                isPresented: $isPresented,
                accessibilityIdentifier: dropdownAccessibilityIdentifier,
                content: content,
            ),
        )
    }
}

private struct ComposerAnchoredDropdownPresenter<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let accessibilityIdentifier: String
    let content: Content

    func makeNSView(context: Context) -> ComposerAnchoredDropdownAnchorView {
        context.coordinator.anchorView
    }

    func updateNSView(_ anchorView: ComposerAnchoredDropdownAnchorView, context: Context) {
        context.coordinator.update(
            binding: $isPresented,
            isPresented: isPresented,
            content: content,
            accessibilityIdentifier: accessibilityIdentifier,
            relativeTo: anchorView,
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, content: content)
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        let anchorView = ComposerAnchoredDropdownAnchorView(frame: .zero)
        let contentController: NSHostingController<ComposerAnchoredDropdownSurface<Content>>
        var binding: Binding<Bool>
        private var panel: ComposerAnchoredDropdownPanel?
        private var mouseDownMonitor: Any?
        private weak var parentWindow: NSWindow?
        private weak var previousFirstResponder: NSResponder?
        private var isDismissing = false

        init(isPresented: Binding<Bool>, content: Content) {
            binding = isPresented
            contentController = NSHostingController(rootView: ComposerAnchoredDropdownSurface(content: content))
            super.init()

            anchorView.onGeometryChange = { [weak self] in
                self?.updatePanelFrame()
            }
        }

        deinit {
            MainActor.assumeIsolated {
                dismissPanel(restoreFocus: false)
            }
        }

        func update(
            binding: Binding<Bool>,
            isPresented: Bool,
            content: Content,
            accessibilityIdentifier: String,
            relativeTo anchorView: NSView,
        ) {
            self.binding = binding
            contentController.rootView = ComposerAnchoredDropdownSurface(content: content)
            contentController.view.setAccessibilityIdentifier(accessibilityIdentifier)
            contentController.view.layoutSubtreeIfNeeded()

            if isPresented {
                show(relativeTo: anchorView)
            } else {
                dismissPanel()
            }
        }

        func windowDidResignKey(_ notification: Notification) {
            guard notification.object as? NSWindow === panel, !isDismissing else { return }
            requestDismiss()
        }

        private func show(relativeTo anchorView: NSView) {
            guard let parentWindow = anchorView.window else { return }
            let panel = panel ?? makePanel()

            if self.panel == nil {
                panel.contentViewController = contentController
                self.panel = panel
            }
            if self.parentWindow !== parentWindow {
                self.parentWindow?.removeChildWindow(panel)
                parentWindow.addChildWindow(panel, ordered: .above)
                self.parentWindow = parentWindow
            }
            if !panel.isVisible {
                previousFirstResponder = parentWindow.firstResponder
                updatePanelFrame()
                panel.makeKeyAndOrderFront(nil)
                startMouseDownMonitor()
            } else {
                updatePanelFrame()
            }
        }

        private func makePanel() -> ComposerAnchoredDropdownPanel {
            let panel = ComposerAnchoredDropdownPanel(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
            )
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = true
            panel.isOpaque = false
            panel.level = .floating
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
            panel.delegate = self
            panel.onCancel = { [weak self] in
                self?.requestDismiss()
            }
            return panel
        }

        private func updatePanelFrame() {
            guard let panel,
                  let parentWindow,
                  anchorView.window === parentWindow
            else {
                return
            }

            contentController.view.layoutSubtreeIfNeeded()
            let fittingSize = contentController.view.fittingSize
            guard fittingSize.width > 0, fittingSize.height > 0 else { return }

            let anchorWindowFrame = anchorView.convert(anchorView.bounds, to: nil)
            let anchorScreenFrame = parentWindow.convertToScreen(anchorWindowFrame)
            let visibleFrame = parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let gap = ComposerUIMetrics.anchoredDropdownGap
            let maximumX = max(visibleFrame.minX, visibleFrame.maxX - fittingSize.width)
            let originX = min(max(anchorScreenFrame.minX, visibleFrame.minX), maximumX)
            let belowOriginY = anchorScreenFrame.minY - fittingSize.height - gap
            let aboveOriginY = anchorScreenFrame.maxY + gap
            let maximumY = max(visibleFrame.minY, visibleFrame.maxY - fittingSize.height)
            let preferredY = belowOriginY >= visibleFrame.minY ? belowOriginY : aboveOriginY
            let originY = min(max(preferredY, visibleFrame.minY), maximumY)

            panel.setFrame(
                CGRect(origin: CGPoint(x: originX, y: originY), size: fittingSize),
                display: true,
            )
        }

        private func startMouseDownMonitor() {
            guard mouseDownMonitor == nil else { return }
            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
            ]) { [weak self] event in
                guard let self else { return event }
                if event.window === panel {
                    return event
                }
                if let eventWindow = event.window {
                    let screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
                    let anchorWindowFrame = anchorView.convert(anchorView.bounds, to: nil)
                    let anchorScreenFrame = parentWindow?.convertToScreen(anchorWindowFrame) ?? .null
                    if anchorScreenFrame.contains(screenPoint) {
                        return event
                    }
                }
                requestDismiss()
                return event
            }
        }

        private func requestDismiss() {
            if binding.wrappedValue {
                binding.wrappedValue = false
            }
            dismissPanel()
        }

        private func dismissPanel(restoreFocus: Bool = true) {
            guard !isDismissing else { return }
            isDismissing = true
            defer { isDismissing = false }

            if let mouseDownMonitor {
                NSEvent.removeMonitor(mouseDownMonitor)
                self.mouseDownMonitor = nil
            }
            guard let panel else { return }

            let parentWindow = parentWindow
            parentWindow?.removeChildWindow(panel)
            panel.orderOut(nil)
            if restoreFocus, let parentWindow, parentWindow.isVisible {
                parentWindow.makeKeyAndOrderFront(nil)
                if let previousFirstResponder {
                    parentWindow.makeFirstResponder(previousFirstResponder)
                }
            }
            self.parentWindow = nil
            previousFirstResponder = nil
        }
    }
}

private struct ComposerAnchoredDropdownSurface<Content: View>: View {
    @Environment(\.colorScheme)
    private var colorScheme
    let content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                    .fill(VoyagerDS.Surface.popoverBackground(for: colorScheme)),
            )
            .clipShape(RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                    .stroke(VoyagerDS.Surface.popoverBorder, lineWidth: 1),
            )
    }
}

private final class ComposerAnchoredDropdownPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_: Any?) {
        onCancel?()
    }
}

private final class ComposerAnchoredDropdownAnchorView: NSView {
    var onGeometryChange: (() -> Void)?

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notifyGeometryChange()
    }

    override func layout() {
        super.layout()
        notifyGeometryChange()
    }

    private func notifyGeometryChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onGeometryChange?()
        }
    }
}

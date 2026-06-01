import AppKit
import SwiftUI

@MainActor
final class ComposerScopeOverlayCoordinator {
    private var panel: ComposerScopeOverlayPanel?
    private var mouseDownMonitor: Any?
    private var anchorScreenFrame: CGRect = .null
    private var content: (() -> AnyView)?
    private weak var parentWindow: NSWindow?

    deinit {
        MainActor.assumeIsolated {
            dismiss()
        }
    }

    func updateAnchorScreenFrame(_ frame: CGRect) {
        anchorScreenFrame = frame
        updatePanelFrame()
    }

    func update(
        isPresented: Bool,
        parentWindow: NSWindow?,
        content: @escaping (CGFloat) -> AnyView,
        onDismiss: @escaping () -> Void,
    ) {
        if isPresented {
            show(parentWindow: parentWindow, content: content, onDismiss: onDismiss)
        } else {
            dismiss()
        }
    }

    func dismiss() {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
        if let panel {
            parentWindow?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil
        }
        parentWindow = nil
    }

    private func show(
        parentWindow: NSWindow?,
        content: @escaping (CGFloat) -> AnyView,
        onDismiss: @escaping () -> Void,
    ) {
        guard !anchorScreenFrame.isNull, let parentWindow else { return }

        self.content = { [weak self] in
            content(self?.preferredPanelHeight() ?? 360)
        }

        let panel = panel ?? makePanel()
        let rootView = self.content?() ?? content(360)
        let hostingController = panel.contentViewController as? NSHostingController<AnyView>
        hostingController?.rootView = rootView
        if self.panel == nil {
            panel.contentViewController = makeHostingController(rootView: rootView)
            parentWindow.addChildWindow(panel, ordered: .above)
            self.panel = panel
        } else if self.parentWindow !== parentWindow {
            self.parentWindow?.removeChildWindow(panel)
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        self.parentWindow = parentWindow

        updatePanelFrame()
        panel.makeKeyAndOrderFront(nil)
        startMouseDownMonitor(onDismiss: onDismiss)
    }

    private func makeHostingController(rootView: AnyView) -> NSHostingController<AnyView> {
        let hostingController = NSHostingController(rootView: rootView)
        configureRoundedContentView(hostingController.view)
        return hostingController
    }

    private func configureRoundedContentView(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = 8
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }

    private func makePanel() -> ComposerScopeOverlayPanel {
        let panel = ComposerScopeOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        return panel
    }

    private func updatePanelFrame() {
        guard let panel, !anchorScreenFrame.isNull else { return }
        let panelHeight = preferredPanelHeight()
        let panelSize = CGSize(width: 420, height: panelHeight)
        let origin = CGPoint(
            x: anchorScreenFrame.maxX - panelSize.width,
            y: anchorScreenFrame.minY - panelSize.height - 8,
        )
        panel.setFrame(CGRect(origin: origin, size: panelSize), display: true)
        if let contentView = panel.contentView {
            configureRoundedContentView(contentView)
        }
        if let hostingController = panel.contentViewController as? NSHostingController<AnyView>,
           let content
        {
            hostingController.rootView = content()
            configureRoundedContentView(hostingController.view)
        }
    }

    private func preferredPanelHeight() -> CGFloat {
        let desiredHeight: CGFloat = 420
        let minimumHeight: CGFloat = 280
        let verticalMargin: CGFloat = 12
        let availableHeight = anchorScreenFrame.minY
            - (parentWindow?.screen?.visibleFrame.minY ?? NSScreen.main?.visibleFrame.minY ?? 0)
            - verticalMargin
        return min(desiredHeight, max(minimumHeight, availableHeight))
    }

    private func startMouseDownMonitor(onDismiss: @escaping () -> Void) {
        if mouseDownMonitor != nil { return }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
        ]) { [weak self] event in
            guard let self else { return event }
            if event.window === panel {
                return event
            }
            guard let window = event.window else {
                return event
            }

            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            if !anchorScreenFrame.contains(screenPoint) {
                onDismiss()
                dismiss()
            }
            return event
        }
    }
}

private final class ComposerScopeOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

struct ComposerAnchorFrameReader: NSViewRepresentable {
    let onFrameChange: (CGRect, NSWindow?) -> Void

    func makeNSView(context _: Context) -> ComposerAnchorFrameReportingView {
        ComposerAnchorFrameReportingView(onFrameChange: onFrameChange)
    }

    func updateNSView(_ nsView: ComposerAnchorFrameReportingView, context _: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.reportFrame()
    }
}

final class ComposerAnchorFrameReportingView: NSView {
    var onFrameChange: (CGRect, NSWindow?) -> Void

    init(onFrameChange: @escaping (CGRect, NSWindow?) -> Void) {
        self.onFrameChange = onFrameChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrame()
    }

    override func layout() {
        super.layout()
        reportFrame()
    }

    func reportFrame() {
        guard let window else { return }
        let windowFrame = convert(bounds, to: nil)
        let screenFrame = window.convertToScreen(windowFrame)
        DispatchQueue.main.async { [onFrameChange, weak window] in
            onFrameChange(screenFrame, window)
        }
    }
}

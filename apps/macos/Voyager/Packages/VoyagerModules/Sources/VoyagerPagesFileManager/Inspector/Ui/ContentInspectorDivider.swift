import AppKit

public class ContentInspectorDivider: NSView {
    var onResize: ((CGFloat) -> Void)?
    private var startX: CGFloat = 0
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.zPosition = 15
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func mouseDown(with event: NSEvent) {
        let locationInWindow = event.locationInWindow
        let locationInView = convert(locationInWindow, from: nil)
        if bounds.contains(locationInView) {
            startX = locationInWindow.x
            isDragging = true
        }
    }

    override public func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let deltaX = event.locationInWindow.x - startX
        onResize?(-deltaX)
        startX = event.locationInWindow.x
    }

    override public func mouseUp(with _: NSEvent) {
        isDragging = false
    }

    override public func resetCursorRects() {
        guard window != nil, !bounds.isEmpty else { return }
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}

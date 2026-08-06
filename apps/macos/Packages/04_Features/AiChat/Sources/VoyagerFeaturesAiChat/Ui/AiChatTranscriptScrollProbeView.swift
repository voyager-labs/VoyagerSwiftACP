import AppKit

final class AiChatTranscriptScrollProbeView: NSView {
    var onHierarchyChanged: (() -> Void)?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil { onHierarchyChanged?() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onHierarchyChanged?() }
    }
}

import AppKit
import SwiftUI

public struct HoverTrackingOverlay: NSViewRepresentable {
    @Binding private var isHovered: Bool

    public init(isHovered: Binding<Bool>) {
        _isHovered = isHovered
    }

    public func makeNSView(context _: Context) -> NSView {
        let view = TrackingView()
        view.onHover = { isHovered = $0 }
        return view
    }

    public func updateNSView(_ nsView: NSView, context _: Context) {
        guard let view = nsView as? TrackingView else {
            return
        }
        view.onHover = { isHovered = $0 }
    }

    private final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area

            super.updateTrackingAreas()
        }

        override func mouseEntered(with _: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with _: NSEvent) {
            onHover?(false)
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}

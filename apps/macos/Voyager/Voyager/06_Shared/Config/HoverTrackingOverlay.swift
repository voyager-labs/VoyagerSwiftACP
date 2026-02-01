import AppKit
import SwiftUI

struct HoverTrackingOverlay: NSViewRepresentable {
    @Binding var isHovered: Bool

    func makeNSView(context _: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = { isHovered = $0 }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context _: Context) {
        nsView.onHover = { isHovered = $0 }
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            // 타이틀바에서도 안정적으로 hover를 감지하기 위한 트래킹 영역.
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

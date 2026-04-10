import AppKit
import SwiftUI

struct SidebarRightClickCaptureView: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context _: Context) -> CaptureView {
        let view = CaptureView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CaptureView, context _: Context) {
        nsView.onRightClick = onRightClick
    }

    @MainActor
    final class CaptureView: NSView {
        var onRightClick: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                let location = convert(event.locationInWindow, from: nil)
                if bounds.contains(location) {
                    onRightClick?()
                }
                return event
            }
        }

        deinit {
            MainActor.assumeIsolated {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
        }
    }
}

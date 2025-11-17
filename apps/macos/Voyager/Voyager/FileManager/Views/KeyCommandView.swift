import AppKit
import SwiftUI

final class KeyCommandHostingView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }
}

struct KeyCommandView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void

    func makeNSView(context _: Context) -> KeyCommandHostingView {
        let view = KeyCommandHostingView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyCommandHostingView, context _: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

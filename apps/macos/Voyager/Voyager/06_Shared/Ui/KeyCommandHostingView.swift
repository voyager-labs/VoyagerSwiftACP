import AppKit
import SwiftUI

final class KeyCommandHostingView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    func restoreFocus() {
        window?.makeFirstResponder(self)
    }
}

struct KeyCommandView: NSViewRepresentable {
    var onViewCreated: ((KeyCommandHostingView) -> Void)?
    var onKeyDown: (NSEvent) -> Void

    init(
        onViewCreated: ((KeyCommandHostingView) -> Void)? = nil,
        onKeyDown: @escaping (NSEvent) -> Void,
    ) {
        self.onViewCreated = onViewCreated
        self.onKeyDown = onKeyDown
    }

    func makeNSView(context _: Context) -> KeyCommandHostingView {
        let view = KeyCommandHostingView()
        view.onKeyDown = onKeyDown
        onViewCreated?(view)
        return view
    }

    func updateNSView(_ nsView: KeyCommandHostingView, context _: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

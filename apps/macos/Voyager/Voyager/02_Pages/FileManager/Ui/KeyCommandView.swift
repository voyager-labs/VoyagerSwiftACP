import AppKit
import SwiftUI

final class KeyCommandHostingView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    weak static var currentFirstResponder: KeyCommandHostingView?

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        KeyCommandHostingView.currentFirstResponder = self
        return true
    }

    override func resignFirstResponder() -> Bool {
        if KeyCommandHostingView.currentFirstResponder == self {
            KeyCommandHostingView.currentFirstResponder = nil
        }
        return true
    }

    func restoreFocus() {
        window?.makeFirstResponder(self)
    }
}

func restoreFileManagerFocus() {
    DispatchQueue.main.async {
        KeyCommandHostingView.currentFirstResponder?.restoreFocus()
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

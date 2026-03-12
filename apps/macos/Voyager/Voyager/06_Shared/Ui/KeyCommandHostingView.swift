import AppKit
import SwiftUI

final class KeyCommandHostingView: NSView {
    weak static var currentFirstResponder: KeyCommandHostingView?
    var onKeyDown: ((NSEvent) -> Void)?

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

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

    override var acceptsFirstResponder: Bool { true }

    static func restoreCurrentFocus() {
        DispatchQueue.main.async {
            KeyCommandHostingView.currentFirstResponder?.restoreFocus()
        }
    }

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

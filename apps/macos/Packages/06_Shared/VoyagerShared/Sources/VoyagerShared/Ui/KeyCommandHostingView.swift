import AppKit
import SwiftUI

public final class KeyCommandHostingView: NSView {
    private weak static var currentFirstResponder: KeyCommandHostingView?
    fileprivate var onKeyDown: ((NSEvent) -> Void)?

    override public func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    override public func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override public func becomeFirstResponder() -> Bool {
        KeyCommandHostingView.currentFirstResponder = self
        return true
    }

    override public func resignFirstResponder() -> Bool {
        if KeyCommandHostingView.currentFirstResponder == self {
            KeyCommandHostingView.currentFirstResponder = nil
        }
        return true
    }

    override public var acceptsFirstResponder: Bool { true }

    static func restoreCurrentFocus() {
        DispatchQueue.main.async {
            KeyCommandHostingView.currentFirstResponder?.restoreFocus()
        }
    }

    func restoreFocus() {
        window?.makeFirstResponder(self)
    }
}

public struct KeyCommandView: NSViewRepresentable {
    public var onViewCreated: ((KeyCommandHostingView) -> Void)?
    public var onKeyDown: (NSEvent) -> Void

    public init(
        onViewCreated: ((KeyCommandHostingView) -> Void)? = nil,
        onKeyDown: @escaping (NSEvent) -> Void
    ) {
        self.onViewCreated = onViewCreated
        self.onKeyDown = onKeyDown
    }

    public func makeNSView(context _: Context) -> KeyCommandHostingView {
        let view = KeyCommandHostingView()
        view.onKeyDown = onKeyDown
        onViewCreated?(view)
        return view
    }

    public func updateNSView(_ nsView: KeyCommandHostingView, context _: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

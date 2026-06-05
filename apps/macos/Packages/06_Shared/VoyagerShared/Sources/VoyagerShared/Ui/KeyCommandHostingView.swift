import AppKit
import SwiftUI

public final class KeyCommandHostingView: NSView {
    fileprivate var onKeyDown: ((NSEvent) -> Void)?

    override public func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    override public func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override public var acceptsFirstResponder: Bool {
        true
    }
}

public struct KeyCommandView: NSViewRepresentable {
    public var onViewCreated: ((KeyCommandHostingView) -> Void)?
    public var onKeyDown: (NSEvent) -> Void

    public init(
        onViewCreated: ((KeyCommandHostingView) -> Void)? = nil,
        onKeyDown: @escaping (NSEvent) -> Void,
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

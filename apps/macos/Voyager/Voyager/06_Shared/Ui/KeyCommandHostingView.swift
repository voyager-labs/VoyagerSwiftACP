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

    // TODO: 현재 Sidebar onTap에서도 이 API를 호출하고 있어 Shared UI 레이어가 FileManager 포커스 정책에 결합되어 있다. 포커스 복구 책임 위치를 재설계하자.
    static func restoreCurrentFocus() {
        DispatchQueue.main.async {
            KeyCommandHostingView.currentFirstResponder?.restoreFocus()
        }
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

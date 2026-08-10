import AppKit
import SwiftUI
import VoyagerShared

@MainActor
final class FileManagerKeyCommandFocusCoordinator {
    private weak var keyCommandView: KeyCommandHostingView?

    func register(_ view: KeyCommandHostingView) {
        keyCommandView = view
    }

    func requestFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.keyCommandView, let window = view.window else { return }
            guard !Self.isEditingText(window.firstResponder) else { return }
            window.makeFirstResponder(view)
        }
    }

    private static func isEditingText(_ responder: NSResponder?) -> Bool {
        guard let textView = responder as? NSTextView else { return false }
        return textView.isEditable
    }
}

extension EnvironmentValues {
    @Entry var fileManagerKeyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator?
}

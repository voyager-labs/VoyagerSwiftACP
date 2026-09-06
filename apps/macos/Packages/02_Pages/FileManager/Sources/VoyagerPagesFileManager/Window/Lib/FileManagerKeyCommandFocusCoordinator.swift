import AppKit
import SwiftUI
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@MainActor
final class FileManagerKeyCommandFocusCoordinator {
    private weak var keyCommandView: KeyCommandHostingView?
    private weak var entryListView: EntryListView?

    func register(_ view: KeyCommandHostingView) {
        keyCommandView = view
    }

    func registerEntryListView(_ view: EntryListView?) {
        entryListView = view
    }

    func routeEntryListKeyDown(_ event: NSEvent) -> Bool {
        entryListView?.handleListKeyDown(with: event) == true
    }

    func requestFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.keyCommandView, let window = view.window else { return }
            guard !Self.isEditingText(window.firstResponder) else { return }
            window.makeFirstResponder(view)
        }
    }

    func cancelMarkedText() {
        keyCommandView?.cancelMarkedTextComposition()
    }

    private static func isEditingText(_ responder: NSResponder?) -> Bool {
        guard let textView = responder as? NSTextView else { return false }
        return textView.isEditable
    }
}

extension EnvironmentValues {
    @Entry var fileManagerKeyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator?
}

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
            guard let view = self?.keyCommandView else { return }
            view.window?.makeFirstResponder(view)
        }
    }
}

extension EnvironmentValues {
    @Entry var fileManagerKeyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator?
}

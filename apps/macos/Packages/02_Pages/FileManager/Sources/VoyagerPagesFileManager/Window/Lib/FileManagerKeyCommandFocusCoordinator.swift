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

private struct FileManagerKeyCommandFocusCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: FileManagerKeyCommandFocusCoordinator? = nil
}

extension EnvironmentValues {
    var fileManagerKeyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator? {
        get { self[FileManagerKeyCommandFocusCoordinatorEnvironmentKey.self] }
        set { self[FileManagerKeyCommandFocusCoordinatorEnvironmentKey.self] = newValue }
    }
}

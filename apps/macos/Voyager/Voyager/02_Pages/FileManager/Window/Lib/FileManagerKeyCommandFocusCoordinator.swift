import AppKit
import SwiftUI

@MainActor
final class FileManagerKeyCommandFocusCoordinator {
    private weak var keyCommandView: KeyCommandHostingView?
    private var isFocusAllowed: Bool = true

    func register(_ view: KeyCommandHostingView) {
        keyCommandView = view
    }

    func setFocusAllowed(_ allowed: Bool) {
        isFocusAllowed = allowed
    }

    func requestFocus() {
        guard isFocusAllowed else { return }

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

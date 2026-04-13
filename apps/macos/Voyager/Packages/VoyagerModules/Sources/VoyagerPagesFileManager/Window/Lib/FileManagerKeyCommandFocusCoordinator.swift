import AppKit
import SwiftUI

@MainActor
public final class FileManagerKeyCommandFocusCoordinator {
    public private(set) weak var keyCommandView: KeyCommandHostingView?

    public func register(_ view: KeyCommandHostingView) {
        keyCommandView = view
    }

    public func requestFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.keyCommandView else { return }
            view.window?.makeFirstResponder(view)
        }
    }
}

public struct FileManagerKeyCommandFocusCoordinatorEnvironmentKey: EnvironmentKey {
    public static let defaultValue: FileManagerKeyCommandFocusCoordinator? = nil
}

public extension EnvironmentValues {
    var fileManagerKeyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator? {
        get { self[FileManagerKeyCommandFocusCoordinatorEnvironmentKey.self] }
        set { self[FileManagerKeyCommandFocusCoordinatorEnvironmentKey.self] = newValue }
    }
}

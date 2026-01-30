import Combine
import ComposableArchitecture
import SwiftUI

class FileManagerWindowController: NSWindowController, NSWindowDelegate {
    private let initialPath: String?
    let windowUndoManager: UndoManager
    let store: StoreOf<FileManagerFeature>
    var cancellables: Set<AnyCancellable> = []

    init(
        registryClient: RegistryClient,
        path: String? = nil,
        duplicateState: FileManagerFeature.State? = nil,
        asTab: Bool = true,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)? = nil,
    ) {
        initialPath = path
        let state = Self.createInitialState(path: path, duplicateState: duplicateState)
        let undoManager = UndoManager()
        windowUndoManager = undoManager
        store = Self.createStore(
            state: state,
            undoManager: undoManager,
            registryClient: registryClient,
        )

        let window = Self.createWindow(
            store: store,
            path: path,
            state: state,
            asTab: asTab,
            makeContentViewController: makeContentViewController,
        )

        super.init(window: window)
        window.delegate = self
        Self.setupWindowFrame(window, path ?? state.currentPath)
        window.title = FileManagerFeature.makeWindowTitle(
            for: path ?? state.currentPath,
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

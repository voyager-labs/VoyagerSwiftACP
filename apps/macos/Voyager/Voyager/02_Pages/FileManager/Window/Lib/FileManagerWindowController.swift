import AppKit
import ComposableArchitecture

class FileManagerWindowController: NSWindowController, NSWindowDelegate {
    let windowID: UUID
    let windowUndoManager: UndoManager
    let store: StoreOf<FileManagerFeature>
    private let onBecameKey: (@MainActor (UUID) -> Void)?
    private let onResignedKey: (@MainActor (UUID) -> Void)?
    private let onWillClose: (@MainActor (UUID) -> Void)?
    private let initialWindowSizeProvider: (() -> NSSize?)?
    /// 외부에서 store/undoManager를 주입하는 designated initializer.
    ///
    /// - AppRootFeature 기반 윈도우 세션으로 전환할 때 사용한다.
    init(
        windowID: UUID,
        store: StoreOf<FileManagerFeature>,
        windowUndoManager: UndoManager,
        path: String? = nil,
        onBecameKey: (@MainActor (UUID) -> Void)? = nil,
        onResignedKey: (@MainActor (UUID) -> Void)? = nil,
        onWillClose: (@MainActor (UUID) -> Void)? = nil,
        initialWindowSizeProvider: (() -> NSSize?)? = nil,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)? = nil,
    ) {
        self.windowID = windowID
        self.store = store
        self.windowUndoManager = windowUndoManager
        self.onBecameKey = onBecameKey
        self.onResignedKey = onResignedKey
        self.onWillClose = onWillClose
        self.initialWindowSizeProvider = initialWindowSizeProvider

        let window = FileManagerWindowView.makeWindow(
            store: store,
            path: path,
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
        )

        super.init(window: window)
        window.delegate = self
    }

    init(
        registryClient: RegistryClient,
        path: String? = nil,
        duplicateState: FileManagerFeature.State? = nil,
        onBecameKey: (@MainActor (UUID) -> Void)? = nil,
        onResignedKey: (@MainActor (UUID) -> Void)? = nil,
        onWillClose: (@MainActor (UUID) -> Void)? = nil,
        initialWindowSizeProvider: (() -> NSSize?)? = nil,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)? = nil,
    ) {
        let windowID = UUID()
        let state = Self.createInitialState(windowID: windowID, path: path, duplicateState: duplicateState)
        let undoManager = UndoManager()
        let store = Self.createStore(
            state: state,
            undoManager: undoManager,
            registryClient: registryClient,
        )

        self.windowID = windowID
        self.store = store
        windowUndoManager = undoManager
        self.onBecameKey = onBecameKey
        self.onResignedKey = onResignedKey
        self.onWillClose = onWillClose
        self.initialWindowSizeProvider = initialWindowSizeProvider

        let window = FileManagerWindowView.makeWindow(
            store: store,
            path: path,
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
        )

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func createInitialState(
        windowID: UUID,
        path: String?,
        duplicateState: FileManagerFeature.State?,
    ) -> FileManagerFeature.State {
        var state: FileManagerFeature.State
        if let duplicateState {
            var newState = duplicateState
            newState.content.entries = EntryFeature.State()
            newState.content.entryOperations = EntryOperationsState()
            newState.content.entryOperations.windowID = windowID
            state = newState
        } else {
            state = FileManagerFeature.State()
            state.content.entryOperations.windowID = windowID
        }

        if duplicateState == nil, let path {
            state.content.navigation.navigationState = .folder(path)
            state.content.navigation.titlePath = path
        }

        return state
    }

    private static func createStore(
        state: FileManagerFeature.State,
        undoManager: UndoManager,
        registryClient: RegistryClient,
    ) -> StoreOf<FileManagerFeature> {
        Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = .live(undoManager: undoManager)
            $0.registryClient = registryClient
        }
    }
}

// MARK: - NSWindowDelegate

extension FileManagerWindowController {
    func windowDidBecomeKey(_: Notification) {
        if let onBecameKey {
            onBecameKey(windowID)
        }
    }

    func windowDidResignKey(_: Notification) {
        if let onResignedKey {
            onResignedKey(windowID)
        }
    }

    func window(
        _: NSWindow,
        willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions,
    ) -> NSApplication.PresentationOptions {
        var options = proposedOptions
        options.insert(.autoHideMenuBar)
        options.insert(.autoHideDock)
        options.insert(.fullScreen)

        if #available(macOS 11.0, *) {
            options.insert(.autoHideToolbar)
        }
        return options
    }

    func windowWillClose(_: Notification) {
        if let onWillClose {
            onWillClose(windowID)
        }
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        true
    }

    func windowWillReturnUndoManager(_: NSWindow) -> UndoManager? {
        windowUndoManager
    }
}

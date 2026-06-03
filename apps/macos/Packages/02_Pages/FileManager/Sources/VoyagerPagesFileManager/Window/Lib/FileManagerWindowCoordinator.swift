import AppKit
import Combine
import ComposableArchitecture
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

public final class FileManagerWindowCoordinator: NSWindowController, NSWindowDelegate {
    public let windowID: UUID
    public let windowUndoManager: UndoManager
    public let store: StoreOf<FileManagerFeature>
    private let onBecameKey: (@MainActor (UUID) -> Void)?
    private let onResignedKey: (@MainActor (UUID) -> Void)?
    private let onWillClose: (@MainActor (UUID) -> Void)?
    private let initialWindowSizeProvider: (() -> NSSize?)?
    private var cancellables: Set<AnyCancellable> = []

    public init(
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

        let window = Self.makeWindow(
            store: store,
            path: path,
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
        )

        super.init(window: window)
        window.delegate = self
        FileManagerWindowChrome.bindTitle(to: window, store: store, cancellables: &cancellables)
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
        let state = Self.createInitialState(path: path, duplicateState: duplicateState)
        let undoManager = UndoManager()
        let store = Self.createStore(
            state: state,
            undoManager: undoManager,
            registryClient: registryClient,
        )

        if duplicateState != nil {
            store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.resetForDuplicate(windowID: windowID))))))
        } else {
            store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(windowID))))))
        }

        self.windowID = windowID
        self.store = store
        windowUndoManager = undoManager
        self.onBecameKey = onBecameKey
        self.onResignedKey = onResignedKey
        self.onWillClose = onWillClose
        self.initialWindowSizeProvider = initialWindowSizeProvider

        let window = Self.makeWindow(
            store: store,
            path: path,
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
        )

        super.init(window: window)
        window.delegate = self
        FileManagerWindowChrome.bindTitle(to: window, store: store, cancellables: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func createInitialState(
        path: String?,
        duplicateState: FileManagerFeature.State?,
    ) -> FileManagerFeature.State {
        var state: FileManagerFeature.State = if let duplicateState {
            duplicateState
        } else {
            FileManagerFeature.State()
        }

        if let path {
            state.content.navigation.seedInitialFolderPath(path)
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

    private static func makeWindow(
        store: StoreOf<FileManagerFeature>,
        path: String?,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)?,
        initialWindowSizeProvider: (() -> NSSize?)?,
    ) -> NSWindow {
        let contentViewController: NSViewController = if let makeContentViewController {
            makeContentViewController(store, path)
        } else {
            FileManagerWindowSplitCoordinator(
                store: store,
                isDark: FileManagerWindowChrome.currentIsDark,
            )
        }

        let window = NSWindow(contentViewController: contentViewController)
        FileManagerWindowChrome.configureWindowStyle(window)
        FileManagerWindowChrome.applyInitialFrame(window, initialWindowSizeProvider: initialWindowSizeProvider)
        return window
    }

    static func configureWindowStyle(_ window: NSWindow) {
        FileManagerWindowChrome.configureWindowStyle(window)
    }

    static func applyTrafficLightVisibility(to window: NSWindow, isSidebarVisible: Bool) {
        FileManagerWindowChrome.applyTrafficLightVisibility(to: window, isSidebarVisible: isSidebarVisible)
    }

    private func tearDownBindings() {
        cancellables.removeAll()
    }
}

// MARK: - NSWindowDelegate

public extension FileManagerWindowCoordinator {
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

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        FileManagerWindowChrome.saveFrame(window)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            FileManagerWindowChrome.saveFrame(window)
        }
        tearDownBindings()
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

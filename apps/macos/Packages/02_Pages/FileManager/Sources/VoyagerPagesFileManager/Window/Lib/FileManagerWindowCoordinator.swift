import AppKit
import Combine
import ComposableArchitecture
import VoyagerEntitiesCollection
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

@MainActor
public final class FileManagerWindowCoordinator: NSWindowController, NSWindowDelegate {
    @MainActor
    private struct SessionLapseGuardContext {
        let store: Store<AccountAccessFeature.State?, AccountAccessAction>
        let resolveState: @MainActor () -> AccountAccessFeature.State?

        init(
            store: Store<AccountAccessFeature.State?, AccountAccessAction>,
            resolveState: (@MainActor () -> AccountAccessFeature.State?)?,
        ) {
            self.store = store
            self.resolveState = resolveState ?? { store.withState(\.self) }
        }
    }

    public let windowID: UUID
    let entryOperationsUndoManager: UndoManager
    public let store: StoreOf<FileManagerFeature>
    private let responderUndoManager: UndoManager
    private let onBecameKey: (@MainActor (UUID) -> Void)?
    private let onResignedKey: (@MainActor (UUID) -> Void)?
    private let onWillClose: (@MainActor (UUID) -> Void)?
    private let initialWindowSizeProvider: (() -> NSSize?)?
    private weak var windowSplitCoordinator: FileManagerWindowSplitCoordinator?
    private var cancellables: Set<AnyCancellable> = []

    public init(
        windowID: UUID,
        store: StoreOf<FileManagerFeature>,
        entryOperationsUndoManager: UndoManager,
        path: String? = nil,
        workspaceClient: WorkspaceClient = .liveValue,
        sessionLapseGuardStore: Store<AccountAccessFeature.State?, AccountAccessAction>? = nil,
        sessionLapseGuardState: (@MainActor () -> AccountAccessFeature.State?)? = nil,
        onBecameKey: (@MainActor (UUID) -> Void)? = nil,
        onResignedKey: (@MainActor (UUID) -> Void)? = nil,
        onWillClose: (@MainActor (UUID) -> Void)? = nil,
        initialWindowSizeProvider: (() -> NSSize?)? = nil,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)? = nil,
    ) {
        self.windowID = windowID
        self.store = store
        self.entryOperationsUndoManager = entryOperationsUndoManager
        responderUndoManager = UndoManager()
        self.onBecameKey = onBecameKey
        self.onResignedKey = onResignedKey
        self.onWillClose = onWillClose
        self.initialWindowSizeProvider = initialWindowSizeProvider

        let window = Self.makeWindow(
            store: store,
            path: path,
            workspaceClient: workspaceClient,
            sessionLapseGuard: sessionLapseGuardStore.map {
                SessionLapseGuardContext(store: $0, resolveState: sessionLapseGuardState)
            },
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
            materialOverride: nil,
        )

        super.init(window: window)
        windowSplitCoordinator = window.contentViewController as? FileManagerWindowSplitCoordinator
        window.delegate = self
        store.send(.internal(.undoManagerWindowIDChanged(windowID)))
        FileManagerWindowChrome.bindTitle(to: window, store: store, cancellables: &cancellables)
    }

    init(
        windowID: UUID,
        store: StoreOf<FileManagerFeature>,
        entryOperationsUndoManager: UndoManager,
        path: String? = nil,
        workspaceClient: WorkspaceClient = .liveValue,
        sessionLapseGuardStore: Store<AccountAccessFeature.State?, AccountAccessAction>? = nil,
        sessionLapseGuardState: (@MainActor () -> AccountAccessFeature.State?)? = nil,
        onBecameKey: (@MainActor (UUID) -> Void)? = nil,
        onResignedKey: (@MainActor (UUID) -> Void)? = nil,
        onWillClose: (@MainActor (UUID) -> Void)? = nil,
        initialWindowSizeProvider: (() -> NSSize?)? = nil,
        materialOverride: FileManagerWindowMaterialOverride?,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)? = nil,
    ) {
        self.windowID = windowID
        self.store = store
        self.entryOperationsUndoManager = entryOperationsUndoManager
        responderUndoManager = UndoManager()
        self.onBecameKey = onBecameKey
        self.onResignedKey = onResignedKey
        self.onWillClose = onWillClose
        self.initialWindowSizeProvider = initialWindowSizeProvider

        let window = Self.makeWindow(
            store: store,
            path: path,
            workspaceClient: workspaceClient,
            sessionLapseGuard: sessionLapseGuardStore.map {
                SessionLapseGuardContext(store: $0, resolveState: sessionLapseGuardState)
            },
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
            materialOverride: materialOverride,
        )

        super.init(window: window)
        windowSplitCoordinator = window.contentViewController as? FileManagerWindowSplitCoordinator
        window.delegate = self
        store.send(.internal(.undoManagerWindowIDChanged(windowID)))
        FileManagerWindowChrome.bindTitle(to: window, store: store, cancellables: &cancellables)
    }

    init(
        registryClient: RegistryClient,
        path: String? = nil,
        workspaceClient: WorkspaceClient = .liveValue,
        duplicateState: FileManagerFeature.State? = nil,
        sessionLapseGuardStore: Store<AccountAccessFeature.State?, AccountAccessAction>? = nil,
        sessionLapseGuardState: (@MainActor () -> AccountAccessFeature.State?)? = nil,
        onBecameKey: (@MainActor (UUID) -> Void)? = nil,
        onResignedKey: (@MainActor (UUID) -> Void)? = nil,
        onWillClose: (@MainActor (UUID) -> Void)? = nil,
        initialWindowSizeProvider: (() -> NSSize?)? = nil,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)? = nil,
    ) {
        let windowID = UUID()
        let state = Self.createInitialState(path: path, duplicateState: duplicateState)
        let entryOperationsUndoManager = UndoManager()
        let store = Self.createStore(
            state: state,
            entryOperationsUndoManager: entryOperationsUndoManager,
            registryClient: registryClient,
        )

        store.send(.internal(.undoManagerWindowIDChanged(windowID)))
        if duplicateState != nil {
            store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.resetForDuplicate(windowID: windowID))))))
            store.send(.internal(.sidebarEntryDrop(.lifecycle(.resetForDuplicate(windowID: windowID)))))
        } else {
            store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(windowID))))))
            store.send(.internal(.sidebarEntryDrop(.lifecycle(.windowIDChanged(windowID)))))
        }

        self.windowID = windowID
        self.store = store
        self.entryOperationsUndoManager = entryOperationsUndoManager
        responderUndoManager = UndoManager()
        self.onBecameKey = onBecameKey
        self.onResignedKey = onResignedKey
        self.onWillClose = onWillClose
        self.initialWindowSizeProvider = initialWindowSizeProvider

        let window = Self.makeWindow(
            store: store,
            path: path,
            workspaceClient: workspaceClient,
            sessionLapseGuard: sessionLapseGuardStore.map {
                SessionLapseGuardContext(store: $0, resolveState: sessionLapseGuardState)
            },
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
            materialOverride: nil,
        )

        super.init(window: window)
        windowSplitCoordinator = window.contentViewController as? FileManagerWindowSplitCoordinator
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
        entryOperationsUndoManager: UndoManager,
        registryClient: RegistryClient,
    ) -> StoreOf<FileManagerFeature> {
        Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = .live(undoManager: entryOperationsUndoManager)
            $0.registryClient = registryClient
        }
    }

    private static func makeWindow(
        store: StoreOf<FileManagerFeature>,
        path: String?,
        workspaceClient: WorkspaceClient,
        sessionLapseGuard: SessionLapseGuardContext?,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)?,
        initialWindowSizeProvider: (() -> NSSize?)?,
        materialOverride: FileManagerWindowMaterialOverride?,
    ) -> NSWindow {
        let contentViewController: NSViewController = if let makeContentViewController {
            makeContentViewController(store, path)
        } else {
            FileManagerWindowSplitCoordinator(
                store: store,
                isDark: FileManagerWindowChrome.currentIsDark,
                workspaceClient: workspaceClient,
                sessionLapseGuardStore: sessionLapseGuard?.store,
                sessionLapseGuardState: sessionLapseGuard?.resolveState,
                materialOverride: materialOverride,
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

    func updateMaterialOverride(_ override: FileManagerWindowMaterialOverride?) {
        windowSplitCoordinator?.updateMaterialOverride(override)
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
        responderUndoManager
    }
}

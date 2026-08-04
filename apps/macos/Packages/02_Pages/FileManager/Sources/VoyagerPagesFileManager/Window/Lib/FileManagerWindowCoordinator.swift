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
    public let store: StoreOf<FileManagerFeature>
    private let fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry
    private let onBecameKey: (@MainActor (UUID) -> Void)?
    private let onResignedKey: (@MainActor (UUID) -> Void)?
    private let onWillClose: (@MainActor (UUID) -> Void)?
    private let initialWindowSizeProvider: (() -> NSSize?)?
    private weak var windowSplitCoordinator: FileManagerWindowSplitCoordinator?
    private var cancellables: Set<AnyCancellable> = []

    public init(
        windowID: UUID,
        store: StoreOf<FileManagerFeature>,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
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
        self.fileOperationUndoManagerRegistry = fileOperationUndoManagerRegistry
        Self.activateInitialScopes(
            windowID: windowID,
            store: store,
            registry: fileOperationUndoManagerRegistry,
        )
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

    init(
        windowID: UUID,
        store: StoreOf<FileManagerFeature>,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
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
        self.fileOperationUndoManagerRegistry = fileOperationUndoManagerRegistry
        Self.activateInitialScopes(
            windowID: windowID,
            store: store,
            registry: fileOperationUndoManagerRegistry,
        )
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
        FileManagerWindowChrome.bindTitle(to: window, store: store, cancellables: &cancellables)
    }

    init(
        registryClient: RegistryClient,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
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
        let state = Self.createInitialState(
            windowID: windowID,
            path: path,
            duplicateState: duplicateState,
        )
        let store = Self.createStore(
            state: state,
            fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
            registryClient: registryClient,
        )

        if duplicateState == nil {
            store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(windowID))))))
        }

        self.windowID = windowID
        self.store = store
        self.fileOperationUndoManagerRegistry = fileOperationUndoManagerRegistry
        Self.activateInitialScopes(
            windowID: windowID,
            store: store,
            registry: fileOperationUndoManagerRegistry,
        )
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
        windowID: UUID,
        path: String?,
        duplicateState: FileManagerFeature.State?,
    ) -> FileManagerFeature.State {
        var state: FileManagerFeature.State = if let duplicateState {
            duplicateState
        } else {
            FileManagerFeature.State()
        }

        if duplicateState != nil {
            for tabID in state.contentTabs.tabs.ids {
                guard var tabContent = state.tabContentStates[tabID]
                    ?? (tabID == state.contentTabs.activeTabID ? state.content : nil)
                else { continue }
                tabContent.entryViewLayout.entryOperations.resetForDuplicate(windowID: windowID)
                tabContent.entryViewLayout.selectedIds = []
                tabContent.entryViewLayout.lastSelectedId = nil
                tabContent.entryViewLayout.rangeAnchorId = nil
                tabContent.entryViewLayout.shouldScrollToSelection = false
                state.tabContentStates[tabID] = tabContent
            }
            if let activeTabID = state.contentTabs.activeTabID,
               let activeContent = state.tabContentStates[activeTabID]
            {
                state.content = activeContent
            }
        }

        if let path {
            state.content.navigation.seedInitialFolderPath(path)
            state.syncActiveTabContentState()
        }

        return state
    }

    private static func createStore(
        state: FileManagerFeature.State,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
        registryClient: RegistryClient,
    ) -> StoreOf<FileManagerFeature> {
        Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileOperationUndoManagerClient = .live(registry: fileOperationUndoManagerRegistry)
            $0.registryClient = registryClient
        }
    }

    private static func activateInitialScopes(
        windowID: UUID,
        store: StoreOf<FileManagerFeature>,
        registry: FileOperationUndoManagerRegistry,
    ) {
        let tabIDs = store.withState { $0.contentTabs.tabs.ids }
        for tabID in tabIDs {
            registry.activate(UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue))
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
        fileOperationUndoManagerRegistry.deactivateAll(windowID: windowID)
        tearDownBindings()
        if let onWillClose {
            onWillClose(windowID)
        }
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        true
    }

    func windowWillReturnUndoManager(_: NSWindow) -> UndoManager? {
        guard let activeTabID = store.withState(\.contentTabs.activeTabID) else {
            return nil
        }
        return fileOperationUndoManagerRegistry.undoManager(for: UndoManagerScope(
            windowID: windowID,
            contentTabID: activeTabID.rawValue,
        ))
    }
}

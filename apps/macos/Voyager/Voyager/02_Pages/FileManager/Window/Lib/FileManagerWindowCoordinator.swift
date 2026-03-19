import AppKit
import Combine
import ComposableArchitecture

final class FileManagerWindowCoordinator: NSWindowController, NSWindowDelegate {
    let windowID: UUID
    let windowUndoManager: UndoManager
    let store: StoreOf<FileManagerFeature>
    private let computerNameClient = FileManagerComputerNameClient.liveValue
    private let onBecameKey: (@MainActor (UUID) -> Void)?
    private let onResignedKey: (@MainActor (UUID) -> Void)?
    private let onWillClose: (@MainActor (UUID) -> Void)?
    private let initialWindowSizeProvider: (() -> NSSize?)?
    private var cancellables: Set<AnyCancellable> = []
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

        let window = Self.makeWindow(
            store: store,
            path: path,
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
        )

        super.init(window: window)
        window.delegate = self
        bindWindowTitle(window)
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

        let window = Self.makeWindow(
            store: store,
            path: path,
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
        )

        super.init(window: window)
        window.delegate = self
        bindWindowTitle(window)
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
        var state: FileManagerFeature.State
        if let duplicateState {
            var newState = duplicateState
            newState.content.entryViewLayout.entryOperations = EntryOperationsState()
            newState.content.entryViewLayout.entryOperations.windowID = windowID
            state = newState
        } else {
            state = FileManagerFeature.State()
            state.content.entryViewLayout.entryOperations.windowID = windowID
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
                isDark: currentIsDark,
            )
        }

        let window = NSWindow(contentViewController: contentViewController)
        configureWindowStyle(window)
        applyInitialFrame(window, initialWindowSizeProvider: initialWindowSizeProvider)
        return window
    }

    private static var currentIsDark: Bool {
        let appearance = NSApp.effectiveAppearance
        let best = appearance.bestMatch(from: [.darkAqua, .aqua])
        return best == .darkAqua
    }

    private static func configureWindowStyle(_ window: NSWindow) {
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize = NSSize(width: 600, height: 350)

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true

        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingIdentifier = "file-manager"
        window.tabbingMode = .preferred
    }

    private static func applyInitialFrame(
        _ window: NSWindow,
        initialWindowSizeProvider: (() -> NSSize?)?,
    ) {
        window.setFrameAutosaveName("VoyagerMainWindow")

        if !window.setFrameUsingName("VoyagerMainWindow") {
            let desiredSize: NSSize = initialWindowSizeProvider?() ?? NSSize(width: 960, height: 510)
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let origin = NSPoint(
                x: screenFrame.midX - desiredSize.width / 2,
                y: screenFrame.midY - desiredSize.height / 2,
            )
            window.setFrame(NSRect(origin: origin, size: desiredSize), display: false)
        }
    }

    private func bindWindowTitle(_ window: NSWindow) {
        let titleClient = computerNameClient
        let makeWindowTitle: (String) -> String = { path in
            if path == "/" {
                return titleClient.computerName()
            }
            if path == titleClient.computerName() {
                return path
            }
            return titleClient.displayNameAtPath(path)
        }

        func makeTitle(
            openedCollectionName: String?,
            isCollectionMode: Bool,
            titlePath: String,
            makeWindowTitle: (String) -> String,
        ) -> String {
            if let openedCollectionName {
                return openedCollectionName
            }
            if isCollectionMode {
                return "New Collection"
            }
            return makeWindowTitle(titlePath)
        }

        let initialTitle = makeTitle(
            openedCollectionName: store.state.content.collectionSession.openedName,
            isCollectionMode: store.state.content.entryViewLayout.entryOperations.loadingContext.isCollectionMode,
            titlePath: store.state.content.navigation.titlePath,
            makeWindowTitle: makeWindowTitle,
        )

        Publishers.CombineLatest3(
            store.publisher.content.collectionSession.openedName.removeDuplicates(),
            store.publisher.content.entryViewLayout.entryOperations.loadingContext.isCollectionMode.removeDuplicates(),
            store.publisher.content.navigation.titlePath.removeDuplicates(),
        )
        .map { openedCollectionName, isCollectionMode, titlePath in
            makeTitle(
                openedCollectionName: openedCollectionName,
                isCollectionMode: isCollectionMode,
                titlePath: titlePath,
                makeWindowTitle: makeWindowTitle,
            )
        }
        .prepend(initialTitle)
        .removeDuplicates()
        .sink { [weak window] title in
            window?.title = title
        }
        .store(in: &cancellables)
    }

    private func tearDownBindings() {
        cancellables.removeAll()
    }
}

// MARK: - NSWindowDelegate

extension FileManagerWindowCoordinator {
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

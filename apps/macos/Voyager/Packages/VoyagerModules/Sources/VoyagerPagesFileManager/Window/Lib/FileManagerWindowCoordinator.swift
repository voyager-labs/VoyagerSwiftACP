import AppKit
import Combine
import ComposableArchitecture

import VoyagerEntitiesEntry
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
    /// 외부에서 store/undoManager를 주입하는 designated initializer.
    ///
    /// - AppRootFeature 기반 윈도우 세션으로 전환할 때 사용한다.
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
        bindWindowTitle(window)
    }

    public init(
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

        // Route windowID initialization through the lifecycle reducer
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
        bindWindowTitle(window)
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static func createInitialState(
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

    public static func makeWindow(
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

    public static var currentIsDark: Bool {
        let appearance = NSApp.effectiveAppearance
        let best = appearance.bestMatch(from: [.darkAqua, .aqua])
        return best == .darkAqua
    }

    public static func configureWindowStyle(_ window: NSWindow) {
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize = NSSize(width: 600, height: 350)

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        let toolbar = NSToolbar(identifier: "VoyagerMainToolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar

        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true

        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingIdentifier = "file-manager"
        window.tabbingMode = .preferred
    }

    public static func applyTrafficLightVisibility(to window: NSWindow, isSidebarVisible: Bool) {
        let shouldHide = !isSidebarVisible
        window.standardWindowButton(.closeButton)?.isHidden = shouldHide
        window.standardWindowButton(.miniaturizeButton)?.isHidden = shouldHide
        window.standardWindowButton(.zoomButton)?.isHidden = shouldHide
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
        let makeWindowTitle: (String) -> String = { path in
            let computerName = FileManagerClient.liveValue.displayName("/")
            if path == "/" {
                return computerName
            }
            if path == computerName {
                return path
            }
            return FileManagerClient.liveValue.displayName(path)
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
            isCollectionMode: store.state.content.isCollectionMode,
            titlePath: store.state.content.navigation.titlePath,
            makeWindowTitle: makeWindowTitle,
        )

        Publishers.CombineLatest3(
            store.publisher.content.collectionSession.openedName.removeDuplicates(),
            store.publisher.content.isCollectionMode.removeDuplicates(),
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

    func window(proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
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

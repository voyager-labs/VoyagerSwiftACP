import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

class FileManagerWindowController: NSWindowController, NSWindowDelegate {
    private let initialPath: String?
    private let windowUndoManager: UndoManager
    let store: StoreOf<FileManagerFeature>
    private var cancellables: Set<AnyCancellable> = []

    init(
        path: String? = nil,
        duplicateState: FileManagerFeature.State? = nil,
        asTab: Bool = true,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)? = nil,
    ) {
        initialPath = path
        let state = Self.createInitialState(path: path, duplicateState: duplicateState)
        let undoManager = UndoManager()
        windowUndoManager = undoManager
        store = Self.createStore(state: state, undoManager: undoManager)

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

    private static func createInitialState(
        path: String?,
        duplicateState: FileManagerFeature.State?,
    ) -> FileManagerFeature.State {
        var state: FileManagerFeature.State
        if let duplicateState {
            var newState = duplicateState
            newState.entries = EntriesFeature.State()
            state = newState
        } else {
            state = FileManagerFeature.State()
        }

        if duplicateState == nil, let path {
            state.navigationState = .folder(path)
            state.titlePath = path
        }

        return state
    }

    private static func createStore(
        state: FileManagerFeature.State,
        undoManager: UndoManager,
    ) -> StoreOf<FileManagerFeature> {
        Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = .live(undoManager: undoManager)
        }
    }

    private static func createWindow(
        store: StoreOf<FileManagerFeature>,
        path: String?,
        state _: FileManagerFeature.State,
        asTab: Bool,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)?,
    ) -> NSWindow {
        let contentViewController = makeContentViewController?(store, path)
            ?? FileManagerSplitViewController(store: store, initialPath: path)
        let window = NSWindow(contentViewController: contentViewController)
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
        if #available(macOS 13.0, *) {
            window.toolbarStyle = .unifiedCompact
        }
        window.isMovableByWindowBackground = true

        // 창을 투명하게 설정 (바탕화면이 블러되어 보이도록)
        window.isOpaque = false
        window.backgroundColor = .clear

        if asTab {
            window.tabbingMode = .preferred
            window.tabbingIdentifier = "file-manager"
        } else {
            window.tabbingMode = .disallowed
        }

        return window
    }

    private static func setupWindowFrame(_ window: NSWindow, _: String) {
        window.setFrameAutosaveName("VoyagerMainWindow")

        if !window.setFrameUsingName("VoyagerMainWindow") {
            let desiredSize: NSSize = if let existingWindow = AppDelegate.shared?.windowControllers.first?.window {
                existingWindow.frame.size
            } else {
                NSSize(width: 960, height: 510)
            }

            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
            let origin = NSPoint(
                x: screenFrame.midX - desiredSize.width / 2,
                y: screenFrame.midY - desiredSize.height / 2,
            )
            window.setFrame(NSRect(origin: origin, size: desiredSize), display: false)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowDidBecomeKey(_: Notification) {
        AppDelegate.shared?.updateFocusHistory(window: window)
        AppDelegate.shared?.updateMenuState(store: store)
        observeStoreChanges()
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

    private func observeStoreChanges() {
        cancellables.removeAll()
        setupTitlePublisher()
        setupMenuStatePublishers()
    }

    private func setupTitlePublisher() {
        let makeTitle: (String?, Bool, String) -> String = { openedCollectionName, isCollectionMode, titlePath in
            if let openedCollectionName {
                return openedCollectionName
            }
            if isCollectionMode {
                return "New Collection"
            }
            return FileManagerFeature.makeWindowTitle(for: titlePath)
        }

        let initialTitle = makeTitle(
            store.state.openedCollectionName,
            store.state.entries.isCollectionMode,
            store.state.titlePath,
        )

        let titlePublisher = Publishers.CombineLatest3(
            store.publisher.openedCollectionName.removeDuplicates(),
            store.publisher.entries.isCollectionMode.removeDuplicates(),
            store.publisher.titlePath.removeDuplicates(),
        )
        .map(makeTitle)
        .prepend(initialTitle)
        .removeDuplicates()

        titlePublisher
            .sink { [weak self] title in
                self?.window?.title = title
            }
            .store(in: &cancellables)
    }

    private func setupMenuStatePublishers() {
        let updateMenuStateIfKeyWindow: () -> Void = { [weak self] in
            guard let self, window?.isKeyWindow == true else { return }
            AppDelegate.shared?.updateMenuState(store: store)
        }

        store.publisher.entries.selectedIds
            .removeDuplicates()
            .sink { _ in updateMenuStateIfKeyWindow() }
            .store(in: &cancellables)

        store.publisher.entries.clipboardItems
            .removeDuplicates()
            .sink { _ in updateMenuStateIfKeyWindow() }
            .store(in: &cancellables)

        store.publisher.entries.undoRecords
            .removeDuplicates()
            .sink { _ in updateMenuStateIfKeyWindow() }
            .store(in: &cancellables)

        store.publisher.entries.redoRecords
            .removeDuplicates()
            .sink { _ in updateMenuStateIfKeyWindow() }
            .store(in: &cancellables)

        store.publisher.entries.operations.itemStates
            .removeDuplicates()
            .sink { _ in updateMenuStateIfKeyWindow() }
            .store(in: &cancellables)

        updateMenuStateIfKeyWindow()
    }

    func windowWillClose(_: Notification) {
        AppDelegate.shared?.windowWillClose(controller: self)
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        true
    }

    func windowWillReturnUndoManager(_: NSWindow) -> UndoManager? {
        windowUndoManager
    }
}

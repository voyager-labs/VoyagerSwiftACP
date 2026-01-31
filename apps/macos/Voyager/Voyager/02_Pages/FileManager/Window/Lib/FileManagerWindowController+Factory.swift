import AppKit
import ComposableArchitecture

extension FileManagerWindowController {
    static func createInitialState(
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

    static func createStore(
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

    static func createWindow(
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

    static func setupWindowFrame(
        _ window: NSWindow,
        _: String,
        windowLifecycleClient: FileManagerWindowLifecycleClient,
    ) {
        window.setFrameAutosaveName("VoyagerMainWindow")

        if !window.setFrameUsingName("VoyagerMainWindow") {
            let desiredSize: NSSize = windowLifecycleClient.existingWindowSize()
                ?? NSSize(width: 960, height: 510)

            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
            let origin = NSPoint(
                x: screenFrame.midX - desiredSize.width / 2,
                y: screenFrame.midY - desiredSize.height / 2,
            )
            window.setFrame(NSRect(origin: origin, size: desiredSize), display: false)
        }
    }
}

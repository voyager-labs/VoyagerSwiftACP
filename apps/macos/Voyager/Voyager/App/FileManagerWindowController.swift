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

        var state: FileManagerFeature.State
        if let duplicateState {
            var newState = duplicateState
            newState.fsItems = FSItemsFeature.State()
            state = newState
        } else {
            state = FileManagerFeature.State()
        }

        if duplicateState == nil, let path {
            state.navigationState = .folder(path)
            state.titlePath = path
        }

        let undoManager = UndoManager()
        windowUndoManager = undoManager

        store = Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = .live(undoManager: undoManager)
        }

        let contentViewController = makeContentViewController?(store, path)
            ?? FileManagerSplitViewController(store: store, initialPath: path)
        let window = NSWindow(contentViewController: contentViewController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize = NSSize(width: 600, height: 350)

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = nil
        window.isMovableByWindowBackground = true

        if asTab {
            window.tabbingMode = .preferred
            window.tabbingIdentifier = "file-manager"
        } else {
            window.tabbingMode = .disallowed
        }

        super.init(window: window)
        window.delegate = self

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

        window.title = FileManagerFeature.makeWindowTitle(for: path ?? state.currentPath)
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

    private func observeStoreChanges() {
        cancellables.removeAll()

        let updateMenuStateIfKeyWindow: () -> Void = { [weak self] in
            guard let self, window?.isKeyWindow == true else { return }
            AppDelegate.shared?.updateMenuState(store: store)
        }

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
            store.state.fsItems.isCollectionMode,
            store.state.titlePath,
        )

        let titlePublisher = Publishers.CombineLatest3(
            store.publisher.openedCollectionName.removeDuplicates(),
            store.publisher.fsItems.isCollectionMode.removeDuplicates(),
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

        store.publisher.fsItems.selectedIds
            .removeDuplicates()
            .sink { _ in updateMenuStateIfKeyWindow() }
            .store(in: &cancellables)

        store.publisher.fsItems.clipboardItems
            .removeDuplicates()
            .sink { _ in updateMenuStateIfKeyWindow() }
            .store(in: &cancellables)

        store.publisher.fsItems.undoRecords
            .removeDuplicates()
            .sink { _ in updateMenuStateIfKeyWindow() }
            .store(in: &cancellables)

        store.publisher.fsItems.redoRecords
            .removeDuplicates()
            .sink { _ in updateMenuStateIfKeyWindow() }
            .store(in: &cancellables)

        store.publisher.fsItems.operations.itemStates
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

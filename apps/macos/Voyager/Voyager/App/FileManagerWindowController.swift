import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

class FileManagerWindowController: NSWindowController, NSWindowDelegate {
    private let initialPath: String?
    let store: StoreOf<FileManagerFeature>
    private var cancellables: Set<AnyCancellable> = []

    init(path: String? = nil, duplicateState: FileManagerFeature.State? = nil, asTab: Bool = true) {
        initialPath = path

        let state: FileManagerFeature.State
        if let duplicateState = duplicateState {
            var newState = duplicateState
            newState.fsItems = FSItemsFeature.State()
            state = newState
        } else {
            state = FileManagerFeature.State()
        }

        store = Store(initialState: state) {
            FileManagerFeature()
        }

        let splitViewController = FileManagerSplitViewController(store: store, initialPath: path)
        let window = NSWindow(contentViewController: splitViewController)
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
            let desiredSize: NSSize

            if let existingWindow = AppDelegate.shared?.windowControllers.first?.window {
                desiredSize = existingWindow.frame.size
            } else {
                desiredSize = NSSize(width: 960, height: 510)
            }

            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
            let origin = NSPoint(
                x: screenFrame.midX - desiredSize.width / 2,
                y: screenFrame.midY - desiredSize.height / 2
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
        observeStoreChanges()
    }

    private func observeStoreChanges() {
        cancellables.removeAll()

        let updateMenuStateIfKeyWindow: () -> Void = { [weak self] in
            guard let self = self, self.window?.isKeyWindow == true else { return }
            AppDelegate.shared?.updateMenuState(store: self.store)
        }

        store.publisher.fsItems.selectedIds
            .removeDuplicates()
            .sink { _ in updateMenuStateIfKeyWindow() }
            .store(in: &cancellables)

        store.publisher.fsItems.clipboardItems
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
}

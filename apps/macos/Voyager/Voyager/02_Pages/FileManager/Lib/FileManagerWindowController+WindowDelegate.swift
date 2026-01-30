import AppKit
import Combine
import ComposableArchitecture

extension FileManagerWindowController {
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

    func windowWillClose(_: Notification) {
        AppDelegate.shared?.windowWillClose(controller: self)
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        true
    }

    func windowWillReturnUndoManager(_: NSWindow) -> UndoManager? {
        windowUndoManager
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
}

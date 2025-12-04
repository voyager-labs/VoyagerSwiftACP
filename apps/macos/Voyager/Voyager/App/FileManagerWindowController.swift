import AppKit
import ComposableArchitecture
import SwiftUI

class FileManagerWindowController: NSWindowController, NSWindowDelegate {
    private let initialPath: String?
    let store: StoreOf<FileManagerFeature>

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

        let desiredSize = NSSize(width: 960, height: 510)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        let origin = NSPoint(
            x: screenFrame.midX - desiredSize.width / 2,
            y: screenFrame.midY - desiredSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: desiredSize), display: false)

        if asTab {
            window.tabbingMode = .preferred
            window.tabbingIdentifier = "file-manager"
        } else {
            window.tabbingMode = .disallowed
        }

        super.init(window: window)
        window.delegate = self

        window.setFrameAutosaveName("VoyagerMainWindow")

        window.title = FileManagerFeature.makeWindowTitle(for: path ?? state.currentPath)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowDidBecomeKey(_: Notification) {
        AppDelegate.shared?.updateFocusHistory(window: window)
    }

    func windowWillClose(_: Notification) {
        AppDelegate.shared?.windowWillClose(controller: self)
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        true
    }
}

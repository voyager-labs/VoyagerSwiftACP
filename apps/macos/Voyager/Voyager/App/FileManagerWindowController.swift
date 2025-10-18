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
        let rootView = FileManagerView(store: store, initialPath: path)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 850, height: 550))
        window.minSize = NSSize(width: 800, height: 600)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        if asTab {
            window.tabbingMode = .preferred
            window.tabbingIdentifier = "file-manager"
        } else {
            window.tabbingMode = .disallowed
        }

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_: Notification) {
        AppDelegate.shared?.windowWillClose(controller: self)
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        true
    }
}

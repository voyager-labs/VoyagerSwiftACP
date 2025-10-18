import AppKit
import ComposableArchitecture
import SwiftUI

class FileManagerWindowController: NSWindowController, NSWindowDelegate {
    private let initialPath: String?

    init(path: String? = nil, asTab: Bool = true) {
        initialPath = path

        let store = Store(initialState: FileManagerFeature.State()) {
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

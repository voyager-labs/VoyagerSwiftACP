import AppKit
import ComposableArchitecture
import SwiftUI

final class UnlockSurfaceWindowController: NSWindowController, NSWindowDelegate {
    private var shouldTerminateOnClose = true
    let store: StoreOf<UnlockSurfaceFeature>

    init(windowClient: UnlockSurfaceWindowClient) {
        store = Store(initialState: UnlockSurfaceFeature.State()) {
            UnlockSurfaceFeature()
        } withDependencies: {
            $0.unlockSurfaceWindowClient = windowClient
        }
        let rootView = UnlockSurfaceView(store: store)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.minSize = NSSize(width: 600, height: 400)
        window.maxSize = NSSize(width: 800, height: 600)
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.alphaValue = 0

        if let btn = window.standardWindowButton(.miniaturizeButton) { btn.isEnabled = false }
        if let btn = window.standardWindowButton(.zoomButton) { btn.isEnabled = false }

        super.init(window: window)
        window.delegate = self
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        shouldTerminateOnClose = true
        guard let window else { return }
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            window.animator().alphaValue = 1
        }
    }

    func dismissWithoutTerminate() {
        shouldTerminateOnClose = false
        window?.close()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        if shouldTerminateOnClose { NSApp.terminate(nil) }
        return true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

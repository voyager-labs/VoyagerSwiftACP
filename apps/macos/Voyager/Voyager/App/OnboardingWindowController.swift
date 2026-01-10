import AppKit
import ComposableArchitecture
import QuartzCore
import SwiftUI

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    let store: StoreOf<OnboardingFeature>

    init() {
        store = Store(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        }

        let rootView = OnboardingView(store: store)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.minSize = NSSize(width: 900, height: 600)
        window.maxSize = NSSize(width: 1200, height: 800)
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.tabbingMode = .disallowed
        window.alphaValue = 0

        if let button = window.standardWindowButton(.miniaturizeButton) {
            button.isEnabled = false
        }

        if let button = window.standardWindowButton(.zoomButton) {
            button.isEnabled = false
        }

        super.init(window: window)
        window.delegate = self

        window.setFrameAutosaveName("VoyagerOnboardingWindow")

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        let desiredWidth = min(max(screenFrame.width * 0.6, 900), 1200)
        let desiredHeight = min(max(screenFrame.height * 0.6, 600), 800)
        let desiredSize = NSSize(width: desiredWidth, height: desiredHeight)
        let origin = NSPoint(
            x: screenFrame.midX - desiredSize.width / 2,
            y: screenFrame.midY - desiredSize.height / 2,
        )
        window.setFrame(NSRect(origin: origin, size: desiredSize), display: false)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window else { return }
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

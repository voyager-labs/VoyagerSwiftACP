import AppKit
import ComposableArchitecture
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
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 520, height: 360)
        window.title = "Voyager Onboarding"
        window.tabbingMode = .disallowed

        super.init(window: window)
        window.delegate = self

        window.setFrameAutosaveName("VoyagerOnboardingWindow")

        if !window.setFrameUsingName("VoyagerOnboardingWindow") {
            let desiredSize = NSSize(width: 720, height: 480)
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
            let origin = NSPoint(
                x: screenFrame.midX - desiredSize.width / 2,
                y: screenFrame.midY - desiredSize.height / 2,
            )
            window.setFrame(NSRect(origin: origin, size: desiredSize), display: false)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Quit Voyager?"
        alert.informativeText = "Onboarding is still in progress. Quitting will resume next time."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        alert.beginSheetModal(for: sender) { response in
            if response == .alertFirstButtonReturn {
                NSApp.terminate(nil)
            }
        }

        return false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

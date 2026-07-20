import AppKit
import ComposableArchitecture
import QuartzCore
import SwiftNavigation
import SwiftUI
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    let onboardingStore: StoreOf<OnboardingFeature>
    let accountAccessStore: StoreOf<AccountAccessFeature>
    private let handlesAuthCallback: Bool
    private var shouldTerminateOnClose = true

    init(
        onboardingStore: StoreOf<OnboardingFeature>,
        accountAccessStore: StoreOf<AccountAccessFeature>,
        handlesAuthCallback: Bool,
    ) {
        self.onboardingStore = onboardingStore
        self.accountAccessStore = accountAccessStore
        self.handlesAuthCallback = handlesAuthCallback

        let accessStore: Store<OnboardingAccessProjection, OnboardingAccessIntent> = accountAccessStore.scope(
            state: OnboardingAccessProjection.init(accountAccess:),
            action: { (intent: OnboardingAccessIntent) in intent.accountAccessAction },
        )
        let rootView = OnboardingView(store: onboardingStore, accessStore: accessStore)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.minSize = NSSize(width: 900, height: 600)
        window.maxSize = NSSize(width: 1200, height: 800)
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
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

        observe { [weak self] in
            guard let self else { return }
            self.onboardingStore.send(.accessProjectionUpdated(
                OnboardingAccessProjection(accountAccess: self.accountAccessStore.state),
            ))
        }
        accountAccessStore.send(.onAppear)

        window.setFrameAutosaveName("VoyagerOnboardingWindow")

        let screenFrame = activeScreenVisibleFrame()
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
        shouldTerminateOnClose = true
        guard let window else { return }
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func dismissWithoutTerminate() {
        shouldTerminateOnClose = false
        window?.close()
    }

    func routeAuthCallback(_ url: URL) -> Bool {
        guard handlesAuthCallback else { return false }
        accountAccessStore.send(.loginCallbackReceived(url))
        return true
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        if shouldTerminateOnClose {
            NSApp.terminate(nil)
        }
        return true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func activeScreenVisibleFrame() -> NSRect {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
    }
}

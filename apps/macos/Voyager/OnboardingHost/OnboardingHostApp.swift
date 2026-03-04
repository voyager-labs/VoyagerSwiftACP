import AppKit
import SwiftUI
import VoyagerPagesOnboarding

@main
struct OnboardingHostApp: App {
    @NSApplicationDelegateAdaptor(OnboardingHostAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class OnboardingHostAppDelegate: NSObject, NSApplicationDelegate {
    private let onboardingWindowClient = OnboardingWindowClient.makeLive(openMainWindow: { _ in
        await MainActor.run {
            NSApp.terminate(nil)
        }
        return true
    })

    func applicationDidFinishLaunching(_: Notification) {
        resetOnboardingProgress()
        _ = onboardingWindowClient.showIfNeeded()
    }

    private func resetOnboardingProgress() {
        OnboardingWindowClient.liveValue.resetStoredProgress()
    }
}

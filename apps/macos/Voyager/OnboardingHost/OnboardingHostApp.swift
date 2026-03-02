import AppKit
import SwiftUI
import VoyagerPagesOnboarding
import VoyagerShared

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
        let userDefaultsClient = UserDefaultsClient.liveValue
        userDefaultsClient.setObject(nil, "onboardingProgressVersion")
        userDefaultsClient.setObject(nil, "onboardingCurrentStep")
        userDefaultsClient.setObject(nil, "onboardingStepState")
    }
}

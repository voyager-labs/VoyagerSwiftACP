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

// MARK: - Smoke Mode

private enum SmokeMode {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ONBOARDING_HOST_SMOKE"] == "1"
    }

    static var shouldResetProgress: Bool {
        ProcessInfo.processInfo.environment["ONBOARDING_HOST_RESET_PROGRESS"] != "0"
    }

    static func runSmoke(onboardingWindowClient: OnboardingWindowClient) -> Never {
        let resetMode = shouldResetProgress ? "reset" : "skip"

        if shouldResetProgress {
            onboardingWindowClient.resetStoredProgress()
        }

        let isRequired = onboardingWindowClient.isRequired()
        let showIfNeededReturned = onboardingWindowClient.showIfNeeded()

        print("resetMode=\(resetMode)")
        print("isRequiredBeforeShow=\(isRequired)")
        print("showIfNeededReturned=\(showIfNeededReturned)")
        print("exitReason=smokeComplete")

        exit(0)
    }
}

// MARK: - App Delegate

@MainActor
final class OnboardingHostAppDelegate: NSObject, NSApplicationDelegate {
    private let onboardingWindowClient = OnboardingWindowClient.makeLive(openMainWindow: { _ in
        await MainActor.run {
            NSApp.terminate(nil)
        }
        return true
    })

    func applicationDidFinishLaunching(_: Notification) {
        if SmokeMode.isEnabled {
            SmokeMode.runSmoke(onboardingWindowClient: onboardingWindowClient)
        }

        resetOnboardingProgress()
        _ = onboardingWindowClient.showIfNeeded()
    }

    private func resetOnboardingProgress() {
        OnboardingWindowClient.liveValue.resetStoredProgress()
    }
}

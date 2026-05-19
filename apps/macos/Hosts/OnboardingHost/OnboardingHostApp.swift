import AppKit
import SwiftUI
import VoyagerPagesOnboarding

// MARK: - Deterministic smoke mode (env-toggle, host-only)

private enum SmokeMode {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ONBOARDING_HOST_SMOKE"] == "1"
    }

    static var resetProgress: Bool {
        ProcessInfo.processInfo.environment["ONBOARDING_HOST_RESET_PROGRESS"] != "0"
    }

    /// Run smoke checks and exit. Returns never (`Never`) via `exit(0)`.
    static func run() -> Never {
        let resetMode = resetProgress
        print("resetMode=\(resetMode)")

        let liveClient = OnboardingWindowClient.liveValue

        if resetMode {
            liveClient.resetStoredProgress()
        }

        let isRequiredBeforeShow = liveClient.isRequired()
        print("isRequiredBeforeShow=\(isRequiredBeforeShow)")

        let showIfNeededReturned = liveClient.showIfNeeded()
        print("showIfNeededReturned=\(showIfNeededReturned)")

        seedCompletedProgress()
        let isRequiredAfterCompletedSnapshot = liveClient.isRequired()
        print("isRequiredAfterCompletedSnapshot=\(isRequiredAfterCompletedSnapshot)")

        print("exitReason=smoke_complete")
        exit(0)
    }

    private static func seedCompletedProgress() {
        let defaults = UserDefaults.standard
        defaults.set(1.1, forKey: "onboardingProgressVersion")
        defaults.set("complete", forKey: "onboardingCurrentStep")

        let stepState: [String: Bool] = [
            "welcomeComplete": true,
            "betaAccessComplete": true,
            "permissionsComplete": true,
            "completeComplete": true,
        ]

        if let data = try? JSONSerialization.data(withJSONObject: stepState) {
            defaults.set(data, forKey: "onboardingStepState")
        }
    }
}

@main
struct OnboardingHostApp: App {
    @NSApplicationDelegateAdaptor(OnboardingHostAppDelegate.self)
    private var appDelegate

    init() {
        // Smoke gate runs BEFORE SwiftUI body is evaluated
        if SmokeMode.isEnabled {
            SmokeMode.run()
        }
    }

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

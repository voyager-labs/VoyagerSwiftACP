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

    private static var expectedRequiredAfterCompleted: Bool? {
        guard let value = ProcessInfo.processInfo.environment["ONBOARDING_HOST_EXPECT_REQUIRED_AFTER_COMPLETED"] else {
            return nil
        }
        return value == "1"
    }

    /// Run smoke checks and exit. Validates contract and exits nonzero on mismatch.
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

        let (valid, failureReason) = validateContract(
            resetMode: resetMode,
            isRequiredBeforeShow: isRequiredBeforeShow,
            showIfNeededReturned: showIfNeededReturned,
            isRequiredAfterCompletedSnapshot: isRequiredAfterCompletedSnapshot,
        )

        if valid {
            print("exitReason=smoke_complete")
            exit(0)
        } else {
            print("failureReason=\(failureReason ?? "unknown")")
            print("exitReason=smoke_failed")
            exit(1)
        }
    }

    private static func validateContract(
        resetMode: Bool,
        isRequiredBeforeShow: Bool,
        showIfNeededReturned: Bool,
        isRequiredAfterCompletedSnapshot: Bool,
    ) -> (Bool, String?) {
        var failures: [String] = []

        if resetMode {
            if !isRequiredBeforeShow {
                failures.append("isRequiredBeforeShow expected true, got false")
            }
            if !showIfNeededReturned {
                failures.append("showIfNeededReturned expected true, got false")
            }
        } else {
            if isRequiredBeforeShow {
                failures.append("isRequiredBeforeShow expected false, got true")
            }
            if showIfNeededReturned {
                failures.append("showIfNeededReturned expected false, got true")
            }
        }

        let expectedAfterCompleted = expectedRequiredAfterCompleted ?? false
        if isRequiredAfterCompletedSnapshot != expectedAfterCompleted {
            failures
                .append(
                    "isRequiredAfterCompletedSnapshot expected \(expectedAfterCompleted), "
                        + "got \(isRequiredAfterCompletedSnapshot)",
                )
        }

        if failures.isEmpty {
            return (true, nil)
        } else {
            return (false, failures.joined(separator: "; "))
        }
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

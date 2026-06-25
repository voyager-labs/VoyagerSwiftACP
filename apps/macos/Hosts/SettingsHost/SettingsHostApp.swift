import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerEntitiesAppPreferences
import VoyagerPagesSettings
import VoyagerShared

// MARK: - Deterministic smoke mode (env-toggle, host-only)

private enum SmokeMode {
    static var isEnabled: Bool {
        // TODO(VOY-432): ProcessInfo 대신 Dotenv 사용 검토 — https://linear.app/voyager-fm/issue/VOY-432
        ProcessInfo.processInfo.environment["SETTINGS_HOST_SMOKE"] == "1"
    }

    static var resetProgress: Bool {
        ProcessInfo.processInfo.environment["SETTINGS_HOST_RESET_PROGRESS"] != "0"
    }

    /// Run smoke checks and exit. Validates contract and exits nonzero on mismatch.
    static func run() -> Never {
        let resetMode = resetProgress
        print("smokeMode=true")
        print("resetMode=\(resetMode)")

        let feature = SettingsFeature()
        var state = SettingsState()

        let initialSection = state.selectedSection.rawValue
        print("initialSection=\(initialSection)")

        feature.reduce(into: &state, action: .onAppear)
        print("onAppearDispatched=true")

        let sectionBefore = state.selectedSection.rawValue
        print("selectedSectionBefore=\(sectionBefore)")

        feature.reduce(into: &state, action: .selectSection(.appearance))
        let sectionAfter = state.selectedSection.rawValue
        print("selectedSectionAfter=\(sectionAfter)")

        feature.reduce(into: &state, action: .closeWindow)
        print("closeActionDispatched=true")

        let sectionAfterClose = state.selectedSection.rawValue
        print("selectedSectionAfterClose=\(sectionAfterClose)")

        let (valid, failureReason) = validateContract(
            initialSection: initialSection,
            sectionBefore: sectionBefore,
            sectionAfter: sectionAfter,
            sectionAfterClose: sectionAfterClose,
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
        initialSection: String,
        sectionBefore: String,
        sectionAfter: String,
        sectionAfterClose: String,
    ) -> (Bool, String?) {
        var failures: [String] = []

        if initialSection != "general" {
            failures.append("initialSection expected general, got \(initialSection)")
        }
        if sectionBefore != "general" {
            failures.append("selectedSectionBefore expected general, got \(sectionBefore)")
        }
        if sectionAfter != "appearance" {
            failures.append("selectedSectionAfter expected appearance, got \(sectionAfter)")
        }
        if sectionAfterClose != "general" {
            failures.append("selectedSectionAfterClose expected general, got \(sectionAfterClose)")
        }

        if failures.isEmpty {
            return (true, nil)
        } else {
            return (false, failures.joined(separator: "; "))
        }
    }
}

@main
struct SettingsHostApp: App {
    @NSApplicationDelegateAdaptor(SettingsHostAppDelegate.self)
    private var appDelegate

    private let store: StoreOf<SettingsHostFeature>

    init() {
        // Smoke gate runs BEFORE SwiftUI body is evaluated
        if SmokeMode.isEnabled {
            SmokeMode.run()
        }

        let hostUserDefaultsClient = Self.suiteBackedUserDefaultsClient(
            suiteName: "group.com.voyager.app.settingshost",
        )

        store = Store(initialState: SettingsHostState()) {
            SettingsHostFeature()
        } withDependencies: { dependencies in
            dependencies.userDefaultsClient = hostUserDefaultsClient
            dependencies.collectionSearchAISettingsClient = .live(userDefaultsClient: hostUserDefaultsClient)
            dependencies.launchAtLoginClient = .testValue
            dependencies.appearanceSettingsClient = .liveValue
        }
    }

    var body: some Scene {
        WindowGroup("Settings") {
            SettingsHostRootView(store: store)
        }
    }

    private static func suiteBackedUserDefaultsClient(suiteName: String) -> UserDefaultsClient {
        UserDefaultsClient(
            bool: { key in
                UserDefaults(suiteName: suiteName)?.bool(forKey: key) ?? false
            },
            setBool: { value, key in
                UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
            },
            string: { key in
                UserDefaults(suiteName: suiteName)?.string(forKey: key)
            },
            setString: { value, key in
                UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
            },
            double: { key in
                UserDefaults(suiteName: suiteName)?.double(forKey: key) ?? 0.0
            },
            setDouble: { value, key in
                UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
            },
            object: { key in
                UserDefaults(suiteName: suiteName)?.object(forKey: key)
            },
            setObject: { value, key in
                UserDefaults(suiteName: suiteName)?.set(value, forKey: key)
            },
        )
    }
}

@MainActor
private final class SettingsHostAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {}

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

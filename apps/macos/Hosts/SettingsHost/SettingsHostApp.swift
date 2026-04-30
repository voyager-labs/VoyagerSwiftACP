import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerPagesSettings
import VoyagerShared

@main
struct SettingsHostApp: App {
    @NSApplicationDelegateAdaptor(SettingsHostAppDelegate.self)
    var appDelegate

    private let store: StoreOf<SettingsHostFeature> = Store(initialState: SettingsHostState()) {
        SettingsHostFeature()
    } withDependencies: { dependencies in
        dependencies.userDefaultsClient = Self.suiteBackedUserDefaultsClient(
            suiteName: "group.com.voyager.app.settingshost"
        )
        dependencies.launchAtLoginClient = LaunchAtLoginClient.testValue
        dependencies.appearanceSettingsClient = AppearanceSettingsClient.liveValue
        dependencies.aiConnectionsFileClient = AIConnectionsFileClient.liveValue
        dependencies.aiProviderVerificationClient = AIProviderVerificationClient.liveValue
        dependencies.aiProviderConnectionClient = AIProviderConnectionClient.liveValue
        dependencies.codexNativeAuthClient = CodexNativeAuthClient.liveValue
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
            }
        )
    }
}

@MainActor
final class SettingsHostAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {}

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

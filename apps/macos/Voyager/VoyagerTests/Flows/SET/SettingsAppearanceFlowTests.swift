// FLOW-ID: set.settings_appearance
import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class SettingsAppearanceFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.bootstrap

    /// set.settings_appearance: happy_path.bootstrap
    func testLaunchBootstrapRestoresAppearanceAndPropagatesPreferencesToWindowManager() async {
        let storage = AppearanceStorage([
            SettingsKeys.theme: AppTheme.dark.rawValue,
            SettingsKeys.showHiddenFiles: true,
            SettingsKeys.listIconSize: CGFloat(28),
            SettingsKeys.gridIconSize: CGFloat(84),
            SettingsKeys.listTextSize: CGFloat(15),
            SettingsKeys.gridTextSize: CGFloat(14),
        ])
        let store = makeStore(storage: storage)
        // store.exhaustivity = .off: launch observer와 Settings bootstrap의 독립 effect 순서 대신 appearance 복원과 root 전달을 검증한다.
        store.exhaustivity = .off

        await store.send(.lifecycle(.launch(.willFinishLaunching)))
        await store.receive(\.settings.bootstrapLocalPreferences)
        await store.receive(\.settings.ai.onAppear)
        await store.receive(\.settings.general.loadSettings)
        await store.receive(\.settings.appearance.loadSettings) { state in
            state.settings.appearanceSettings.theme = .dark
            state.settings.appearanceSettings.showHiddenFiles = true
            state.settings.appearanceSettings.listIconSize = 28
            state.settings.appearanceSettings.gridIconSize = 84
            state.settings.appearanceSettings.listTextSize = 15
            state.settings.appearanceSettings.gridTextSize = 14
        }

        await store.send(.appPreferences(.load)) { state in
            state.appPreferences.showHiddenFiles = true
            state.appPreferences.listIconSize = 28
            state.appPreferences.gridIconSize = 84
            state.appPreferences.listTextSize = 15
            state.appPreferences.gridTextSize = 14
        }
        await store.receive(\.appPreferences)
        await store.receive(\.windowManager.lifecycle.applyAppPreferences) { state in
            state.windowManager.appPreferences = state.appPreferences
        }
        await store.finish()
    }

    // FLOW-PATH: happy_path.preference_update

    /// set.settings_appearance: happy_path.preference_update
    func testAppearanceChangePersistsAndUpdatesRootWindowPreferences() async {
        let storage = AppearanceStorage()
        let store = makeStore(storage: storage)
        // store.exhaustivity = .off: Settings persistence와 AppRoot window preference 전달의 reducer 경계를 함께 검증한다.
        store.exhaustivity = .off

        await store.send(.settings(.appearance(.setShowHiddenFiles(true)))) { state in
            state.settings.appearanceSettings.showHiddenFiles = true
        }
        XCTAssertTrue(storage.bool(SettingsKeys.showHiddenFiles))

        await store.send(.appPreferences(.reloadFromUserDefaults)) { state in
            state.appPreferences.showHiddenFiles = true
        }
        await store.receive(\.appPreferences)
        await store.receive(\.windowManager.lifecycle.applyAppPreferences) { state in
            state.windowManager.appPreferences = state.appPreferences
        }
        await store.finish()
    }

    private func makeStore(
        storage: AppearanceStorage,
    ) -> TestStore<AppRootFeature.State, AppRootFeature.Action> {
        TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        } withDependencies: {
            $0.directorySelectionClient = DirectorySelectionClient(
                pickDirectory: { nil },
                pathExists: { _ in false },
                isDirectory: { _ in false },
                standardDirectories: {
                    StandardDirectories(
                        homePath: "/flow-home",
                        homeDisplayName: "flow-home",
                        desktopPath: nil,
                        documentsPath: nil,
                        downloadsPath: nil,
                    )
                },
            )
            $0.launchAtLoginClient.isEnabled = { false }
            $0.launchAtLoginClient.setEnabled = { _ in }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
            $0.userDefaultsClient = UserDefaultsClient(
                bool: { key in
                    storage.bool(key)
                },
                setBool: { value, key in
                    storage.setBool(value, key)
                },
                string: { key in
                    storage.string(key)
                },
                setString: { value, key in
                    storage.setString(value, key)
                },
                double: { key in
                    storage.double(key)
                },
                setDouble: { value, key in
                    storage.setDouble(value, key)
                },
                object: { key in
                    storage.object(key)
                },
                setObject: { value, key in
                    storage.setObject(value, key)
                },
            )
            $0.appearanceSettingsClient = AppearanceSettingsClient(
                loadTheme: {
                    guard let rawValue = storage.string(SettingsKeys.theme) else { return .system }
                    return AppTheme(rawValue: rawValue) ?? .system
                },
                applyTheme: { _ in },
                applyThemeSync: { _ in },
            )
        }
    }
}

private final class AppearanceStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any]

    init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    func bool(_ key: String) -> Bool {
        lock.withLock { values[key] as? Bool ?? false }
    }

    func setBool(_ value: Bool, _ key: String) {
        lock.withLock { values[key] = value }
    }

    func string(_ key: String) -> String? {
        lock.withLock { values[key] as? String }
    }

    func setString(_ value: String, _ key: String) {
        lock.withLock { values[key] = value }
    }

    func double(_ key: String) -> Double {
        lock.withLock { values[key] as? Double ?? 0 }
    }

    func setDouble(_ value: Double, _ key: String) {
        lock.withLock { values[key] = value }
    }

    func object(_ key: String) -> Any? {
        lock.withLock { values[key] }
    }

    func setObject(_ value: Any?, _ key: String) {
        lock.withLock { values[key] = value }
    }
}

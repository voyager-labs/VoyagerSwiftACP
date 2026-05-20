import ComposableArchitecture
import CoreGraphics
import Foundation
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

// MARK: - SET003 Appearance Settings — Evidence Contract

// Interaction IDs covered:
//   SET-003:set_theme_mode → focused automated test
//     - testLoadSettingsRestoresTheme (load theme from dependency)
//     - testSetThemePersistsRawValueAndApplies (persist raw value + applyTheme call)
//   SET-003:set_list_icon_size → focused automated test
//     - testLoadSettingsRestoresListIconSize (load saved value)
//     - testMissingListIconSizePreservesDefault (missing numeric → default)
//     - testSetListIconSizePersistsExactKeyValue
//   SET-003:set_grid_icon_size → focused automated test
//     - testLoadSettingsRestoresGridIconSize
//     - testMissingGridIconSizePreservesDefault
//     - testSetGridIconSizePersistsExactKeyValue
//   SET-003:set_list_text_size → focused automated test
//     - testLoadSettingsRestoresListTextSize
//     - testMissingListTextSizePreservesDefault
//     - testSetListTextSizePersistsExactKeyValue
//   SET-003:set_grid_text_size → focused automated test
//     - testLoadSettingsRestoresGridTextSize
//     - testMissingGridTextSizePreservesDefault
//     - testSetGridTextSizePersistsExactKeyValue
//   SET-003:toggle_show_hidden_files → focused automated test
//     - testLoadSettingsRestoresShowHiddenFiles
//     - testSetShowHiddenFilesEnabled
//     - testSetShowHiddenFilesDisabled
//
// Unsupported surface classification:
//   - Permissions: follow-up/manual QA (implementation lives in Onboarding, not Settings)
//   - SET-005 Shortcuts: manual QA (docs-only; app uses static menu commands, no Settings UI)
//   - SET-007 AI Connections: external project dependency
//     (https://linear.app/voyager-fm/project/byok구독-계정-연결-기반-ai-채팅-기능-도입-453bf1118aec)
//   - Account/License: external project dependency
//     (https://linear.app/voyager-fm/project/dollar5-core-license-결제권한앱-unlock-실험-21b8e66140e2)
//
// Evidence path: .sisyphus/evidence/task-f1-set003-remediation.txt
// Fixture reset: InMemoryStorage reset per test via setUp(); no persistent UserDefaults.
// Classification: focused automated test

@MainActor
final class SET003AppearanceSettingsFeatureTests: XCTestCase {
    private var storage: InMemoryStorage!
    private var themeRecorder: ThemeApplyRecorder!

    override func setUp() {
        super.setUp()
        storage = InMemoryStorage()
        themeRecorder = ThemeApplyRecorder()
    }

    override func tearDown() {
        storage = nil
        themeRecorder = nil
        super.tearDown()
    }

    private func makeStore(
        loadTheme: @escaping @Sendable () -> AppTheme = { .system },
    ) -> TestStore<AppearanceSettingsFeature.State, AppearanceSettingsFeature.Action> {
        // swiftlint:disable:next force_unwrapping
        let storage = storage!
        // swiftlint:disable:next force_unwrapping
        let recorder = themeRecorder!
        let userDefaultsClient = UserDefaultsClient(
            bool: { key in storage.getBool(key) ?? false },
            setBool: { value, key in storage.setBool(value, forKey: key) },
            string: { key in storage.getString(key) },
            setString: { value, key in storage.setString(value, forKey: key) },
            double: { key in storage.getDouble(key) ?? 0 },
            setDouble: { value, key in storage.setDouble(value, forKey: key) },
            object: { key in storage.getObject(key) },
            setObject: { value, key in storage.setObject(value, forKey: key) },
        )
        return TestStore(initialState: AppearanceSettingsFeature.State()) {
            AppearanceSettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = userDefaultsClient
            $0.appearanceSettingsClient = AppearanceSettingsClient(
                loadTheme: loadTheme,
                applyTheme: { theme in
                    recorder.record(theme)
                },
                applyThemeSync: { _ in },
            )
        }
    }

    // MARK: - SET-003:set_theme_mode

    func testLoadSettingsRestoresTheme() async {
        let store = makeStore(loadTheme: { .dark })
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.theme, .dark)
    }

    func testSetThemePersistsRawValueAndApplies() async {
        let store = makeStore(loadTheme: { .system })
        store.exhaustivity = .off

        await store.send(.setTheme(.dark)) { state in
            state.theme = .dark
        }

        XCTAssertEqual(store.state.theme, .dark)
        XCTAssertEqual(storage.getObject(SettingsKeys.theme) as? String, AppTheme.dark.rawValue)
        XCTAssertEqual(themeRecorder.values, [.dark])
    }

    func testSetThemeToLightPersistsAndApplies() async {
        let store = makeStore(loadTheme: { .dark })
        store.exhaustivity = .off

        await store.send(.setTheme(.light)) { state in
            state.theme = .light
        }

        XCTAssertEqual(storage.getObject(SettingsKeys.theme) as? String, AppTheme.light.rawValue)
        XCTAssertEqual(themeRecorder.values, [.light])
    }

    // MARK: - SET-003:set_list_icon_size

    func testLoadSettingsRestoresListIconSize() async {
        storage.setObject(CGFloat(25.0), forKey: SettingsKeys.listIconSize)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listIconSize, 25.0)
    }

    func testMissingListIconSizePreservesDefault() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listIconSize, AppearanceSettingsDefaults.listIconSize)
    }

    func testSetListIconSizePersistsExactKeyValue() async {
        let store = makeStore()
        store.exhaustivity = .off

        let newSize: CGFloat = 35.0
        await store.send(.setListIconSize(newSize)) { state in
            state.listIconSize = newSize
        }

        XCTAssertEqual(store.state.listIconSize, newSize)
        let persisted = storage.getObject(SettingsKeys.listIconSize) as? CGFloat
        XCTAssertEqual(persisted, newSize)
    }

    // MARK: - SET-003:set_grid_icon_size

    func testLoadSettingsRestoresGridIconSize() async {
        storage.setObject(CGFloat(80.0), forKey: SettingsKeys.gridIconSize)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridIconSize, 80.0)
    }

    func testMissingGridIconSizePreservesDefault() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridIconSize, AppearanceSettingsDefaults.gridIconSize)
    }

    func testSetGridIconSizePersistsExactKeyValue() async {
        let store = makeStore()
        store.exhaustivity = .off

        let newSize: CGFloat = 96.0
        await store.send(.setGridIconSize(newSize)) { state in
            state.gridIconSize = newSize
        }

        XCTAssertEqual(store.state.gridIconSize, newSize)
        let persisted = storage.getObject(SettingsKeys.gridIconSize) as? CGFloat
        XCTAssertEqual(persisted, newSize)
    }

    // MARK: - SET-003:set_list_text_size

    func testLoadSettingsRestoresListTextSize() async {
        storage.setObject(CGFloat(15.0), forKey: SettingsKeys.listTextSize)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listTextSize, 15.0)
    }

    func testMissingListTextSizePreservesDefault() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listTextSize, AppearanceSettingsDefaults.listTextSize)
    }

    func testSetListTextSizePersistsExactKeyValue() async {
        let store = makeStore()
        store.exhaustivity = .off

        let newSize: CGFloat = 16.0
        await store.send(.setListTextSize(newSize)) { state in
            state.listTextSize = newSize
        }

        XCTAssertEqual(store.state.listTextSize, newSize)
        let persisted = storage.getObject(SettingsKeys.listTextSize) as? CGFloat
        XCTAssertEqual(persisted, newSize)
    }

    // MARK: - SET-003:set_grid_text_size

    func testLoadSettingsRestoresGridTextSize() async {
        storage.setObject(CGFloat(14.0), forKey: SettingsKeys.gridTextSize)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridTextSize, 14.0)
    }

    func testMissingGridTextSizePreservesDefault() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridTextSize, AppearanceSettingsDefaults.gridTextSize)
    }

    func testSetGridTextSizePersistsExactKeyValue() async {
        let store = makeStore()
        store.exhaustivity = .off

        let newSize: CGFloat = 14.0
        await store.send(.setGridTextSize(newSize)) { state in
            state.gridTextSize = newSize
        }

        XCTAssertEqual(store.state.gridTextSize, newSize)
        let persisted = storage.getObject(SettingsKeys.gridTextSize) as? CGFloat
        XCTAssertEqual(persisted, newSize)
    }

    // MARK: - SET-003:toggle_show_hidden_files

    func testLoadSettingsRestoresShowHiddenFiles() async {
        storage.setBool(true, forKey: SettingsKeys.showHiddenFiles)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.showHiddenFiles)
    }

    func testSetShowHiddenFilesEnabled() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.setShowHiddenFiles(true)) { state in
            state.showHiddenFiles = true
        }

        XCTAssertTrue(store.state.showHiddenFiles)
        XCTAssertTrue(storage.getBool(SettingsKeys.showHiddenFiles))
    }

    func testSetShowHiddenFilesDisabled() async {
        storage.setBool(true, forKey: SettingsKeys.showHiddenFiles)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.setShowHiddenFiles(false)) { state in
            state.showHiddenFiles = false
        }

        XCTAssertFalse(store.state.showHiddenFiles)
        XCTAssertFalse(storage.getBool(SettingsKeys.showHiddenFiles))
    }
}

private final class ThemeApplyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [AppTheme] = []

    func record(_ theme: AppTheme) {
        lock.lock()
        defer { lock.unlock() }
        _values.append(theme)
    }

    var values: [AppTheme] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }
}

private final class InMemoryStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var bools: [String: Bool] = [:]
    private var strings: [String: String] = [:]
    private var objects: [String: Any] = [:]

    func setBool(_ value: Bool, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        bools[key] = value
    }

    func getBool(_ key: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return bools[key]
    }

    func setString(_ value: String, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        strings[key] = value
    }

    func getString(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return strings[key]
    }

    func setDouble(_ value: Double, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        objects[key] = value
    }

    func getDouble(_ key: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return objects[key] as? Double
    }

    func setObject(_ value: Any?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        objects[key] = value
    }

    func getObject(_ key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return objects[key]
    }
}

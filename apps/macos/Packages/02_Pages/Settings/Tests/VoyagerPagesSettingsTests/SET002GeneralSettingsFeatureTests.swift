import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

// MARK: - SET002 General Settings — Evidence Contract

// Interaction IDs covered:
//   SET-002:configure_initial_page → focused automated test
//     - testLoadSettingsUsesHomeWhenNoSavedPath (default directory load)
//     - testLoadSettingsRestoresSavedDirectory (saved directory load)
//     - testSelectDirectoryOptionWithStandardOption (standard directory option)
//     - testSelectDirectoryOptionOtherOpensPanel (.other → openOtherDirectoryPanel)
//     - testStartingDirectorySelectedWithCancelReturnsNil (cancel path)
//     - testStartingDirectorySelectedWithValidDirectoryPath (valid picker path)
//     - testStartingDirectorySelectedWithNonexistentPathRejection (nonexistent path)
//     - testStartingDirectorySelectedWithNonDirectoryPathRejection (non-directory path)
//   SET-002:toggle_launch_at_startup → focused automated test
//     - testToggleLaunchAtStartupSuccess (launch-at-login success)
//     - testToggleLaunchAtStartupFailure (launch-at-login failure)
//     - testLoadSettingsSyncsLaunchAtStartupWhenMismatch (load sync on mismatch)
//   SET-002:toggle_automatic_update_install → focused automated test
//     - testToggleAutomaticUpdateEnabled
//     - testToggleAutomaticUpdateDisabled
//   SET-002:toggle_alert_before_app_quit → focused automated test
//     - testToggleAlertBeforeQuitEnabled
//   SET-002:check_for_updates → focused automated test (package-level no-op)
//     - testCheckForUpdatesIsNoOp
//
// Unsupported surface classification:
//   - Permissions: follow-up/manual QA (implementation lives in Onboarding, not Settings)
//   - SET-005 Shortcuts: manual QA (docs-only; app uses static menu commands, no Settings UI)
//   - SET-007 AI Connections: external project dependency
//     (https://linear.app/voyager-fm/project/byok구독-계정-연결-기반-ai-채팅-기능-도입-453bf1118aec)
//   - Account/License: external project dependency
//     (https://linear.app/voyager-fm/project/dollar5-core-license-결제권한앱-unlock-실험-21b8e66140e2)
//
// Evidence path: .sisyphus/evidence/task-f1-set002-remediation.txt
// Fixture reset: InMemoryStorage reset per test via setUp(); no persistent UserDefaults.
// Classification: focused automated test + follow-up (AppRoot forwarding tested elsewhere)

@MainActor
final class SET002GeneralSettingsFeatureTests: XCTestCase {
    private nonisolated(unsafe) var storage: InMemoryStorage!

    override func setUp() {
        super.setUp()
        storage = InMemoryStorage()
    }

    override func tearDown() {
        storage = nil
        super.tearDown()
    }

    private func makeStore(
        launchAtLoginEnabled: Bool = false,
        launchAtLoginSetEnabled: @escaping @Sendable (Bool) throws -> Void = { _ in },
        homePath: String = "/",
        pickDirectory: @escaping @Sendable () async -> String? = { nil },
        pathExists: @escaping @Sendable (String) -> Bool = { _ in false },
        isDirectory: @escaping @Sendable (String) -> Bool = { _ in false },
    ) -> TestStore<GeneralSettingsFeature.State, GeneralSettingsFeature.Action> {
        // swiftlint:disable:next force_unwrapping
        let storage = storage!
        let userDefaultsClient = UserDefaultsClient(
            bool: { key in storage.getBool(key) ?? false },
            setBool: { value, key in storage.setBool(value, forKey: key) },
            string: { key in storage.getString(key) },
            setString: { value, key in storage.setString(value, forKey: key) },
            double: { _ in 0 },
            setDouble: { _, _ in },
            object: { key in storage.getObject(key) },
            setObject: { value, key in storage.setObject(value, forKey: key) },
        )
        let directoryClient = DirectorySelectionClient(
            pickDirectory: pickDirectory,
            pathExists: pathExists,
            isDirectory: isDirectory,
            defaultHomePath: { homePath },
        )
        return TestStore(initialState: GeneralSettingsFeature.State()) {
            GeneralSettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = userDefaultsClient
            $0.launchAtLoginClient = LaunchAtLoginClient(
                isEnabled: { launchAtLoginEnabled },
                setEnabled: launchAtLoginSetEnabled,
            )
            $0.directorySelectionClient = directoryClient
        }
    }

    // MARK: - SET-002:configure_initial_page — Directory Load

    func testLoadSettingsUsesHomeWhenNoSavedPath() async {
        let store = makeStore(homePath: "/home/user")
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.startingDirectory, "/home/user")
        XCTAssertEqual(store.state.selectedDirectoryOption, .custom("/home/user"))
    }

    func testLoadSettingsRestoresSavedDirectory() async {
        storage.setString("/Users/test/saved-dir", forKey: SettingsKeys.defaultTabPath)
        let store = makeStore(homePath: "/home/user")
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.startingDirectory, "/Users/test/saved-dir")
    }

    // MARK: - SET-002:configure_initial_page — Automatic Update & Alert Before Quit Load

    func testLoadSettingsRestoresAutomaticUpdateFromStorage() async {
        storage.setObject(true, forKey: SettingsKeys.automaticUpdate)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.automaticUpdate)
    }

    func testLoadSettingsRestoresAlertBeforeQuitFromStorage() async {
        storage.setBool(true, forKey: SettingsKeys.alertBeforeQuit)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.alertBeforeQuit)
    }

    func testLoadSettingsDefaultsAutomaticUpdateToFalseWhenMissing() async {
        // No automaticUpdate key set in storage
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertFalse(store.state.automaticUpdate)
    }

    func testLoadSettingsDefaultsAlertBeforeQuitToFalseWhenMissing() async {
        // No alertBeforeQuit key set in storage
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertFalse(store.state.alertBeforeQuit)
    }

    // MARK: - SET-002:configure_initial_page — Directory Option Selection

    func testSelectDirectoryOptionWithStandardOption() async {
        let store = makeStore()

        await store.send(.selectDirectoryOption(.root))
        await store.receive(\.setStartingDirectory) { state in
            state.startingDirectory = "/"
            state.selectedDirectoryOption = .root
            state.startingDirectoryError = nil
        }

        XCTAssertEqual(store.state.startingDirectory, "/")
        XCTAssertEqual(store.state.selectedDirectoryOption, .root)
        XCTAssertEqual(storage.getString(SettingsKeys.defaultTabPath), "/")
    }

    func testSelectDirectoryOptionOtherOpensPanel() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.selectDirectoryOption(.other))
        await store.receive(\.openOtherDirectoryPanel) { state in
            state.isSelectingDirectory = true
            state.startingDirectoryError = nil
        }
    }

    // MARK: - SET-002:configure_initial_page — Directory Picker Paths

    func testStartingDirectorySelectedWithCancelReturnsNil() async {
        let store = makeStore(pickDirectory: { nil })
        store.exhaustivity = .off

        await store.send(.openOtherDirectoryPanel)
        await store.receive(\.startingDirectorySelected) { state in
            state.isSelectingDirectory = false
        }
    }

    func testStartingDirectorySelectedWithValidDirectoryPath() async {
        let validPath = "/tmp/valid-set002-dir"
        try? FileManager.default.createDirectory(atPath: validPath, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(atPath: validPath) }

        nonisolated(unsafe) let fm = FileManager.default
        let store = makeStore(
            pickDirectory: { validPath },
            pathExists: { path in fm.fileExists(atPath: path) },
            isDirectory: { path in
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
                return exists && isDir.boolValue
            },
        )

        await store.send(.openOtherDirectoryPanel) { state in
            state.isSelectingDirectory = true
            state.startingDirectoryError = nil
        }
        await store.receive(\.startingDirectorySelected) { state in
            state.isSelectingDirectory = false
        }
        await store.receive(\.setStartingDirectory) { state in
            state.startingDirectory = validPath
            state.selectedDirectoryOption = .custom(validPath)
            state.startingDirectoryError = nil
        }

        XCTAssertEqual(store.state.startingDirectory, validPath)
        XCTAssertNil(store.state.startingDirectoryError)
        XCTAssertEqual(storage.getString(SettingsKeys.defaultTabPath), validPath)
    }

    func testStartingDirectorySelectedWithNonexistentPathRejection() async {
        let nonexistentPath = "/tmp/set002-nonexistent-dir-XYZ"
        let store = makeStore(
            pickDirectory: { nonexistentPath },
            pathExists: { _ in false },
            isDirectory: { _ in false },
        )
        store.exhaustivity = .off

        await store.send(.openOtherDirectoryPanel)
        await store.receive(\.startingDirectorySelected) { state in
            state.isSelectingDirectory = false
            state.startingDirectoryError = "Invalid directory path"
        }

        XCTAssertEqual(store.state.startingDirectoryError, "Invalid directory path")
    }

    func testStartingDirectorySelectedWithNonDirectoryPathRejection() async {
        let filePath = "/tmp/set002-test-file.txt"
        FileManager.default.createFile(atPath: filePath, contents: Data())

        defer { try? FileManager.default.removeItem(atPath: filePath) }

        let store = makeStore(
            pickDirectory: { filePath },
            pathExists: { _ in true },
            isDirectory: { _ in false },
        )
        store.exhaustivity = .off

        await store.send(.openOtherDirectoryPanel)
        await store.receive(\.startingDirectorySelected) { state in
            state.isSelectingDirectory = false
            state.startingDirectoryError = "Selected path is not a directory"
        }

        XCTAssertEqual(store.state.startingDirectoryError, "Selected path is not a directory")
    }

    // MARK: - SET-002:toggle_launch_at_startup

    func testToggleLaunchAtStartupSuccess() async {
        let recorder = MutationRecorder<Bool>()
        let store = makeStore(
            launchAtLoginEnabled: false,
            launchAtLoginSetEnabled: { enabled in
                recorder.record(enabled)
            },
        )
        store.exhaustivity = .off

        await store.send(.toggleLaunchAtStartup(true)) { state in
            state.launchAtStartup = true
            state.launchAtStartupError = nil
        }

        XCTAssertEqual(recorder.values, [true])
        XCTAssertTrue(storage.getBool(SettingsKeys.launchAtStartup) ?? false)
        XCTAssertNil(store.state.launchAtStartupError)
    }

    func testToggleLaunchAtStartupFailure() async {
        struct LaunchAtLoginError: Error {}
        let store = makeStore(
            launchAtLoginEnabled: false,
            launchAtLoginSetEnabled: { _ in
                throw LaunchAtLoginError()
            },
        )
        store.exhaustivity = .off

        let previousLaunchAtStartup = store.state.launchAtStartup
        await store.send(.toggleLaunchAtStartup(true))

        XCTAssertNotNil(store.state.launchAtStartupError)
        XCTAssertTrue(
            store.state.launchAtStartupError?.contains("Failed to set launch at startup") ?? false,
        )
        XCTAssertEqual(store.state.launchAtStartup, previousLaunchAtStartup)
    }

    func testLoadSettingsSyncsLaunchAtStartupWhenMismatch() async {
        storage.setBool(false, forKey: SettingsKeys.launchAtStartup)
        let store = makeStore(launchAtLoginEnabled: true)
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.launchAtStartup)
        XCTAssertTrue(storage.getBool(SettingsKeys.launchAtStartup) ?? false)
    }

    // MARK: - SET-002:toggle_automatic_update_install

    func testToggleAutomaticUpdateEnabled() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.toggleAutomaticUpdate(true)) { state in
            state.automaticUpdate = true
            state.automaticUpdateError = nil
        }

        XCTAssertTrue(storage.getBool(SettingsKeys.automaticUpdate) ?? false)
    }

    func testToggleAutomaticUpdateDisabled() async {
        storage.setBool(true, forKey: SettingsKeys.automaticUpdate)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.toggleAutomaticUpdate(false)) { state in
            state.automaticUpdate = false
            state.automaticUpdateError = nil
        }

        XCTAssertFalse(storage.getBool(SettingsKeys.automaticUpdate) ?? true)
    }

    // MARK: - SET-002:toggle_alert_before_app_quit

    func testToggleAlertBeforeQuitEnabled() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.toggleAlertBeforeQuit(true)) { state in
            state.alertBeforeQuit = true
        }

        XCTAssertTrue(storage.getBool(SettingsKeys.alertBeforeQuit) ?? false)
    }

    // MARK: - SET-002:check_for_updates (package-level no-op)

    func testCheckForUpdatesIsNoOp() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.checkForUpdates)

        XCTAssertFalse(store.state.automaticUpdate)
        XCTAssertNil(store.state.automaticUpdateError)
    }
}

private final class MutationRecorder<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [T] = []

    func record(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        _values.append(value)
    }

    var values: [T] {
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

import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

// MARK: - SET-002-configure_general_settings — 증거 계약

// 포함한 interaction_id:
//   SET-002-configure_initial_page → 집중 자동화 테스트
//     - testLoadSettingsUsesHomeWhenNoSavedPath (기본 디렉터리 로드)
//     - testLoadSettingsRestoresSavedDirectory (저장 디렉터리 로드)
//     - testSelectDirectoryOptionWithStandardOption (표준 디렉터리 옵션)
//     - testSelectDirectoryOptionOtherOpensPanel (.other → openOtherDirectoryPanel)
//     - testStartingDirectorySelectedWithCancelReturnsNil (취소 경로)
//     - testStartingDirectorySelectedWithValidDirectoryPath (유효한 picker 경로)
//     - testStartingDirectorySelectedWithNonexistentPathRejection (존재하지 않는 경로)
//     - testStartingDirectorySelectedWithNonDirectoryPathRejection (디렉터리가 아닌 경로)
//   SET-002-toggle_launch_at_startup → 집중 자동화 테스트
//     - testToggleLaunchAtStartupSuccess (로그인 시 실행 성공)
//     - testToggleLaunchAtStartupFailure (로그인 시 실행 실패)
//     - testLoadSettingsSyncsLaunchAtStartupWhenMismatch (로드 시 mismatch 동기화)
//   SET-002-toggle_automatic_update_install → 집중 자동화 테스트
//     - testToggleAutomaticUpdateEnabled
//     - testToggleAutomaticUpdateDisabled
//   SET-002-toggle_alert_before_app_quit → 집중 자동화 테스트
//     - testToggleAlertBeforeQuitEnabled
//   SET-002-check_for_updates → 집중 자동화 테스트 (package-level no-op)
//     - testCheckForUpdatesIsNoOp
//
// 미지원 surface 분류:
//   - Permissions: follow-up/manual QA (구현이 Settings가 아니라 Onboarding에 있음)
//   - SET-005 Shortcuts: 수동 QA (문서 전용 항목이며 앱은 정적 메뉴 명령을 사용함)
//   - SET-007 AI Connections: 외부 프로젝트 dependency
//     (https://linear.app/voyager-fm/project/byok구독-계정-연결-기반-ai-채팅-기능-도입-453bf1118aec)
//   - Account/License: 외부 프로젝트 dependency
//     (https://linear.app/voyager-fm/project/dollar5-core-license-결제권한앱-unlock-실험-21b8e66140e2)
//
// fixture reset: setUp()마다 InMemoryStorage를 재생성하며 영구 UserDefaults 상태가 필요 없다.
// 분류: 집중 자동화 테스트 + follow-up(AppRoot 전달은 별도 테스트에서 검증)

@MainActor
final class SET002ConfigureGeneralSettingsTests: XCTestCase {
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

    // MARK: - SET-002-configure_initial_page — 디렉터리 로드

    // SET-002-configure_initial_page — AC: 저장된 default_tab_path가 없으면 home directory가 기본값으로 선택되는지 검증한다.
    func testLoadSettingsUsesHomeWhenNoSavedPath() async {
        let store = makeStore(homePath: "/home/user")
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.startingDirectory, "/home/user")
        XCTAssertEqual(store.state.selectedDirectoryOption, .custom("/home/user"))
    }

    // SET-002-configure_initial_page — AC: 저장된 default_tab_path가 있으면 General tab 로드 시 해당 시작 경로가 복원되는지 검증한다.
    func testLoadSettingsRestoresSavedDirectory() async {
        storage.setString("/Users/test/saved-dir", forKey: SettingsKeys.defaultTabPath)
        let store = makeStore(homePath: "/home/user")
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.startingDirectory, "/Users/test/saved-dir")
    }

    // MARK: - SET-002-configure_initial_page — 자동 업데이트 및 종료 전 알림 로드

    // SET-002-toggle_automatic_update_install — AC: 저장된 automatic_update 값이 General tab 로드 시 토글 상태에 반영되는지 검증한다.
    func testLoadSettingsRestoresAutomaticUpdateFromStorage() async {
        storage.setObject(true, forKey: SettingsKeys.automaticUpdate)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.automaticUpdate)
    }

    // SET-002-toggle_alert_before_app_quit — AC: 저장된 alert_before_quit 값이 General tab 로드 시 토글 상태에 반영되는지 검증한다.
    func testLoadSettingsRestoresAlertBeforeQuitFromStorage() async {
        storage.setBool(true, forKey: SettingsKeys.alertBeforeQuit)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.alertBeforeQuit)
    }

    // SET-002-toggle_automatic_update_install — AC: automatic_update 저장값이 없으면 기본 off 상태를 유지하는지 검증한다.
    func testLoadSettingsDefaultsAutomaticUpdateToFalseWhenMissing() async {
        // storage에 automaticUpdate key가 없는 상태를 구성한다.
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertFalse(store.state.automaticUpdate)
    }

    // SET-002-toggle_alert_before_app_quit — AC: alert_before_quit 저장값이 없으면 기본 off 상태를 유지하는지 검증한다.
    func testLoadSettingsDefaultsAlertBeforeQuitToFalseWhenMissing() async {
        // storage에 alertBeforeQuit key가 없는 상태를 구성한다.
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertFalse(store.state.alertBeforeQuit)
    }

    // MARK: - SET-002-configure_initial_page — 디렉터리 옵션 선택

    // SET-002-configure_initial_page — AC: 표준 옵션을 선택하면 해당 시스템 경로가 default_tab_path에 저장되는지 검증한다.
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

    // SET-002-configure_initial_page — AC: Other... 선택 시 directory picker가 열리는 경로로 전환되는지 검증한다.
    func testSelectDirectoryOptionOtherOpensPanel() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.selectDirectoryOption(.other))
        await store.receive(\.openOtherDirectoryPanel) { state in
            state.isSelectingDirectory = true
            state.startingDirectoryError = nil
        }
    }

    // MARK: - SET-002-configure_initial_page — 디렉터리 picker 경로

    // SET-002-configure_initial_page — AC: directory picker를 취소하면 이전 설정을 유지하고 선택 상태만 해제되는지 검증한다.
    func testStartingDirectorySelectedWithCancelReturnsNil() async {
        let store = makeStore(pickDirectory: { nil })
        store.exhaustivity = .off

        await store.send(.openOtherDirectoryPanel)
        await store.receive(\.startingDirectorySelected) { state in
            state.isSelectingDirectory = false
        }
    }

    // SET-002-configure_initial_page — AC: Other...에서 유효한 directory를 선택하면 해당 경로가 default_tab_path에 저장되는지 검증한다.
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

    // SET-002-configure_initial_page — AC: 존재하지 않는 경로를 선택하면 저장하지 않고 오류 문구가 표시되는지 검증한다.
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

    // SET-002-configure_initial_page — AC: 디렉터리가 아닌 경로를 선택하면 저장하지 않고 오류 문구가 표시되는지 검증한다.
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

    // MARK: - SET-002-toggle_launch_at_startup

    // SET-002-toggle_launch_at_startup — AC: 토글을 켜면 launch_at_startup이 true로 저장되고 Login Items 등록 의존성이 호출되는지 검증한다.
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

    // SET-002-toggle_launch_at_startup — AC: launch_at_login_client 호출 실패 시 토글이 이전 상태로 돌아가고 오류 안내가 표시되는지 검증한다.
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

    // SET-002-toggle_launch_at_startup — AC: General tab 로드 시 시스템 Login Items 상태와 저장값 mismatch를 실제 시스템 상태 기준으로 보정하는지
    // 검증한다.
    func testLoadSettingsSyncsLaunchAtStartupWhenMismatch() async {
        storage.setBool(false, forKey: SettingsKeys.launchAtStartup)
        let store = makeStore(launchAtLoginEnabled: true)
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.launchAtStartup)
        XCTAssertTrue(storage.getBool(SettingsKeys.launchAtStartup) ?? false)
    }

    // MARK: - SET-002-toggle_automatic_update_install

    // SET-002-toggle_automatic_update_install — AC: Automatic Update를 켜면 automatic_update가 true로 저장되는지 검증한다.
    func testToggleAutomaticUpdateEnabled() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.toggleAutomaticUpdate(true)) { state in
            state.automaticUpdate = true
            state.automaticUpdateError = nil
        }

        XCTAssertTrue(storage.getBool(SettingsKeys.automaticUpdate) ?? false)
    }

    // SET-002-toggle_automatic_update_install — AC: Automatic Update를 끄면 automatic_update가 false로 저장되는지 검증한다.
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

    // MARK: - SET-002-toggle_alert_before_app_quit

    // SET-002-toggle_alert_before_app_quit — AC: Alert Before Quit 토글을 on으로 전환하면 alert_before_quit가 true로 저장되는지 검증한다.
    func testToggleAlertBeforeQuitEnabled() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.toggleAlertBeforeQuit(true)) { state in
            state.alertBeforeQuit = true
        }

        XCTAssertTrue(storage.getBool(SettingsKeys.alertBeforeQuit) ?? false)
    }

    // MARK: - SET-002-check_for_updates (package-level no-op)

    // SET-002-check_for_updates — AC: Check for Updates 실행은 package-level no-op으로 부분 상태 변경을 만들지 않는지 검증한다.
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

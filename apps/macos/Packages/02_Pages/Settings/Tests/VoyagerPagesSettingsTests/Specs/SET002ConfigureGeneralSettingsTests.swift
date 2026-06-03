import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

/*
 SET-002-configure_general_settings 증거 계약

 포함한 interaction_id:
 - SET-002-configure_initial_page: 집중 자동화 테스트
   `default_tab_path` 로드, 표준 디렉터리 옵션, Other picker의 취소/성공/거부 경로를 검증한다.
 - SET-002-toggle_launch_at_startup: 집중 자동화 테스트
   Login Items 등록 성공/실패와 저장값 mismatch 동기화를 검증한다.
 - SET-002-toggle_automatic_update_install: 집중 자동화 테스트
   automatic_update 토글 저장과 기본값 복원을 검증한다.
 - SET-002-toggle_alert_before_app_quit: 집중 자동화 테스트
   alert_before_quit 토글 저장과 기본값 복원을 검증한다.
 - SET-002-check_for_updates: 집중 자동화 테스트
   Settings package 레벨에서는 no-op임을 검증한다.

 Fixture reset:
 - `setUp()`마다 `InMemoryStorage`를 재생성하므로 영구 UserDefaults 상태가 필요 없다.

 미지원 surface 분류:
 - Permissions: follow-up/manual QA. 구현이 Settings가 아니라 Onboarding에 있다.
 - SET-005 Shortcuts: 수동 QA. 문서 전용 항목이며 앱은 정적 메뉴 명령을 사용한다.
 - SET-007 AI Connections: 외부 프로젝트 dependency.
 - Account/License: 외부 프로젝트 dependency.
 */

@MainActor
final class SET002ConfigureGeneralSettingsTests: XCTestCase {
    nonisolated(unsafe) private var storage: InMemoryStorage!

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

    // MARK: - SET-002-configure_initial_page

    /// 디렉터리 로드
    /// SET-002-configure_initial_page: 저장된 시작 경로가 없으면 home directory를 기본 시작 위치로 사용한다.
    /// General tab 첫 로드에서 사용자가 별도 시작 폴더를 저장하지 않은 fresh 상태를 검증한다.
    /// - 검증 내용: `.loadSettings`가 `default_tab_path` 부재 시 `DirectorySelectionClient.defaultHomePath()` 값을 적용한다.
    /// - 사전 조건: `InMemoryStorage`에 `SettingsKeys.defaultTabPath`가 없고 home path는 `/home/user`로 주입된다.
    /// - 기대 결과: `startingDirectory = "/home/user"`, `selectedDirectoryOption = .custom("/home/user")`이다.
    func testLoadSettingsUsesHomeWhenNoSavedPath() async {
        let store = makeStore(homePath: "/home/user")
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 startingDirectory만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.startingDirectory, "/home/user")
        XCTAssertEqual(store.state.selectedDirectoryOption, .custom("/home/user"))
    }

    /// SET-002-configure_initial_page: 저장된 `default_tab_path`가 있으면 General tab 로드 시 해당 시작 경로를 복원한다.
    /// 이전 세션에서 선택한 custom directory가 앱 재실행 후에도 유지되는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 storage의 `default_tab_path` 문자열을 `startingDirectory`로 반영한다.
    /// - 사전 조건: `SettingsKeys.defaultTabPath`에 `/Users/test/saved-dir`가 저장되어 있다.
    /// - 기대 결과: `startingDirectory`가 저장된 `/Users/test/saved-dir`로 복원된다.
    func testLoadSettingsRestoresSavedDirectory() async {
        storage.setString("/Users/test/saved-dir", forKey: SettingsKeys.defaultTabPath)
        let store = makeStore(homePath: "/home/user")
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 startingDirectory만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.startingDirectory, "/Users/test/saved-dir")
    }

    // MARK: - SET-002-configure_initial_page

    /// 자동 업데이트 및 종료 전 알림 로드
    /// SET-002-toggle_automatic_update_install: 저장된 automatic update 설정을 General tab 토글 상태로 복원한다.
    /// 사용자가 이전에 켜 둔 자동 업데이트 설정이 load 단계에서 UI state로 반영되는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 `SettingsKeys.automaticUpdate` 값을 `automaticUpdate`에 반영한다.
    /// - 사전 조건: storage에 `automaticUpdate = true`가 object 값으로 저장되어 있다.
    /// - 기대 결과: `store.state.automaticUpdate`가 `true`다.
    func testLoadSettingsRestoresAutomaticUpdateFromStorage() async {
        storage.setObject(true, forKey: SettingsKeys.automaticUpdate)
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 automaticUpdate만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.automaticUpdate)
    }

    /// SET-002-toggle_alert_before_app_quit: 저장된 종료 전 알림 설정을 General tab 토글 상태로 복원한다.
    /// 사용자가 앱 종료 전 확인 알림을 켜 둔 상태가 Settings 로드 후에도 유지되는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 `SettingsKeys.alertBeforeQuit` 값을 `alertBeforeQuit`에 반영한다.
    /// - 사전 조건: storage에 `alertBeforeQuit = true`가 저장되어 있다.
    /// - 기대 결과: `store.state.alertBeforeQuit`가 `true`다.
    func testLoadSettingsRestoresAlertBeforeQuitFromStorage() async {
        storage.setBool(true, forKey: SettingsKeys.alertBeforeQuit)
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 alertBeforeQuit만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.alertBeforeQuit)
    }

    /// SET-002-toggle_automatic_update_install: 저장값이 없으면 automatic update 기본 off 상태를 유지한다.
    /// fresh storage에서 누락된 설정값이 실수로 on으로 해석되지 않는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 `automaticUpdate` key 부재를 `false`로 처리한다.
    /// - 사전 조건: storage에 `SettingsKeys.automaticUpdate` 값이 없다.
    /// - 기대 결과: `store.state.automaticUpdate`가 `false`다.
    func testLoadSettingsDefaultsAutomaticUpdateToFalseWhenMissing() async {
        // storage에 automaticUpdate key가 없는 상태를 구성한다.
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 automaticUpdate 기본값만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertFalse(store.state.automaticUpdate)
    }

    /// SET-002-toggle_alert_before_app_quit: 저장값이 없으면 종료 전 알림 기본 off 상태를 유지한다.
    /// fresh storage에서 누락된 alert preference가 실수로 활성화되지 않는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 `alertBeforeQuit` key 부재를 `false`로 처리한다.
    /// - 사전 조건: storage에 `SettingsKeys.alertBeforeQuit` 값이 없다.
    /// - 기대 결과: `store.state.alertBeforeQuit`가 `false`다.
    func testLoadSettingsDefaultsAlertBeforeQuitToFalseWhenMissing() async {
        // storage에 alertBeforeQuit key가 없는 상태를 구성한다.
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 alertBeforeQuit 기본값만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertFalse(store.state.alertBeforeQuit)
    }

    // MARK: - SET-002-configure_initial_page

    /// 디렉터리 옵션 선택
    /// SET-002-configure_initial_page: 표준 디렉터리 옵션을 선택하면 해당 시스템 경로를 시작 경로로 저장한다.
    /// 사용자가 Root 같은 predefined option을 선택했을 때 state와 persistence가 함께 갱신되는지 검증한다.
    /// - 검증 내용: `.selectDirectoryOption(.root)`가 `.setStartingDirectory`를 거쳐 state와 storage를 갱신한다.
    /// - 사전 조건: General settings는 기본 상태이고 storage에는 기존 시작 경로가 없다.
    /// - 기대 결과: `startingDirectory = "/"`, `selectedDirectoryOption = .root`, 저장된 `default_tab_path = "/"`다.
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

    /// SET-002-configure_initial_page: Other... 옵션을 선택하면 directory picker flow를 시작한다.
    /// custom directory 선택 UI로 진입할 때 기존 오류를 지우고 선택 중 상태로 바뀌는지 검증한다.
    /// - 검증 내용: `.selectDirectoryOption(.other)`가 `.openOtherDirectoryPanel` action을 방출한다.
    /// - 사전 조건: General settings는 기본 상태이며 directory picker dependency는 호출 대기 상태다.
    /// - 기대 결과: `isSelectingDirectory = true`, `startingDirectoryError = nil`이다.
    func testSelectDirectoryOptionOtherOpensPanel() async {
        let store = makeStore()
        // store.exhaustivity = .off: openOtherDirectoryPanel 이후 pickDirectory 효과의 완료 액션 추적 생략
        store.exhaustivity = .off

        await store.send(.selectDirectoryOption(.other))
        await store.receive(\.openOtherDirectoryPanel) { state in
            state.isSelectingDirectory = true
            state.startingDirectoryError = nil
        }

        // finish(): pickDirectory 비동기 효과가 startingDirectorySelected를 발생시키나 검증 범위 밖
        await store.finish()
    }

    // MARK: - SET-002-configure_initial_page

    /// 디렉터리 picker 경로
    /// SET-002-configure_initial_page: Directory picker를 취소하면 기존 시작 경로를 유지하고 선택 상태만 해제한다.
    /// 사용자가 picker에서 취소를 눌렀을 때 저장값이나 선택 옵션이 불필요하게 바뀌지 않는지 검증한다.
    /// - 검증 내용: `.openOtherDirectoryPanel` 후 picker가 `nil`을 반환하면 `.startingDirectorySelected`에서 선택 상태만 종료한다.
    /// - 사전 조건: `pickDirectory` dependency가 `nil`을 반환하도록 주입된다.
    /// - 기대 결과: `isSelectingDirectory = false`가 되고 추가 `setStartingDirectory` action은 발생하지 않는다.
    func testStartingDirectorySelectedWithCancelReturnsNil() async {
        let store = makeStore(pickDirectory: { nil })
        // store.exhaustivity = .off: openOtherDirectoryPanel 상태 변화(isSelectingDirectory, startingDirectoryError) 추적 생략
        store.exhaustivity = .off

        await store.send(.openOtherDirectoryPanel)
        await store.receive(\.startingDirectorySelected) { state in
            state.isSelectingDirectory = false
        }
    }

    /// SET-002-configure_initial_page: Other...에서 유효한 directory를 선택하면 custom 시작 경로로 저장한다.
    /// picker가 반환한 경로가 실제 directory일 때 reducer가 검증을 통과시키고 persistence까지 완료하는지 검증한다.
    /// - 검증 내용: picker 성공 후 `.startingDirectorySelected`와 `.setStartingDirectory` chain이 state/storage를 갱신한다.
    /// - 사전 조건: 임시 directory를 만들고 `pathExists`, `isDirectory` dependency가 실제 파일 시스템 결과를 반환한다.
    /// - 기대 결과: `startingDirectory`와 `default_tab_path`가 선택된 valid path이고 오류는 `nil`이다.
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

    /// SET-002-configure_initial_page: 존재하지 않는 경로를 선택하면 저장하지 않고 오류 문구를 표시한다.
    /// picker가 stale 또는 삭제된 path를 반환해도 잘못된 시작 경로가 persistence에 기록되지 않는지 검증한다.
    /// - 검증 내용: `pathExists = false`일 때 `.startingDirectorySelected`가 validation error state를 설정한다.
    /// - 사전 조건: `pickDirectory`는 nonexistent path를 반환하고 `pathExists`, `isDirectory`는 모두 `false`다.
    /// - 기대 결과: `startingDirectoryError = "Invalid directory path"`이며 시작 경로 저장은 진행되지 않는다.
    func testStartingDirectorySelectedWithNonexistentPathRejection() async {
        let nonexistentPath = "/tmp/set002-nonexistent-dir-XYZ"
        let store = makeStore(
            pickDirectory: { nonexistentPath },
            pathExists: { _ in false },
            isDirectory: { _ in false },
        )
        // store.exhaustivity = .off: openOtherDirectoryPanel 상태 변화 추적 생략, 에러 경로 검증에 집중
        store.exhaustivity = .off

        await store.send(.openOtherDirectoryPanel)
        await store.receive(\.startingDirectorySelected) { state in
            state.isSelectingDirectory = false
            state.startingDirectoryError = "Invalid directory path"
        }

        XCTAssertEqual(store.state.startingDirectoryError, "Invalid directory path")
    }

    /// SET-002-configure_initial_page: 디렉터리가 아닌 경로를 선택하면 저장하지 않고 오류 문구를 표시한다.
    /// 사용자가 file path를 선택한 경우 Settings 시작 위치가 파일로 설정되지 않도록 검증한다.
    /// - 검증 내용: `pathExists = true`, `isDirectory = false`일 때 directory 전용 validation error가 설정된다.
    /// - 사전 조건: 임시 file path를 만들고 picker가 그 file path를 반환한다.
    /// - 기대 결과: `startingDirectoryError = "Selected path is not a directory"`이며 저장값은 갱신되지 않는다.
    func testStartingDirectorySelectedWithNonDirectoryPathRejection() async {
        let filePath = "/tmp/set002-test-file.txt"
        FileManager.default.createFile(atPath: filePath, contents: Data())

        defer { try? FileManager.default.removeItem(atPath: filePath) }

        let store = makeStore(
            pickDirectory: { filePath },
            pathExists: { _ in true },
            isDirectory: { _ in false },
        )
        // store.exhaustivity = .off: openOtherDirectoryPanel 상태 변화 추적 생략, 에러 경로 검증에 집중
        store.exhaustivity = .off

        await store.send(.openOtherDirectoryPanel)
        await store.receive(\.startingDirectorySelected) { state in
            state.isSelectingDirectory = false
            state.startingDirectoryError = "Selected path is not a directory"
        }

        XCTAssertEqual(store.state.startingDirectoryError, "Selected path is not a directory")
    }

    // MARK: - SET-002-toggle_launch_at_startup

    /// SET-002-toggle_launch_at_startup: Launch at Startup 토글을 켜면 저장값과 Login Items 등록을 함께 갱신한다.
    /// UI 토글 변경이 reducer state에만 머무르지 않고 system-facing dependency까지 호출되는지 검증한다.
    /// - 검증 내용: `.toggleLaunchAtStartup(true)`가 state, storage, `LaunchAtLoginClient.setEnabled` 호출을 모두 수행한다.
    /// - 사전 조건: Login Items는 비활성 상태이며 `MutationRecorder`가 `setEnabled` 입력값을 기록한다.
    /// - 기대 결과: recorder 값은 `[true]`, 저장된 `launchAtStartup = true`, 오류는 `nil`이다.
    func testToggleLaunchAtStartupSuccess() async {
        let recorder = MutationRecorder<Bool>()
        let store = makeStore(
            launchAtLoginEnabled: false,
            launchAtLoginSetEnabled: { enabled in
                recorder.record(enabled)
            },
        )

        await store.send(.toggleLaunchAtStartup(true)) { state in
            state.launchAtStartup = true
            state.launchAtStartupError = nil
        }

        XCTAssertEqual(recorder.values, [true])
        XCTAssertTrue(storage.getBool(SettingsKeys.launchAtStartup) ?? false)
        XCTAssertNil(store.state.launchAtStartupError)
    }

    /// SET-002-toggle_launch_at_startup: Login Items 등록 실패 시 토글 상태를 되돌리고 오류 안내를 표시한다.
    /// system dependency 실패가 사용자 설정 state를 성공처럼 남기지 않는지 검증한다.
    /// - 검증 내용: `LaunchAtLoginClient.setEnabled`가 throw하면 reducer가 이전 `launchAtStartup` 값을 복구한다.
    /// - 사전 조건: Login Items는 비활성 상태이고 `setEnabled`는 `LaunchAtLoginError`를 throw한다.
    /// - 기대 결과: `launchAtStartup`은 이전 값으로 돌아가며 `launchAtStartupError`에 실패 안내가 들어 있다.
    func testToggleLaunchAtStartupFailure() async {
        struct LaunchAtLoginError: Error {}
        let store = makeStore(
            launchAtLoginEnabled: false,
            launchAtLoginSetEnabled: { _ in
                throw LaunchAtLoginError()
            },
        )
        // store.exhaustivity = .off: setEnabled throw 시 state 변화를 assert로 간접 검증
        store.exhaustivity = .off

        let previousLaunchAtStartup = store.state.launchAtStartup
        await store.send(.toggleLaunchAtStartup(true))

        XCTAssertNotNil(store.state.launchAtStartupError)
        XCTAssertTrue(
            store.state.launchAtStartupError?.contains("Failed to set launch at startup") ?? false,
        )
        XCTAssertEqual(store.state.launchAtStartup, previousLaunchAtStartup)
    }

    /// SET-002-toggle_launch_at_startup: General tab 로드 시 저장값과 시스템 Login Items 상태 mismatch를 시스템 기준으로 보정한다.
    /// storage 값이 오래되었을 때 실제 OS Login Items 상태가 Settings UI와 persistence의 source of truth가 되는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 `LaunchAtLoginClient.isEnabled()` 결과를 state와 storage에 동기화한다.
    /// - 사전 조건: storage에는 `launchAtStartup = false`, dependency에는 실제 상태 `true`가 주입된다.
    /// - 기대 결과: `store.state.launchAtStartup = true`이고 storage의 `launchAtStartup`도 `true`로 보정된다.
    func testLoadSettingsSyncsLaunchAtStartupWhenMismatch() async {
        storage.setBool(false, forKey: SettingsKeys.launchAtStartup)
        let store = makeStore(launchAtLoginEnabled: true)
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 launchAtStartup 동기화만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.launchAtStartup)
        XCTAssertTrue(storage.getBool(SettingsKeys.launchAtStartup) ?? false)
    }

    // MARK: - SET-002-toggle_automatic_update_install

    /// SET-002-toggle_automatic_update_install: Automatic Update를 켜면 state와 storage에 true를 저장한다.
    /// 사용자가 자동 업데이트 설치를 활성화한 선택이 Settings persistence에 남는지 검증한다.
    /// - 검증 내용: `.toggleAutomaticUpdate(true)`가 `automaticUpdate` state와 `SettingsKeys.automaticUpdate`를 갱신한다.
    /// - 사전 조건: General settings는 기본 off 상태이며 storage에는 기존 automatic update 값이 없다.
    /// - 기대 결과: `automaticUpdate = true`, `automaticUpdateError = nil`, 저장값은 `true`다.
    func testToggleAutomaticUpdateEnabled() async {
        let store = makeStore()

        await store.send(.toggleAutomaticUpdate(true)) { state in
            state.automaticUpdate = true
            state.automaticUpdateError = nil
        }

        XCTAssertTrue(storage.getBool(SettingsKeys.automaticUpdate) ?? false)
    }

    /// SET-002-toggle_automatic_update_install: Automatic Update를 끄면 state와 storage에 false를 저장한다.
    /// 이전에 켜져 있던 자동 업데이트 설정을 명시적으로 비활성화할 수 있는지 검증한다.
    /// - 검증 내용: `.toggleAutomaticUpdate(false)`가 state와 저장값을 false로 갱신한다.
    /// - 사전 조건: storage에는 `automaticUpdate = true`가 저장되어 있다.
    /// - 기대 결과: `automaticUpdate = false`, `automaticUpdateError = nil`, 저장값은 `false`다.
    func testToggleAutomaticUpdateDisabled() async {
        storage.setBool(true, forKey: SettingsKeys.automaticUpdate)
        let store = makeStore()
        // store.exhaustivity = .off: 초기값(false)과 토글값(false)이 같아 상태 변화 없음, storage 갱신만 검증
        store.exhaustivity = .off

        await store.send(.toggleAutomaticUpdate(false)) { state in
            state.automaticUpdate = false
            state.automaticUpdateError = nil
        }

        XCTAssertFalse(storage.getBool(SettingsKeys.automaticUpdate) ?? true)
    }

    // MARK: - SET-002-toggle_alert_before_app_quit

    /// SET-002-toggle_alert_before_app_quit: Alert Before Quit 토글을 켜면 종료 전 확인 설정을 저장한다.
    /// 사용자가 앱 종료 전 확인을 요구하도록 설정했을 때 state와 storage가 함께 갱신되는지 검증한다.
    /// - 검증 내용: `.toggleAlertBeforeQuit(true)`가 `alertBeforeQuit` state와 `SettingsKeys.alertBeforeQuit`를 true로 저장한다.
    /// - 사전 조건: General settings는 기본 off 상태이며 storage에는 기존 alert preference가 없다.
    /// - 기대 결과: `alertBeforeQuit = true`이고 저장값도 `true`다.
    func testToggleAlertBeforeQuitEnabled() async {
        let store = makeStore()

        await store.send(.toggleAlertBeforeQuit(true)) { state in
            state.alertBeforeQuit = true
        }

        XCTAssertTrue(storage.getBool(SettingsKeys.alertBeforeQuit) ?? false)
    }

    // MARK: - SET-002-check_for_updates

    /// package-level no-op
    /// SET-002-check_for_updates: Settings package 레벨의 Check for Updates action은 no-op으로 유지된다.
    /// 업데이트 확인의 실제 orchestration이 상위 앱 경계에 있을 때 package reducer가 부분 state를 변경하지 않는지 검증한다.
    /// - 검증 내용: `.checkForUpdates` 전송 후 automatic update 관련 state가 바뀌지 않는다.
    /// - 사전 조건: General settings는 기본 상태이며 update service dependency는 이 package에 주입하지 않는다.
    /// - 기대 결과: `automaticUpdate = false`, `automaticUpdateError = nil`로 유지된다.
    func testCheckForUpdatesIsNoOp() async {
        let store = makeStore()

        await store.send(.checkForUpdates)

        XCTAssertFalse(store.state.automaticUpdate)
        XCTAssertNil(store.state.automaticUpdateError)
    }
}

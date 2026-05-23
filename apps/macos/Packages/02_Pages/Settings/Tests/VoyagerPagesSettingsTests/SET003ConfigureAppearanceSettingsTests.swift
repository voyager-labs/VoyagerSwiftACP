import ComposableArchitecture
import CoreGraphics
import Foundation
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

// MARK: - SET-003-configure_appearance_settings — 증거 계약

// 포함한 interaction_id:
//   SET-003-switch_theme_mode → 집중 자동화 테스트
//     - testLoadSettingsRestoresTheme (dependency에서 theme 로드)
//     - testSetThemePersistsRawValueAndApplies (raw value 저장 + applyTheme 호출)
//   SET-003-adjust_icon_size → 집중 자동화 테스트
//     - testLoadSettingsRestoresListIconSize (저장값 로드)
//     - testMissingListIconSizePreservesDefault (숫자 저장값 누락 → 기본값)
//     - testSetListIconSizePersistsExactKeyValue
//   SET-003-adjust_icon_size → 집중 자동화 테스트
//     - testLoadSettingsRestoresGridIconSize
//     - testMissingGridIconSizePreservesDefault
//     - testSetGridIconSizePersistsExactKeyValue
//   SET-003-adjust_text_size → 집중 자동화 테스트
//     - testLoadSettingsRestoresListTextSize
//     - testMissingListTextSizePreservesDefault
//     - testSetListTextSizePersistsExactKeyValue
//   SET-003-adjust_text_size → 집중 자동화 테스트
//     - testLoadSettingsRestoresGridTextSize
//     - testMissingGridTextSizePreservesDefault
//     - testSetGridTextSizePersistsExactKeyValue
//   SET-003 supplemental current behavior(showHiddenFiles; canonical interaction_id 없음) → 집중 자동화 테스트
//     - testLoadSettingsRestoresShowHiddenFiles
//     - testSetShowHiddenFilesEnabled
//     - testSetShowHiddenFilesDisabled
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
// 분류: 집중 자동화 테스트

@MainActor
final class SET003ConfigureAppearanceSettingsTests: XCTestCase {
    private nonisolated(unsafe) var storage: InMemoryStorage!
    private nonisolated(unsafe) var themeRecorder: ThemeApplyRecorder!

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

    // MARK: - SET-003-switch_theme_mode

    // SET-003-switch_theme_mode — AC: Appearance tab 로드 시 저장된 theme가 유효한 theme 상태로 복원되는지 검증한다.
    func testLoadSettingsRestoresTheme() async {
        let store = makeStore(loadTheme: { .dark })
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.theme, .dark)
    }

    // SET-003-switch_theme_mode — AC: Dark 선택 시 theme이 Dark로 저장되고 app appearance 적용 의존성이 호출되는지 검증한다.
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

    // SET-003-switch_theme_mode — AC: Light 선택 시 theme이 Light로 저장되고 app appearance 적용 의존성이 호출되는지 검증한다.
    func testSetThemeToLightPersistsAndApplies() async {
        let store = makeStore(loadTheme: { .dark })
        store.exhaustivity = .off

        await store.send(.setTheme(.light)) { state in
            state.theme = .light
        }

        XCTAssertEqual(storage.getObject(SettingsKeys.theme) as? String, AppTheme.light.rawValue)
        XCTAssertEqual(themeRecorder.values, [.light])
    }

    // MARK: - SET-003-adjust_icon_size

    // SET-003-adjust_icon_size — AC: 저장된 list_icon_size가 있으면 Appearance tab 로드 시 해당 값이 표시되는지 검증한다.
    func testLoadSettingsRestoresListIconSize() async {
        storage.setObject(CGFloat(25.0), forKey: SettingsKeys.listIconSize)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listIconSize, 25.0)
    }

    // SET-003-adjust_icon_size — AC: 저장된 icon size 값이 없으면 appearance_settings_defaults 값이 표시되는지 검증한다.
    func testMissingListIconSizePreservesDefault() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listIconSize, AppearanceSettingsDefaults.listIconSize)
    }

    // SET-003-adjust_icon_size — AC: list 아이콘 크기를 조절하면 list_icon_size로 저장되는지 검증한다.
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

    // MARK: - SET-003-adjust_icon_size

    // SET-003-adjust_icon_size — AC: 저장된 grid_icon_size가 있으면 Appearance tab 로드 시 해당 값이 표시되는지 검증한다.
    func testLoadSettingsRestoresGridIconSize() async {
        storage.setObject(CGFloat(80.0), forKey: SettingsKeys.gridIconSize)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridIconSize, 80.0)
    }

    // SET-003-adjust_icon_size — AC: 저장된 icon size 값이 없으면 grid 아이콘 크기도 기본값을 유지하는지 검증한다.
    func testMissingGridIconSizePreservesDefault() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridIconSize, AppearanceSettingsDefaults.gridIconSize)
    }

    // SET-003-adjust_icon_size — AC: grid 아이콘 크기를 조절하면 grid_icon_size로 저장되는지 검증한다.
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

    // MARK: - SET-003-adjust_text_size

    // SET-003-adjust_text_size — AC: 저장된 list_text_size가 있으면 Appearance tab 로드 시 해당 값이 표시되는지 검증한다.
    func testLoadSettingsRestoresListTextSize() async {
        storage.setObject(CGFloat(15.0), forKey: SettingsKeys.listTextSize)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listTextSize, 15.0)
    }

    // SET-003-adjust_text_size — AC: 저장된 text size 값이 없으면 appearance_settings_defaults 기본값이 표시되는지 검증한다.
    func testMissingListTextSizePreservesDefault() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listTextSize, AppearanceSettingsDefaults.listTextSize)
    }

    // SET-003-adjust_text_size — AC: list text size를 조절하면 list_text_size가 저장되는지 검증한다.
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

    // MARK: - SET-003-adjust_text_size

    // SET-003-adjust_text_size — AC: 저장된 grid_text_size가 있으면 Appearance tab 로드 시 해당 값이 표시되는지 검증한다.
    func testLoadSettingsRestoresGridTextSize() async {
        storage.setObject(CGFloat(14.0), forKey: SettingsKeys.gridTextSize)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridTextSize, 14.0)
    }

    // SET-003-adjust_text_size — AC: 저장된 text size 값이 없으면 grid 텍스트 크기도 기본값을 유지하는지 검증한다.
    func testMissingGridTextSizePreservesDefault() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridTextSize, AppearanceSettingsDefaults.gridTextSize)
    }

    // SET-003-adjust_text_size — AC: grid text size를 조절하면 grid_text_size가 저장되는지 검증한다.
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

    // MARK: - SET-003 supplemental current behavior — showHiddenFiles

    // SET-003 supplemental current behavior — AC: flow에 포함된 hidden files 표시 설정 저장값이 로드 시 복원되는지 검증한다.
    func testLoadSettingsRestoresShowHiddenFiles() async {
        storage.setBool(true, forKey: SettingsKeys.showHiddenFiles)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.showHiddenFiles)
    }

    // SET-003 supplemental current behavior — AC: hidden files 표시 활성화 토글이 상태와 저장값을 true로 반영하는지 검증한다.
    func testSetShowHiddenFilesEnabled() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.setShowHiddenFiles(true)) { state in
            state.showHiddenFiles = true
        }

        XCTAssertTrue(store.state.showHiddenFiles)
        XCTAssertTrue(storage.getBool(SettingsKeys.showHiddenFiles) ?? false)
    }

    // SET-003 supplemental current behavior — AC: hidden files 표시 비활성화 토글이 상태와 저장값을 false로 반영하는지 검증한다.
    func testSetShowHiddenFilesDisabled() async {
        storage.setBool(true, forKey: SettingsKeys.showHiddenFiles)
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.setShowHiddenFiles(false)) { state in
            state.showHiddenFiles = false
        }

        XCTAssertFalse(store.state.showHiddenFiles)
        XCTAssertFalse(storage.getBool(SettingsKeys.showHiddenFiles) ?? true)
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

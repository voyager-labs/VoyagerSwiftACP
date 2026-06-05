import ComposableArchitecture
import CoreGraphics
import Foundation
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

/*
 SET-003-configure_appearance_settings 증거 계약

 포함한 interaction_id:
 - SET-003-switch_theme_mode: 집중 자동화 테스트
   저장된 theme 로드, theme raw value 저장, app appearance 적용 dependency 호출을 검증한다.
 - SET-003-adjust_icon_size: 집중 자동화 테스트
   list/grid icon size의 저장값 로드, 기본값 유지, exact key persistence를 검증한다.
 - SET-003-adjust_text_size: 집중 자동화 테스트
   list/grid text size의 저장값 로드, 기본값 유지, exact key persistence를 검증한다.
 - SET-003 supplemental current behavior(showHiddenFiles): 집중 자동화 테스트
   canonical interaction_id는 없지만 현재 Appearance flow에 포함된 hidden files 표시 설정의 load/toggle persistence를 검증한다.

 Fixture reset:
 - `setUp()`마다 `InMemoryStorage`와 `ThemeApplyRecorder`를 재생성하므로 영구 UserDefaults 상태가 필요 없다.

 미지원 surface 분류:
 - Permissions: follow-up/manual QA. 구현이 Settings가 아니라 Onboarding에 있다.
 - SET-005 Shortcuts: 수동 QA. 문서 전용 항목이며 앱은 정적 메뉴 명령을 사용한다.
 - SET-007 AI Connections: 외부 프로젝트 dependency.
 - Account/License: 외부 프로젝트 dependency.
 */

@MainActor
final class SET003ConfigureAppearanceSettingsTests: XCTestCase {
    nonisolated(unsafe) private var storage: InMemoryStorage!
    nonisolated(unsafe) private var themeRecorder: ThemeApplyRecorder!

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

    /// SET-003-switch_theme_mode: Appearance tab 로드 시 저장된 theme를 reducer state로 복원한다.
    /// app-wide appearance dependency가 제공하는 현재 theme가 UI 선택 상태와 일치하는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 `AppearanceSettingsClient.loadTheme()` 결과를 `theme` state에 반영한다.
    /// - 사전 조건: `loadTheme` dependency는 `.dark`를 반환하도록 주입된다.
    /// - 기대 결과: `store.state.theme = .dark`다.
    func testLoadSettingsRestoresTheme() async {
        let store = makeStore(loadTheme: { .dark })
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 theme만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.theme, .dark)
    }

    /// SET-003-switch_theme_mode: Dark 선택 시 theme raw value를 저장하고 app appearance 적용 dependency를 호출한다.
    /// 사용자가 theme mode를 바꿀 때 Settings persistence와 실제 appearance side effect가 함께 실행되는지 검증한다.
    /// - 검증 내용: `.setTheme(.dark)`가 state, `SettingsKeys.theme`, `applyTheme` 호출을 모두 갱신한다.
    /// - 사전 조건: 현재 theme는 `.system`이고 `ThemeApplyRecorder`가 적용 요청을 기록한다.
    /// - 기대 결과: `theme = .dark`, 저장 raw value는 `AppTheme.dark.rawValue`, recorder 값은 `[.dark]`다.
    func testSetThemePersistsRawValueAndApplies() async {
        let store = makeStore(loadTheme: { .system })
        // store.exhaustivity = .off: setTheme의 applyTheme run 효과가 action을 발생시키지 않아 추적 생략
        store.exhaustivity = .off

        await store.send(.setTheme(.dark)) { state in
            state.theme = .dark
        }

        XCTAssertEqual(store.state.theme, .dark)
        XCTAssertEqual(storage.getObject(SettingsKeys.theme) as? String, AppTheme.dark.rawValue)
        XCTAssertEqual(themeRecorder.values, [.dark])

        // finish(): applyTheme 비동기 효과 완료 대기
        await store.finish()
    }

    /// SET-003-switch_theme_mode: Light 선택 시 theme raw value를 저장하고 app appearance 적용 dependency를 호출한다.
    /// 기존 Dark 상태에서 Light로 변경하는 분기에서도 동일한 persistence/apply 계약이 지켜지는지 검증한다.
    /// - 검증 내용: `.setTheme(.light)`가 `SettingsKeys.theme`과 `applyTheme` 호출 값을 `.light`로 갱신한다.
    /// - 사전 조건: `loadTheme` dependency는 `.dark`를 반환하고 recorder는 비어 있다.
    /// - 기대 결과: 저장 raw value는 `AppTheme.light.rawValue`, recorder 값은 `[.light]`다.
    func testSetThemeToLightPersistsAndApplies() async {
        let store = makeStore(loadTheme: { .dark })
        // store.exhaustivity = .off: setTheme의 applyTheme run 효과가 action을 발생시키지 않아 추적 생략
        store.exhaustivity = .off

        await store.send(.setTheme(.light)) { state in
            state.theme = .light
        }

        XCTAssertEqual(storage.getObject(SettingsKeys.theme) as? String, AppTheme.light.rawValue)
        XCTAssertEqual(themeRecorder.values, [.light])

        // finish(): applyTheme 비동기 효과 완료 대기
        await store.finish()
    }

    // MARK: - SET-003-adjust_icon_size

    /// SET-003-adjust_icon_size: 저장된 list icon size가 있으면 Appearance tab 로드 시 해당 값을 표시한다.
    /// list view icon slider가 이전 세션에서 저장된 사용자 값을 복원하는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 `SettingsKeys.listIconSize` object 값을 `listIconSize` state로 반영한다.
    /// - 사전 조건: storage에 `CGFloat(25.0)`이 list icon size로 저장되어 있다.
    /// - 기대 결과: `store.state.listIconSize = 25.0`이다.
    func testLoadSettingsRestoresListIconSize() async {
        storage.setObject(CGFloat(25.0), forKey: SettingsKeys.listIconSize)
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 listIconSize만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listIconSize, 25.0)
    }

    /// SET-003-adjust_icon_size: list icon size 저장값이 없으면 Appearance defaults 값을 유지한다.
    /// fresh storage에서 누락된 숫자 preference가 0이나 잘못된 값으로 덮이지 않는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 list icon size key 부재 시 기본 state를 보존한다.
    /// - 사전 조건: storage에 `SettingsKeys.listIconSize` 값이 없다.
    /// - 기대 결과: `listIconSize = AppearanceSettingsDefaults.listIconSize`다.
    func testMissingListIconSizePreservesDefault() async {
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 listIconSize 기본값만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listIconSize, AppearanceSettingsDefaults.listIconSize)
    }

    /// SET-003-adjust_icon_size: list icon size를 조절하면 exact CGFloat 값을 list_icon_size로 저장한다.
    /// slider 입력이 반올림/정규화 없이 사용자가 선택한 크기 그대로 persistence에 기록되는지 검증한다.
    /// - 검증 내용: `.setListIconSize`가 state와 `SettingsKeys.listIconSize` object 값을 같은 `CGFloat`로 갱신한다.
    /// - 사전 조건: Appearance settings는 기본 상태이고 새 크기는 `35.0`이다.
    /// - 기대 결과: state와 저장값 모두 `35.0`이다.
    func testSetListIconSizePersistsExactKeyValue() async {
        let store = makeStore()

        let newSize: CGFloat = 35.0
        await store.send(.setListIconSize(newSize)) { state in
            state.listIconSize = newSize
        }

        XCTAssertEqual(store.state.listIconSize, newSize)
        let persisted = storage.getObject(SettingsKeys.listIconSize) as? CGFloat
        XCTAssertEqual(persisted, newSize)
    }

    // MARK: - SET-003-adjust_icon_size

    /// SET-003-adjust_icon_size: 저장된 grid icon size가 있으면 Appearance tab 로드 시 해당 값을 표시한다.
    /// grid view icon slider가 이전 세션에서 저장된 사용자 값을 복원하는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 `SettingsKeys.gridIconSize` object 값을 `gridIconSize` state로 반영한다.
    /// - 사전 조건: storage에 `CGFloat(80.0)`이 grid icon size로 저장되어 있다.
    /// - 기대 결과: `store.state.gridIconSize = 80.0`이다.
    func testLoadSettingsRestoresGridIconSize() async {
        storage.setObject(CGFloat(80.0), forKey: SettingsKeys.gridIconSize)
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 gridIconSize만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridIconSize, 80.0)
    }

    /// SET-003-adjust_icon_size: grid icon size 저장값이 없으면 Appearance defaults 값을 유지한다.
    /// fresh storage에서 grid icon preference가 누락되어도 기본 UI 크기가 보존되는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 grid icon size key 부재 시 기본 state를 보존한다.
    /// - 사전 조건: storage에 `SettingsKeys.gridIconSize` 값이 없다.
    /// - 기대 결과: `gridIconSize = AppearanceSettingsDefaults.gridIconSize`다.
    func testMissingGridIconSizePreservesDefault() async {
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 gridIconSize 기본값만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridIconSize, AppearanceSettingsDefaults.gridIconSize)
    }

    /// SET-003-adjust_icon_size: grid icon size를 조절하면 exact CGFloat 값을 grid_icon_size로 저장한다.
    /// grid slider 입력이 list slider와 독립된 key에 정확히 persistence되는지 검증한다.
    /// - 검증 내용: `.setGridIconSize`가 state와 `SettingsKeys.gridIconSize` object 값을 같은 `CGFloat`로 갱신한다.
    /// - 사전 조건: Appearance settings는 기본 상태이고 새 크기는 `96.0`이다.
    /// - 기대 결과: state와 저장값 모두 `96.0`이다.
    func testSetGridIconSizePersistsExactKeyValue() async {
        let store = makeStore()

        let newSize: CGFloat = 96.0
        await store.send(.setGridIconSize(newSize)) { state in
            state.gridIconSize = newSize
        }

        XCTAssertEqual(store.state.gridIconSize, newSize)
        let persisted = storage.getObject(SettingsKeys.gridIconSize) as? CGFloat
        XCTAssertEqual(persisted, newSize)
    }

    // MARK: - SET-003-adjust_text_size

    /// SET-003-adjust_text_size: 저장된 list text size가 있으면 Appearance tab 로드 시 해당 값을 표시한다.
    /// list view text slider가 이전 세션에서 저장된 사용자 값을 복원하는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 `SettingsKeys.listTextSize` object 값을 `listTextSize` state로 반영한다.
    /// - 사전 조건: storage에 `CGFloat(15.0)`이 list text size로 저장되어 있다.
    /// - 기대 결과: `store.state.listTextSize = 15.0`이다.
    func testLoadSettingsRestoresListTextSize() async {
        storage.setObject(CGFloat(15.0), forKey: SettingsKeys.listTextSize)
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 listTextSize만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listTextSize, 15.0)
    }

    /// SET-003-adjust_text_size: list text size 저장값이 없으면 Appearance defaults 값을 유지한다.
    /// fresh storage에서 누락된 text preference가 기본 typography 값을 훼손하지 않는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 list text size key 부재 시 기본 state를 보존한다.
    /// - 사전 조건: storage에 `SettingsKeys.listTextSize` 값이 없다.
    /// - 기대 결과: `listTextSize = AppearanceSettingsDefaults.listTextSize`다.
    func testMissingListTextSizePreservesDefault() async {
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 listTextSize 기본값만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.listTextSize, AppearanceSettingsDefaults.listTextSize)
    }

    /// SET-003-adjust_text_size: list text size를 조절하면 exact CGFloat 값을 list_text_size로 저장한다.
    /// list text slider 입력이 사용자 선택값 그대로 persistence에 기록되는지 검증한다.
    /// - 검증 내용: `.setListTextSize`가 state와 `SettingsKeys.listTextSize` object 값을 같은 `CGFloat`로 갱신한다.
    /// - 사전 조건: Appearance settings는 기본 상태이고 새 크기는 `16.0`이다.
    /// - 기대 결과: state와 저장값 모두 `16.0`이다.
    func testSetListTextSizePersistsExactKeyValue() async {
        let store = makeStore()

        let newSize: CGFloat = 16.0
        await store.send(.setListTextSize(newSize)) { state in
            state.listTextSize = newSize
        }

        XCTAssertEqual(store.state.listTextSize, newSize)
        let persisted = storage.getObject(SettingsKeys.listTextSize) as? CGFloat
        XCTAssertEqual(persisted, newSize)
    }

    // MARK: - SET-003-adjust_text_size

    /// SET-003-adjust_text_size: 저장된 grid text size가 있으면 Appearance tab 로드 시 해당 값을 표시한다.
    /// grid view text slider가 이전 세션에서 저장된 사용자 값을 복원하는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 `SettingsKeys.gridTextSize` object 값을 `gridTextSize` state로 반영한다.
    /// - 사전 조건: storage에 `CGFloat(14.0)`이 grid text size로 저장되어 있다.
    /// - 기대 결과: `store.state.gridTextSize = 14.0`이다.
    func testLoadSettingsRestoresGridTextSize() async {
        storage.setObject(CGFloat(14.0), forKey: SettingsKeys.gridTextSize)
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 gridTextSize만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridTextSize, 14.0)
    }

    /// SET-003-adjust_text_size: grid text size 저장값이 없으면 Appearance defaults 값을 유지한다.
    /// fresh storage에서 grid text preference가 누락되어도 기본 typography 값이 보존되는지 검증한다.
    /// - 검증 내용: `.loadSettings`가 grid text size key 부재 시 기본 state를 보존한다.
    /// - 사전 조건: storage에 `SettingsKeys.gridTextSize` 값이 없다.
    /// - 기대 결과: `gridTextSize = AppearanceSettingsDefaults.gridTextSize`다.
    func testMissingGridTextSizePreservesDefault() async {
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 gridTextSize 기본값만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertEqual(store.state.gridTextSize, AppearanceSettingsDefaults.gridTextSize)
    }

    /// SET-003-adjust_text_size: grid text size를 조절하면 exact CGFloat 값을 grid_text_size로 저장한다.
    /// grid text slider 입력이 list text key와 독립된 persistence key에 정확히 저장되는지 검증한다.
    /// - 검증 내용: `.setGridTextSize`가 state와 `SettingsKeys.gridTextSize` object 값을 같은 `CGFloat`로 갱신한다.
    /// - 사전 조건: Appearance settings는 기본 상태이고 새 크기는 `14.0`이다.
    /// - 기대 결과: state와 저장값 모두 `14.0`이다.
    func testSetGridTextSizePersistsExactKeyValue() async {
        let store = makeStore()

        let newSize: CGFloat = 14.0
        await store.send(.setGridTextSize(newSize)) { state in
            state.gridTextSize = newSize
        }

        XCTAssertEqual(store.state.gridTextSize, newSize)
        let persisted = storage.getObject(SettingsKeys.gridTextSize) as? CGFloat
        XCTAssertEqual(persisted, newSize)
    }

    // MARK: - SET-003-show_hidden_files

    /// supplemental current behavior — showHiddenFiles
    /// SET-003-show_hidden_files: hidden files 표시 저장값이 Appearance tab 로드 시 복원된다.
    /// canonical interaction_id는 없지만 현재 Appearance flow가 소유한 표시 preference의 load 계약을 검증한다.
    /// - 검증 내용: `.loadSettings`가 `SettingsKeys.showHiddenFiles` bool 값을 `showHiddenFiles` state로 반영한다.
    /// - 사전 조건: storage에 `showHiddenFiles = true`가 저장되어 있다.
    /// - 기대 결과: `store.state.showHiddenFiles = true`다.
    func testLoadSettingsRestoresShowHiddenFiles() async {
        storage.setBool(true, forKey: SettingsKeys.showHiddenFiles)
        let store = makeStore()
        // store.exhaustivity = .off: loadSettings 다중 필드 갱신 중 showHiddenFiles만 검증
        store.exhaustivity = .off

        await store.send(.loadSettings)

        XCTAssertTrue(store.state.showHiddenFiles)
    }

    /// SET-003 supplemental current behavior: hidden files 표시를 켜면 state와 storage에 true를 저장한다.
    /// 사용자가 숨김 파일 표시를 활성화한 선택이 즉시 UI state와 persistence에 반영되는지 검증한다.
    /// - 검증 내용: `.setShowHiddenFiles(true)`가 state와 `SettingsKeys.showHiddenFiles` 저장값을 true로 갱신한다.
    /// - 사전 조건: Appearance settings는 기본 off 상태이며 storage에는 기존 값이 없다.
    /// - 기대 결과: `showHiddenFiles = true`이고 저장값도 `true`다.
    func testSetShowHiddenFilesEnabled() async {
        let store = makeStore()

        await store.send(.setShowHiddenFiles(true)) { state in
            state.showHiddenFiles = true
        }

        XCTAssertTrue(store.state.showHiddenFiles)
        XCTAssertTrue(storage.getBool(SettingsKeys.showHiddenFiles) ?? false)
    }

    /// SET-003 supplemental current behavior: hidden files 표시를 끄면 state와 storage에 false를 저장한다.
    /// 이전에 켜져 있던 숨김 파일 표시 preference를 명시적으로 비활성화할 수 있는지 검증한다.
    /// - 검증 내용: `.setShowHiddenFiles(false)`가 state와 `SettingsKeys.showHiddenFiles` 저장값을 false로 갱신한다.
    /// - 사전 조건: storage에는 `showHiddenFiles = true`가 저장되어 있다.
    /// - 기대 결과: `showHiddenFiles = false`이고 저장값도 `false`다.
    func testSetShowHiddenFilesDisabled() async {
        storage.setBool(true, forKey: SettingsKeys.showHiddenFiles)
        let store = makeStore()
        // store.exhaustivity = .off: 초기값(false)과 설정값(false)이 같아 상태 변화 없음, storage 갱신만 검증
        store.exhaustivity = .off

        await store.send(.setShowHiddenFiles(false)) { state in
            state.showHiddenFiles = false
        }

        XCTAssertFalse(store.state.showHiddenFiles)
        XCTAssertFalse(storage.getBool(SettingsKeys.showHiddenFiles) ?? true)
    }
}

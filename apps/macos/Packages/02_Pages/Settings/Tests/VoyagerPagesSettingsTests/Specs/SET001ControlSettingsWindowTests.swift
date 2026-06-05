import ComposableArchitecture
@testable import VoyagerPagesSettings
import XCTest

/*
 SET-001-control_settings_window 증거 계약

 포함한 interaction_id:
 - SET-001-open_settings_window: 집중 자동화 테스트
   `testOpenSettingsWindowOnAppearLoadsGeneralAndAppearance`
 - SET-001-switch_setting_tabs: 집중 자동화 테스트
   `testSwitchSettingTabsPreservesChildState`
 - SET-001-close_settings_window: 수동 QA + 상태 계약 자동화
   AppKit close side effect는 headless/CI에서 비결정적이므로 수동 QA로 남기고,
   fresh reopen 기준 section 초기화는 `testResetSectionForFreshOpenReturnsToGeneralWithoutClearingChildState`로 검증한다.

 Fixture reset:
 - 메모리 기반 `TestStore`만 사용하므로 영구 UserDefaults 상태가 필요 없다.

 미지원 surface 분류:
 - Permissions: follow-up/manual QA. 구현이 Settings가 아니라 Onboarding에 있다.
 - SET-005 Shortcuts: 수동 QA. 문서 전용 항목이며 앱은 정적 메뉴 명령을 사용한다.
 - SET-007 AI Connections: 외부 프로젝트 dependency.
 - Account/License: 외부 프로젝트 dependency.
 */

@MainActor
final class SET001ControlSettingsWindowTests: XCTestCase {
    /// SET-001-open_settings_window: Settings window가 표시될 때 General/Appearance section load action을 라우팅한다.
    /// Settings root가 처음 나타나는 시점에 두 하위 section의 현재 설정을 로드할 준비가 되는지 검증한다.
    /// - 검증 내용: `.onAppear`가 `general.loadSettings`와 `appearance.loadSettings`를 순서대로 방출한다.
    /// - 사전 조건: Settings root 상태는 기본 section과 기본 child state로 시작한다.
    /// - 기대 결과: General은 시작 디렉터리 `/`, Appearance는 `.system` theme 상태로 로드된다.
    func testOpenSettingsWindowOnAppearLoadsGeneralAndAppearance() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.launchAtLoginClient = .testValue
            $0.directorySelectionClient = .testValue
            $0.appearanceSettingsClient = .testValue
        }
        // store.exhaustivity = .off: loadSettings가 다수 필드를 동시 갱신하나 검증 대상은 일부 필드만 해당
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.general.loadSettings) { state in
            state.generalSettings.startingDirectory = "/"
        }
        await store.receive(\.appearance.loadSettings) { state in
            state.appearanceSettings.theme = .system
        }
    }

    /// SET-001-switch_setting_tabs: General/Appearance section 전환은 현재 선택 section만 바꾸고 child state를 보존한다.
    /// 사용자가 tab을 바꿔도 이미 로드되거나 수정된 General 설정값이 손실되지 않는지 검증한다.
    /// - 검증 내용: `.selectSection(.appearance)`와 `.selectSection(.general)`이 root 선택 상태만 변경한다.
    /// - 사전 조건: General section의 `startingDirectory`에 보존되어야 하는 테스트 경로가 들어 있다.
    /// - 기대 결과: section 전환 후에도 `generalSettings.startingDirectory`가 `/test/preserved`로 유지된다.
    func testSwitchSettingTabsPreservesChildState() async {
        var initialState = SettingsFeature.State()
        initialState.generalSettings.startingDirectory = "/test/preserved"
        initialState.selectedSection = .general

        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        }

        await store.send(.selectSection(.appearance)) { state in
            state.selectedSection = .appearance
        }

        XCTAssertEqual(store.state.generalSettings.startingDirectory, "/test/preserved")
        XCTAssertEqual(store.state.selectedSection, .appearance)

        await store.send(.selectSection(.general)) { state in
            state.selectedSection = .general
        }

        XCTAssertEqual(store.state.generalSettings.startingDirectory, "/test/preserved")
    }

    /// SET-001-close_settings_window: Settings를 닫으면 다음 fresh reopen은 General section에서 시작한다.
    /// AppKit window close side effect 자체는 수동 QA로 남기되, persisted root state에 마지막 탭이 남지 않는 계약을 검증한다.
    /// - 검증 내용: `.resetSectionForFreshOpen`이 선택 section만 `.general`로 초기화하고 child state를 보존한다.
    /// - 사전 조건: Appearance section이 선택되어 있고 General child state에는 저장된 테스트 경로가 들어 있다.
    /// - 기대 결과: 다음 Settings fresh reopen의 기준 section은 General이며 저장된 설정값은 유지된다.
    func testResetSectionForFreshOpenReturnsToGeneralWithoutClearingChildState() async {
        var initialState = SettingsFeature.State()
        initialState.selectedSection = .appearance
        initialState.generalSettings.startingDirectory = "/test/preserved"

        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        }

        await store.send(.resetSectionForFreshOpen) { state in
            state.selectedSection = .general
        }

        XCTAssertEqual(store.state.generalSettings.startingDirectory, "/test/preserved")
    }

    // SET-001-close_settings_window: 닫기 control/⌘W는 현재 Settings window를 닫는 AppKit lifecycle 경로다.
    // AppKit side effect 자체는 `NSApp.keyWindow?.close()`에 의존하므로 수동 QA로 남긴다.
    // - 검증 내용: 실제 앱 런타임에서 close control/⌘W가 현재 Settings window를 닫는지 확인한다.
    // - 사전 조건: 실제 앱 런타임에서 Settings window가 key window로 열린 상태여야 한다.
    // - 기대 결과: 닫기 control 또는 ⌘W 입력 후 현재 Settings window가 닫히고 다음 fresh reopen은 General로 시작한다.
}

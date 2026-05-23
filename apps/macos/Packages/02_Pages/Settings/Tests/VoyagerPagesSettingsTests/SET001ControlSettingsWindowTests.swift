import ComposableArchitecture
@testable import VoyagerPagesSettings
import XCTest

// MARK: - SET-001-control_settings_window — 증거 계약

// 포함한 interaction_id:
//   SET-001-open_settings_window → 집중 자동화 테스트 (testOpenSettingsWindowOnAppearLoadsGeneralAndAppearance)
//   SET-001-close_settings_window → 수동 QA (NSApp.keyWindow?.close()는 headless/CI 환경에서 비결정적임)
//   SET-001-switch_setting_tabs → 집중 자동화 테스트 (testSwitchSettingTabsPreservesChildState)
// fixture reset: 메모리 기반 TestStore만 사용하며 영구 UserDefaults 상태가 필요 없다.
// 분류: 집중 자동화 테스트 + 수동 QA(NSApp 의존성)
//
// 미지원 surface 분류:
//   - Permissions: follow-up/manual QA (구현이 Settings가 아니라 Onboarding에 있음)
//   - SET-005 Shortcuts: 수동 QA (문서 전용 항목이며 앱은 정적 메뉴 명령을 사용함)
//   - SET-007 AI Connections: 외부 프로젝트 dependency
//     (https://linear.app/voyager-fm/project/byok구독-계정-연결-기반-ai-채팅-기능-도입-453bf1118aec)
//   - Account/License: 외부 프로젝트 dependency
//     (https://linear.app/voyager-fm/project/dollar5-core-license-결제권한앱-unlock-실험-21b8e66140e2)

@MainActor
final class SET001ControlSettingsWindowTests: XCTestCase {
    // SET-001-open_settings_window — AC: Settings window 표시 시 [now] General/Appearance toolbar/body 진입에 필요한 section 로드가
    // 수행되는지 검증한다.
    func testOpenSettingsWindowOnAppearLoadsGeneralAndAppearance() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.launchAtLoginClient = .testValue
            $0.directorySelectionClient = .testValue
            $0.appearanceSettingsClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.general.loadSettings) { state in
            state.generalSettings.startingDirectory = "/"
        }
        await store.receive(\.appearance.loadSettings) { state in
            state.appearanceSettings.theme = .system
        }
    }

    // SET-001-switch_setting_tabs — AC: [now] General/Appearance section 전환 시 선택 상태가 바뀌고 이전 section 저장값은 초기화되지 않는지
    // 검증한다.
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

    // SET-001-close_settings_window — AC: 닫기 control/⌘W로 현재 Settings window를 닫는 경로는 AppKit window lifecycle에 의존하므로 수동
    // QA로 분류한다.
    // .closeWindow는 .run effect에서 NSApp.keyWindow?.close()를 호출하며,
    // headless 테스트 환경에서는 NSApp 접근이 비결정적이어서 자동화하지 않는다.
}

// FLOW-ID: set.settings_window
import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesSettings
import XCTest

@MainActor
final class SettingsWindowFlowTests: XCTestCase {
    // 네이티브 Settings scene open/reopen은 AppKit 외부 수동 검증 경계다.
    // 이 suite는 reducer가 소유하는 section 및 저장 상태만 자동화한다.

    // FLOW-PATH: happy_path.open_and_switch

    /// SET-001-open_settings_window: 기본 Settings 진입은 General에서 시작하고 현재 지원 section으로 전환한다.
    /// 사용자가 열린 Settings 창에서 section을 전환해도 reducer가 선택 상태를 결정적으로 바꾸는지 검증한다.
    /// - 검증 내용: `.selectSection`이 visible section을 반영하고 dormant Account 요청은 General로 정규화한다.
    /// - 사전 조건: 기본 `SettingsFeature.State`는 General section에서 시작한다.
    /// - 기대 결과: visible section은 요청대로 선택되고 Account 요청은 General로 정규화된다.
    func testSettingsEntryDefaultsToGeneralAndAllowsSectionSwitching() async {
        XCTAssertEqual(SettingsSection.visibleCases, [.general, .appearance, .ai])

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        XCTAssertEqual(store.state.selectedSection, .general)

        await store.send(.selectSection(.appearance)) {
            $0.selectedSection = .appearance
        }
        await store.send(.selectSection(.ai)) {
            $0.selectedSection = .ai
        }
        await store.send(.selectSection(.account)) {
            $0.selectedSection = .general
        }
        await store.send(.selectSection(.general))
    }

    // FLOW-PATH: ai_settings_deep_link

    /// SET-001-switch_setting_tabs: AppRoot의 AI deep link는 optional account 상태와 무관하게 AI section을 선택한다.
    /// Free Plan runtime에서 open-AI command가 기존 Settings 값을 보존하면서 AI section으로 라우팅하는지 검증한다.
    /// - 검증 내용: `.openAISettings`가 `.settings.selectSection(.ai)`를 보내고 저장된 General/Appearance 값을 유지한다.
    /// - 사전 조건: Settings는 Appearance section과 저장된 directory 및 theme 값을 가진다.
    /// - 기대 결과: AI section을 선택하며 기존 설정값은 바뀌지 않는다.
    func testOpenAISettingsSelectsAIWithoutAccessGate() async {
        var initialState = AppRootFeature.State()
        initialState.settings.selectedSection = .appearance
        initialState.settings.generalSettings.startingDirectory = "/flow/preserved"
        initialState.settings.appearanceSettings.theme = .dark
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: AppRoot native scene effect의 내부 순서 대신 AI section routing 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.openAISettings)
        await store.receive(\.settings.selectSection) {
            $0.settings.selectedSection = .ai
        }
        await store.finish()

        XCTAssertEqual(store.state.settings.selectedSection, .ai)
        XCTAssertEqual(store.state.settings.generalSettings.startingDirectory, "/flow/preserved")
        XCTAssertEqual(store.state.settings.appearanceSettings.theme, .dark)
    }

    // FLOW-PATH: reopen_existing

    /// SET-001-open_settings_window: 이미 열린 Settings surface를 다시 요청해도 현재 section과 저장된 값은 유지한다.
    /// 기존 window의 native reopen은 수동 경계로 두고 reducer가 보존하는 상태를 검증한다.
    /// - 검증 내용: `.selectSection` 뒤 existing surface state는 selected section과 General/Appearance 저장값을 유지한다.
    /// - 사전 조건: Settings는 Appearance section과 저장된 directory 및 theme 값을 가진다.
    /// - 기대 결과: AI section으로 전환한 뒤에도 두 저장값은 바뀌지 않는다.
    func testReopenExistingSettingsPreservesCurrentSectionAndValues() async {
        var initialState = SettingsFeature.State(appearanceTheme: .dark)
        initialState.selectedSection = .appearance
        initialState.generalSettings.startingDirectory = "/flow/preserved"
        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        }

        await store.send(.selectSection(.ai)) {
            $0.selectedSection = .ai
        }

        XCTAssertEqual(store.state.selectedSection, .ai)
        XCTAssertEqual(store.state.generalSettings.startingDirectory, "/flow/preserved")
        XCTAssertEqual(store.state.appearanceSettings.theme, .dark)
    }

    // FLOW-PATH: fresh_reopen

    /// SET-001-close_settings_window: 닫은 뒤 fresh reopen은 section만 General로 재설정하고 저장된 값은 유지한다.
    /// AppKit close 및 native scene reopen 가시성은 외부 수동 검증 경계로 두고 reducer state 계약만 자동화한다.
    /// - 검증 내용: `.closeWindow`와 `.resetSectionForFreshOpen`이 selectedSection만 General로 설정한다.
    /// - 사전 조건: AI 또는 Account section이 선택되어 있고 General directory 및 Appearance theme 값이 저장되어 있다.
    /// - 기대 결과: close/fresh reopen 뒤 General section이며 두 저장값은 초기화되지 않는다.
    func testFreshReopenResetsSectionWithoutResettingPersistedValues() async {
        var closedState = SettingsFeature.State(appearanceTheme: .dark)
        closedState.selectedSection = .ai
        closedState.generalSettings.startingDirectory = "/flow/preserved"
        let closedStore = TestStore(initialState: closedState) {
            SettingsFeature()
        }

        await closedStore.send(.closeWindow) {
            $0.selectedSection = .general
        }
        await closedStore.finish()

        XCTAssertEqual(closedStore.state.selectedSection, .general)
        XCTAssertEqual(closedStore.state.generalSettings.startingDirectory, "/flow/preserved")
        XCTAssertEqual(closedStore.state.appearanceSettings.theme, .dark)

        var freshState = SettingsFeature.State(appearanceTheme: .dark)
        freshState.selectedSection = .account
        freshState.generalSettings.startingDirectory = "/flow/preserved"
        let freshStore = TestStore(initialState: freshState) {
            SettingsFeature()
        }

        await freshStore.send(.resetSectionForFreshOpen) {
            $0.selectedSection = .general
        }

        XCTAssertEqual(freshStore.state.generalSettings.startingDirectory, "/flow/preserved")
        XCTAssertEqual(freshStore.state.appearanceSettings.theme, .dark)
    }
}

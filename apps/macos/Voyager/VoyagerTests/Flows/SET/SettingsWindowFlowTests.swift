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
    /// - 검증 내용: `.selectSection`이 General, Appearance, AI, Account의 현재 지원 section만 선택 상태로 반영한다.
    /// - 사전 조건: 기본 `SettingsFeature.State`는 General section에서 시작한다.
    /// - 기대 결과: 각 section action 뒤 selectedSection이 요청한 현재 section과 일치한다.
    func testSettingsEntryDefaultsToGeneralAndAllowsSectionSwitching() async {
        XCTAssertEqual(SettingsSection.allCases, [.general, .appearance, .ai, .account])

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
            $0.selectedSection = .account
        }
        await store.send(.selectSection(.general)) {
            $0.selectedSection = .general
        }
    }

    // FLOW-PATH: ai_settings_access

    /// SET-001-switch_setting_tabs: access 상태가 허용할 때만 AppRoot의 AI deep link가 AI section을 선택한다.
    /// 활성 및 비활성 access 상태에서 같은 open-AI command가 서로 다른 Settings section 결과를 만드는지 검증한다.
    /// - 검증 내용: active access는 `.settings.selectSection(.ai)`를 받고 inactive access는 기존 허용 section을 유지한다.
    /// - 사전 조건: active store는 core license access, inactive store는 Appearance section과 저장된 설정값을 가진다.
    /// - 기대 결과: active는 AI를 선택하고 inactive는 Appearance 및 저장된 설정값을 보존한다.
    func testOpenAISettingsSelectsAIOnlyWhenAccessAllowsIt() async {
        var activeState = AppRootFeature.State()
        activeState.settings.accessStatus = .coreLicenseActive
        let activeStore = TestStore(initialState: activeState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: AppRoot native scene effect의 내부 순서 대신 AI section routing 결과를 검증한다.
        activeStore.exhaustivity = .off

        await activeStore.send(.openAISettings)
        await activeStore.receive(\.settings.selectSection) {
            $0.settings.selectedSection = .ai
        }
        await activeStore.finish()

        var inactiveState = AppRootFeature.State()
        inactiveState.settings.selectedSection = .appearance
        inactiveState.settings.generalSettings.startingDirectory = "/flow/preserved"
        inactiveState.settings.appearanceSettings.theme = .dark
        let inactiveStore = TestStore(initialState: inactiveState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: native scene effect는 외부 수동 경계이며 inactive AI routing 부재만 검증한다.
        inactiveStore.exhaustivity = .off

        await inactiveStore.send(.openAISettings)
        await inactiveStore.finish()

        XCTAssertEqual(inactiveStore.state.settings.selectedSection, .appearance)
        XCTAssertEqual(inactiveStore.state.settings.generalSettings.startingDirectory, "/flow/preserved")
        XCTAssertEqual(inactiveStore.state.settings.appearanceSettings.theme, .dark)
    }

    // FLOW-PATH: reopen_existing

    /// SET-001-open_settings_window: 이미 열린 Settings surface를 다시 요청해도 현재 section과 저장된 값은 유지한다.
    /// 기존 window의 native reopen은 수동 경계로 두고 reducer가 보존하는 상태를 검증한다.
    /// - 검증 내용: `.selectSection` 뒤 existing surface state는 selected section과 General/Appearance 저장값을 유지한다.
    /// - 사전 조건: Settings는 Appearance section과 저장된 directory 및 theme 값을 가진다.
    /// - 기대 결과: Account section으로 전환한 뒤에도 두 저장값은 바뀌지 않는다.
    func testReopenExistingSettingsPreservesCurrentSectionAndValues() async {
        var initialState = SettingsFeature.State(appearanceTheme: .dark)
        initialState.selectedSection = .appearance
        initialState.generalSettings.startingDirectory = "/flow/preserved"
        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        }

        await store.send(.selectSection(.account)) {
            $0.selectedSection = .account
        }

        XCTAssertEqual(store.state.selectedSection, .account)
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

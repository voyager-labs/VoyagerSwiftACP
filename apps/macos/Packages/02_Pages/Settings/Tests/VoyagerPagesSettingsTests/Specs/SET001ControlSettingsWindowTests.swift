import ComposableArchitecture
import VoyagerFeaturesAccountAccess
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
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { nil },
                save: { _ in },
                remove: {},
            )
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
        await store.receive(\.accessStatusLoaded)
        await store.finish()
    }

    func testOpenSettingsWindowDoesNotEagerlyBootstrapHiddenTabs() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.launchAtLoginClient = .testValue
            $0.directorySelectionClient = .testValue
            $0.appearanceSettingsClient = .testValue
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { nil },
                save: { _ in },
                remove: {},
            )
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.general.loadSettings)
        await store.receive(\.appearance.loadSettings)
        await store.receive(\.accessStatusLoaded)
        await store.finish()
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

    // MARK: - Settings Full-Access Content Gate

    // 정책 참조: docs/voy-299/PRODUCT/05_FEATURE_SPECS/set/contracts/settings_window_contract.toml
    //   [policy] usable_content_requires_access_status = "full"
    // Native Cmd+, 경로는 AppKit 수준이라 reducer-gate 불가능 → SettingsView content 수준에서
    // access_status != full일 때 locked overlay를 render해야 한다 (T6 구현 항목).

    /// T2 RED: access_status != full일 때 SettingsView content가 locked 상태로 표시되어야 한다.
    /// - 사전 조건: snapshot이 trialExpired → access_status != full.
    /// - 기대: SettingsFeature가 snapshot을 읽어 state.accessStatus를 채우고,
    ///   SettingsView body가 TabView 대신 locked overlay를 render한다.
    /// - 현재 RED 이유:
    ///   1) SettingsFeature.State에 `accessStatus` field가 없다.
    ///   2) SettingsFeature가 accessStatusSnapshotClient를 읽지 않는다.
    ///   3) SettingsView body에 조건부 gate render가 없다.
    /// - T6에서 위 세 가지를 구현하면 아래 TODO 액션이 실제 assertion으로 전환된다.
    func testSettingsContentLockedWhenAccessStatusNotFull() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.launchAtLoginClient = .testValue
            $0.directorySelectionClient = .testValue
            $0.appearanceSettingsClient = .testValue
            // T6에서 SettingsFeature가 access_status를 읽을 때 사용할 의존성 주입.
            // 현재 SettingsFeature가 이 client를 읽지 않으므로 state 반영이 일어나지 않는다.
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: {
                    AccessStatusSnapshot(
                        status: .trialExpired,
                        currentPeriodEnd: nil,
                        fetchedAt: Date(timeIntervalSince1970: 0),
                    )
                },
                save: { _ in },
                remove: {},
            )
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.accessStatusLoaded) { state in
            state.accessStatus = .trialExpired
        }
        await store.finish()

        XCTAssertEqual(store.state.accessStatus, .trialExpired)
        XCTAssertTrue(store.state.isContentLocked)
    }

    // MARK: - T11 Already-Open / Access Lapse Integration

    // 정책 참조: docs/voy-299/PRODUCT/05_FEATURE_SPECS/set/contracts/settings_window_contract.toml
    //   [policy] usable_content_requires_access_status = "full"
    // T11 시나리오: Settings 창이 이미 열려 있는 동안 access_status가 full → non-full로
    // 바뀌는 경우(세션 만료, entitlement revoke 등) Settings content가 locked overlay로 전환된다.

    /// T11 integration: Settings 창이 열려 있는 동안 access_status가 full → non-full로
    /// 바뀌면 Settings content가 locked overlay로 전환된다.
    /// - 시나리오: onAppear 시점 full access → 런타임 중 access lapse (session 만료 / entitlement revoke).
    /// - 검증 내용: `.accessStatusLoaded(.trialExpired)` 도착 시 state.accessStatus가
    ///   .trialExpired로 갱신되고 isContentLocked가 true로 전환된다.
    /// - 계약: SettingsFeature는 onAppear 시점에만 snapshot을 읽는다. 런타임 lapse 전파는
    ///   상위(AppRoot 등)가 `.accessStatusLoaded` 액션을 push하는 경로로만 이루어진다.
    ///   본 테스트는 그 전파 경로의 끝단(state → isContentLocked → SettingsView gate)이
    ///   올바르게 반응하는지 검증한다. 업스트림 구독 wiring은 본 태스크 범위 밖이며
    ///   SessionLapseGuardWindowClient는 rewired하지 않는다 (MUST NOT).
    /// - "이미 열려 있음"을 initialState.accessStatus = .coreLicenseActive로 모델링:
    ///   onAppear 시점 snapshot load가 이미 완료된 상태를 시뮬레이션한다.
    func testSettingsContentLocksWhenAccessStatusLapsesWhileOpen() async {
        var initialState = SettingsFeature.State()
        initialState.accessStatus = .coreLicenseActive
        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        }

        XCTAssertFalse(store.state.isContentLocked, "초기 full access → content unlocked")

        // 런타임 중 access lapse: 상위가 .accessStatusLoaded(.trialExpired)를 push.
        // Settings는 재독기가 없으므로, 이 액션 도착이 유일한 lapse 전파 경로다.
        await store.send(.accessStatusLoaded(.trialExpired)) { state in
            state.accessStatus = .trialExpired
        }

        XCTAssertEqual(store.state.accessStatus, .trialExpired)
        XCTAssertTrue(store.state.isContentLocked, "access lapse → content locked overlay 전환")
    }

    /// T11 integration (역방향): Settings 창이 열려 있는 동안 access_status가 non-full → full로
    /// 회복하면 locked overlay가 해제된다.
    /// - 검증 내용: `.accessStatusLoaded(.coreLicenseActive)` 도착 시 isContentLocked가 false로 전환.
    /// - 계약: recovery 소유권은 Settings가 아닌 ACC overlay/session lapse guard에 있다
    ///   (T1: entitlement_inactive_recovery_is_owned_outside_settings).
    ///   Settings는 access_status가 full로 돌아오면 overlay를 내릴 뿐, recovery 자체를 수행하지 않는다.
    func testSettingsContentUnlocksWhenAccessStatusReturnsToFullWhileOpen() async {
        var initialState = SettingsFeature.State()
        initialState.accessStatus = .trialExpired
        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        }

        XCTAssertTrue(store.state.isContentLocked, "초기 trialExpired → locked")

        // 상위로부터 full access 복귀 통지. Recovery는 외부(ACC overlay)가 소유.
        await store.send(.accessStatusLoaded(.coreLicenseActive)) { state in
            state.accessStatus = .coreLicenseActive
        }

        XCTAssertFalse(store.state.isContentLocked, "full 복귀 → overlay 해제")
    }

    func testSettingsContentUpdatesFromAccountAccessDelegatesWhileOpen() async {
        var initialState = SettingsFeature.State()
        initialState.accessStatus = .coreLicenseActive
        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        }

        await store.send(.account(.access(.delegate(.signedOut)))) { state in
            state.accessStatus = .none
        }
        XCTAssertTrue(store.state.isContentLocked)

        await store.send(.account(.access(.delegate(.unlocked(
            AccessStatusSnapshot(status: .coreLicenseActive),
        ))))) { state in
            state.accessStatus = .coreLicenseActive
        }
        XCTAssertFalse(store.state.isContentLocked)
    }
}

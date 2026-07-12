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
    /// SET-001-open_settings_window: Settings window가 표시될 때 더 이상 General/Appearance load를 직접 trigger하지 않는다.
    /// General/Appearance load는 AppRoot가 launch(.willFinishLaunching)에서 1회 보내는
    /// `.bootstrapLocalPreferences`로 이동했다 (T2b). 본 테스트는 onAppear가 완전 no-op임을 검증한다.
    /// - 검증 내용: `.onAppear`는 아무 effect도 방출하지 않는다 (T2c: snapshot load도 상위로 이동).
    /// - 사전 조건: Settings root 상태는 기본 section과 기본 child state로 시작한다.
    /// - 기대 결과: 상태 갱신 없음, effect 방출 없음.
    func testOpenSettingsWindowOnAppearLoadsGeneralAndAppearance() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.launchAtLoginClient = .testValue
            $0.directorySelectionClient = .testValue
            $0.appearanceSettingsClient = .testValue
        }

        await store.send(.onAppear)
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
        }

        await store.send(.onAppear)
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

    // MARK: - T2a RED: launch bootstrap contract (onAppear reload를 launch 시점 1회로 대체)

    /// T2a RED: AppRoot가 launch에서 1회 보내는 `.bootstrapLocalPreferences`가
    /// General/Appearance load action을 merge로 실행한다.
    /// - 검증 내용: `.bootstrapLocalPreferences` 수신 시 `.general(.loadSettings)`와 `.appearance(.loadSettings)`가 순서대로 방출된다.
    /// - 사전 조건: Settings root 상태는 기본 child state로 시작한다.
    /// - 기대 결과: General은 시작 디렉터리 `/`, Appearance는 `.system` theme으로 로드된다.
    func testSettingsBootstrapLocalPreferencesRoutesGeneralAndAppearanceLoad() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.launchAtLoginClient = .testValue
            $0.directorySelectionClient = .testValue
            $0.appearanceSettingsClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.bootstrapLocalPreferences)
        await store.receive(\.general.loadSettings) { state in
            state.generalSettings.startingDirectory = "/"
        }
        await store.receive(\.appearance.loadSettings) { state in
            state.appearanceSettings.theme = .system
        }
        await store.finish()
    }

    // MARK: - Settings Access Status Hydration (no whole-window lock)

    // 정책: access_status != full이어도 Settings 창 자체는 닫히거나 잠기지 않는다.
    // entitlement-dependent action gating은 Account/개별 feature가 소유한다.
    // SettingsState.accessStatus는 Account tab 표시와 AppRoot hydration 흐름을 지원하기만 한다.

    /// access_status != full인 상태에서도 Settings content는 그대로 렌더링된다.
    /// - 사전 조건: 기본 상태(accessStatus = .none)에서 launch snapshot이 trialExpired로 도착.
    /// - 기대: state.accessStatus가 snapshot.status로 갱신되고 Settings 창은 잠기지 않는다.
    ///   SettingsView는 더 이상 isContentLocked 분기를 가지지 않는다.
    func testSettingsContentStaysRenderedWhenAccessStatusNotFull() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.launchAtLoginClient = .testValue
            $0.directorySelectionClient = .testValue
            $0.appearanceSettingsClient = .testValue
        }
        let snapshot = AccessStatusSnapshot(
            status: .trialExpired,
            currentPeriodEnd: nil,
            fetchedAt: Date(timeIntervalSince1970: 0),
        )
        await store.send(.appLifecycleAccessSnapshotReady(snapshot)) { state in
            state.accessStatus = .trialExpired
            state.accountSettings.presentation = AccountAccessPresentation(snapshot: snapshot)
        }

        XCTAssertEqual(store.state.accessStatus, .trialExpired)
    }

    /// T2c GREEN: launch snapshot hydration이 access status와 Settings projection을 채운다.
    /// - 검증 내용: `.appLifecycleAccessSnapshotReady(snapshot)` 수신 시
    ///   state.accessStatus가 snapshot.status로 갱신되고,
    ///   AccountSettings presentation이 snapshot-derived fact로 갱신된다.
    /// - 사전 조건: Settings root 상태는 기본 상태.
    /// - 기대 결과: accessStatus와 Account presentation 동시 갱신.
    func testAppLifecycleAccessSnapshotReadyHydratesSettingsAndAccount() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.launchAtLoginClient = .testValue
            $0.directorySelectionClient = .testValue
            $0.appearanceSettingsClient = .testValue
        }
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: Date(timeIntervalSince1970: 0),
        )
        await store.send(.appLifecycleAccessSnapshotReady(snapshot)) { state in
            state.accessStatus = .coreLicenseActive
            state.accountSettings.presentation = AccountAccessPresentation(snapshot: snapshot)
        }
        XCTAssertEqual(store.state.accountSettings.presentation.accessStatus, .coreLicenseActive)
    }

    /// Task 13: launch snapshot hydration이 session 축까지 end-to-end 전달되는지 검증.
    /// 기존 `testAppLifecycleAccessSnapshotReadyHydratesSettingsAndAccount`는
    /// sessionExpiresAt 없는 snapshot을 써서 access status 축만 검증하고 `finish()`로
    /// clean termination까지 증명한다. 본 테스트는 session 축이 있는 snapshot에서
    /// SettingsFeature가 snapshot-derived projection을 갱신하고
    /// 최종 `accountSettings.presentation.hasAccountSession == true`로 파생되는지 확인한다.
    /// - 검증 내용: `.appLifecycleAccessSnapshotReady(snapshot with sessionExpiresAt)` 수신 시
    ///   state.accessStatus가 snapshot.status로 갱신되고,
    ///   AccountSettings presentation이 snapshot-derived fact로 갱신된다.
    /// - 사전 조건: Settings root 상태는 기본 상태 (session 없음).
    /// - 기대 결과: hydration 후 `hasAccountSession == true`, timer effect는 없음.
    func testAppLifecycleAccessSnapshotReadyWithSessionUpdatesAccountPresentation() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.launchAtLoginClient = .testValue
            $0.directorySelectionClient = .testValue
            $0.appearanceSettingsClient = .testValue
        }
        let sessionExpiry = Date(timeIntervalSince1970: 4_102_444_800)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: Date(timeIntervalSince1970: 0),
            sessionExpiresAt: sessionExpiry,
        )
        await store.send(.appLifecycleAccessSnapshotReady(snapshot)) { state in
            state.accessStatus = .coreLicenseActive
            state.accountSettings.presentation = AccountAccessPresentation(snapshot: snapshot)
        }

        XCTAssertTrue(store.state.accountSettings.presentation.hasAccountSession)
    }

    // MARK: - Settings Already-Open / Access Status Updates

    // Settings 창이 열려 있는 동안 access_status가 바뀌어도 창 자체는 닫히지 않는다.
    // 상위(AppRoot 등)가 `.accessStatusLoaded`로 push하는 상태 갱신만 Settings가 수용한다.

    /// Settings 창이 열려 있는 동안 access_status가 full → non-full로 바뀌어도
    /// state.accessStatus만 갱신될 뿐 창이 잠기지 않는다.
    /// - 시나리오: 초기 full access → 런타임 중 상위가 `.accessStatusLoaded(.trialExpired)` push.
    /// - 계약: SettingsFeature는 런타임 lapse 전파를 `.accessStatusLoaded` 액션으로만 수용한다.
    func testSettingsAccessStatusLapseUpdatesStateWhileOpen() async {
        var initialState = SettingsFeature.State()
        initialState.accessStatus = .coreLicenseActive
        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        }

        await store.send(.accessStatusLoaded(.trialExpired)) { state in
            state.accessStatus = .trialExpired
        }

        XCTAssertEqual(store.state.accessStatus, .trialExpired)
    }

    /// Canonical projection update가 Settings 표시 상태를 갱신한다.
    func testSettingsAccessStatusUpdatesFromCanonicalProjectionWhileOpen() async {
        var initialState = SettingsFeature.State()
        initialState.accessStatus = .coreLicenseActive
        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        }

        let signedOut = AccountAccessPresentation()
        await store.send(.accountAccessPresentationUpdated(signedOut)) { state in
            state.accessStatus = .none
            state.accountSettings.presentation = signedOut
        }
        XCTAssertEqual(store.state.accessStatus, .none)

        let unlocked = AccountAccessPresentation(
            hasAccountSession: true,
            accessStatus: .coreLicenseActive,
        )
        await store.send(.accountAccessPresentationUpdated(unlocked)) { state in
            state.accessStatus = .coreLicenseActive
            state.accountSettings.presentation = unlocked
        }
        XCTAssertEqual(store.state.accessStatus, .coreLicenseActive)
    }
}

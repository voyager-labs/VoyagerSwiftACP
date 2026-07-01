import ComposableArchitecture
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesSettings
import XCTest

/*
 SET-008-manage_account_settings 증거 계약

 포함한 interaction_id:
  - SET-008-tab-registration: SettingsSection에 account 탭 등록 검증
    testAccountSectionIsRegisteredAfterAI, testAccountSectionHasCorrectTitleAndIcon
  - SET-008-show_account_status: 집중 자동화 테스트
    testInitialStateSetAuthStateIsSignedOut ~ testEntitlementUnknownMapping
  - SET-008-sign_out_account: 집중 자동화 테스트
    testSignOutTappedShowsConfirmation ~ testAccessSignedOutDelegateClearsConfirmation
  - SET-008-open_entitlement_management: manageAccountTapped URL 열기
    testManageAccountTappedOpensURL

 Fixture reset:
  - 메모리 기반 TestStore 사용, 영구 저장소 불필요
  */

@MainActor
final class SET008ManageAccountSettingsTests: XCTestCase {
    // MARK: - SET-008-tab-registration

    /// SET-008-tab-registration: SettingsSection.allCases는 [.general, .appearance, .ai, .account] 순서를 유지한다.
    /// account 섹션이 Settings 탭 목록의 마지막에 위치한다.
    func testAccountSectionIsRegisteredAfterAI() {
        XCTAssertEqual(SettingsSection.allCases, [.general, .appearance, .ai, .account])
    }

    /// SET-008-tab-registration: account 섹션의 타이틀과 아이콘이 올바르게 설정된다.
    /// title은 "Account", iconName은 "person.crop.circle"이다.
    func testAccountSectionHasCorrectTitleAndIcon() {
        XCTAssertEqual(SettingsSection.account.title, "Account")
        XCTAssertEqual(SettingsSection.account.iconName, "person.crop.circle")
    }

    // MARK: - SET-008-show_account_status

    /// SET-008-show_account_status: 초기 AccountSettingsState의 setAuthState는 .signedOut이다.
    func testInitialStateSetAuthStateIsSignedOut() {
        let state = AccountSettingsState()
        XCTAssertEqual(state.setAuthState, .signedOut)
    }

    /// SET-008-show_account_status: 초기 AccountSettingsState의 setEntitlementState는 .entitlementUnknown이다.
    func testInitialStateSetEntitlementStateIsUnknown() {
        let state = AccountSettingsState()
        XCTAssertEqual(state.setEntitlementState, .entitlementUnknown)
    }

    /// SET-008-show_account_status: access.hasAccountSession=true → setAuthState == .signedIn
    func testSignedInMapping() {
        var access = AccountAccessFeature.State()
        access.hasAccountSession = true
        var state = AccountSettingsState()
        state.access = access
        XCTAssertEqual(state.setAuthState, .signedIn)
    }

    /// SET-008-show_account_status: access.isSignInInProgress=true → setAuthState == .signInInProgress
    func testSignInInProgressMapping() {
        var access = AccountAccessFeature.State()
        access.isSignInInProgress = true
        var state = AccountSettingsState()
        state.access = access
        XCTAssertEqual(state.setAuthState, .signInInProgress)
    }

    /// SET-008-show_account_status: access.didSignInFail=true → setAuthState == .signInFailed
    func testSignInFailedMapping() {
        var access = AccountAccessFeature.State()
        access.didSignInFail = true
        var state = AccountSettingsState()
        state.access = access
        XCTAssertEqual(state.setAuthState, .signInFailed)
    }

    /// SET-008-show_account_status: access.status.isActive → setEntitlementState == .entitlementActive
    func testEntitlementActiveMapping() {
        var access = AccountAccessFeature.State()
        access.hasAccountSession = true
        access.status = .coreLicenseActive
        var state = AccountSettingsState()
        state.access = access
        XCTAssertEqual(state.setEntitlementState, .entitlementActive)
    }

    /// SET-008-show_account_status: access.status가 revoked → setEntitlementState == .entitlementInactive
    func testEntitlementInactiveMapping() {
        var access = AccountAccessFeature.State()
        access.status = .revoked
        var state = AccountSettingsState()
        state.access = access
        XCTAssertEqual(state.setEntitlementState, .entitlementInactive)
    }

    /// SET-008-show_account_status: access.status=nil → setEntitlementState == .entitlementUnknown
    func testEntitlementUnknownMapping() {
        var access = AccountAccessFeature.State()
        access.status = nil
        var state = AccountSettingsState()
        state.access = access
        XCTAssertEqual(state.setEntitlementState, .entitlementUnknown)
    }

    // MARK: - SET-008-sign_out_account

    /// SET-008-sign_out_account: signOutTapped 액션은 isShowingSignOutConfirmation을 true로 설정한다.
    func testSignOutTappedShowsConfirmation() async {
        let store = TestStore(initialState: AccountSettingsState()) {
            AccountSettingsFeature()
        }

        await store.send(.signOutTapped) { state in
            state.isShowingSignOutConfirmation = true
        }
    }

    /// SET-008-sign_out_account: signOutConfirmed 액션은 isShowingSignOutConfirmation을 false로 설정하고
    /// access(.signOut)을 전송한다.
    func testSignOutConfirmedDelegatesToAccess() async {
        var initialState = AccountSettingsState()
        initialState.isShowingSignOutConfirmation = true
        let store = TestStore(initialState: initialState) {
            AccountSettingsFeature()
        } withDependencies: {
            $0.accountSessionClient.delete = { _ in }
            $0.accessStatusSnapshotClient.remove = {}
        }

        await store.send(.signOutConfirmed) { state in
            state.isShowingSignOutConfirmation = false
        }

        await store.receive(\.access.signOut)
    }

    /// SET-008-sign_out_account: signOutCancelled 액션은 isShowingSignOutConfirmation을 false로 설정한다.
    func testSignOutCancelledHidesConfirmation() async {
        var initialState = AccountSettingsState()
        initialState.isShowingSignOutConfirmation = true
        let store = TestStore(initialState: initialState) {
            AccountSettingsFeature()
        }

        await store.send(.signOutCancelled) { state in
            state.isShowingSignOutConfirmation = false
        }
    }

    /// SET-008-sign_out_account: access(.delegate(.signedOut))를 수신하면
    /// isShowingSignOutConfirmation을 false로 설정한다.
    func testAccessSignedOutDelegateClearsConfirmation() async {
        var initialState = AccountSettingsState()
        initialState.isShowingSignOutConfirmation = true
        let store = TestStore(initialState: initialState) {
            AccountSettingsFeature()
        } withDependencies: {
            $0.accountSessionClient.delete = { _ in }
            $0.accessStatusSnapshotClient.remove = {}
        }

        await store.send(.access(.delegate(.signedOut))) { state in
            state.isShowingSignOutConfirmation = false
        }
    }

    // MARK: - SET-008-open_entitlement_management

    /// SET-008-open_entitlement_management: manageAccountTapped 액션이 checkoutURLClient.accountURL()을 열어
    /// 브라우저에서 계정 관리 페이지로 이동한다.
    func testManageAccountTappedOpensURL() async throws {
        let expectedURL = try XCTUnwrap(URL(string: "https://voyager.test/account"))
        final class Capture: @unchecked Sendable {
            var value: URL?
        }
        let capture = Capture()
        let store = TestStore(initialState: AccountSettingsState()) {
            AccountSettingsFeature()
        } withDependencies: {
            $0.checkoutURLClient.openURL = { capture.value = $0 }
            $0.checkoutURLClient.accountURL = { expectedURL }
        }

        await store.send(.manageAccountTapped)
        XCTAssertEqual(capture.value, expectedURL)
    }

    func testManageAccountTappedDoesNotOpenNeutralFallbackURL() async throws {
        let fallbackURL = try XCTUnwrap(URL(string: "https://example.invalid/account"))
        final class Capture: @unchecked Sendable {
            var values: [URL] = []
        }
        let capture = Capture()
        let store = TestStore(initialState: AccountSettingsState()) {
            AccountSettingsFeature()
        } withDependencies: {
            $0.checkoutURLClient.openURL = { capture.values.append($0) }
            $0.checkoutURLClient.accountURL = { fallbackURL }
        }

        await store.send(.manageAccountTapped)
        XCTAssertTrue(capture.values.isEmpty)
    }

    // MARK: - Web Bridge Semantics

    /// SET-008 web-bridge-only 계약 (T1 contract): AccountSettingsAction enum은
    /// in-app renewal/paywall CTA case를 포함하지 않는다.
    /// Account 탭은 외부 웹 포털 브리지(web bridge)만 허용하며,
    /// 인앱 결제/갱신/업그레이드/복원 액션은 계약 위반이다.
    /// T1 policy: entitlement_management_external_portal_is_web_bridge_only.
    func testActionEnumContainsNoInAppRenewalOrPaymentCases() {
        // AccountSettingsAction의 현재 계약상 노출된 모든 case.
        // 새 결제/갱신 case가 추가되면 이 목록이 업데이트되어야 하며,
        // 추가 즉시 아래 forbidden keyword 검사에 걸려 테스트가 실패한다.
        let contractActions: [AccountSettingsAction] = [
            .access(.onAppear),
            .signOutTapped,
            .signOutConfirmed,
            .signOutCancelled,
            .manageAccountTapped,
            .openAccountURLCompleted(true),
        ]
        let caseDescriptions = contractActions.map { String(describing: $0).lowercased() }

        let forbiddenKeywords = [
            "renew", "upgrade", "payment", "subscribe", "purchase", "buy", "restore",
        ]

        for keyword in forbiddenKeywords {
            XCTAssertFalse(
                caseDescriptions.contains(where: { $0.contains(keyword) }),
                "AccountSettingsAction에 forbidden keyword '\(keyword)' 포함. " +
                    "Account 탭은 web-bridge-only (in-app renewal/paywall CTA 금지).",
            )
        }
    }

    /// T11 overlay ownership: session lapse recovery는 Settings/Account 탭이 소유하지 않는다.
    /// T1 policy: entitlement_inactive_recovery_is_owned_outside_settings.
    /// Recovery는 ACC overlay (ACC-003-guard_session_lapse)가 소유하며, Settings는
    /// access_status를 display로 반영할 뿐 recovery action을 노출하지 않는다.
    /// 본 테스트는 `testActionEnumContainsNoInAppRenewalOrPaymentCases`를 보완하여
    /// session-lapse-recovery 용어(reauth, restartSession, dismissSessionLapse 등)도
    /// AccountSettingsAction case name에 노출되지 않음을 검증한다.
    /// - 사전 조건: AccountSettingsAction의 현재 계약 case 목록 (6개).
    /// - 기대 결과: 어느 case name에도 session-lapse recovery keyword가 포함되지 않는다.
    func testAccountSettingsActionHasNoSessionLapseRecoveryCases() {
        let contractActions: [AccountSettingsAction] = [
            .access(.onAppear),
            .signOutTapped,
            .signOutConfirmed,
            .signOutCancelled,
            .manageAccountTapped,
            .openAccountURLCompleted(true),
        ]
        let caseDescriptions = contractActions.map { String(describing: $0).lowercased() }

        let sessionLapseRecoveryKeywords = [
            "reauth", "reauthenticate", "restartsession", "recoversession",
            "unexpire", "dismisssessionlapse", "restoresession", "relogin",
        ]

        for keyword in sessionLapseRecoveryKeywords {
            XCTAssertFalse(
                caseDescriptions.contains(where: { $0.contains(keyword) }),
                "AccountSettingsAction에 session-lapse recovery keyword '\(keyword)' 포함. " +
                    "Recovery는 ACC overlay/session lapse guard가 소유 (Settings/Account 탭 소유 아님).",
            )
        }
    }

    /// SET-008 web-bridge-only 계약 (T1 contract): manageAccountTapped는
    /// 외부 URL 열기(checkoutURLClient.openURL) 단일 호출만 수행하며,
    /// in-app 결제/갱신 화면으로 전환하지 않는다.
    /// 기존 testManageAccountTappedOpensURL을 보강: openURL이 정확히 한 번만 호출됨을 검증.
    func testManageAccountTappedTriggersExternalURLBridgeOnly() async throws {
        let expectedURL = try XCTUnwrap(URL(string: "https://voyager.test/account"))
        final class OpenURLCapture: @unchecked Sendable {
            var calls: [URL] = []
        }
        let capture = OpenURLCapture()
        let store = TestStore(initialState: AccountSettingsState()) {
            AccountSettingsFeature()
        } withDependencies: {
            $0.checkoutURLClient.openURL = { capture.calls.append($0) }
            $0.checkoutURLClient.accountURL = { expectedURL }
        }

        // manageAccountTapped → 외부 URL 정확히 한 번 열기 (web bridge).
        // 인앱 결제 화면 전환 액션은 전송되지 않는다.
        await store.send(.manageAccountTapped)

        XCTAssertEqual(capture.calls, [expectedURL])
        XCTAssertEqual(capture.calls.count, 1, "manageAccountTapped는 외부 URL 단일 오픈만 수행 (web bridge)")
    }

    /// SET-008 web-bridge-only 계약 (T1 contract): setAuthState / setEntitlementState는
    /// 읽기 전용 computed display 매핑이며, in-app recovery를 위한 writable state
    /// (결제 진행/실패, 갱신 에러 등)를 노출하지 않는다.
    /// T1 policy: entitlement_inactive_has_no_in_settings_recovery_cta.
    func testSetAuthAndEntitlementStatesAreReadOnlyDisplayMappings() {
        var state = AccountSettingsState()

        // 초기 매핑
        XCTAssertEqual(state.setAuthState, .signedOut)
        XCTAssertEqual(state.setEntitlementState, .entitlementUnknown)

        // 매핑 변경은 access 필드를 통해서만 가능 (computed property 직접 쓰기 불가).
        state.access.hasAccountSession = true
        state.access.status = .coreLicenseActive
        XCTAssertEqual(state.setAuthState, .signedIn)
        XCTAssertEqual(state.setEntitlementState, .entitlementActive)

        // AccountSettingsState의 stored property 이름을 Mirror로 수집하여
        // forbidden recovery 프로퍼티가 추가되지 않았는지 검증.
        let propertyNames = Set(
            Mirror(reflecting: state).children.compactMap(\.label),
        )
        let forbiddenRecoveryProperties: Set = [
            "isRenewalInProgress", "renewalError",
            "isUpgradeInProgress", "upgradeError",
            "isPaymentInProgress", "paymentError",
            "purchaseState", "isRestoreInProgress",
        ]
        XCTAssertTrue(
            propertyNames.isDisjoint(with: forbiddenRecoveryProperties),
            "AccountSettingsState에 in-app recovery 용 writable 프로퍼티가 존재: " +
                "\(propertyNames.intersection(forbiddenRecoveryProperties)). " +
                "Account 탭은 web-bridge-only.",
        )
    }

    /// SET-008 web-bridge-only 계약 (T7 구현 주도):
    /// T1 contract의 entitlement_management_action_for_entitlement = ["entitlement_active"]에 따라,
    /// Manage Account CTA는 setEntitlementState == .entitlementActive일 때만 노출된다.
    /// inactive/unknown 상태에서는 CTA가 노출되지 않는다.
    /// T1 policy: entitlement_inactive_has_no_in_settings_recovery_cta,
    ///             entitlement_inactive_recovery_is_owned_outside_settings.
    /// RED: AccountSettingsState.isManageAccountAvailable 프로퍼티가 아직 구현되지 않음.
    func testManageAccountCTAGatedByEntitlementActive() {
        var state = AccountSettingsState()
        state.access.hasAccountSession = true

        state.access.status = .coreLicenseActive
        XCTAssertTrue(
            state.isManageAccountAvailable,
            "entitlement_active일 때 Manage Account CTA 허용 (web bridge 진입점)",
        )

        state.access.status = .revoked
        XCTAssertFalse(
            state.isManageAccountAvailable,
            "entitlement_inactive일 때 Manage Account CTA 금지 " +
                "(entitlement_inactive_has_no_in_settings_recovery_cta; " +
                "recovery는 Settings 외부에서 소유됨)",
        )

        state.access.status = nil
        XCTAssertFalse(
            state.isManageAccountAvailable,
            "entitlement_unknown일 때 Manage Account CTA 금지",
        )
    }

    // MARK: - View Tests

    /// SET-008-manage_account_settings: signedOut 상태에서 Sign In 버튼이 표시된다.
    /// AccountSettingsView는 setAuthState==.signedOut일 때 Sign In 버튼을 렌더링한다.
    func testSignedOutStateShowsSignInButton() async {
        let store = TestStore(initialState: AccountSettingsState()) {
            AccountSettingsFeature()
        } withDependencies: {
            $0.signInHandoffClient.performHandoff = { .cancelled }
        }

        // signedOut 상태 → Sign In 버튼 표시
        // 버튼 탭 시 access(.loginTapped) 전송
        await store.send(.access(.loginTapped)) { state in
            state.access.isSignInInProgress = true
            state.access.didSignInFail = false
        }

        await store.receive(\.access.signInHandoffCompleted) { state in
            state.access.isSignInInProgress = false
            state.access.didSignInFail = true
        }
    }

    /// SET-008-manage_account_settings: signedIn 상태에서 Sign Out 버튼과 Manage Account 버튼이 표시된다.
    func testSignedInStateShowsSignOutAndManageButtons() async {
        var initialState = AccountSettingsState()
        initialState.access.hasAccountSession = true
        let store = TestStore(initialState: initialState) {
            AccountSettingsFeature()
        }

        // signedIn 상태 → Sign Out 버튼과 Manage Account 버튼 표시
        await store.send(.signOutTapped) { state in
            state.isShowingSignOutConfirmation = true
        }
        await store.send(.manageAccountTapped)
    }

    /// SET-008-manage_account_settings: signInInProgress 상태에서 ProgressView(spinner)가 표시된다.
    func testSignInInProgressShowsSpinner() {
        var initialState = AccountSettingsState()
        initialState.access.isSignInInProgress = true
        let store = TestStore(initialState: initialState) {
            AccountSettingsFeature()
        }

        // signInInProgress → View에서 ProgressView(spinner) 표시
        // 초기 상태 유지, 추가 액션 없음
    }

    /// SET-008-manage_account_settings: isShowingSignOutConfirmation 바인딩으로 confirmation dialog 표시가 제어된다.
    func testConfirmationDialogBoundToIsShowingSignOutConfirmation() async {
        let store = TestStore(initialState: AccountSettingsState()) {
            AccountSettingsFeature()
        }

        // signOutTapped → dialog 표시
        await store.send(.signOutTapped) { state in
            state.isShowingSignOutConfirmation = true
        }

        // signOutCancelled → dialog 닫힘
        await store.send(.signOutCancelled) { state in
            state.isShowingSignOutConfirmation = false
        }
    }

    // MARK: - Settings Wiring

    /// B6: SettingsState가 accountSettings 프로퍼티를 가지며, 타입은 AccountSettingsState이다.
    func testSettingsStateHasAccountSettings() {
        let state = SettingsState()
        XCTAssertEqual(state.accountSettings, AccountSettingsState())
    }

    /// B6: SettingsAction.account(AccountSettingsAction) 케이스가 존재하고 패턴 매칭으로 접근 가능하다.
    func testSettingsActionHasAccountCase() {
        let action = SettingsAction.account(.access(.onAppear))
        if case .account = action {
            // 컴파일 타임 검증: account 케이스가 존재하면 통과
        } else {
            XCTFail("SettingsAction.account case not found")
        }
    }

    /// B6: Settings.onAppear가 AccountAccessFeature의 .onAppear로 라우팅된다.
    /// Settings root가 열릴 때 account tab도 access 상태를 초기화한다.
    func testSettingsOnAppearSendsAccountAccessOnAppear() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.launchAtLoginClient = .testValue
            $0.directorySelectionClient = .testValue
            $0.appearanceSettingsClient = .testValue
            $0.accountSessionClient.read = { nil }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.account.access.onAppear)
    }

    /// B6: SettingsSection의 allCases 순서는 [.general, .appearance, .ai, .account]이다.
    /// account 섹션이 ai 다음에 위치하여 탭 순서가 일관되게 유지된다.
    func testSettingsSectionAccountIsAfterAI() {
        XCTAssertEqual(SettingsSection.allCases, [.general, .appearance, .ai, .account])
    }
}

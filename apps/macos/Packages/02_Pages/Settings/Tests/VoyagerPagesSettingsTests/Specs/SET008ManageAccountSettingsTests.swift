import ComposableArchitecture
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesSettings
import XCTest

@MainActor
final class SET008ManageAccountSettingsTests: XCTestCase {
    // MARK: - SET-008-tab-registration

    /// SET-008-tab-registration: Account 탭은 Settings 탭 목록의 마지막에 유지된다.
    /// - 검증 내용: account 섹션의 등록 순서와 표시 메타데이터
    /// - 사전 조건: 기본 SettingsSection 목록
    /// - 기대 결과: account가 AI 다음에 있고 기존 제목과 아이콘을 유지함
    func testAccountSectionIsRegisteredAfterAI() {
        XCTAssertEqual(SettingsSection.allCases, [.general, .appearance, .ai, .account])
        XCTAssertEqual(SettingsSection.account.title, "Account")
        XCTAssertEqual(SettingsSection.account.iconName, "person.crop.circle")
    }

    // MARK: - SET-008-show_account_status

    /// SET-008-show_account_status: canonical snapshot은 signed-in active 표시 projection으로 갱신된다.
    /// - 검증 내용: snapshot session과 access status의 Settings display mapping
    /// - 사전 조건: 기본 Settings 상태
    /// - 기대 결과: signed-in 및 entitlement active 표시와 accessStatus가 함께 갱신됨
    func testCanonicalSnapshotUpdatesAccountPresentation() async {
        let store = TestStore(initialState: SettingsState()) {
            SettingsFeature()
        }
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: Date(timeIntervalSince1970: 0),
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
        )

        await store.send(.appLifecycleAccessSnapshotReady(snapshot)) { state in
            state.accessStatus = .coreLicenseActive
            state.accountSettings.presentation = AccountAccessPresentation(snapshot: snapshot)
        }

        XCTAssertEqual(store.state.accountSettings.setAuthState, .signedIn)
        XCTAssertEqual(store.state.accountSettings.setEntitlementState, .entitlementActive)
        XCTAssertTrue(store.state.accountSettings.isManageAccountAvailable)
    }

    /// SET-008-show_account_status: canonical presentation update는 progress, failure, unavailable 표시를 구분한다.
    /// - 검증 내용: progress/failure와 network failure access status의 display mapping
    /// - 사전 조건: 기본 Settings 상태
    /// - 기대 결과: 각 projection fact가 대응하는 Settings UI 상태로 즉시 반영됨
    func testCanonicalPresentationUpdatesAccountDisplayStates() async {
        let store = TestStore(initialState: SettingsState()) {
            SettingsFeature()
        }
        let signingIn = AccountAccessPresentation(isSignInInProgress: true)
        await store.send(.accountAccessPresentationUpdated(signingIn)) { state in
            state.accountSettings.presentation = signingIn
        }
        XCTAssertEqual(store.state.accountSettings.setAuthState, .signInInProgress)

        let failed = AccountAccessPresentation(didSignInFail: true)
        await store.send(.accountAccessPresentationUpdated(failed)) { state in
            state.accountSettings.presentation = failed
        }
        XCTAssertEqual(store.state.accountSettings.setAuthState, .signInFailed)

        let unavailable = AccountAccessPresentation(
            hasAccountSession: true,
            accessStatus: .networkFailure,
        )
        await store.send(.accountAccessPresentationUpdated(unavailable)) { state in
            state.accessStatus = .networkFailure
            state.accountSettings.presentation = unavailable
        }
        XCTAssertEqual(store.state.accountSettings.setEntitlementState, .entitlementUnavailable)
    }

    // MARK: - SET-008-start_account_sign_in

    /// SET-008-start_account_sign_in: signed-out Sign In은 상위 canonical owner로 한 번 전달된다.
    /// - 검증 내용: signInTapped의 단일 narrow delegate
    /// - 사전 조건: signed-out AccountSettingsState
    /// - 기대 결과: local runtime 변화 없이 signInRequested delegate를 한 번 수신함
    func testSignedOutSignInForwardsOnce() async {
        let store = TestStore(initialState: AccountSettingsState()) {
            AccountSettingsFeature()
        }

        await store.send(.signInTapped)
        await store.receive(\.delegate.signInRequested)
    }

    /// SET-008-start_account_sign_in: signed-in Sign In은 re-auth 없이 no-op이다.
    /// - 검증 내용: session 존재 시 Sign In delegate 미발행
    /// - 사전 조건: canonical projection이 signed-in임
    /// - 기대 결과: state와 effect가 변하지 않음
    func testSignedInSignInIsNoOp() async {
        var initialState = AccountSettingsState()
        initialState.presentation.hasAccountSession = true
        let store = TestStore(initialState: initialState) {
            AccountSettingsFeature()
        }

        await store.send(.signInTapped)
    }

    // MARK: - SET-008-sign_out_account

    /// SET-008-sign_out_account: confirmed Sign Out만 상위 canonical owner로 전달된다.
    /// - 검증 내용: confirmation 전 local state, confirmation 후 signOutRequested delegate
    /// - 사전 조건: signed-in projection과 숨겨진 confirmation dialog
    /// - 기대 결과: dialog 표시 뒤 확인 시 한 번만 delegate를 수신함
    func testConfirmedSignOutForwardsOnlyAfterConfirmation() async {
        var initialState = AccountSettingsState()
        initialState.presentation.hasAccountSession = true
        let store = TestStore(initialState: initialState) {
            AccountSettingsFeature()
        }

        await store.send(.signOutTapped) { state in
            state.isShowingSignOutConfirmation = true
        }
        await store.send(.signOutConfirmed) { state in
            state.isShowingSignOutConfirmation = false
        }
        await store.receive(\.delegate.signOutRequested)
    }

    /// SET-008-sign_out_account: Cancel은 local confirmation만 닫는다.
    /// - 검증 내용: cancel action의 local UI state 전이
    /// - 사전 조건: sign-out confirmation이 표시 중임
    /// - 기대 결과: confirmation이 닫히고 delegate가 발생하지 않음
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

    // MARK: - SET-008-retry_account_access

    /// SET-008-retry_account_access: Retry는 canonical owner로 한 번 전달된다.
    /// - 검증 내용: retryTapped의 단일 narrow delegate
    /// - 사전 조건: signed-in network failure projection
    /// - 기대 결과: local fetch 없이 retryRequested delegate를 한 번 수신함
    func testRetryForwardsOnce() async {
        var initialState = AccountSettingsState()
        initialState.presentation = AccountAccessPresentation(
            hasAccountSession: true,
            accessStatus: .networkFailure,
        )
        let store = TestStore(initialState: initialState) {
            AccountSettingsFeature()
        }

        await store.send(.retryTapped)
        await store.receive(\.delegate.retryRequested)
    }

    // MARK: - SET-008-open_entitlement_management

    /// SET-008-open_entitlement_management: Manage Account는 Settings-local 외부 URL effect로 유지된다.
    /// - 검증 내용: configured account URL의 단일 open 호출
    /// - 사전 조건: 유효한 checkout URL client
    /// - 기대 결과: URL이 정확히 한 번 열리고 auth runtime intent는 생성되지 않음
    func testManageAccountTappedOpensURL() async throws {
        let expectedURL = try XCTUnwrap(URL(string: "https://voyager.test/account"))
        let capture = LockIsolated<[URL]>([])
        let store = TestStore(initialState: AccountSettingsState()) {
            AccountSettingsFeature()
        } withDependencies: {
            $0.checkoutURLClient.accountURL = { expectedURL }
            $0.checkoutURLClient.openURL = { url in
                capture.withValue { $0.append(url) }
            }
        }

        await store.send(.manageAccountTapped)

        XCTAssertEqual(capture.value, [expectedURL])
    }
}

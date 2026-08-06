import ComposableArchitecture
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
        XCTAssertEqual(SettingsSection.visibleCases, [.general, .appearance, .ai])
        XCTAssertEqual(SettingsSection.account.title, "Account")
        XCTAssertEqual(SettingsSection.account.iconName, "person.crop.circle")
    }

    // MARK: - SET-008-show_account_status

    /// SET-008-show_account_status: canonical account presentation은 signed-in 표시로 갱신된다.
    /// - 검증 내용: account session fact의 Settings display mapping
    /// - 사전 조건: 기본 Settings 상태
    /// - 기대 결과: signed-in 표시가 갱신됨
    func testCanonicalPresentationUpdatesSignedInState() async {
        let store = TestStore(initialState: SettingsState()) {
            SettingsFeature()
        }
        let presentation = AccountAccessPresentation(hasAccountSession: true)

        await store.send(.accountAccessPresentationUpdated(presentation)) { state in
            state.accountSettings.presentation = presentation
        }

        XCTAssertEqual(store.state.accountSettings.setAuthState, .signedIn)
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

    /// SET-008-start_account_sign_in: 만료된 세션의 Sign In은 refresh가 아닌 새 로그인을 요청한다.
    /// - 검증 내용: sign-in failure projection에서 signInTapped의 narrow delegate
    /// - 사전 조건: 세션이 없고 didSignInFail이 설정된 AccountSettingsState
    /// - 기대 결과: retryRequested가 아니라 signInRequested delegate를 한 번 수신함
    func testExpiredSessionSignInForwardsOnce() async {
        var initialState = AccountSettingsState()
        initialState.presentation.didSignInFail = true
        let store = TestStore(initialState: initialState) {
            AccountSettingsFeature()
        }

        XCTAssertEqual(store.state.setAuthState, .signInFailed)

        await store.send(.signInTapped)
        await store.receive(\.delegate.signInRequested)
    }

    /// SET-008-start_account_sign_in: 실패 상태 CTA는 refresh Retry가 아닌 Sign In으로 매핑된다.
    /// - 검증 내용: AccountSettingsView가 실제 사용하는 button title/action mapping
    /// - 사전 조건: signInFailed account status rendering
    /// - 기대 결과: "Sign In" 표시와 signInTapped action
    func testSignInFailedCTAStartsSignIn() {
        XCTAssertEqual(AccountSettingsView.signInButtonTitle, "Sign In")
        if case .signInTapped = AccountSettingsView.signInButtonAction {} else {
            XCTFail("Sign-in failure CTA must start a new sign-in flow")
        }
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
}

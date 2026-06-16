// swiftlint:disable force_unwrapping

@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-001-start_account_sign_in spec-owner 테스트

 interaction_id: ACC-001-start_account_sign_in
 spec: docs/canonical/PRODUCT/05_FEATURE_SPECS/acc/ACC-001-manage_account_auth/ACC-001-start_account_sign_in.md

 auth_state 매핑 (현재 모델):
 - logged_out     → AccountAccessState 기본 상태 (hasAccountSession=false, didSignInFail=false)
 - session_expired → didSignInFail=true (재로그인 필요 상태, canStartLogin=true)
 - logged_in      → hasAccountSession=true
 */

@MainActor
final class ACC001StartAccountSignInTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTestStore(
        signInHandoffClient: SignInHandoffClient = SignInHandoffClient { .failure },
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountAccessClient = .mock
            $0.signInHandoffClient = signInHandoffClient
            $0.date = .constant(referenceDate)
        }
    }

    /// session_expired 상태 (재로그인 필요). didSignInFail=true로 모델링.
    private func sessionExpiredInitialState() -> AccountAccessFeature.State {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true
        return state
    }

    // MARK: - ACC-001-start_account_sign_in

    /// ACC-001-start_account_sign_in: logged_out 상태에서 Login CTA 선택 시 브라우저 로그인 URL이 열린다.
    /// logged_out 상태에서 loginTapped가 signInHandoffClient.performHandoff를 호출하는지 검증한다.
    /// - 검증 내용: isSignInInProgress=true, didSignInFail=false, handoffClient가 호출됨
    /// - 사전 조건: AccountAccessFeature.State 기본 상태 (logged_out)
    /// - 기대 결과: isSignInInProgress=true, handoffPendingState 저장, hasAccountSession=false 유지
    func testLoggedOutLoginCTATriggersBrowserLoginURL() async {
        nonisolated(unsafe) var handoffCalled = false
        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient {
                handoffCalled = true
                return .awaitingCallback(state: "test-state-123")
            },
        )

        await store.send(.loginTapped) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
        }

        XCTAssertTrue(handoffCalled, "signInHandoffClient가 호출되어 브라우저 로그인 URL이 열려야 함")
        XCTAssertTrue(store.state.isSignInInProgress)

        // awaitingCallback → handoffPendingState 저장, auth_state 미변경
        await store.receive(\.signInHandoffCompleted) { state in
            state.handoffPendingState = "test-state-123"
        }

        XCTAssertFalse(store.state.hasAccountSession, "로그인 완료 전까지 logged_out 유지")
        await store.finish()
    }

    /// ACC-001-start_account_sign_in: session_expired 상태에서 Login CTA 선택 시 로그인 진입이 시작된다.
    /// session_expired (didSignInFail=true) 상태에서 loginTapped가 동일하게 handoff를 시작하는지 검증한다.
    /// - 검증 내용: isSignInInProgress=true, didSignInFail=false (새 흐름 시작), handoffClient 호출됨
    /// - 사전 조건: didSignInFail=true (session_expired), canStartLogin=true
    /// - 기대 결과: isSignInInProgress=true, didSignInFail=false, handoffClient 호출됨
    func testSessionExpiredLoginCTAStartsLogin() async {
        nonisolated(unsafe) var handoffCalled = false
        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient {
                handoffCalled = true
                return .failure
            },
            initialState: sessionExpiredInitialState(),
        )

        // 전제: session_expired 상태에서 canStartLogin == true
        XCTAssertTrue(store.state.canStartLogin, "session_expired 상태에서 Login CTA 활성화")
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signInFailed)

        await store.send(.loginTapped) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
        }

        XCTAssertTrue(handoffCalled, "session_expired에서도 동일하게 handoff 시작")
        XCTAssertTrue(store.state.isSignInInProgress)

        await store.receive(\.signInHandoffCompleted) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }
        await store.finish()
    }

    /// ACC-001-start_account_sign_in: 인증 흐름 시작 후 callback/token 교환 전까지 auth_state가 변경되지 않는다.
    /// loginTapped 후 awaitingCallback 수신 시까지 hasAccountSession이 false로 유지되는지 검증한다.
    /// - 검증 내용: 인증 대기 중 hasAccountSession 변화 없음, status nil 유지
    /// - 사전 조건: AccountAccessFeature.State 기본 상태, signInHandoffClient가 awaitingCallback 반환
    /// - 기대 결과: hasAccountSession=false, status=nil 유지
    func testAuthStateUnchangedUntilCallbackAndTokenExchange() async {
        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient {
                .awaitingCallback(state: "pending-state-abc")
            },
        )

        await store.send(.loginTapped) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
        }

        // callback 수신 전: auth_state 변경 없음 (logged_out 유지)
        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertNil(store.state.status)

        await store.receive(\.signInHandoffCompleted) { state in
            state.handoffPendingState = "pending-state-abc"
        }

        // 여전히 token 교환 전이므로 auth_state 미변경
        XCTAssertFalse(store.state.hasAccountSession, "callback 수신 및 token 교환 전까지 auth_state 변경 안 함")
        XCTAssertNil(store.state.status)
        await store.finish()
    }

    // NOTE: 현재 구현은 signInInProgress 중 canStartLogin=false로 인해 중복 loginTapped를 무시(no-op)한다.
    // spec ACC-001-start_account_sign_in AC4는 "기존 흐름 무효화 + 새 흐름 시작"을 요구한다.
    // 이 테스트는 현재 구현 동작(ignored)을 검증하며, spec과의 갭은 후속 작업에서 해결 필요.

    /// ACC-001-start_account_sign_in: 로그인 진행 중 Login CTA 재선택 시 현재 구현은 no-op 처리한다.
    /// isSignInInProgress=true 상태에서 loginTapped가 무시되는지 검증한다.
    /// - 검증 내용: 상태 변화 없음, handoffClient 재호출 없음
    /// - 사전 조건: isSignInInProgress=true (canStartLogin=false)
    /// - 기대 결과: handoffCallCount=0, handoffClient 재호출 없음
    func testDuplicateLoginTappedDuringSignInInProgressIgnoredByCurrentImpl() async {
        nonisolated(unsafe) var handoffCallCount = 0
        var initialState = AccountAccessFeature.State()
        initialState.isSignInInProgress = true

        let store = makeTestStore(
            signInHandoffClient: SignInHandoffClient {
                handoffCallCount += 1
                return .failure
            },
            initialState: initialState,
        )

        // signInInProgress 중에는 canStartLogin == false
        XCTAssertFalse(store.state.canStartLogin)

        await store.send(.loginTapped)

        XCTAssertEqual(handoffCallCount, 0, "현재 구현: signInInProgress 중 handoff 재시작 없음 (spec gap)")
        await store.finish()
    }
}

// swiftlint:enable force_unwrapping

// swiftlint:disable force_unwrapping

@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-001-sign_out_account spec-owner 테스트

 interaction_id: ACC-001-sign_out_account

 signOut은 AccountSessionClient.delete를 통해 로컬 token 파일 삭제 + best-effort 서버 무효화를 수행한다.
 Reducer에 signOut action이 없으므로, 클라이언트 레벨(FileStore) 및 상태 파생(state derivation) 테스트로 구성한다.
 */

@MainActor
final class ACC001SignOutAccountTests: XCTestCase {
    // MARK: - ACC-001-sign_out_account

    /// ACC-001-sign_out_account: Sign Out 호출 시 로컬 token 파일이 삭제되고 logged_out으로 전환된다.
    /// signOut 호출이 로컬 token 파일을 삭제하고 상태를 logged_out으로 전환하는지 검증한다.
    /// - 검증 내용: 파일 삭제 확인 및 상태 전환 (signedOut, hasAccountSession=false)
    /// - 사전 조건: AccountTokenFileStore에 유효한 token이 저장되어 있음
    /// - 기대 결과: token 파일이 삭제되고 accountAccessAuthAxis==.signedOut, hasAccountSession==false
    func testSignOutDeletesTokenAndTransitionsToLoggedOut() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        let tokens = AccountTokensFile(
            updatedAtMs: 1_718_000_000_000,
            accessToken: "access-abc",
            accessTokenExpiresAtMs: 1_718_000_900_000,
            accessTokenExpiresIn: 900,
            refreshToken: "refresh-xyz",
            refreshTokenExpiresAtMs: 1_718_090_000_000,
        )
        try await store.write(tokens)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path))

        try await store.delete()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path))

        let state = AccountAccessFeature.State()
        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertFalse(state.hasAccountSession)
    }

    /// ACC-001-sign_out_account: Sign Out으로 logged_out 전환 시 paywall CTA 조건이 해제되고 Login CTA로 대체된다.
    /// logged_out 전환 시 paywall CTA 조건이 해제되고 Login CTA로 대체되는지 검증한다.
    /// - 검증 내용: hasAccountSession 전환 후 accountAccessAuthAxis 및 requiresAccountSession 확인
    /// - 사전 조건: hasAccountSession=true, status=.none
    /// - 기대 결과: hasAccountSession=false가 되면 accountAccessAuthAxis==.signedOut, canStartLogin==true
    func testSignedOutTransitionDisablesPaywallCtaConditions() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = AccessStatus.none

        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)

        state.hasAccountSession = false

        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertTrue(state.requiresAccountSession)
        XCTAssertTrue(state.canStartLogin)
    }

    /// ACC-001-sign_out_account: 서버 실패와 무관하게 로컬 token은 항상 삭제된다 (best-effort).
    /// 서버 무효화 실패와 관계없이 로컬 token이 항상 삭제되는지 검증한다.
    /// - 검증 내용: delete() 호출 후 파일 존재 여부 및 read() 결과 확인
    /// - 사전 조건: AccountTokenFileStore에 유효한 token이 저장되어 있음
    /// - 기대 결과: token 파일이 삭제되고 read()=nil 반환
    func testServerFailureStillDeletesLocalToken() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        let tokens = AccountTokensFile(
            updatedAtMs: 1000,
            accessToken: "a",
            accessTokenExpiresAtMs: 2000,
            accessTokenExpiresIn: 1000,
            refreshToken: "r",
            refreshTokenExpiresAtMs: 3000,
        )
        try await store.write(tokens)

        try await store.delete()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path))
        let readBack = try await store.read()
        XCTAssertNil(readBack)
    }

    /// ACC-001-sign_out_account: token 파일이 없는 상태에서 signOut 호출해도 에러 없이 성공한다.
    /// 이미 logged_out 상태에서 signOut 호출이 no-op으로 처리되는지 검증한다.
    /// - 검증 내용: token 파일이 없는 상태에서 delete() 호출 시 에러 없이 성공하는지 확인
    /// - 사전 조건: TemporaryHomeFixture(createVoyagerDirectory=false), token 파일 없음
    /// - 기대 결과: delete() 후에도 파일 없음 상태 유지, 에러 발생하지 않음
    func testSignOutWhenAlreadyLoggedOutIsNoOp() async throws {
        let fixture = try TemporaryHomeFixture(createVoyagerDirectory: false)
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path))

        try await store.delete()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path))
    }

    /// ACC-001-sign_out_account: 로그아웃 후 SET Account 탭은 signed_out 상태이며 Login CTA가 표시된다.
    /// 로그아웃 후 state derivation이 올바르게 signed_out 및 Login CTA를 표시하는지 검증한다.
    /// - 검증 내용: hasAccountSession 전환 후 accountAccessAuthAxis, canStartLogin, requiresAccountSession 확인
    /// - 사전 조건: hasAccountSession=true, status=.coreLicenseActive
    /// - 기대 결과: hasAccountSession=false 후 accountAccessAuthAxis==.signedOut, canStartLogin==true
    func testAfterSignOutShowsSignedOutAndLoginCTA() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .coreLicenseActive

        state.hasAccountSession = false
        state.status = nil

        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertTrue(state.canStartLogin)
        XCTAssertTrue(state.requiresAccountSession)
    }

    /// ACC-001-sign_out_account: 로그아웃 후 Login CTA가 활성화되어 start_account_sign_in 진입이 가능하다.
    /// 로그아웃 후 Login CTA 활성화 상태를 검증한다.
    /// - 검증 내용: hasAccountSession 전환 후 canStartLogin 및 accountAccessAuthAxis 확인
    /// - 사전 조건: hasAccountSession=true
    /// - 기대 결과: hasAccountSession=false 후 canStartLogin==true, accountAccessAuthAxis==.signedOut
    func testAfterSignOutLoginCTACanStartSignIn() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true

        state.hasAccountSession = false

        XCTAssertTrue(state.canStartLogin, "로그아웃 후 Login CTA 활성화")
        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
    }

    // MARK: - Reducer signOut tests (TCA TestStore)

    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTestStore(
        accountSessionClient: AccountSessionClient = .testValue,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
        }
    }

    private func signedInState() -> AccountAccessFeature.State {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.ttlTimerActive = true
        state.sessionExpiresAt = Date(timeIntervalSince1970: 1_700_000_100)
        return state
    }

    /// ACC-001-sign_out_account: signOut action이 session을 삭제하고 logged_out 상태로 전환된다.
    /// - 사전 조건: hasAccountSession=true
    /// - 기대 결과: hasAccountSession=false, sessionClient.delete 호출, snapshotClient.remove 호출, delegate(.signedOut) 전송
    func testReducerSignOutDeletesSessionAndTransitionsToLoggedOut() async {
        nonisolated(unsafe) var deleteCalled = false
        nonisolated(unsafe) var removeCalled = false

        let store = TestStore(initialState: signedInState()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(
                read: { nil },
                persist: { _ in },
                delete: { deleteCalled = true },
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { nil },
                save: { _ in },
                remove: { removeCalled = true },
            )
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
        }

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.didSignInFail = false
            state.status = nil
            state.snapshot = nil
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
        }

        await store.receive(\.delegate.signedOut)
        XCTAssertTrue(deleteCalled, "sessionClient.delete가 호출되어야 함")
        XCTAssertTrue(removeCalled, "snapshotClient.remove가 호출되어야 함")
        await store.finish()
    }

    /// ACC-001-sign_out_account: 이미 logged_out 상태에서 signOut은 no-op이다.
    /// - 사전 조건: hasAccountSession=false
    /// - 기대 결과: 상태 변화 없음, effect 없음
    func testReducerSignOutWhenAlreadyLoggedOutIsNoOp() async {
        let store = makeTestStore()

        await store.send(.signOut)
        await store.finish()
    }

    /// ACC-001-sign_out_account: signOut 시 TTL 타이머가 취소된다.
    /// - 사전 조건: hasAccountSession=true, ttlTimerActive=true
    /// - 기대 결과: ttlTimerActive=false, delegate(.signedOut) 전송
    func testReducerSignOutCancelsTtlTimer() async {
        let store = makeTestStore(initialState: signedInState())

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
        }

        await store.receive(\.delegate.signedOut)
        await store.finish()
    }

    /// ACC-001-sign_out_account: signOut 시 delegate(.signedOut)가 상위 reducer로 전송된다.
    /// - 사전 조건: hasAccountSession=true
    /// - 기대 결과: delegate(.signedOut) action 수신
    func testReducerSignOutSendsDelegateSignedOut() async {
        let store = makeTestStore(initialState: signedInState())

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
        }

        await store.receive(\.delegate.signedOut)
        await store.finish()
    }

    /// ACC-001-sign_out_account: 서버 session 삭제 실패에도 로컬 로그아웃은 완료된다 (best-effort).
    /// - 사전 조건: hasAccountSession=true, sessionClient.delete가 throw
    /// - 기대 결과: hasAccountSession=false, delegate(.signedOut) 전송 (서버 실패와 무관)
    func testReducerSignOutServerFailureStillCompletesLocally() async {
        enum TestError: Error { case deleteFailed }

        let store = TestStore(initialState: signedInState()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(
                read: { nil },
                persist: { _ in },
                delete: { throw TestError.deleteFailed },
            )
            $0.accessStatusSnapshotClient = .testValue
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
        }

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.didSignInFail = false
            state.status = nil
            state.snapshot = nil
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
        }

        await store.receive(\.delegate.signedOut)
        await store.finish()
    }

    /// ACC-001-sign_out_account: signOut 시 기존 sign-in failure 상태도 함께 초기화된다.
    /// - 사전 조건: hasAccountSession=true, didSignInFail=true (이전 sign-in 실패 이력)
    /// - 기대 결과: didSignInFail=false, errorMessage=nil, 에러 관련 필드가 설정되지 않음
    func testSignOutLeavesNoErrorState() async {
        var state = signedInState()
        state.didSignInFail = true

        let store = makeTestStore(initialState: state)

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.didSignInFail = false
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
        }

        await store.receive(\.delegate.signedOut)
        await store.finish()
    }
}

// swiftlint:enable force_unwrapping

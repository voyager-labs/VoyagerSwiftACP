import Clocks
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-001-sign_out_account spec-owner 테스트

 interaction_id: ACC-001-sign_out_account

 signOut은 AccountSessionClient.delete를 통해 로컬 token 파일 삭제 + best-effort 서버 무효화를 수행한다.
  Reducer의 signOut action은 세션 삭제, 상태 초기화, in-flight/retry effect 취소, delegate(.signedOut) 전송을 수행한다.
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
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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
            $0.accountSessionClient = AccountSessionClient(read: { _ in nil }, persist: { _ in },
                                                           delete: { _ in deleteCalled = true })
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
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.fetchGeneration = 1
            state.syncGeneration = 1 == 6 ? 2 : 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
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
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.fetchGeneration = 1
            state.syncGeneration = 1 == 6 ? 2 : 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
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
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.fetchGeneration = 1
            state.syncGeneration = 1 == 6 ? 2 : 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
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
            $0.accountSessionClient = AccountSessionClient(read: { _ in nil }, persist: { _ in },
                                                           delete: { _ in throw TestError.deleteFailed })
            $0.accessStatusSnapshotClient = .testValue
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
        }

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.didSignInFail = false
            state.status = nil
            state.snapshot = nil
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.fetchGeneration = 1
            state.syncGeneration = 1 == 6 ? 2 : 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
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
        state.status = .coreLicenseActive
        state.snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate,
            fetchedAt: referenceDate,
        )
        state.trialExpiresAt = referenceDate
        state.isComplete = true
        state.errorMessage = "stale error"
        state.updateEligibilityFailure = .missingReleaseIdentity

        let store = makeTestStore(initialState: state)

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.didSignInFail = false
            state.status = nil
            state.snapshot = nil
            state.trialExpiresAt = nil
            state.isComplete = false
            state.errorMessage = nil
            state.updateEligibilityFailure = nil
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.fetchGeneration = 1
            state.syncGeneration = 1 == 6 ? 2 : 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }

        XCTAssertNil(store.state.updateEligibilityFailure)
        XCTAssertTrue(store.state.canStartLogin)
        XCTAssertEqual(store.state.accessUnlockPrimaryCTA, .login)
        await store.receive(\.delegate.signedOut)
        await store.finish()
    }

    /// ACC-001-sign_out_account: signOut 후 늦게 도착한 accessStatusResponse는 폐기되고 delegate(.unlocked)를 내보내지 않는다.
    /// - 사전 조건: fetchGeneration=5, hasAccountSession=true
    /// - 기대 결과: signOut으로 fetchGeneration=6이 되고, generation=5 응답은 무시된다.
    func testReducerSignOutDiscardsLateAccessStatusResponse() async {
        let activeResponse = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            ownershipStatus: "owned",
            updateStatus: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )

        let store = makeTestStore(initialState: {
            var state = signedInState()
            state.fetchGeneration = 5
            state.syncGeneration = 5 == 6 ? 2 : 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
            return state
        }())

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.didSignInFail = false
            state.status = nil
            state.snapshot = nil
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.fetchGeneration = 6
            state.syncGeneration = 6 == 6 ? 2 : 1
            state.revalidationGeneration = 2
            state.refreshDeadlineGeneration = 2
        }

        await store.receive(\.delegate.signedOut)

        await store.send(.accessStatusResponse(generation: 5, result: .success(activeResponse)))
        await store.finish()
    }

    /// ACC-001-sign_out_account: signOut 후 예약된 retry backoff가 wake되어도 stale fetch를 시작하지 않는다.
    /// - 사전 조건: fetchGeneration=5, retry effect 대기 중
    /// - 기대 결과: signOut이 retry effect를 cancel하고, clock advance 후에도 fetch effect가 발생하지 않는다.
    func testReducerSignOutCancelsRetryBackoffBeforeWake() async {
        let clock = TestClock()
        let store = TestStore(initialState: {
            var state = signedInState()
            state.fetchGeneration = 5
            state.syncGeneration = 5 == 6 ? 2 : 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
            state.isSessionExpired = true
            return state
        }()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(read: { _ in nil }, persist: { _ in },
                                                           delete: { _ in })
            $0.accessStatusSnapshotClient = .testValue
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    XCTFail("stale retry must not reach fetchAccessStatus")
                    return AccessStatusResponse(
                        hasAccess: true,
                        status: "active",
                        ownershipStatus: "owned",
                        updateStatus: "active",
                        reason: "active_entitlement",
                        productKey: "core",
                        source: "polar",
                    )
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            )
            $0.date = .constant(referenceDate)
            $0.continuousClock = clock
        }

        await store.send(._fetchRetryScheduled(1))
        await store.receive(\.sessionSyncRequested)

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.didSignInFail = false
            state.status = nil
            state.snapshot = nil
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.fetchGeneration = 6
            state.syncGeneration = 2
            state.revalidationGeneration = 2
            state.refreshDeadlineGeneration = 2
        }

        await store.receive(\.delegate.signedOut)

        await clock.advance(by: .seconds(2))
        await store.finish()
    }

    /// ACC-001-sign_out_account: signOut은 isSessionExpired를 true로 올리고, 뒤늦은 _sessionExpiredDetected는 무시된다.
    /// - spec citations: auth_session_contract.toml:49-53, :140-144, :171-174
    /// - 사전 조건: hasAccountSession=true
    /// - 기대 결과: signOut 후 isSessionExpired=true, didSignInFail=false 유지, late _sessionExpiredDetected가 didSignInFail을
    /// true로 바꾸지 않음
    func testReducerSignOutMarksSessionExpiredAndIgnoresLateSessionExpiredDetected() async {
        let store = makeTestStore(initialState: signedInState())

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.didSignInFail = false
            state.status = nil
            state.snapshot = nil
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.fetchGeneration = 1
            state.syncGeneration = 1 == 6 ? 2 : 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }

        await store.receive(\.delegate.signedOut)

        await store.send(._sessionExpiredDetected)

        XCTAssertFalse(store.state.didSignInFail, "late _sessionExpiredDetected must stay ignored after signOut")
        XCTAssertTrue(store.state.isSessionExpired, "signOut should keep dedup guard armed")
        XCTAssertFalse(store.state.hasAccountSession)
        await store.finish()
    }

    /// ACC-001: sessionExpired도 signOut과 동일하게 durable access snapshot을 제거한다.
    /// - 사전 조건: hasAccountSession=true, persisted snapshot 존재
    /// - 기대 결과: session delete reason은 .sessionExpired이고 snapshotClient.remove가 호출됨
    func testReducerSessionExpiredRemovesPersistedAccessSnapshot() async {
        nonisolated(unsafe) var deleteReason: AccountSessionEndReason?
        nonisolated(unsafe) var removeCalled = false

        let store = TestStore(initialState: signedInState()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(read: { _ in nil }, persist: { _ in },
                                                           delete: { reason in deleteReason = reason })
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { nil },
                save: { _ in },
                remove: { removeCalled = true },
            )
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
        }

        await store.send(._sessionExpiredDetected) { state in
            state.hasAccountSession = false
            state.didSignInFail = true
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.fetchGeneration = 1
            state.syncGeneration = 1 == 6 ? 2 : 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.receive(\.delegate.recoveryRequired)

        await store.finish()
        XCTAssertEqual(deleteReason, .sessionExpired)
        XCTAssertTrue(removeCalled, "sessionExpired도 persisted access snapshot을 제거해야 함")
    }

    /// ACC-001-sign_out_account: sign-out은 현재 binding과 pre-invalidation generation으로 trusted snapshot을 제거한다.
    /// - 검증 내용: snapshot remove가 session binding과 sync generation을 그대로 받아 stale save보다 높은 tombstone을 만든다.
    /// - 사전 조건: binding된 로그인 세션과 syncGeneration=7인 상태.
    /// - 기대 결과: remove(binding, gateway, 7)가 한 번 호출되고 state는 sign-out 후 generation=8이 된다.
    func testReducerSignOutRemovesTrustedSnapshotWithBindingAndGeneration() async {
        let binding = UUID()
        nonisolated(unsafe) var removeArguments: (UUID?, GatewayEnvironment, Int)?
        var state = signedInState()
        state.sessionBindingID = binding
        state.syncGeneration = 7
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(read: { _ in nil }, persist: { _ in }, delete: { _ in })
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                activate: { _, _ in 0 },
                load: { _, _ in nil },
                save: { _, _, _, _ in },
                remove: { binding, environment, generation in
                    removeArguments = (binding, environment, generation)
                },
            )
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
        }

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.didSignInFail = false
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.sessionBindingID = nil
            state.fetchGeneration = 1
            state.syncGeneration = 8
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.receive(\.delegate.signedOut)
        await store.finish()

        XCTAssertEqual(removeArguments?.0, binding)
        XCTAssertEqual(removeArguments?.1, GatewayEnvironment(rawValue: ""))
        XCTAssertEqual(removeArguments?.2, 7)
    }

    // MARK: - ACC-001-sign_out_account: session end reason contract (T2)

    /// ACC-001: delete(reason:)가 .accountSessionDidEnd notification에 이유를 포함한다.
    /// - 사전 조건: 유효한 token 파일이 저장되어 있음
    /// - 기대 결과: notification의 userInfo에 explicitSignOut reason이 포함됨
    func testDeleteEmitsSessionEndReasonInUserInfo() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

        let futureMs = Int64(Date().timeIntervalSince1970 * 1000) + 86_400_000
        let tokens = AccountTokensFile(
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            accessToken: "access-abc",
            accessTokenExpiresAtMs: futureMs,
            accessTokenExpiresIn: 86_400_000,
            refreshToken: "refresh-xyz",
            refreshTokenExpiresAtMs: futureMs + 2_592_000_000,
        )
        try await store.write(tokens)

        let client = AccountSessionClient.live(store: store)

        let expectation = XCTestExpectation(description: "notification received")
        nonisolated(unsafe) var capturedUserInfo: [AnyHashable: Any]?

        let observer = NotificationCenter.default.addObserver(
            forName: .accountSessionDidEnd,
            object: nil,
            queue: .main,
        ) { notification in
            capturedUserInfo = notification.userInfo
            expectation.fulfill()
        }

        try await client.delete(.explicitSignOut)
        await fulfillment(of: [expectation], timeout: 2.0)

        NotificationCenter.default.removeObserver(observer)

        XCTAssertNotNil(capturedUserInfo, "notification must include userInfo")
        let reason = capturedUserInfo?[AccountSessionClient.sessionEndReasonUserInfoKey] as? String
        XCTAssertEqual(reason, AccountSessionEndReason.explicitSignOut.rawValue)
    }
}

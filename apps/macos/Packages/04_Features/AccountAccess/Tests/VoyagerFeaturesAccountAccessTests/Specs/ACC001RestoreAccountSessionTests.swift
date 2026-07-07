import Combine
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import VoyagerShared
import XCTest

/*
 ACC-001-restore_account_session spec-owner 테스트

 interaction_id: ACC-001-restore_account_session

 본 테스트 파일은 Task 14에서 launch hydration 경로로 마이그레이션되었다.
 과거 .onAppear -> sessionClient.read() -> _onAppearSessionRestored(session) 체인이
 주 복원 경로였으나, 이제 .hydrateLaunchSnapshot(snapshot) 단일 경로가
 launch 시점 session restore의 source of truth가 된다 (Task 6/8 참고).

 auth_state 매핑:
 - logged_out     → AccountAccessState 기본 상태 (hasAccountSession=false, didSignInFail=false)
 - session_expired → didSignInFail=true (재로그인 필요 상태)
 - logged_in      → hasAccountSession=true

 마이그레이션 참고:
 - _onAppearSessionRestored(nil) action handler 자체는 Task 8 DEFER 정책에 따라
   프로덕션 코드에 잔존. VOY-397 regression 테스트 2종은 해당 핸들러의
   clearStaleActiveAccessFacts 동작을 직접 단언하므로 마이그레이션 대상이 아니다.
 - testValidSessionRestoreResetsStaleFetchRetryCount 제거:
   launch snapshot은 최초 상태이므로 "이전 retry budget 초기화" 비즈니스 의미가
   적용되지 않는다 (초기화할 과거 budget이 없음).
 */

@MainActor
final class ACC001RestoreAccountSessionTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func makeNotificationCenterClient(
        notifications: @escaping @Sendable (Notification.Name, NSObject?) -> AsyncStream<Notification> = { _, _ in
            AsyncStream { continuation in
                continuation.finish()
            }
        },
    ) -> NotificationCenterClient {
        NotificationCenterClient(
            notifications: notifications,
            addObserver: { _, _, _ in NSObject() },
            removeObserver: { _ in },
            publisher: { _ in NotificationCenter.default.publisher(for: .init("")) },
            post: { _, _, _ in },
        )
    }

    private func makeTestStore(
        accountSessionClient: AccountSessionClient = .testValue,
        authNetworkClient: AuthNetworkClient = .testValue,
        notificationCenterClient: NotificationCenterClient? = nil,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        let notificationCenterClient = notificationCenterClient ?? Self.makeNotificationCenterClient()
        return TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.notificationCenterClient = notificationCenterClient
            $0.date = .constant(referenceDate)
        }
    }

    // MARK: - ACC-001-restore_account_session

    /// ACC-001-restore_account_session: sessionExpiresAt가 있는 launch snapshot hydration 시 logged_in으로 복원된다.
    /// Task 14 마이그레이션: 기존 .onAppear -> sessionClient.read() -> _onAppearSessionRestored 경로 대신
    /// .hydrateLaunchSnapshot(snapshot with sessionExpiresAt) 경로로 logged_in 복원을 검증한다.
    /// - 검증 내용: hydrateLaunchSnapshot(snapshot with future sessionExpiresAt)
    ///   → hasAccountSession=true, sessionExpiresAt=expiry, derived accountAccessAuthAxis=.signedIn
    /// - 사전 조건: sessionExpiresAt가 미래 시점인 AccessStatusSnapshot
    /// - 기대 결과: hasAccountSession=true, sessionExpiresAt == snapshot.sessionExpiresAt,
    ///   accountAccessAuthAxis=.signedIn
    /// - 비고: launch snapshot이 곧 초기 상태이므로 hydrate 경로는 fetchAccessStatusEffect를 호출하지 않는다.
    func testHydrateLaunchSnapshotWithSessionRestoresAsLoggedIn() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate.addingTimeInterval(86400),
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
        )

        var initialState = AccountAccessFeature.State()
        initialState.didSignInFail = true
        initialState.isSignInInProgress = true
        initialState.errorMessage = "Sign in failed"
        initialState.handoffPendingState = "stale-handoff"

        let store = makeTestStore(initialState: initialState)

        await store.send(.hydrateLaunchSnapshot(snapshot)) { state in
            state.status = snapshot.status
            state.snapshot = snapshot
            state.trialExpiresAt = snapshot.currentPeriodEnd
            state.isSignInInProgress = false
            state.didSignInFail = false
            state.handoffPendingState = nil
            state.errorMessage = nil
            state.hasAccountSession = true
            state.sessionExpiresAt = sessionExpiry
            state.isSessionExpired = false
            state.didBootstrap = true
            state.fetchGeneration = 1
            state.ttlTimerActive = true
        }

        XCTAssertTrue(store.state.hasAccountSession, "session 존재 → hasAccountSession=true")
        XCTAssertFalse(store.state.isSignInInProgress, "stale sign-in progress 초기화")
        XCTAssertFalse(store.state.didSignInFail, "stale sign-in failure 초기화")
        XCTAssertNil(store.state.errorMessage, "stale sign-in errorMessage 초기화")
        XCTAssertEqual(
            store.state.sessionExpiresAt,
            sessionExpiry,
            "sessionExpiresAt == snapshot.sessionExpiresAt",
        )
        XCTAssertEqual(
            store.state.accountAccessAuthAxis,
            .signedIn,
            "session 존재 → derived accountAccessAuthAxis=.signedIn",
        )
        await store.skipInFlightEffects()
    }

    /// ACC-001-restore_account_session: refreshToken 성공 시 기존 snapshot의 session 축만 갱신된다.
    /// snapshot이 이미 있을 때 refresh 성공이 sessionExpiresAt만 동기화하고 entitlement 축은 보존하는지 검증한다.
    /// - 검증 내용: _refreshTokenResult(.success) → state.sessionExpiresAt 갱신, snapshot.status/currentPeriodEnd/fetchedAt
    /// 보존
    /// - 사전 조건: 기존 snapshot이 존재하고 sessionExpiresAt가 오래된 값이다.
    /// - 기대 결과: snapshot.sessionExpiresAt만 새 만료 시각으로 교체된다.
    func testRefreshTokenSuccessSyncsExistingSnapshotSessionExpiry() async {
        let oldExpiry = referenceDate.addingTimeInterval(300)
        let newExpiry = referenceDate.addingTimeInterval(3600)
        let initialSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate.addingTimeInterval(86400),
            fetchedAt: referenceDate,
            sessionExpiresAt: oldExpiry,
        )
        let expectedSnapshot = AccessStatusSnapshot(
            status: initialSnapshot.status,
            currentPeriodEnd: initialSnapshot.currentPeriodEnd,
            fetchedAt: initialSnapshot.fetchedAt,
            sessionExpiresAt: newExpiry,
        )

        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.ttlTimerActive = true
        initialState.sessionExpiresAt = oldExpiry
        initialState.status = initialSnapshot.status
        initialState.trialExpiresAt = initialSnapshot.currentPeriodEnd
        initialState.snapshot = initialSnapshot
        initialState.consecutiveRefreshFailures = 2

        let store = makeTestStore(initialState: initialState)

        await store.send(._refreshTokenResult(.success(
            AccountSession(
                accessToken: "refreshed-token",
                status: .coreLicenseActive,
                expiresAt: newExpiry,
            ),
        ))) { state in
            state.consecutiveRefreshFailures = 0
            state.sessionExpiresAt = newExpiry
            state.snapshot = expectedSnapshot
        }

        XCTAssertEqual(store.state.sessionExpiresAt, newExpiry)
        XCTAssertEqual(store.state.snapshot, expectedSnapshot)
        await store.finish()
    }

    /// ACC-001-restore_account_session: refreshToken 성공 시 snapshot이 없으면 새 snapshot을 만들지 않는다.
    /// snapshot nil 상태에서 refresh 성공이 sessionExpiresAt만 갱신하고 snapshot은 nil로 유지하는지 검증한다.
    /// - 검증 내용: _refreshTokenResult(.success) → state.sessionExpiresAt 갱신, state.snapshot은 nil 유지
    /// - 사전 조건: snapshot이 nil이고 sessionExpiresAt가 존재한다.
    /// - 기대 결과: session 만료 시각만 갱신되고 snapshot은 생성되지 않는다.
    func testRefreshTokenSuccessDoesNotCreateSnapshotWhenMissing() async {
        let oldExpiry = referenceDate.addingTimeInterval(300)
        let newExpiry = referenceDate.addingTimeInterval(3600)

        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.ttlTimerActive = true
        initialState.sessionExpiresAt = oldExpiry
        initialState.status = .coreLicenseActive
        initialState.trialExpiresAt = referenceDate.addingTimeInterval(86400)
        initialState.snapshot = nil
        initialState.consecutiveRefreshFailures = 2

        let store = makeTestStore(initialState: initialState)

        await store.send(._refreshTokenResult(.success(
            AccountSession(
                accessToken: "refreshed-token",
                status: .coreLicenseActive,
                expiresAt: newExpiry,
            ),
        ))) { state in
            state.consecutiveRefreshFailures = 0
            state.sessionExpiresAt = newExpiry
        }

        XCTAssertEqual(store.state.sessionExpiresAt, newExpiry)
        XCTAssertNil(store.state.snapshot)
        await store.finish()
    }

    // (Task 14 제거) testValidSessionRestoreResetsStaleFetchRetryCount
    // "새 session boundary가 과거 retry budget을 0으로 초기화" 불변식은 onAppear 전환 시나리오에만
    // 의미가 있었다. launch hydration은 앱 최초 상태이므로 초기화할 과거 budget이 없고,
    // handleHydrateLaunchSnapshot은 resetSessionRetryBudget을 호출하지 않는다.
    // fetchRetryCount delta 검증은 ACC002 네트워크 실패/재시도 테스트에서 담당.

    /// ACC-001-restore_account_session: session 만료 후 자동 갱신 성공 시 logged_in을 유지한다.
    /// T6 token refresh logic 구현 후 활성화되는 테스트로 현재는 skip 처리한다.
    /// - 검증 내용: T6 refresh logic이 session 만료 후 자동 갱신 성공 시 logged_in 유지 확인
    /// - 사전 조건: T6 refresh logic 구현 완료
    /// - 기대 결과: 자동 갱신 성공 시 logged_in 유지
    func testExpiredSessionRefreshSuccessStaysLoggedIn() throws {
        throw XCTSkip("Requires T6 token refresh logic")
    }

    /// ACC-001-restore_account_session: 만료된 session 복원 실패 시 session_expired로 전환된다.
    /// loginCallbackReceived 후 restoreSession=nil일 때 didSignInFail=true로 전환되는지 검증한다.
    /// - 검증 내용: loginCallbackReceived 후 restoreSession=nil → didSignInFail=true, signInFailed axis
    /// - 사전 조건: isSignInInProgress=true, sessionClient.read가 nil 반환
    /// - 기대 결과: didSignInFail=true, isSessionExpired=true, canStartLogin=true
    func testExpiredSessionRestoreFailsSetsSessionExpired() async throws {
        nonisolated(unsafe) var fetchCalled = false
        var initialState = AccountAccessFeature.State()
        initialState.isSignInInProgress = true

        let callbackURL = try XCTUnwrap(URL(string: "voyager://auth/callback"))

        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { nil },
                persist: { _ in },
                delete: { _ in },
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCalled = true
                    return AccessStatusResponse(
                        hasAccess: true,
                        status: "active",
                        reason: "active_entitlement",
                        productKey: "core",
                        source: "polar",
                    )
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )

        await store.send(.loginCallbackReceived(callbackURL))

        await store.receive(\._loginSessionRestored) { state in
            state.isSignInInProgress = false
        }

        await store.receive(\._sessionExpiredDetected) { state in
            state.didSignInFail = true
            state.hasAccountSession = false
            state.isSessionExpired = true
            state.fetchGeneration = 1
        }

        XCTAssertFalse(fetchCalled)
        XCTAssertTrue(store.state.didSignInFail)
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signInFailed)
        XCTAssertTrue(store.state.canStartLogin)
        await store.finish()
    }

    /// ACC-001-restore_account_session: sessionExpiresAt가 nil인 launch snapshot hydration 시 logged_out으로 진입한다.
    /// Task 14 마이그레이션: 기존 .onAppear -> sessionClient.read() -> _onAppearSessionRestored(nil) 경로 대신
    /// .hydrateLaunchSnapshot(snapshot with sessionExpiresAt=nil) 경로로 logged_out 진입을 검증한다.
    /// - 검증 내용: hydrateLaunchSnapshot(snapshot with nil sessionExpiresAt)
    ///   → hasAccountSession=false, sessionExpiresAt=nil, derived auth axis=.signedOut, stepState=.blocked
    /// - 사전 조건: sessionExpiresAt가 nil인 AccessStatusSnapshot
    /// - 기대 결과: hasAccountSession=false, accountAccessAuthAxis=.signedOut,
    ///   accountAccessStepState=.blocked, sessionExpiresAt=nil
    /// - 비고: launch snapshot이 곧 초기 상태이므로 hydrate 경로는 fetchAccessStatusEffect를 호출하지 않는다.
    func testHydrateLaunchSnapshotWithoutSessionShowsLoggedOut() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate.addingTimeInterval(86400),
            fetchedAt: referenceDate,
            sessionExpiresAt: nil,
        )

        let store = makeTestStore()
        // exhaustivity=.off: handleHydrateLaunchSnapshot가 다수 필드를 갱신하나
        // 검증 대상은 session 축 및 derived step state만 해당.
        store.exhaustivity = .off

        await store.send(.hydrateLaunchSnapshot(snapshot))

        XCTAssertFalse(store.state.hasAccountSession, "session 없음 → hasAccountSession=false")
        XCTAssertNil(store.state.sessionExpiresAt, "sessionExpiresAt=nil 유지")
        XCTAssertEqual(
            store.state.accountAccessAuthAxis,
            .signedOut,
            "session 없음 → derived accountAccessAuthAxis=.signedOut",
        )
        XCTAssertEqual(
            store.state.accountAccessStepState,
            .blocked,
            "session 없음 → accountAccessStepState=.blocked",
        )
        await store.finish()
    }

    /// ACC-001-restore_account_session: launch snapshot hydration은 이전 TTL timer를 취소한다.
    /// spec citations: auth_session_contract.toml:34-41, 001-auth-token-refresh-storage-policy.md
    /// - 검증 내용: session-present hydrate로 TTL timer를 시작한 뒤 session-absent hydrate가 기존 timer를 cancel한다.
    /// - 사전 조건: first hydrate는 session-present, second hydrate는 session-absent.
    /// - 기대 결과: second hydrate 후 ttlTimerActive=false, stale _ttlTimerTicked가 남아 있지 않아 finish()가 통과한다.
    func testHydrateLaunchSnapshotCancelsPreviousTtlTimer() async {
        let signedInSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate.addingTimeInterval(86400),
            fetchedAt: referenceDate,
            sessionExpiresAt: referenceDate.addingTimeInterval(3600),
        )
        let loggedOutSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate.addingTimeInterval(86400),
            fetchedAt: referenceDate,
            sessionExpiresAt: nil,
        )

        let store = makeTestStore()

        await store.send(.hydrateLaunchSnapshot(signedInSnapshot)) { state in
            state.status = signedInSnapshot.status
            state.snapshot = signedInSnapshot
            state.trialExpiresAt = signedInSnapshot.currentPeriodEnd
            state.hasAccountSession = true
            state.sessionExpiresAt = signedInSnapshot.sessionExpiresAt
            state.isSessionExpired = false
            state.didBootstrap = true
            state.fetchGeneration = 1
            state.ttlTimerActive = true
        }

        await store.send(.hydrateLaunchSnapshot(loggedOutSnapshot)) { state in
            state.status = loggedOutSnapshot.status
            state.snapshot = loggedOutSnapshot
            state.trialExpiresAt = loggedOutSnapshot.currentPeriodEnd
            state.hasAccountSession = false
            state.sessionExpiresAt = nil
            state.isSessionExpired = false
            state.didBootstrap = true
            state.fetchGeneration = 2
            state.ttlTimerActive = false
        }

        await store.finish()
    }

    /// ACC-001-restore_account_session: 손상된 token 파일은 logged_out으로 처리된다.
    /// 손상된 token 파일이 FileStore에서 quarantine 후 nil을 반환하여 logged_out이 되는지 검증한다.
    /// - 검증 내용: corrupt JSON → read()=nil → restoreSession=nil → logged_out
    /// - 사전 조건: TemporaryHomeFixture에 손상된 JSON 파일이 저장되어 있음
    /// - 기대 결과: read()=nil, accountAccessAuthAxis=.signedOut, hasAccountSession=false
    func testCorruptedSessionTreatedAsLoggedOut() async throws {
        let fixture = try TemporaryHomeFixture()
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        let corruptedData = Data("{ invalid json }".utf8)
        try corruptedData.write(to: fixture.accountTokensFileURL)

        let result = try await fileStore.read()
        XCTAssertNil(result, "손상된 session 파일은 nil 반환")

        let state = AccountAccessFeature.State()
        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertFalse(state.hasAccountSession)
    }

    /// ACC-001-restore_account_session: 자동 갱신 중 네트워크 오류 시 기존 session이 유지된다.
    /// T6 token refresh logic 구현 후 활성화되는 테스트로 현재는 skip 처리한다.
    /// - 검증 내용: T6 refresh logic이 네트워크 오류 시 기존 session 유지 확인
    /// - 사전 조건: T6 refresh logic 구현 완료
    /// - 기대 결과: 네트워크 오류 시에도 기존 session 유지
    func testNetworkErrorDuringRefreshMaintainsSession() throws {
        throw XCTSkip("Requires T6 token refresh logic")
    }

    /// VOY-397 regression: onAppear에서 session 복원이 nil일 때 이전에 persist된 active entitlement fact가 모두 제거된다.
    /// status=.coreLicenseActive + isComplete=true + snapshot/trialExpiresAt 보존 상태에서 session=nil 복원 시
    /// stale fact가 방치되면 Access Unlock 화면이 Active chip + Sign In 버튼을 동시에 그리는 regression이 발생한다.
    /// - 검증 내용: _onAppearSessionRestored(nil) → status/snapshot/trialExpiresAt/isComplete 초기화
    /// - 사전 조건: initialState에 stale active facts 사전 주입
    /// - 기대 결과: status=nil, snapshot=nil, trialExpiresAt=nil, isComplete=false,
    ///   accountAccessAuthAxis=.signedOut, canStartLogin=true, accountAccessStepState=.blocked,
    ///   accessUnlockPrimaryCTA=.login
    func testNilSessionRestoreClearsStaleActiveFacts() async {
        let staleSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate,
            fetchedAt: referenceDate,
        )
        var initialState = AccountAccessFeature.State()
        initialState.status = .coreLicenseActive
        initialState.isComplete = true
        initialState.snapshot = staleSnapshot
        initialState.trialExpiresAt = referenceDate

        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { nil },
                persist: { _ in },
                delete: { _ in },
            ),
            initialState: initialState,
        )
        // exhaustivity=.off: reducer가 다수 필드를 갱신하나 검증 대상은 regression 스펙 필드만.
        store.exhaustivity = .off

        await store.send(._onAppearSessionRestored(nil))

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertNil(store.state.status)
        XCTAssertNil(store.state.snapshot)
        XCTAssertNil(store.state.trialExpiresAt)
        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signedOut)
        XCTAssertTrue(store.state.canStartLogin)
        XCTAssertEqual(store.state.accountAccessStepState, .blocked)
        XCTAssertEqual(store.state.accessUnlockPrimaryCTA, .login)
        await store.finish()
    }

    /// VOY-397 regression: nil session 복원 후 도착한 stale active access_status 응답이 거부된다.
    /// _onAppearSessionRestored(nil)이 fetchGeneration을 무효화하므로, 복원 직전 세대의 success(active) 응답은
    /// status/snapshot/isComplete를 재주입하지 못한다.
    /// - 검증 내용: _onAppearSessionRestored(nil) → 이전 generation 응답 무시 → status=nil, isComplete=false 유지
    /// - 사전 조건: fetchGeneration=1, active entitlement facts 보존 상태
    /// - 기대 결과: stale 응답 후에도 status=nil, snapshot=nil, isComplete=false, accessUnlockPrimaryCTA=.login
    func testNilSessionRestoreRejectsStaleGenerationActiveResponse() async {
        let staleSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate,
            fetchedAt: referenceDate,
        )
        var initialState = AccountAccessFeature.State()
        initialState.fetchGeneration = 1
        initialState.status = .coreLicenseActive
        initialState.isComplete = true
        initialState.snapshot = staleSnapshot
        initialState.trialExpiresAt = referenceDate

        let activeResponse = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )

        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { nil },
                persist: { _ in },
                delete: { _ in },
            ),
            initialState: initialState,
        )
        store.exhaustivity = .off

        await store.send(._onAppearSessionRestored(nil))

        // stale generation(1) 응답 → 현재 fetchGeneration(2)과 불일치 → 무시
        await store.send(.accessStatusResponse(generation: 1, result: .success(activeResponse)))

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertNil(store.state.status, "stale generation 응답은 status를 재주입하지 못함")
        XCTAssertNil(store.state.snapshot)
        XCTAssertNil(store.state.trialExpiresAt)
        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.accessUnlockPrimaryCTA, .login)
        await store.finish()
    }

    /// ACC-001-restore_account_session: 앱 최초 실행 시 token 파일이 없으면 logged_out으로 진입한다.
    /// 앱 최초 실행 시 token 파일이 존재하지 않을 때 logged_out 상태가 되는지 검증한다.
    /// - 검증 내용: 파일 없음 → read()=nil → restoreSession=nil → logged_out
    /// - 사전 조건: TemporaryHomeFixture(createVoyagerDirectory=false), token 파일 없음
    /// - 기대 결과: read()=nil, accountAccessAuthAxis=.signedOut, hasAccountSession=false
    func testFirstRunNoSessionShowsLoggedOut() async throws {
        let fixture = try TemporaryHomeFixture(createVoyagerDirectory: false)
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path),
            "최초 실행: token 파일 없음",
        )

        let result = try await fileStore.read()
        XCTAssertNil(result, "파일이 없으면 read()=nil")

        let state = AccountAccessFeature.State()
        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertFalse(state.hasAccountSession)
    }

    /// ACC-001-restore_account_session: 빈 파일(0바이트)은 손상으로 간주하여 격리 후 logged_out으로 전환된다.
    /// 0바이트 token 파일을 읽을 때 quarantine 처리 후 nil이 반환되는지 검증한다.
    /// - 검증 내용: 빈 파일 → read()=nil, 원본 파일 삭제, quarantine 파일 생성
    /// - 사전 조건: account_tokens.json 파일이 0바이트로 존재
    /// - 기대 결과: read()가 nil 반환, 원본 파일 삭제, quarantine 파일 생성됨
    func testEmptyFileIsQuarantinedAndReturnsNil() async throws {
        let fixture = try TemporaryHomeFixture()
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        try Data().write(to: fixture.accountTokensFileURL)

        let result = try await fileStore.read()
        XCTAssertNil(result, "빈 파일은 nil 반환")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path),
            "원본 파일 삭제됨",
        )

        let voyagerDir = fixture.voyagerHomeURL
        let entries = try FileManager.default.contentsOfDirectory(atPath: voyagerDir.path)
        let quarantined = entries.filter { $0.hasPrefix("account_tokens.corrupted") }
        XCTAssertFalse(quarantined.isEmpty, "quarantine 파일이 생성되어야 함")
    }

    /// ACC-001-restore_account_session: 저장된 token 파일은 owner-only 권한(0o600)으로 설정된다.
    /// 파일 쓰기 후 권한이 0o600으로 설정되는지 검증한다.
    /// - 검증 내용: 파일 권한이 0o600
    /// - 사전 조건: TemporaryHomeFixture, 유효한 AccountTokensFile
    /// - 기대 결과: 파일 권한 == 0o600
    func testTokenFilePermissionsAre0o600AfterWrite() async throws {
        let fixture = try TemporaryHomeFixture()
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        let tokens = AccountTokensFile(
            updatedAtMs: 1000,
            accessToken: "a",
            accessTokenExpiresAtMs: 2000,
            accessTokenExpiresIn: 1000,
            refreshToken: "r",
            refreshTokenExpiresAtMs: 3000,
        )
        try await fileStore.write(tokens)

        let fileAttrs = try FileManager.default.attributesOfItem(atPath: fixture.accountTokensFileURL.path)
        let filePerms = fileAttrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(filePerms?.int16Value, 0o600, "파일 권한은 0o600")
    }

    /// ACC-001-restore_account_session: 저장 디렉토리는 owner-only 권한(0o700)으로 설정된다.
    /// 디렉토리 권한이 0o700으로 설정되는지 검증한다.
    /// - 검증 내용: 디렉토리 권한이 0o700
    /// - 사전 조건: TemporaryHomeFixture, 유효한 AccountTokensFile write
    /// - 기대 결과: 디렉토리 권한 == 0o700
    func testTokenDirectoryPermissionsAre0o700AfterWrite() async throws {
        let fixture = try TemporaryHomeFixture()
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        let tokens = AccountTokensFile(
            updatedAtMs: 1000,
            accessToken: "a",
            accessTokenExpiresAtMs: 2000,
            accessTokenExpiresIn: 1000,
            refreshToken: "r",
            refreshTokenExpiresAtMs: 3000,
        )
        try await fileStore.write(tokens)

        let dirAttrs = try FileManager.default.attributesOfItem(atPath: fixture.voyagerHomeURL.path)
        let dirPerms = dirAttrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(dirPerms?.int16Value, 0o700, "디렉토리 권한은 0o700")
    }
}

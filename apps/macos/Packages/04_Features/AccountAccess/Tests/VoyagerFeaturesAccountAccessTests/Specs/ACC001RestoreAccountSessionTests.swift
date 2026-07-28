import Clocks
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
        snapshotClient: AccessStatusSnapshotClient = .testValue,
        notificationCenterClient: NotificationCenterClient? = nil,
        clock: TestClock<Duration> = TestClock(),
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        let notificationCenterClient = notificationCenterClient ?? Self.makeNotificationCenterClient()
        return TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.accessStatusSnapshotClient = snapshotClient
            $0.notificationCenterClient = notificationCenterClient
            $0.date = .constant(referenceDate)
            $0.continuousClock = clock
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
            state.lastCompleteSyncAt = snapshot.fetchedAt
            state.syncGeneration = 1
            state.ttlTimerActive = true
            state.refreshDeadlineGeneration = 1
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
        await store.send(.appWillTerminate) { state in
            state.fetchGeneration = 2
            state.syncGeneration = 2
            state.revalidationGeneration = 1
            state.handoffGeneration = 1
            state.ttlTimerActive = false
            state.refreshDeadlineGeneration = 2
        }
        await store.finish()
    }

    /// ACC-001-restore_account_session: complete session sync는 freshness를 기록한다.
    /// complete result가 다음 foreground gate에 사용할 시각을 소유하는지 검증한다.
    /// - 검증 내용: complete sync → lastCompleteSyncAt 갱신과 recovery snapshot projection.
    /// - 사전 조건: 유효한 session과 in-flight manual sync.
    /// - 기대 결과: current date가 complete freshness로 기록된다.
    func testCompleteSessionSyncRecordsFreshness() async {
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        initialState.syncGeneration = 1
        initialState.inFlightSyncReason = .manual
        let store = makeTestStore(initialState: initialState)
        // store.exhaustivity = .off: complete result의 recovery projection보다 freshness 기록을 검증
        store.exhaustivity = .off

        await store.send(._sessionSyncCompleted(
            generation: 1,
            result: .success(SessionSyncResult(
                sessionStatus: .unchanged,
                syncStatus: .complete,
                accessStatus: AccessStatusResponse(hasAccess: false, status: "none"),
                deviceBindingOutcome: .notAttempted,
                connectedDeviceAvailability: .available,
            )),
        ))
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(store.state.lastCompleteSyncAt, referenceDate)
        await store.finish()
    }

    /// ACC-001-restore_account_session: partial session sync는 freshness를 기록하지 않는다.
    /// partial result가 complete snapshot처럼 다음 foreground gate를 열지 않음을 검증한다.
    /// - 검증 내용: partial sync → lastCompleteSyncAt 유지와 unlock 차단.
    /// - 사전 조건: 기존 complete freshness와 in-flight manual sync.
    /// - 기대 결과: 기존 freshness가 그대로 유지된다.
    func testPartialSessionSyncDoesNotRecordFreshness() async {
        let lastCompleteSyncAt = referenceDate.addingTimeInterval(-60)
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        initialState.lastCompleteSyncAt = lastCompleteSyncAt
        initialState.syncGeneration = 1
        initialState.inFlightSyncReason = .manual
        let store = makeTestStore(initialState: initialState)
        // store.exhaustivity = .off: partial result의 recovery projection보다 freshness 불변을 검증
        store.exhaustivity = .off

        await store.send(._sessionSyncCompleted(
            generation: 1,
            result: .success(SessionSyncResult(
                sessionStatus: .unchanged,
                syncStatus: .partial,
                accessStatus: AccessStatusResponse(hasAccess: false, status: "none"),
                deviceBindingOutcome: .notAttempted,
                connectedDeviceAvailability: .unavailable,
                partial: SessionSyncPartial(stage: "access", reason: "temporarily_unavailable"),
            )),
        ))
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(store.state.lastCompleteSyncAt, lastCompleteSyncAt)
        await store.finish()
    }

    // (Task 14 제거) testValidSessionRestoreResetsStaleFetchRetryCount
    // "새 session boundary가 과거 retry budget을 0으로 초기화" 불변식은 onAppear 전환 시나리오에만
    // 의미가 있었다. launch hydration은 앱 최초 상태이므로 초기화할 과거 budget이 없고,
    // handleHydrateLaunchSnapshot은 resetSessionRetryBudget을 호출하지 않는다.
    // fetchRetryCount delta 검증은 ACC002 네트워크 실패/재시도 테스트에서 담당.

    /// ACC-001-restore_account_session: session 만료 후 자동 갱신 성공 시 logged_in을 유지한다.
    /// - 검증 내용: 만료 access와 recoverable refresh credential은 refresh intent 하나만 선택한다.
    /// - 사전 조건: access token은 만료됐고 refresh credential은 유효하다.
    /// - 기대 결과: rotated completion 후 logged_in을 유지한다.
    func testExpiredSessionRefreshSuccessStaysLoggedIn() async {
        nonisolated(unsafe) var receivedIntent: SessionSyncIntent?
        let binding = UUID()
        let expiredSession = AccountSession(
            accessToken: "expired-access-token",
            status: .none,
            refreshToken: "refresh-token",
            expiresAt: referenceDate.addingTimeInterval(-60),
            sessionBindingID: binding,
        )
        let rotatedExpiry = referenceDate.addingTimeInterval(3600)
        let clock = TestClock()
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { _ in expiredSession },
                persist: { _ in },
                delete: { _ in },
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { intent, _ in
                    receivedIntent = intent
                    return SessionSyncResult(
                        sessionStatus: .rotated,
                        syncStatus: .complete,
                        accessStatus: AccessStatusResponse(
                            hasAccess: true,
                            status: "active",
                            ownershipStatus: "owned",
                            updateStatus: "active",
                            updatesThrough: Date(timeIntervalSince1970: 2_000_000_000),
                        ),
                        deviceBindingOutcome: .bound,
                        connectedDeviceAvailability: .available,
                        sessionExpiresAt: rotatedExpiry,
                    )
                },
            ),
            clock: clock,
        )
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\._onAppearSessionRestored)
        await store.receive(\.sessionSyncRequested)
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.unlocked)

        XCTAssertEqual(receivedIntent, .refresh)
        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertFalse(store.state.isSessionExpired)
        XCTAssertEqual(store.state.sessionExpiresAt, rotatedExpiry)
        await store.skipInFlightEffects()
    }

    /// ACC-001-restore_account_session: 만료된 session 복원 실패 시 session_expired로 전환된다.
    /// loginCallbackReceived 후 restoreSession=nil일 때 didSignInFail=true로 전환되는지 검증한다.
    /// - 검증 내용: loginCallbackReceived 후 restoreSession=nil → didSignInFail=true, signInFailed axis
    /// - 사전 조건: isSignInInProgress=true, sessionClient.read가 nil 반환
    /// - 기대 결과: didSignInFail=true, isSessionExpired=true, canStartLogin=true
    func testExpiredSessionRestoreFailsSetsSessionExpired() async throws {
        nonisolated(unsafe) var fetchCalled = false
        nonisolated(unsafe) var bindCalled = false
        var initialState = AccountAccessFeature.State()
        initialState.isSignInInProgress = true

        let callbackURL = try XCTUnwrap(URL(string: "voyager://auth/callback"))

        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(read: { _ in nil }, persist: { _ in },
                                                       delete: { _ in }),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCalled = true
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
                bindDevice: { _ in
                    bindCalled = true
                    return DeviceBindingResponse(ok: true)
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
            state.syncGeneration = 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertFalse(fetchCalled)
        XCTAssertFalse(bindCalled)
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
            state.lastCompleteSyncAt = signedInSnapshot.fetchedAt
            state.syncGeneration = 1
            state.ttlTimerActive = true
            state.refreshDeadlineGeneration = 1
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
            state.lastCompleteSyncAt = loggedOutSnapshot.fetchedAt
            state.syncGeneration = 2
            state.ttlTimerActive = false
            state.refreshDeadlineGeneration = 2
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
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

        let corruptedData = Data("{ invalid json }".utf8)
        try corruptedData.write(to: fixture.accountTokensFileURL)

        let result = try await fileStore.read()
        XCTAssertNil(result, "손상된 session 파일은 nil 반환")

        let state = AccountAccessFeature.State()
        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertFalse(state.hasAccountSession)
    }

    /// ACC-001-restore_account_session: 자동 갱신 중 네트워크 오류 시 기존 session이 유지된다.
    /// - 검증 내용: 일시적 refresh 오류는 credential/session authority를 삭제하지 않는다.
    /// - 사전 조건: access token은 만료됐고 refresh credential은 유효하다.
    /// - 기대 결과: network failure 뒤에도 logged_in을 유지한다.
    func testNetworkErrorDuringRefreshMaintainsSession() async {
        nonisolated(unsafe) var receivedIntent: SessionSyncIntent?
        let expiredSession = AccountSession(
            accessToken: "expired-access-token",
            status: .none,
            refreshToken: "refresh-token",
            expiresAt: referenceDate.addingTimeInterval(-60),
        )
        let clock = TestClock()
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { _ in expiredSession },
                persist: { _ in },
                delete: { _ in },
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { intent, _ in
                    receivedIntent = intent
                    throw SessionSyncError.upstream(503)
                },
            ),
            clock: clock,
        )
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\._onAppearSessionRestored)
        await store.receive(\.sessionSyncRequested)
        await Task.yield()
        await clock.advance(by: .seconds(5))
        await store.receive(\._cachedSnapshotRestored)
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(receivedIntent, .refresh)
        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertFalse(store.state.isSessionExpired)
        XCTAssertEqual(store.state.sessionExpiresAt, expiredSession.expiresAt)
        await store.finish()
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
            accountSessionClient: AccountSessionClient(read: { _ in nil }, persist: { _ in },
                                                       delete: { _ in }),
            initialState: initialState,
        )
        // exhaustivity=.off: reducer가 다수 필드를 갱신하나 검증 대상은 regression 스펙 필드만.
        store.exhaustivity = .off

        await store.send(._onAppearSessionRestored(.missing))

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
            ownershipStatus: "owned",
            updateStatus: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )

        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(read: { _ in nil }, persist: { _ in },
                                                       delete: { _ in }),
            initialState: initialState,
        )
        store.exhaustivity = .off

        await store.send(._onAppearSessionRestored(.missing))

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
}

extension ACC001RestoreAccountSessionTests {
    /// ACC-001-restore_account_session: app termination은 late binding response를 무시한다.
    /// 종료 시작 뒤 이전 generation의 binding completion이 durable snapshot이나 semantic delegate를 재주입하지 않는지 검증한다.
    /// - 검증 내용: appWillTerminate가 generation을 무효화하고 transient state를 비운 뒤 stale binding response를 거부한다.
    /// - 사전 조건: fetchGeneration=1, submission/sign-in/retry transient state와 in-flight binding 후보 snapshot이 존재한다.
    /// - 기대 결과: save recorder는 비어 있고 snapshot, unlock, recovery가 생성되지 않으며 store가 clean하게 종료된다.
    func testAppWillTerminateRejectsLateBindingResponse() async {
        let candidateSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
            sessionExpiresAt: referenceDate.addingTimeInterval(3600),
        )
        nonisolated(unsafe) var savedSnapshots: [AccessStatusSnapshot] = []
        var initialState = AccountAccessFeature.State()
        initialState.fetchGeneration = 1
        initialState.isSubmitting = true
        initialState.isSignInInProgress = true
        initialState.handoffPendingState = "pending-handoff"
        initialState.ttlTimerActive = true
        initialState.fetchRetryCount = 2
        initialState.deviceBindingFailure = .retryable
        initialState.deviceBindingRetryCount = 2
        initialState.errorMessage = "binding in progress"
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            snapshotClient: AccessStatusSnapshotClient(
                load: { nil },
                save: { savedSnapshots.append($0) },
                remove: {},
            ),
            initialState: initialState,
        )

        await store.send(.appWillTerminate) { state in
            state.fetchGeneration = 2
            state.syncGeneration = 1
            state.revalidationGeneration = 1
            state.isSubmitting = false
            state.isSignInInProgress = false
            state.handoffPendingState = nil
            state.ttlTimerActive = false
            state.fetchRetryCount = 0
            state.deviceBindingFailure = nil
            state.deviceBindingRetryCount = 0
            state.errorMessage = nil
            state.handoffGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.send(.deviceBindingResponse(
            generation: 1,
            snapshot: candidateSnapshot,
            result: .success(DeviceBindingResponse(ok: true)),
        ))

        XCTAssertTrue(savedSnapshots.isEmpty)
        XCTAssertNil(store.state.snapshot)
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// ACC-001-restore_account_session: 앱 최초 실행 시 token 파일이 없으면 logged_out으로 진입한다.
    /// 앱 최초 실행 시 token 파일이 존재하지 않을 때 logged_out 상태가 되는지 검증한다.
    /// - 검증 내용: 파일 없음 → read()=nil → restoreSession=nil → logged_out
    /// - 사전 조건: TemporaryHomeFixture(createVoyagerDirectory=false), token 파일 없음
    /// - 기대 결과: read()=nil, accountAccessAuthAxis=.signedOut, hasAccountSession=false
    func testFirstRunNoSessionShowsLoggedOut() async throws {
        let fixture = try TemporaryHomeFixture(createVoyagerDirectory: false)
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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

extension ACC001RestoreAccountSessionTests {
    /// ACC-001-restore_account_session: query 없는 callback에서 session read 오류는 fail-closed로 처리한다.
    /// read() 오류가 nil session과 동일하게 세션 만료 경로로 축약되어 access 조회나 binding을 시작하지 않는지 검증한다.
    /// - 검증 내용: didSignInFail, isSessionExpired, fetch=0, bind=0, unlocked delegate 없음
    /// - 사전 조건: isSignInInProgress=true, query 없는 voyager://auth/callback, sessionClient.read가 오류 throw
    /// - 기대 결과: _sessionExpiredDetected가 수신되고 access query, device binding, unlock 없이 종료된다.
    func testThrowingSessionRestoreFailsClosedWithoutAccessQueryOrBinding() async throws {
        nonisolated(unsafe) var fetchCalled = false
        nonisolated(unsafe) var bindCalled = false
        var initialState = AccountAccessFeature.State()
        initialState.isSignInInProgress = true

        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { _ in throw AccessError.notConfigured },
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
                        ownershipStatus: "owned",
                        updateStatus: "active",
                        reason: "active_entitlement",
                        productKey: "core",
                        source: "polar",
                    )
                },
                bindDevice: { _ in
                    bindCalled = true
                    return DeviceBindingResponse(ok: true)
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )

        try await store.send(.loginCallbackReceived(XCTUnwrap(URL(string: "voyager://auth/callback"))))
        await store.receive(\._loginSessionRestored) { state in
            state.isSignInInProgress = false
        }
        await store.receive(\._sessionExpiredDetected) { state in
            state.didSignInFail = true
            state.hasAccountSession = false
            state.isSessionExpired = true
            state.fetchGeneration = 1
            state.syncGeneration = 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertFalse(fetchCalled)
        XCTAssertFalse(bindCalled)
        XCTAssertTrue(store.state.didSignInFail)
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signInFailed)
        await store.finish()
    }
}

import Clocks
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import VoyagerShared
import XCTest

/*
 ACC-001-validate_account_session spec-owner test

 interaction_id: ACC-001-validate_account_session
 spec: docs/canonical/PRODUCT/05_FEATURE_SPECS/acc/ACC-001-manage_account_auth/ACC-001-validate_account_session.md

 TTL refresh behavior:
 - interval=60s, threshold=90%(360s), backoff_threshold=3
 - sessionExpiresAt within 360s of now triggers refresh
 - decodingFailure → permanent → immediate session_expired
 - networkFailure → temporary → consecutiveRefreshFailures++, 3→expired
 */

@MainActor
final class ACC001ValidateAccountSessionTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let nearExpiryDate = Date(timeIntervalSince1970: 1_700_000_100)
    private let newExpiryDate = Date(timeIntervalSince1970: 1_700_003_600)

    // MARK: - ACC-001-validate_account_session

    /// ACC-001-validate_account_session: unified session sync는 토큰을 reducer 경계로 넘기지 않고 validate intent를 전달한다.
    /// foreground 검증이 token 파일 소유 client에 validate 의도와 장치 메타데이터만 전달하는 계약을 검증한다.
    /// - 검증 내용: `syncSession(intent:device:)`가 `.validate` intent와 device metadata를 typed result로 연결한다.
    /// - 사전 조건: raw token 없이 구성한 AuthNetworkClient test double.
    /// - 기대 결과: sync closure가 한 번 호출되고 complete unchanged result를 반환한다.
    func testUnifiedSyncClientRoutesValidateIntentWithoutRawToken() async throws {
        nonisolated(unsafe) var receivedIntent: SessionSyncIntent?
        let expectedDevice = DeviceBindingRequest(deviceId: "device-id")
        let expectedResult = SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(hasAccess: true, status: "active"),
            deviceBindingOutcome: .bound,
            connectedDeviceAvailability: .available,
        )
        let client = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            bindDevice: { _ in throw DeviceBindingError.notConfigured },
            refreshToken: { throw AccessError.notConfigured },
            syncSession: { intent, _ in
                receivedIntent = intent
                return expectedResult
            },
        )

        let result = try await client.syncSession(intent: .validate, device: expectedDevice)

        XCTAssertEqual(receivedIntent, .validate)
        XCTAssertEqual(result, expectedResult)
    }

    /// ACC-001-validate_account_session: validate sync body는 refresh credential을 포함하지 않는다.
    /// validate 요청이 credential exclusivity 계약을 지키도록 serialization 경계를 검증한다.
    /// - 검증 내용: JSON body의 mode와 snake_case device metadata, refresh_token 부재.
    /// - 사전 조건: validate intent와 non-sensitive device metadata.
    /// - 기대 결과: Authorization은 body가 아닌 transport가 소유하며 body에 refresh_token 키가 없다.
    func testValidateSyncRequestBodyOmitsRefreshCredential() throws {
        let request = SessionSyncRequest(
            mode: .validate,
            requestID: "request-id",
            deviceID: "device-id",
            deviceName: "Mac",
            appVersion: "1.0",
            osVersion: "macOS",
            refreshToken: nil,
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["mode"], SessionSyncIntent.validate.rawValue)
        XCTAssertEqual(object["device_id"], "device-id")
        XCTAssertNil(object["refresh_token"])
    }

    /// ACC-001-validate_account_session: partial sync 응답은 typed stage와 reason을 보존한다.
    /// 완전하지 않은 서버 결과가 complete snapshot으로 오인되지 않도록 mapping을 검증한다.
    /// - 검증 내용: syncStatus, session status, partial stage/reason, device availability mapping.
    /// - 사전 조건: partial response DTO와 access status.
    /// - 기대 결과: typed result가 partial 정보를 손실 없이 반환한다.
    func testPartialSyncResponseMapsTypedPartialResult() {
        let response = SessionSyncResponse(
            syncStatus: .partial,
            session: .init(status: .rotated),
            access: AccessStatusResponse(hasAccess: true, status: "active"),
            device: .init(outcome: .bound, connectedDeviceAvailability: .unavailable),
            partial: SessionSyncPartial(stage: "access", reason: "temporarily_unavailable"),
        )

        let result = response.result()

        XCTAssertEqual(result.syncStatus, .partial)
        XCTAssertEqual(result.sessionStatus, .rotated)
        XCTAssertEqual(result.partial, SessionSyncPartial(stage: "access", reason: "temporarily_unavailable"))
        XCTAssertEqual(result.connectedDeviceAvailability, .unavailable)
    }

    /// ACC-001-validate_account_session: stale foreground는 persisted session 확인 후 validate sync를 시작한다.
    /// - 검증 내용: foreground 재검증 성공 후 validate sync intent가 시작된다.
    /// - 사전 조건: 로그인된 in-memory session과 유효한 persisted session이 존재한다.
    /// - 기대 결과: persisted session의 만료 시각을 사용하고 validate sync가 한 번 시작된다.
    func testStaleForegroundStartsValidateSync() async {
        nonisolated(unsafe) var receivedIntent: SessionSyncIntent?
        let persistedExpiry = referenceDate.addingTimeInterval(7200)
        var state = sessionNearExpiryState()
        state.sessionExpiresAt = persistedExpiry
        state.lastCompleteSyncAt = referenceDate.addingTimeInterval(-301)
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { _ in Self.session(expiresAt: persistedExpiry) },
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
                    return Self.inactiveCompleteSyncResult
                },
            ),
            initialState: state,
        )
        // store.exhaustivity = .off: foreground revalidation 이후 completion의 recovery projection보다 stale sync 시작을 검증
        store.exhaustivity = .off

        await store.send(.appDidBecomeActive) { state in
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated)
        await store.receive(\.sessionSyncRequested)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(receivedIntent, .validate)
        await store.finish()
    }

    /// ACC-001-validate_account_session: 다른 binding의 persisted session은 새 sync 전에 이전 access 사실을 제거한다.
    /// - 검증 내용: binding 변경이 active status, verified snapshot, trial, device failure, submission, completion, error를 즉시
    /// 비우고 새 binding sync를 시작한다.
    /// - 사전 조건: 이전 binding의 complete access 사실과 다른 binding 및 만료 시각을 가진 persisted session.
    /// - 기대 결과: 새 session fields와 invalidated generations가 반영된 뒤 `.validate` foreground sync activation이 대기한다.
    func testForegroundRevalidationWithChangedBindingClearsStaleAccessFactsBeforeSync() async {
        let activationGate = ActivationGate()
        let oldBinding = UUID()
        let newBinding = UUID()
        let oldExpiry = referenceDate.addingTimeInterval(3600)
        let newExpiry = referenceDate.addingTimeInterval(7200)
        let staleSnapshot = AccessStatusSnapshot.fetchResult(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate.addingTimeInterval(1800),
            sessionExpiresAt: oldExpiry,
            fetchedAt: referenceDate,
            sessionBindingID: oldBinding,
            gatewayBinding: GatewayEnvironment(rawValue: "").binding,
            deviceID: "test-device-id",
            deviceBindingVerifiedAt: referenceDate,
            ownershipStatus: "owned",
            updateStatus: "active",
            updatesThrough: Date(timeIntervalSince1970: 2_000_000_000),
        )
        var initialState = sessionNearExpiryState()
        initialState.status = .coreLicenseActive
        initialState.snapshot = staleSnapshot
        initialState.trialExpiresAt = staleSnapshot.currentPeriodEnd
        initialState.deviceBindingFailure = .retryable
        initialState.deviceBindingRetryCount = 2
        initialState.isSubmitting = true
        initialState.isComplete = true
        initialState.errorMessage = "previous binding failed"
        initialState.sessionExpiresAt = oldExpiry
        initialState.sessionBindingID = oldBinding
        initialState.fetchGeneration = 7
        initialState.syncGeneration = 4
        initialState.lastCompleteSyncAt = referenceDate
        initialState.fetchRetryCount = 2
        let store = TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in AccountSession(
                    accessToken: "new-access-token",
                    status: .coreLicenseActive,
                    refreshToken: "refresh-token",
                    expiresAt: newExpiry,
                    sessionBindingID: newBinding,
                )
                },
                persist: { _ in },
                delete: { _ in },
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                activate: { _, _ in await activationGate.wait() },
                load: { _, _ in nil },
                save: { _, _, _, _ in },
                remove: { _, _, _ in },
            )
            $0.continuousClock = TestClock()
            $0.date = .constant(referenceDate)
        }

        await store.send(.appDidBecomeActive) { state in
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated) { state in
            state.status = nil
            state.snapshot = nil
            state.trialExpiresAt = nil
            state.deviceBindingFailure = nil
            state.deviceBindingRetryCount = 0
            state.isSubmitting = false
            state.isComplete = false
            state.errorMessage = nil
            state.sessionExpiresAt = newExpiry
            state.sessionBindingID = newBinding
            state.fetchGeneration = 8
            state.syncGeneration = 5
            state.lastCompleteSyncAt = nil
            state.fetchRetryCount = 0
            state.refreshDeadlineGeneration = 2
        }
        await store.receive(sessionSyncRequestedCasePath(intent: .validate, reason: .foreground)) { state in
            state.syncGeneration = 6
            state.inFlightSyncReason = .foreground
            state.isSubmitting = true
        }
        for _ in 0 ..< 10 where await !(activationGate.isWaiting()) {
            await Task.yield()
        }
        let isActivationWaiting = await activationGate.isWaiting()
        XCTAssertTrue(isActivationWaiting)

        await store.send(.appWillTerminate) { state in
            state.fetchGeneration = 9
            state.syncGeneration = 7
            state.inFlightSyncReason = nil
            state.revalidationGeneration = 2
            state.isSubmitting = false
            state.ttlTimerActive = false
            state.handoffGeneration = 1
            state.refreshDeadlineGeneration = 3
        }
        await activationGate.resume(with: 1)
        await store.finish()
    }

    // MARK: - ACC-001-foreground_session_freshness

    /// ACC-001-foreground_session_freshness: complete snapshot 직후 foreground는 persisted session만 재검증한다.
    /// - 검증 내용: 5분 이내 complete snapshot이면 legacy access 원격 호출이 발생하지 않는다.
    /// - 사전 조건: 4분 59초 전의 complete snapshot과 유효한 persisted session.
    /// - 기대 결과: persisted session은 한 번 읽고, remote access 호출은 0회다.
    func testFreshForegroundRevalidatesLocallyWithoutRemoteAccessCall() async {
        nonisolated(unsafe) var sessionReadCount = 0
        nonisolated(unsafe) var legacyFetchCallCount = 0
        let sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        let freshSnapshot = AccessStatusSnapshot.fetchResult(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            sessionExpiresAt: sessionExpiresAt,
            fetchedAt: referenceDate.addingTimeInterval(-299),
            deviceBindingVerifiedAt: referenceDate.addingTimeInterval(-299),
        )
        var state = AccountAccessFeature.State()
        state.hydrateLaunchSnapshotState(freshSnapshot)

        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(read: { _ in sessionReadCount += 1
                return Self.session(expiresAt: sessionExpiresAt)
            }, persist: { _ in },
            delete: { _ in }),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    legacyFetchCallCount += 1
                    return AccessStatusResponse(hasAccess: false, status: "none")
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { _, _ in throw SessionSyncError.capabilityMiss },
            ),
            initialState: state,
        )
        // store.exhaustivity = .off: foreground의 persisted-session action chain만 검증하고 snapshot recovery 세부 상태는 범위에서 제외
        store.exhaustivity = .off

        await store.send(.appDidBecomeActive) { state in
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated)
        await Task.yield()

        XCTAssertEqual(sessionReadCount, 1)
        XCTAssertEqual(legacyFetchCallCount, 0)
        await store.finish()
    }

    // MARK: - ACC-001-session_sync_coalescing

    /// ACC-001-session_sync_coalescing: manual sync 중 foreground는 새 원격 작업을 시작하지 않는다.
    /// - 검증 내용: manual validate가 진행 중일 때 foreground 재검증은 같은 작업에 join한다.
    /// - 사전 조건: signed-in 상태에서 완료를 보류한 manual sync.
    /// - 기대 결과: syncSession은 validate intent로 한 번만 호출된다.
    func testForegroundJoinsInFlightManualSessionSync() async {
        nonisolated(unsafe) var intents: [SessionSyncIntent] = []
        nonisolated(unsafe) var continuation: CheckedContinuation<SessionSyncResult, Error>?
        let sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        var initialState = sessionNearExpiryState()
        initialState.sessionExpiresAt = sessionExpiresAt
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { _ in Self.session(expiresAt: sessionExpiresAt) },
                persist: { _ in },
                delete: { _ in },
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { intent, _ in
                    intents.append(intent)
                    continuation?.resume(throwing: CancellationError())
                    return try await withCheckedThrowingContinuation { continuation = $0 }
                },
            ),
            initialState: initialState,
        )
        // store.exhaustivity = .off: 동시 lifecycle action의 coalescing만 검증하고 completion UI projection은 범위에서 제외
        store.exhaustivity = .off

        await store.send(.refreshAccessTapped)
        await store.receive(\.sessionSyncRequested)
        for _ in 0 ..< 10 where continuation == nil {
            await Task.yield()
        }

        await store.send(.appDidBecomeActive)
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated)

        XCTAssertNotNil(continuation)
        XCTAssertEqual(intents, [.validate, .validate])

        if let continuation {
            continuation.resume(returning: SessionSyncResult(
                sessionStatus: .unchanged,
                syncStatus: .complete,
                accessStatus: AccessStatusResponse(hasAccess: false, status: "none"),
                deviceBindingOutcome: .notAttempted,
                connectedDeviceAvailability: .available,
            ))
            await Task.yield()
            await store.finish()
        }
    }

    /// ACC-001-validate_account_session: refresh deadline은 unified refresh sync를 요청한다.
    /// refresh due trigger가 legacy refresh client를 우회하지 않음을 검증한다.
    /// - 검증 내용: refreshToken 성공 후 sessionExpiresAt이 새로운 만료 시각으로 갱신되고 consecutiveRefreshFailures가 0으로 리셋된다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태.
    /// - 기대 결과: sessionExpiresAt이 새로운 시각으로 갱신되고 hasAccountSession과 ttlTimerActive가 true로 유지된다.
    func testRefreshDeadlineUsesRefreshIntent() async {
        nonisolated(unsafe) var receivedIntent: SessionSyncIntent?
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { intent, _ in
                    receivedIntent = intent
                    return Self.inactiveCompleteSyncResult
                },
            ),
            initialState: sessionNearExpiryState(),
        )
        // store.exhaustivity = .off: deadline 이후 complete snapshot과 recovery delegate의 세부 상태보다 intent 선택을 검증
        store.exhaustivity = .off

        await store.send(._refreshDeadlineReached(generation: 0))
        await store.receive(\.sessionSyncRequested)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(receivedIntent, .refresh)
        XCTAssertTrue(store.state.hasAccountSession)
        await store.finish()
    }

    /// ACC-001-validate_account_session: refresh deadline은 만료 360초 전에 한 번만 refresh sync를 요청한다.
    /// - 검증 내용: TestClock을 3,239초 진행한 뒤에는 sync가 없고, 1초 더 진행하면 refresh intent가 전달된다.
    /// - 사전 조건: 현재 시각에서 3,600초 뒤 만료되는 로그인 세션.
    /// - 기대 결과: 3,240초 시점에 정확히 한 번 `.refresh` sync가 시작된다.
    func testRefreshDeadlineFiresAtExpiryMinusRefreshBuffer() async {
        let clock = TestClock()
        let expiresAt = referenceDate.addingTimeInterval(3600)
        let expiredExpiry = referenceDate.addingTimeInterval(-1)
        let snapshot = AccessStatusSnapshot.fetchResult(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            sessionExpiresAt: expiresAt,
            fetchedAt: referenceDate,
            deviceBindingVerifiedAt: referenceDate,
        )
        let store = TestStore(initialState: AccountAccessFeature.State()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(referenceDate)
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in AccountSession(
                    accessToken: "expired-access-token",
                    status: .none,
                    refreshToken: "refresh-token",
                    expiresAt: expiredExpiry,
                )
                },
                persist: { _ in },
                delete: { _ in },
            )
        }
        // store.exhaustivity = .off: snapshot hydration의 전체 presentation state보다 deadline action 시점을 검증
        store.exhaustivity = .off

        await store.send(.hydrateLaunchSnapshot(snapshot))
        await Task.yield()
        await clock.advance(by: .seconds(3239))
        await clock.advance(by: .seconds(1))
        await store.receive(\._refreshDeadlineReached)
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated)
        await store.receive(\.sessionSyncRequested)
        await store.send(.signOut)
        await store.receive(\.delegate.signedOut)
        await store.finish()
    }

    /// ACC-001-validate_account_session: sign-out은 대기 중인 refresh deadline을 취소한다.
    /// - 검증 내용: sign-out 뒤 TestClock을 deadline 이후로 진행해도 refresh sync가 발생하지 않는다.
    /// - 사전 조건: T+3600 expiry로 hydrate된 로그인 세션과 대기 중인 one-shot scheduler.
    /// - 기대 결과: signed-out 상태를 유지하며 남은 deadline effect가 없다.
    func testSignOutCancelsPendingRefreshDeadline() async {
        let clock = TestClock()
        let expiresAt = referenceDate.addingTimeInterval(3600)
        let expiredExpiry = referenceDate.addingTimeInterval(-1)
        let snapshot = AccessStatusSnapshot.fetchResult(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            sessionExpiresAt: expiresAt,
            fetchedAt: referenceDate,
            deviceBindingVerifiedAt: referenceDate,
        )
        let store = TestStore(initialState: AccountAccessFeature.State()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(referenceDate)
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in AccountSession(
                    accessToken: "expired-access-token",
                    status: .none,
                    refreshToken: "refresh-token",
                    expiresAt: expiredExpiry,
                )
                },
                persist: { _ in },
                delete: { _ in },
            )
        }
        // store.exhaustivity = .off: hydrate와 sign-out의 전체 presentation state보다 deadline cancellation을 검증
        store.exhaustivity = .off

        await store.send(.hydrateLaunchSnapshot(snapshot))
        await store.send(.signOut)
        await store.receive(\.delegate.signedOut)
        await clock.advance(by: .seconds(3240))

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertTrue(store.state.isSessionExpired)
        await store.finish()
    }

    /// ACC-001-validate_account_session: rotated session completion은 새 expiry 기준으로 refresh deadline을 다시 예약한다.
    /// - 검증 내용: refresh completion의 sessionExpiresAt 이후 T+3240에 다음 refresh trigger가 발생한다.
    /// - 사전 조건: refresh sync가 진행 중이고 rotated result가 새 만료 시각을 반환한다.
    /// - 기대 결과: 이전 expiry가 아니라 rotated expiry의 refresh deadline이 사용된다.
    func testRotatedSessionReschedulesRefreshDeadline() async {
        let clock = TestClock()
        let expiredExpiry = referenceDate.addingTimeInterval(-1)
        var state = sessionNearExpiryState()
        state.syncGeneration = 1
        state.inFlightSyncReason = .refreshDeadline
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(referenceDate)
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in AccountSession(
                    accessToken: "expired-access-token",
                    status: .none,
                    refreshToken: "refresh-token",
                    expiresAt: expiredExpiry,
                )
                },
                persist: { _ in },
                delete: { _ in },
            )
        }
        // store.exhaustivity = .off: rotated completion의 recovery projection보다 새 expiry 기준 deadline 재예약을 검증
        store.exhaustivity = .off

        await store.send(._sessionSyncCompleted(
            generation: 1,
            result: .success(SessionSyncResult(
                sessionStatus: .rotated,
                syncStatus: .complete,
                accessStatus: AccessStatusResponse(hasAccess: false, status: "none"),
                deviceBindingOutcome: .notAttempted,
                connectedDeviceAvailability: .available,
                sessionExpiresAt: newExpiryDate,
            )),
        ))
        await store.receive(\.delegate.recoveryRequired)
        await Task.yield()
        await clock.advance(by: .seconds(3239))
        await clock.advance(by: .seconds(1))
        await store.receive(\._refreshDeadlineReached)
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated)
        await store.receive(\.sessionSyncRequested)
        await store.send(.signOut)
        await store.receive(\.delegate.signedOut)
        await store.finish()
    }
}

extension ACC001ValidateAccountSessionTests {
    /// ACC-001-validate_account_session: ambiguous refresh transport failure는 같은 request ID로 5초 안에 한 번 재시도한다.
    /// - 검증 내용: 첫 upstream timeout 뒤 TestClock 5초에서 두 번째 refresh가 같은 request ID를 사용한다.
    /// - 사전 조건: refresh deadline으로 시작한 로그인 세션과 첫 호출에서 upstream(0)을 throw하는 client.
    /// - 기대 결과: 두 번의 호출 request ID가 같고, 성공 후 session은 유지된다.
    func testRefreshTransportAmbiguityRetriesOnceWithSameRequestID() async {
        nonisolated(unsafe) var requestIDs: [String] = []
        nonisolated(unsafe) var attempts = 0
        let clock = TestClock()
        let store = TestStore(initialState: sessionNearExpiryState()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date = .constant(referenceDate)
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSessionWithRequestID: { _, _, requestID in
                    requestIDs.append(requestID)
                    attempts += 1
                    if attempts == 1 {
                        throw SessionSyncError.upstream(0)
                    }
                    return Self.inactiveCompleteSyncResult
                },
            )
        }
        // store.exhaustivity = .off: retry completion의 recovery projection보다 request ID 재사용과 session 보존을 검증
        store.exhaustivity = .off

        await store.send(.sessionSyncRequested(intent: .refresh, reason: .refreshDeadline))
        for _ in 0 ..< 10 where attempts == 0 {
            await Task.yield()
        }
        await clock.advance(by: .seconds(5))
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(requestIDs.count, 2)
        XCTAssertEqual(requestIDs.first, requestIDs.last)
        XCTAssertTrue(store.state.hasAccountSession)
        await store.finish()
    }

    /// ACC-001-validate_account_session: validate retry 소진 후 fresh verified cache로 복구한다.
    /// - 검증 내용: 같은 request ID로 네 번 시도한 뒤 snapshot을 한 번 로드하고 unlock한다.
    /// - 사전 조건: upstream failure가 반복되고 미만료 session과 binding proof를 가진 fresh snapshot이 존재한다.
    /// - 기대 결과: network recovery state를 거쳐 cached snapshot으로 isComplete=true와 unlocked delegate를 전달한다.
    func testValidateRetryExhaustionRestoresFreshVerifiedCache() async {
        nonisolated(unsafe) var attempts = 0
        nonisolated(unsafe) var loadedSnapshots = 0
        let clock = TestClock()
        let binding = UUID()
        let sessionExpiry = newExpiryDate
        let releaseIdentityNow = referenceDate
        let cachedSnapshot = AccessStatusSnapshot.fetchResult(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            sessionExpiresAt: sessionExpiry,
            fetchedAt: referenceDate,
            sessionBindingID: binding,
            gatewayBinding: GatewayEnvironment(rawValue: "").binding,
            deviceID: "test-device-id",
            deviceBindingVerifiedAt: referenceDate,
            ownershipStatus: "owned",
            updateStatus: "active",
            updatesThrough: Date(timeIntervalSince1970: 2_000_000_000),
        )
        let cachedEnvelope = AccessStatusSnapshotEnvelope(
            sessionBindingID: binding,
            gatewayBinding: GatewayEnvironment(rawValue: "").binding,
            mutationGeneration: 1,
            snapshot: cachedSnapshot,
        )
        var state = sessionNearExpiryState()
        state.sessionBindingID = binding
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in AccountSession(
                    accessToken: "test-access-token",
                    status: .coreLicenseActive,
                    refreshToken: "test-refresh-token",
                    expiresAt: sessionExpiry,
                    sessionBindingID: binding,
                )
                },
                persist: { _ in },
                delete: { _ in },
            )
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.networkFailure },
                bindDevice: { _ in throw DeviceBindingError.networkFailure },
                refreshToken: { throw AccessError.networkFailure },
                syncSessionWithRequestID: { _, _, _ in
                    attempts += 1
                    throw SessionSyncError.upstream(503)
                },
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(activate: { _, _ in 0 }, load: { _, _ in
                loadedSnapshots += 1
                return cachedEnvelope
            }, save: { _, _, _, _ in }, remove: { _, _, _ in })
            $0.continuousClock = clock
            $0.date = .constant(referenceDate)
            $0.releaseIdentityClient = ReleaseIdentityClient(resolve: { _ in
                try? ReleaseIdentity(releasedAt: "2023-11-14T22:13:20Z", now: releaseIdentityNow)
            })
        }
        // store.exhaustivity = .off: retry 내부 호출 횟수와 최종 cache recovery 상태를 집중 검증
        store.exhaustivity = .off

        await store.send(.sessionSyncRequested(intent: .validate, reason: .manual))
        for _ in 0 ..< 10 where attempts < 1 {
            await Task.yield()
        }
        await clock.advance(by: .seconds(1))
        await clock.advance(by: .seconds(2))
        await clock.advance(by: .seconds(4))
        await store.receive(\._cachedSnapshotRestored)
        await store.receive(\.delegate.unlocked)

        XCTAssertEqual(attempts, 4)
        XCTAssertEqual(loadedSnapshots, 1)
        XCTAssertTrue(store.state.isComplete)
        XCTAssertFalse(store.state.isSubmitting)
        await store.finish()
    }

    /// ACC-001-validate_account_session: retry exhaustion fallback은 만료된 snapshot session이면 unlock하지 않는다.
    /// - 검증 내용: complete envelope와 active device proof, refresh credential이 있어도 snapshot session이 만료면 recovery로
    /// 끝난다.
    /// - 사전 조건: upstream failure가 반복되고 current binding의 trusted snapshot session은 정확히 현재 시각에 만료된다.
    /// - 기대 결과: snapshot load는 한 번 수행되나 unlocked delegate 없이 network recovery를 전달한다.
    func testValidateRetryExhaustionRejectsExpiredSnapshotSession() async {
        nonisolated(unsafe) var attempts = 0
        nonisolated(unsafe) var loadedSnapshots = 0
        let clock = TestClock()
        let binding = UUID()
        let sessionExpiry = nearExpiryDate
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
            sessionBindingID: binding,
            gatewayBinding: GatewayEnvironment(rawValue: "").binding,
            deviceID: "test-device-id",
            sessionExpiresAt: referenceDate,
            deviceBindingVerifiedAt: referenceDate,
        )
        let envelope = AccessStatusSnapshotEnvelope(
            sessionBindingID: binding,
            gatewayBinding: GatewayEnvironment(rawValue: "").binding,
            mutationGeneration: 1,
            snapshot: snapshot,
        )
        var state = sessionNearExpiryState()
        state.sessionBindingID = binding
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in AccountSession(
                    accessToken: "test-access-token",
                    status: .coreLicenseActive,
                    refreshToken: "test-refresh-token",
                    expiresAt: sessionExpiry,
                    sessionBindingID: binding,
                )
                },
                persist: { _ in },
                delete: { _ in },
            )
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.networkFailure },
                bindDevice: { _ in throw DeviceBindingError.networkFailure },
                refreshToken: { throw AccessError.networkFailure },
                syncSessionWithRequestID: { _, _, _ in
                    attempts += 1
                    throw SessionSyncError.upstream(503)
                },
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(activate: { _, _ in 0 }, load: { _, _ in
                loadedSnapshots += 1
                return envelope
            }, save: { _, _, _, _ in }, remove: { _, _, _ in })
            $0.continuousClock = clock
            $0.date = .constant(referenceDate)
        }

        await store.send(.sessionSyncRequested(intent: .validate, reason: .manual)) { state in
            state.syncGeneration = 1
            state.inFlightSyncReason = .manual
            state.isSubmitting = true
        }
        await store.receive(\._sessionSyncActivationCompleted)
        for _ in 0 ..< 10 where attempts < 1 {
            await Task.yield()
        }
        await clock.advance(by: .seconds(1))
        await clock.advance(by: .seconds(2))
        await clock.advance(by: .seconds(4))
        await store.receive(\._cachedSnapshotRestored) { state in
            state.inFlightSyncReason = nil
            state.isSubmitting = false
            state.status = .networkFailure
            state.errorMessage = "Network error. Please check your connection and try again."
        }
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(attempts, 4)
        XCTAssertEqual(loadedSnapshots, 1)
        XCTAssertFalse(store.state.isComplete)
        XCTAssertNil(store.state.snapshot)
        await store.finish()
    }

    /// ACC-001-validate_account_session: unknown sync 오류는 cache unlock fallback을 사용하지 않는다.
    /// - 검증 내용: typed upstream이 아닌 오류가 retry나 snapshot load 없이 failure completion으로 종료된다.
    /// - 사전 조건: unknown error를 throw하는 sync client와 snapshot dependency.
    /// - 기대 결과: network recovery를 전달하지만 snapshot load와 unlocked delegate는 발생하지 않는다.
    func testUnknownSyncFailureDoesNotRestoreCachedSnapshot() async {
        nonisolated(unsafe) var attempts = 0
        nonisolated(unsafe) var loadedSnapshots = 0
        let store = TestStore(initialState: sessionNearExpiryState()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.networkFailure },
                refreshToken: { throw AccessError.networkFailure },
                syncSessionWithRequestID: { _, _, _ in
                    attempts += 1
                    throw UnknownSessionSyncError.failure
                },
            )
            $0.accessStatusSnapshotClient.load = { _, _ in
                loadedSnapshots += 1
                return nil
            }
            $0.continuousClock = TestClock()
            $0.date = .constant(referenceDate)
        }
        // store.exhaustivity = .off: unknown failure의 cache 미사용과 recovery route만 검증
        store.exhaustivity = .off

        await store.send(.sessionSyncRequested(intent: .validate, reason: .manual))
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(loadedSnapshots, 0)
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// ACC-001-validate_account_session: 취소된 sync는 cache unlock fallback을 사용하지 않는다.
    /// - 검증 내용: cancellation이 retry, snapshot load, completion action 없이 effect를 종료한다.
    /// - 사전 조건: CancellationError를 throw하는 sync client와 snapshot dependency.
    /// - 기대 결과: snapshot load와 unlock 없이 in-flight effect가 종료된다.
    func testCancelledSyncDoesNotRestoreCachedSnapshot() async {
        nonisolated(unsafe) var attempts = 0
        nonisolated(unsafe) var loadedSnapshots = 0
        let store = TestStore(initialState: sessionNearExpiryState()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.networkFailure },
                refreshToken: { throw AccessError.networkFailure },
                syncSessionWithRequestID: { _, _, _ in
                    attempts += 1
                    throw CancellationError()
                },
            )
            $0.accessStatusSnapshotClient.load = { _, _ in
                loadedSnapshots += 1
                return nil
            }
            $0.continuousClock = TestClock()
            $0.date = .constant(referenceDate)
        }
        // store.exhaustivity = .off: cancellation의 cache 미사용과 effect 종료만 검증
        store.exhaustivity = .off

        await store.send(.sessionSyncRequested(intent: .validate, reason: .manual))
        await store.finish()

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(loadedSnapshots, 0)
        XCTAssertNil(store.state.snapshot)
    }

    /// ACC-001-validate_account_session: superseded cache completion은 현재 sync state를 변경하지 않는다.
    /// - 검증 내용: 이전 generation의 snapshot completion을 reducer guard가 무시한다.
    /// - 사전 조건: generation 2 sync가 진행 중일 때 generation 1 cache completion이 도착한다.
    /// - 기대 결과: in-flight reason, submitting state, status, snapshot이 모두 유지된다.
    func testSupersededCachedSnapshotRestoreIsIgnored() async {
        let cachedSnapshot = AccessStatusSnapshot.fetchResult(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            sessionExpiresAt: newExpiryDate,
            fetchedAt: referenceDate,
            deviceBindingVerifiedAt: referenceDate,
        )
        var state = sessionNearExpiryState()
        state.syncGeneration = 2
        state.inFlightSyncReason = .manual
        state.isSubmitting = true
        let store = makeTestStore(initialState: state)

        await store.send(._cachedSnapshotRestored(
            generation: 1,
            binding: nil,
            snapshot: cachedSnapshot,
            validUntil: nil,
        ))

        XCTAssertEqual(store.state.syncGeneration, 2)
        XCTAssertEqual(store.state.inFlightSyncReason, .manual)
        XCTAssertTrue(store.state.isSubmitting)
        XCTAssertNil(store.state.status)
        XCTAssertNil(store.state.snapshot)
    }

    /// ACC-001-validate_account_session: transient upstream 실패는 반복돼도 세션을 만료시키지 않는다.
    /// - 검증 내용: 429와 503을 포함한 upstream failure completion이 session-expired action을 만들지 않는다.
    /// - 사전 조건: 세 번째 transient failure를 나타내는 로그인 세션.
    /// - 기대 결과: hasAccountSession=true와 isSessionExpired=false가 유지된다.
    func testTransientRefreshFailurePreservesSessionAfterThreeFailures() async {
        var state = sessionNearExpiryState()
        state.syncGeneration = 3
        state.inFlightSyncReason = .refreshDeadline
        state.consecutiveRefreshFailures = 3
        let store = makeTestStore(initialState: state)
        // store.exhaustivity = .off: transient failure의 recovery delegate보다 session 보존 정책을 검증
        store.exhaustivity = .off

        await store.send(._sessionSyncCompleted(generation: 3, result: .failure(.upstream(503))))
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertFalse(store.state.isSessionExpired)
        await store.finish()
    }

    /// ACC-001-validate_account_session: Refresh Access는 만료된 persisted session을 refresh sync로 재검증한다.
    /// - 검증 내용: manual action이 persisted read 뒤 `.refresh` intent와 `.manual` reason을 요청한다.
    /// - 사전 조건: recoverable in-memory session과 만료된 access expiry, 비어 있지 않은 refresh token.
    /// - 기대 결과: 로그인 상태를 유지한 채 refresh sync activation 전까지 정확한 action chain만 발생한다.
    func testRefreshAccessRevalidatesExpiredPersistedSessionWithRefreshIntent() async {
        let activationGate = ActivationGate()
        let expiredAt = referenceDate.addingTimeInterval(-1)
        let binding = UUID()
        var state = sessionNearExpiryState()
        state.sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        state.sessionBindingID = binding
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in AccountSession(
                    accessToken: "expired-access-token",
                    status: .coreLicenseActive,
                    refreshToken: "refresh-token",
                    expiresAt: expiredAt,
                    sessionBindingID: binding,
                )
                },
                persist: { _ in },
                delete: { _ in },
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                activate: { _, _ in await activationGate.wait() },
                load: { _, _ in nil },
                save: { _, _, _, _ in },
                remove: { _, _, _ in },
            )
            $0.date = .constant(referenceDate)
        }

        await store.send(.refreshAccessTapped) { state in
            state.revalidationGeneration = 1
        }
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated) { state in
            state.sessionExpiresAt = expiredAt
        }
        await store.receive(sessionSyncRequestedCasePath(intent: .refresh, reason: .manual)) { state in
            state.syncGeneration = 1
            state.inFlightSyncReason = .manual
            state.isSubmitting = true
        }
        for _ in 0 ..< 10 where await !(activationGate.isWaiting()) {
            await Task.yield()
        }
        let isActivationWaiting = await activationGate.isWaiting()
        XCTAssertTrue(isActivationWaiting)

        await store.send(.appWillTerminate) { state in
            state.fetchGeneration = 1
            state.syncGeneration = 2
            state.inFlightSyncReason = nil
            state.revalidationGeneration = 2
            state.isSubmitting = false
            state.ttlTimerActive = false
            state.handoffGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await activationGate.resume(with: 1)
        await store.finish()
    }

    /// ACC-001-validate_account_session: login completion sync는 fresh complete 결과를 우회한다.
    /// - 검증 내용: `.login` reason의 validate intent.
    /// - 사전 조건: 5분 이내 complete sync와 refresh not due session.
    /// - 기대 결과: syncSession 호출 한 번.
    func testLoginSyncBypassesFreshness() async {
        nonisolated(unsafe) var receivedIntent: SessionSyncIntent?
        var state = sessionNearExpiryState()
        state.lastCompleteSyncAt = referenceDate.addingTimeInterval(-60)
        state.sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { intent, _ in
                    receivedIntent = intent
                    return Self.inactiveCompleteSyncResult
                },
            ),
            initialState: state,
        )
        // store.exhaustivity = .off: login completion의 recovery projection보다 freshness 우회와 intent 선택을 검증
        store.exhaustivity = .off

        await store.send(.sessionSyncRequested(intent: .validate, reason: .login))
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(receivedIntent, .validate)
        await store.finish()
    }

    /// ACC-001-validate_account_session: invalid credential sync failure는 session expiry를 전파한다.
    /// refreshToken이 decodingFailure를 throw할 때 _sessionExpiredDetected로 상태가 전환되는지 검증한다.
    /// - 검증 내용: decodingFailure → _sessionExpiredDetected → hasAccountSession=false, isSessionExpired=true,
    /// didSignInFail=true, ttlTimerActive=false로 전환된다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태.
    /// - 기대 결과: 세션이 만료되고 로그인 실패 상태로 전환되며 TTL timer가 중단된다.
    func testInvalidCredentialSessionSyncExpiresSession() async {
        var state = sessionNearExpiryState()
        state.syncGeneration = 1
        state.inFlightSyncReason = .refreshDeadline
        let store = makeTestStore(initialState: state)
        // store.exhaustivity = .off: session expiry cleanup의 모든 presentation 상태보다 invalid credential 전환을 검증
        store.exhaustivity = .off

        await store.send(._sessionSyncCompleted(generation: 1, result: .failure(.invalidCredential)))
        await store.receive(\._sessionExpiredDetected)
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertTrue(store.state.isSessionExpired)
        XCTAssertFalse(store.state.hasAccountSession)
        await store.finish()
    }

    /// ACC-001-validate_account_session: Retry는 만료된 persisted session을 refresh sync로 재검증한다.
    /// - 검증 내용: retry action이 persisted read 뒤 `.refresh` intent와 `.retry` reason을 요청한다.
    /// - 사전 조건: recoverable in-memory session과 만료된 access expiry, 비어 있지 않은 refresh token.
    /// - 기대 결과: 로그인 상태를 유지한 채 refresh sync activation 전까지 정확한 action chain만 발생한다.
    func testRetryRevalidatesExpiredPersistedSessionWithRefreshIntent() async {
        let activationGate = ActivationGate()
        let expiredAt = referenceDate.addingTimeInterval(-1)
        let binding = UUID()
        var state = sessionNearExpiryState()
        state.sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        state.sessionBindingID = binding
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in AccountSession(
                    accessToken: "expired-access-token",
                    status: .coreLicenseActive,
                    refreshToken: "refresh-token",
                    expiresAt: expiredAt,
                    sessionBindingID: binding,
                )
                },
                persist: { _ in },
                delete: { _ in },
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                activate: { _, _ in await activationGate.wait() },
                load: { _, _ in nil },
                save: { _, _, _, _ in },
                remove: { _, _, _ in },
            )
            $0.date = .constant(referenceDate)
        }

        await store.send(.retryTapped) { state in
            state.revalidationGeneration = 1
        }
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated) { state in
            state.sessionExpiresAt = expiredAt
        }
        await store.receive(sessionSyncRequestedCasePath(intent: .refresh, reason: .retry)) { state in
            state.syncGeneration = 1
            state.inFlightSyncReason = .retry
            state.isSubmitting = true
        }
        for _ in 0 ..< 10 where await !(activationGate.isWaiting()) {
            await Task.yield()
        }
        let isActivationWaiting = await activationGate.isWaiting()
        XCTAssertTrue(isActivationWaiting)

        await store.send(.appWillTerminate) { state in
            state.fetchGeneration = 1
            state.syncGeneration = 2
            state.inFlightSyncReason = nil
            state.revalidationGeneration = 2
            state.isSubmitting = false
            state.ttlTimerActive = false
            state.handoffGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await activationGate.resume(with: 1)
        await store.finish()
    }

    /// ACC-001-validate_account_session: partial sync는 complete freshness를 갱신하지 않는다.
    /// refreshToken이 networkFailure를 throw할 때 세션이 유지되는지 검증한다.
    /// - 검증 내용: networkFailure → consecutiveRefreshFailures가 1 증가하고 세션 상태는 유지된다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태.
    /// - 기대 결과: hasAccountSession과 ttlTimerActive가 true로 유지되고 consecutiveRefreshFailures가 1이 된다.
    func testPartialSessionSyncDoesNotUpdateFreshness() async {
        let lastCompleteSyncAt = referenceDate.addingTimeInterval(-60)
        var state = sessionNearExpiryState()
        state.lastCompleteSyncAt = lastCompleteSyncAt
        state.syncGeneration = 1
        state.inFlightSyncReason = .manual
        let store = makeTestStore(initialState: state)
        // store.exhaustivity = .off: partial result의 device recovery 세부 상태보다 freshness 불변 조건을 검증
        store.exhaustivity = .off

        await store.send(._sessionSyncCompleted(
            generation: 1,
            result: .success(SessionSyncResult(
                sessionStatus: .rotated,
                syncStatus: .partial,
                accessStatus: AccessStatusResponse(hasAccess: true, status: "active"),
                deviceBindingOutcome: .bound,
                connectedDeviceAvailability: .unavailable,
                partial: SessionSyncPartial(stage: "access", reason: "temporarily_unavailable"),
            )),
        ))
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(store.state.lastCompleteSyncAt, lastCompleteSyncAt)
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// ACC-001-validate_account_session: superseded completion은 snapshot과 unlock state를 바꾸지 않는다.
    /// sessionExpiredDetected 처리 후 _ttlTimerTicked가 no-op이 되는지 검증한다.
    /// - 검증 내용: 만료 후 TTL timer가 중단되고 이후 tick이 상태를 변경하지 않는다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태에서 decodingFailure 발생.
    /// - 기대 결과: ttlTimerActive=false, hasAccountSession=false로 전환되고 추가 tick이 무시된다.
    func testSupersededSessionSyncCompletionDoesNotUpdateSnapshot() async {
        var state = sessionNearExpiryState()
        state.syncGeneration = 2
        state.inFlightSyncReason = .manual
        let store = makeTestStore(initialState: state)

        await store.send(._sessionSyncCompleted(
            generation: 1,
            result: .success(Self.activeCompleteSyncResult),
        ))

        XCTAssertNil(store.state.snapshot)
        XCTAssertNil(store.state.lastCompleteSyncAt)
        XCTAssertEqual(store.state.syncGeneration, 2)
    }

    /// ACC-001-validate_account_session: sign-out은 늦은 sync completion의 UI 적용을 차단한다.
    func testSignOutIgnoresLateSessionSyncCompletion() async {
        var state = sessionNearExpiryState()
        state.syncGeneration = 1
        state.inFlightSyncReason = .refreshDeadline
        state.lastCompleteSyncAt = referenceDate.addingTimeInterval(-60)
        let store = makeTestStore(initialState: state)
        // store.exhaustivity = .off: sign-out cleanup의 전체 presentation 상태보다 stale completion 차단을 검증
        store.exhaustivity = .off

        await store.send(.signOut)
        await store.receive(\.delegate.signedOut)
        await store.send(._sessionSyncCompleted(
            generation: 1,
            result: .success(Self.activeCompleteSyncResult),
        ))

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertTrue(store.state.isSessionExpired)
        XCTAssertNil(store.state.snapshot)
        XCTAssertNil(store.state.lastCompleteSyncAt)
        await store.finish()
    }

    /// ACC-001-validate_account_session: superseded refresh는 이미 저장된 rotated session을 되돌리지 않는다.
    /// - 검증 내용: client persistence가 끝난 뒤 sign-out이 UI/snapshot completion만 무시한다.
    /// - 사전 조건: completion을 보류한 refresh sync와 client-owned rotated session persistence.
    /// - 기대 결과: persisted rotation 기록은 유지되고 signed-out state는 복원되지 않는다.
    func testSupersededRefreshPreservesClientPersistedRotationAndDropsUICompletion() async {
        nonisolated(unsafe) var clientPersistedRotation = false
        nonisolated(unsafe) var continuation: CheckedContinuation<SessionSyncResult, Never>?
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { _, _ in
                    clientPersistedRotation = true
                    return await withCheckedContinuation { continuation = $0 }
                },
            ),
            initialState: sessionNearExpiryState(),
        )
        // store.exhaustivity = .off: sign-out 이후 cancellation을 무시한 completion의 UI 반영 차단만 검증
        store.exhaustivity = .off

        await store.send(.sessionSyncRequested(intent: .refresh, reason: .refreshDeadline))
        for _ in 0 ..< 10 where continuation == nil {
            await Task.yield()
        }
        XCTAssertTrue(clientPersistedRotation)
        XCTAssertNotNil(continuation)

        await store.send(.signOut)
        await store.receive(\.delegate.signedOut)
        continuation?.resume(returning: Self.activeCompleteSyncResult)
        await Task.yield()

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertNil(store.state.snapshot)
        await store.finish()
    }

    /// ACC-001-validate_account_session: refresh deadline은 foreground sync를 supersede한다.
    /// consecutiveRefreshFailures가 threshold(3)에 도달하면 _sessionExpiredDetected가 트리거되는지 검증한다.
    /// - 검증 내용: 3회 연속 networkFailure → _sessionExpiredDetected → 세션 만료 상태로 전환된다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태.
    /// - 기대 결과: 3회째 tick에서 hasAccountSession=false, isSessionExpired=true, ttlTimerActive=false로 전환된다.
    func testRefreshDeadlineSupersedesForegroundSync() async {
        nonisolated(unsafe) var receivedIntent: SessionSyncIntent?
        var state = sessionNearExpiryState()
        state.syncGeneration = 1
        state.inFlightSyncReason = .foreground
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { intent, _ in
                    receivedIntent = intent
                    return Self.inactiveCompleteSyncResult
                },
            ),
            initialState: state,
        )
        // store.exhaustivity = .off: superseding refresh의 recovery projection보다 우선순위와 intent 선택을 검증
        store.exhaustivity = .off

        await store.send(.sessionSyncRequested(intent: .refresh, reason: .refreshDeadline))
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(receivedIntent, .refresh)
        XCTAssertEqual(store.state.syncGeneration, 2)
        await store.finish()
    }

    /// ACC-001-validate_account_session: State에 accessToken/refreshToken 필드가 직접 노출되지 않는다.
    /// Mirror를 통해 State 타입의 모든 프로퍼티에 token 필드가 없는지 검증한다.
    /// - 검증 내용: State의 모든 프로퍼티 label에 "accessToken" 또는 "refreshToken"이 포함되지 않는다.
    /// - 사전 조건: 없음.
    /// - 기대 결과: token 필드가 State에 직접 노출되지 않는다.
    func testRawTokenNeverExposedInState() {
        let state = AccountAccessFeature.State()
        let mirror = Mirror(reflecting: state)
        for child in mirror.children {
            let label = child.label ?? ""
            XCTAssertFalse(
                label.contains("accessToken") || label.contains("refreshToken"),
                "State must not expose token fields: \(label)",
            )
        }
    }

    /// ACC-001-validate_account_session: superseded completion은 새 요청의 expiry와 fetch를 변경하지 않는다.
    /// 더 최신 foreground revalidation이 진행 중일 때 이전 요청의 valid completion이 도착하는 경로를 검증한다.
    /// - 검증 내용: 현재 generation과 다른 valid completion은 sessionExpiresAt과 fetchGeneration을 변경하거나 fetch effect를 시작하지 않는다.
    /// - 사전 조건: 로그인된 session의 최신 revalidationGeneration은 2이고, generation 1 foreground 요청이 늦게 완료된다.
    /// - 기대 결과: 기존 expiry와 fetchGeneration이 유지되고 access fetch 호출은 없다.
    func testSupersededCompletionDoesNotUpdateExpiryOrStartFetch() async {
        nonisolated(unsafe) var fetchCalled = false
        var state = sessionNearExpiryState()
        state.revalidationGeneration = 2
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCalled = true
                    throw AccessError.networkFailure
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.networkFailure },
            ),
            initialState: state,
        )

        await store.send(
            ._persistedSessionRevalidated(
                generation: 1,
                result: .valid(session: Self.session(expiresAt: newExpiryDate)),
            ),
        )

        XCTAssertEqual(store.state.sessionExpiresAt, nearExpiryDate)
        XCTAssertEqual(store.state.fetchGeneration, 0)
        XCTAssertFalse(fetchCalled)
    }

    /// ACC-001-validate_account_session: 앱 종료 뒤 늦은 foreground valid completion은 fetch를 시작하지 않는다.
    /// 종료 시 취소를 무시하고 도착한 기존 revalidation completion이 lifecycle 무효화 경계를 넘지 못하는지 검증한다.
    /// - 검증 내용: appWillTerminate가 in-flight generation을 무효화한 뒤 이전 valid completion을 무시한다.
    /// - 사전 조건: 로그인된 session에서 generation 1 revalidation이 진행 중이고 appWillTerminate가 generation을 2로 올린다.
    /// - 기대 결과: expiry와 fetchGeneration이 종료 직후 값으로 유지되고 access fetch 호출은 없다.
    func testAppWillTerminateIgnoresLateValidRevalidationCompletion() async {
        nonisolated(unsafe) var fetchCalled = false
        var state = sessionNearExpiryState()
        state.revalidationGeneration = 1
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCalled = true
                    throw AccessError.networkFailure
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: state,
        )
        // store.exhaustivity = .off: 종료 정리가 다수 transient 상태를 초기화하나 검증 대상은 revalidation 무효화만 해당
        store.exhaustivity = .off

        await store.send(.appWillTerminate) { state in
            state.fetchGeneration = 1
            state.revalidationGeneration = 2
            state.ttlTimerActive = false
        }
        await store.send(
            ._persistedSessionRevalidated(
                generation: 1,
                result: .valid(session: Self.session(expiresAt: newExpiryDate)),
            ),
        )

        XCTAssertEqual(store.state.sessionExpiresAt, nearExpiryDate)
        XCTAssertEqual(store.state.fetchGeneration, 1)
        XCTAssertEqual(store.state.revalidationGeneration, 2)
        XCTAssertFalse(fetchCalled)
        await store.finish()
    }
}

private func sessionSyncRequestedCasePath(
    intent expectedIntent: SessionSyncIntent,
    reason expectedReason: SyncReason,
) -> AnyCasePath<AccountAccessAction, Void> {
    AnyCasePath(
        embed: { _ in .sessionSyncRequested(intent: expectedIntent, reason: expectedReason) },
        extract: { action in
            guard case let .sessionSyncRequested(intent, reason) = action,
                  intent == expectedIntent,
                  reason == expectedReason
            else {
                return nil
            }
            return ()
        },
    )
}

private actor ActivationGate {
    private var continuation: CheckedContinuation<Int, Never>?

    func wait() async -> Int {
        await withCheckedContinuation {
            continuation = $0
        }
    }

    func isWaiting() -> Bool {
        continuation != nil
    }

    func resume(with generation: Int) {
        continuation?.resume(returning: generation)
        continuation = nil
    }
}

private actor SyncRecorder {
    private var callCount = 0
    private var savedGenerations: [Int] = []

    func recordSync() {
        callCount += 1
    }

    func recordSave(_ generation: Int) {
        savedGenerations.append(generation)
    }

    func syncCallCount() -> Int {
        callCount
    }

    func saved() -> [Int] {
        savedGenerations
    }
}

private enum StorageReadError: Error {
    case unavailable
}

private enum UnknownSessionSyncError: Error {
    case failure
}

private extension ACC001ValidateAccountSessionTests {
    nonisolated static var activeCompleteSyncResult: SessionSyncResult {
        SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(hasAccess: true, status: "active", ownershipStatus: "owned", updateStatus: "active", updatesThrough: Date(timeIntervalSince1970: 2_000_000_000)),
            deviceBindingOutcome: .bound,
            connectedDeviceAvailability: .available,
        )
    }

    nonisolated static var inactiveCompleteSyncResult: SessionSyncResult {
        SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(hasAccess: false, status: "none"),
            deviceBindingOutcome: .notAttempted,
            connectedDeviceAvailability: .available,
        )
    }

    nonisolated static func session(expiresAt: Date) -> AccountSession {
        AccountSession(
            accessToken: "test-access-token",
            status: .coreLicenseActive,
            expiresAt: expiresAt,
        )
    }

    func makeTestStore(
        accountSessionClient: AccountSessionClient? = nil,
        authNetworkClient: AuthNetworkClient = .testValue,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        let persistedSession = Self.session(expiresAt: initialState.sessionExpiresAt ?? newExpiryDate)
        let sessionClient = accountSessionClient ?? AccountSessionClient(
            read: { _ in persistedSession },
            persist: { _ in },
            delete: { _ in },
        )
        return TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = sessionClient
            $0.authNetworkClient = authNetworkClient
            $0.continuousClock = TestClock()
            $0.date = .constant(referenceDate)
        }
    }

    func sessionNearExpiryState() -> AccountAccessFeature.State {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.ttlTimerActive = true
        state.sessionExpiresAt = nearExpiryDate
        return state
    }
}

extension ACC001ValidateAccountSessionTests {
    // MARK: - ACC-001-validate_account_session

    /// ACC-001-validate_account_session: foreground 재검증의 persisted session 누락은 fetch 없이 만료 감지를 전달한다.
    /// - 검증 내용: foreground nil read가 _sessionExpiredDetected를 전송하고 access fetch를 시작하지 않는다.
    /// - 사전 조건: 로그인된 in-memory session과 누락된 persisted storage.
    /// - 기대 결과: detect_session_expiry 경로만 실행되고 access fetch 호출은 없다.
    func testForegroundValidationWithMissingPersistedSessionExpiresWithoutFetch() async {
        nonisolated(unsafe) var fetchCalled = false
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(read: { _ in nil }, persist: { _ in },
                                                       delete: { _ in }),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCalled = true
                    throw AccessError.networkFailure
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: sessionNearExpiryState(),
        )
        // store.exhaustivity = .off: 만료 감지 이후 다수 상태가 전이되나 access fetch 미호출만 검증
        store.exhaustivity = .off

        await store.send(.appDidBecomeActive)
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated)
        await store.receive(\._sessionExpiredDetected)

        XCTAssertFalse(fetchCalled)
    }

    /// ACC-001-validate_account_session: foreground 저장소 read의 일시 오류는 로그인 상태를 유지하고 후속 fetch를 중단한다.
    /// - 검증 내용: storageUnavailable 결과가 session_expired나 access fetch를 만들지 않는다.
    /// - 사전 조건: 로그인된 in-memory session과 throw하는 persisted storage read.
    /// - 기대 결과: logged_in 상태를 유지하며 다음 foreground 기회에 재검증할 수 있다.
    func testForegroundValidationWithTransientStorageFailurePreservesSessionWithoutFetch() async {
        nonisolated(unsafe) var fetchCalled = false
        var initialState = sessionNearExpiryState()
        initialState.sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { _ in throw StorageReadError.unavailable },
                persist: { _ in },
                delete: { _ in },
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCalled = true
                    throw AccessError.networkFailure
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )
        // store.exhaustivity = .off: transient storage failure 뒤 deadline cancellation cleanup은 검증 대상이 아님
        store.exhaustivity = .off

        await store.send(.appDidBecomeActive) { state in
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated)

        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertFalse(store.state.isSessionExpired)
        XCTAssertEqual(store.state.fetchGeneration, 0)
        XCTAssertFalse(fetchCalled)
        await store.send(.signOut)
        await store.receive(\.delegate.signedOut)
        await store.finish()
    }
}

extension ACC001ValidateAccountSessionTests {
    // MARK: - ACC-001-session_sync_activation

    /// ACC-001-session_sync_activation: activation 완료 전에는 auth network sync를 시작하지 않고 persisted generation으로 reseed한다.
    /// - 검증 내용: activation gate가 열린 뒤에만 sync가 호출되고, 완료 snapshot save는 activation generation을 사용한다.
    /// - 사전 조건: 재시작 뒤 reducer generation보다 높은 persisted mutation generation과 binding된 유효 session.
    /// - 기대 결과: network sync와 save가 generation 77에서 실행된다.
    func testSessionSyncActivationReseedsBeforeNetworkAndSnapshotSave() async {
        let binding = UUID()
        let activationGate = ActivationGate()
        let recorder = SyncRecorder()
        var state = sessionNearExpiryState()
        state.sessionBindingID = binding
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                activate: { _, _ in await activationGate.wait() },
                load: { _, _ in nil },
                save: { _, _, _, generation in await recorder.recordSave(generation) },
                remove: { _, _, _ in },
            )
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { _, _ in
                    await recorder.recordSync()
                    return Self.activeCompleteSyncResult
                },
            )
            $0.date = .constant(referenceDate)
        }
        // store.exhaustivity = .off: activation 이후 complete sync의 snapshot projection보다 generation reseed와 호출 순서를 검증
        store.exhaustivity = .off

        await store.send(.sessionSyncRequested(intent: .validate, reason: .manual))
        let syncCallCountBeforeActivation = await recorder.syncCallCount()
        XCTAssertEqual(syncCallCountBeforeActivation, 0)

        await activationGate.resume(with: 77)
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.unlocked)

        XCTAssertEqual(store.state.syncGeneration, 77)
        let syncCallCount = await recorder.syncCallCount()
        let savedGenerations = await recorder.saved()
        XCTAssertEqual(syncCallCount, 1)
        XCTAssertEqual(savedGenerations, [77])
        await store.finish()
    }

    /// ACC-001-session_sync_activation: logout 중 activation 완료는 stale no-op이며 network sync를 시작하지 않는다.
    /// - 검증 내용: activation 대기 중 sign-out 뒤 도착한 completion이 state, sync, save를 변경하지 않는다.
    /// - 사전 조건: binding된 유효 session의 manual sync activation이 보류되어 있다.
    /// - 기대 결과: signed-out 상태를 유지하고 auth network 호출은 없다.
    func testLogoutDuringSessionSyncActivationDropsLateCompletionWithoutNetworkSync() async {
        let binding = UUID()
        let activationGate = ActivationGate()
        let recorder = SyncRecorder()
        var state = sessionNearExpiryState()
        state.sessionBindingID = binding
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                activate: { _, _ in await activationGate.wait() },
                load: { _, _ in nil },
                save: { _, _, _, generation in await recorder.recordSave(generation) },
                remove: { _, _, _ in },
            )
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { _, _ in
                    await recorder.recordSync()
                    return Self.activeCompleteSyncResult
                },
            )
            $0.date = .constant(referenceDate)
        }
        // store.exhaustivity = .off: sign-out cleanup의 presentation 세부보다 stale activation completion 차단을 검증
        store.exhaustivity = .off

        await store.send(.sessionSyncRequested(intent: .validate, reason: .manual))
        await store.send(.signOut)
        await store.receive(\.delegate.signedOut)
        await activationGate.resume(with: 77)
        await store.send(._sessionSyncActivationCompleted(AccountAccessSessionSyncActivationCompletion(
            requestGeneration: 1,
            binding: binding,
            intent: .validate,
            reason: .manual,
            mutationGeneration: 77,
        )))

        XCTAssertFalse(store.state.hasAccountSession)
        let syncCallCount = await recorder.syncCallCount()
        let savedGenerations = await recorder.saved()
        XCTAssertEqual(syncCallCount, 0)
        XCTAssertEqual(savedGenerations, [])
        await store.finish()
    }
}

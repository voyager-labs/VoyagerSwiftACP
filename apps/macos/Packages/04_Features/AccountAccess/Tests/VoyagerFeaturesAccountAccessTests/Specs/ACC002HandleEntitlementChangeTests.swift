@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-002-handle_entitlement_change spec-owner 테스트

 interaction_id: ACC-002-handle_entitlement_change

 entitlement change 상태 매핑:
 - status 변화 → accountAccessStepState 재계산 (complete / blocked / error / pending)
 - hasAccountSession=true → appDidBecomeActive가 fetchAccessStatusEffect 트리거
 - hasAccountSession=false → appDidBecomeActive가 guard에 의해 .none 반환
 */

@MainActor
final class ACC002HandleEntitlementChangeTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private let eligibleUpdatesThrough = Date(timeIntervalSince1970: 2_000_000_000)

    private static func session(expiresAt: Date) -> AccountSession {
        AccountSession(
            accessToken: "test-access-token",
            status: .coreLicenseActive,
            expiresAt: expiresAt,
        )
    }

    private func makeTestStore(
        accountSessionClient: AccountSessionClient? = nil,
        authNetworkClient: AuthNetworkClient = .testValue,
        snapshotClient: AccessStatusSnapshotClient = .testValue,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        let persistedSession = Self.session(
            expiresAt: initialState.sessionExpiresAt ?? referenceDate.addingTimeInterval(3600),
        )
        let sessionClient = accountSessionClient ?? AccountSessionClient(
            read: { _ in persistedSession },
            persist: { _ in },
            delete: { _ in },
        )
        let clock = TestClock()
        let currentAuthNetworkClient = currentSessionSyncClient(from: authNetworkClient)
        return TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = sessionClient
            $0.authNetworkClient = currentAuthNetworkClient
            $0.accessStatusSnapshotClient = snapshotClient
            $0.date = .constant(referenceDate)
            $0.continuousClock = clock
        }
    }

    private func currentSessionSyncClient(from legacy: AuthNetworkClient) -> AuthNetworkClient {
        AuthNetworkClient(
            exchangeHandoff: legacy.exchangeHandoff,
            fetchAccessStatus: legacy.fetchAccessStatus,
            bindDevice: legacy.bindDevice,
            refreshToken: legacy.refreshToken,
            syncSession: { _, device in
                let access = try await legacy.fetchAccessStatus()
                let outcome: SessionSyncDeviceBindingOutcome
                if access.toAccessStatus().isActive {
                    do {
                        _ = try await legacy.bindDevice(device)
                        outcome = .bound
                    } catch let error as DeviceBindingError {
                        switch error {
                        case .seatCapacityExceeded:
                            outcome = .deviceLimitReached
                        case .unauthorized:
                            throw SessionSyncError.invalidCredential
                        default:
                            outcome = .notAttempted
                        }
                    }
                } else {
                    outcome = .notAttempted
                }
                return SessionSyncResult(
                    sessionStatus: .unchanged,
                    syncStatus: .complete,
                    accessStatus: access,
                    deviceBindingOutcome: outcome,
                    connectedDeviceAvailability: .available,
                )
            },
        )
    }

    private func receiveValidForegroundRevalidation(
        from store: TestStore<AccountAccessFeature.State, AccountAccessFeature.Action>,
        sessionExpiry: Date,
    ) async {
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated)
    }

    private func expectedSnapshot(status: AccessStatus, sessionExpiry: Date) -> AccessStatusSnapshot {
        AccessStatusSnapshot(
            status: status,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
            deviceBindingVerifiedAt: referenceDate,
        )
    }

    // MARK: - ACC-002-handle_entitlement_change

    // MARK: Pattern A — 순수 상태 전환 (computed property)

    /// ACC-002-handle_entitlement_change: 구매와 device binding 완료 시 accountAccessStepState가 .complete로 전환된다.
    /// active status만으로는 complete가 아니며 binding 성공이 함께 필요함을 검증한다.
    /// - 검증 내용: .coreLicenseActive + isComplete=true → accountAccessStepState == .complete
    /// - 사전 조건: hasAccountSession=true, status=.none
    /// - 기대 결과: status 변경 후 accountAccessStepState == .complete
    func testPurchaseCompleteStepState() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        // AccessStatus.none을 명시적으로 지정 (`.none`은 Optional.none= nil로 해석됨)
        state.status = AccessStatus.none

        XCTAssertEqual(state.accountAccessStepState, .blocked)

        state.status = .coreLicenseActive
        XCTAssertEqual(state.accountAccessStepState, .pending)

        state.isComplete = true

        XCTAssertEqual(state.accountAccessStepState, .complete)
    }

    /// ACC-002-handle_entitlement_change: trial 만료 시 accountAccessStepState가 .blocked로 전환된다.
    /// status가 .trialActive에서 .trialExpired로 변경될 때 step state가 올바르게 계산되는지 검증한다.
    /// - 검증 내용: .trialExpired → accountAccessStepState == .blocked
    /// - 사전 조건: hasAccountSession=true, status=.trialActive
    /// - 기대 결과: status 변경 후 accountAccessStepState == .blocked
    func testExpirationStepState() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .trialActive
        state.isComplete = true

        // 초기 상태: active → complete
        XCTAssertEqual(state.accountAccessStepState, .complete)

        // 만료: 상태 전환
        state.status = .trialExpired

        XCTAssertEqual(state.accountAccessStepState, .blocked)
    }

    /// ACC-002-handle_entitlement_change: 결제 환불 시 accountAccessStepState가 .blocked로 전환된다.
    /// status가 .coreLicenseActive에서 .refunded로 변경될 때 step state가 올바르게 계산되는지 검증한다.
    /// - 검증 내용: .refunded → accountAccessStepState == .blocked
    /// - 사전 조건: hasAccountSession=true, status=.coreLicenseActive
    /// - 기대 결과: status 변경 후 accountAccessStepState == .blocked
    func testRefundStepState() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .coreLicenseActive
        state.isComplete = true

        // 초기 상태: active → complete
        XCTAssertEqual(state.accountAccessStepState, .complete)

        // 환불: 상태 전환
        state.status = .refunded

        XCTAssertEqual(state.accountAccessStepState, .blocked)
    }

    /// ACC-002-handle_entitlement_change: status 변화가 showsRetry를 올바르게 갱신한다.
    /// active status에서 inactive status로 변경될 때 showsRetry가 false→true로 전환되는지 검증한다.
    /// - 검증 내용: active status → showsRetry=false, inactive status → showsRetry=true
    /// - 사전 조건: status=nil, hasAccountSession=true
    /// - 기대 결과: status가 active→inactive로 변경 시 showsRetry가 true로 변경
    func testShowsRetryReflectsStatusChange() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true

        // status=nil → showsRetry=false
        XCTAssertFalse(state.showsRetry)

        // active status → showsRetry=false
        state.status = .coreLicenseActive
        XCTAssertFalse(state.showsRetry)

        // inactive status → showsRetry=true
        state.status = .trialExpired
        XCTAssertTrue(state.showsRetry)

        // 다시 active → showsRetry=false
        state.status = .trialActive
        XCTAssertFalse(state.showsRetry)
    }

    // MARK: Pattern B — TestStore (appDidBecomeActive reducer 동작)

    /// ACC-002-handle_entitlement_change: hasAccountSession=true 상태에서 appDidBecomeActive가 fetch를 트리거한다.
    /// 유효한 세션이 있을 때 foreground 복귀가 access status 갱신을 유발하는지 검증한다.
    /// - 검증 내용: appDidBecomeActive → fetchGeneration 증가, fetchAccessStatus 호출
    /// - 사전 조건: hasAccountSession=true
    /// - 기대 결과: fetchGeneration이 1 증가하고 fetchAccessStatus가 호출됨
    func testAppDidBecomeActiveWithSessionTriggersFetch() async {
        nonisolated(unsafe) var fetchCalled = false
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true

        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCalled = true
                    return AccessStatusResponse(hasAccess: true, status: "active", ownershipStatus: "owned", updateStatus: "active", reason: "active_entitlement",
                    productKey: "core",
                    source: "polar",)
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )
        store.exhaustivity = .off

        XCTAssertEqual(store.state.fetchGeneration, 0)

        await store.send(.appDidBecomeActive)
        await receiveValidForegroundRevalidation(
            from: store,
            sessionExpiry: referenceDate.addingTimeInterval(3600),
        )

        await store.receive(\.sessionSyncRequested)
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.unlocked)

        XCTAssertEqual(store.state.fetchGeneration, 0)
        XCTAssertEqual(store.state.syncGeneration, 1)
        XCTAssertTrue(store.state.isComplete)
        XCTAssertTrue(fetchCalled)
        await store.skipInFlightEffects()
    }

    /// ACC-002-handle_entitlement_change: hasAccountSession=false에서 appDidBecomeActive가 .none을 반환한다.
    /// 세션이 없을 때 foreground 복귀가 불필요한 네트워크 요청을 방지하는지 검증한다.
    /// - 검증 내용: hasAccountSession=false → guard가 fetch를 차단
    /// - 사전 조건: hasAccountSession=false (기본값)
    /// - 기대 결과: fetchGeneration이 증가하지 않고 fetchAccessStatus가 호출되지 않음
    func testAppDidBecomeActiveWithoutSessionReturnsNone() async {
        nonisolated(unsafe) var fetchCalled = false

        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCalled = true
                    return AccessStatusResponse(hasAccess: true, status: "active", ownershipStatus: "owned", updateStatus: "active", reason: "active_entitlement",
                    productKey: "core",
                    source: "polar",)
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
        )

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertEqual(store.state.revalidationGeneration, 0)

        await store.send(.appDidBecomeActive)

        // guard에 의해 .none 반환 → fetchGeneration 변화 없음
        XCTAssertEqual(store.state.fetchGeneration, 0)
        XCTAssertFalse(fetchCalled)
    }

    /// ACC-002-handle_entitlement_change: appDidBecomeActive가 fetchGeneration을 정확히 1 증가시킨다.
    /// foreground 복귀 시 generation 카운터가 올바르게 증가하는지 반복 호출로 검증한다.
    /// - 검증 내용: appDidBecomeActive 2회 → fetchGeneration 2 증가
    /// - 사전 조건: hasAccountSession=true
    /// - 기대 결과: fetchGeneration이 호출 횟수만큼 정확히 증가
    func testAppDidBecomeActiveIncrementsGenerationEachTime() async {
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true

        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    AccessStatusResponse(hasAccess: true, status: "active", ownershipStatus: "owned", updateStatus: "active", reason: "active_entitlement",
                    productKey: "core",
                    source: "polar",)
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )
        store.exhaustivity = .off

        XCTAssertEqual(store.state.fetchGeneration, 0)

        await store.send(.appDidBecomeActive)
        await receiveValidForegroundRevalidation(
            from: store,
            sessionExpiry: referenceDate.addingTimeInterval(3600),
        )
        await store.receive(\.sessionSyncRequested)
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.unlocked)
        XCTAssertEqual(store.state.revalidationGeneration, 1)

        await store.send(.appDidBecomeActive)
        await receiveValidForegroundRevalidation(
            from: store,
            sessionExpiry: referenceDate.addingTimeInterval(3600),
        )
        XCTAssertEqual(store.state.revalidationGeneration, 2)

        await store.send(.appDidBecomeActive)
        await receiveValidForegroundRevalidation(
            from: store,
            sessionExpiry: referenceDate.addingTimeInterval(3600),
        )
        XCTAssertEqual(store.state.revalidationGeneration, 3)
        XCTAssertEqual(store.state.syncGeneration, 1)
        await store.skipInFlightEffects()
    }

    /// ACC-002-handle_entitlement_change: appDidBecomeActive 후 fetch 성공 시 status가 갱신된다.
    /// foreground 복귀 후 fetchAccessStatus 응답이 올바르게 state에 반영되는지 검증한다.
    /// - 검증 내용: accessStatusResponse → state.status 업데이트
    /// - 사전 조건: hasAccountSession=true, fetchAccessStatus가 .trialActive 반환
    /// - 기대 결과: status == .trialActive, isComplete == true
    func testFetchSucceedsAfterAppDidBecomeActiveUpdatesStatus() async {
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.sessionExpiresAt = referenceDate.addingTimeInterval(3600)

        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    AccessStatusResponse(hasAccess: true, status: "active", ownershipStatus: "owned", updateStatus: "active", reason: "active_entitlement",
                    productKey: "trial",
                    source: "polar",)
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )
        store.exhaustivity = .off

        await store.send(.appDidBecomeActive)
        await receiveValidForegroundRevalidation(
            from: store,
            sessionExpiry: referenceDate.addingTimeInterval(3600),
        )

        let expectedSnapshot = AccessStatusSnapshot(
            status: .trialActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
            sessionExpiresAt: referenceDate.addingTimeInterval(3600),
            deviceBindingVerifiedAt: referenceDate,
        )

        store.exhaustivity = .off
        await store.receive(\.sessionSyncRequested)
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.unlocked)
        XCTAssertEqual(store.state.status, .trialActive)
        XCTAssertEqual(store.state.snapshot?.status, expectedSnapshot.status)
        XCTAssertTrue(store.state.isComplete)
        await store.skipInFlightEffects()
    }

    // MARK: - Pattern C — Hydration (entitlement + session 축 통합 매핑)

    /// ACC-002-handle_entitlement_change: `.coreLicenseActive + sessionExpiresAt` snapshot hydration 시
    /// entitlement 축은 active/step complete로, session 축은 signedIn으로 동시에 파생된다.
    /// launch snapshot hydration 한 번에 두 축이 모두 채워지는지 검증한다.
    /// - 검증 내용: hydrateLaunchSnapshot(.coreLicenseActive + sessionExpiresAt) →
    ///   status == .coreLicenseActive, accountAccessStepState == .complete,
    ///   accountAccessAuthAxis == .signedIn, hasAccountSession == true
    /// - 사전 조건: 빈 초기 상태
    /// - 기대 결과: 두 축 모두 active/signedIn으로 파생. session 기반 auth 단언 (status.isActive에서 추론하지 않음)
    func testHydrateLaunchSnapshotWithCoreLicenseActiveSessionMapsToCompleteAndSignedIn() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate.addingTimeInterval(86400),
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
            deviceBindingVerifiedAt: referenceDate,
        )

        let store = makeTestStore()
        store.exhaustivity = .off

        await store.send(.hydrateLaunchSnapshot(snapshot))

        // entitlement 축: active → step complete
        XCTAssertEqual(store.state.status, .coreLicenseActive)
        XCTAssertEqual(store.state.accountAccessStepState, .complete)
        // session 축: sessionExpiresAt != nil → signedIn 파생 (가짜 세션 금지)
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signedIn)
        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertEqual(store.state.sessionExpiresAt, sessionExpiry)
        await store.finish()
    }

    // MARK: - Integration

    /// ACC-002 Integration: appDidBecomeActive → fetchGeneration 증가 → fetchAccessStatus → delegate(.unlocked) 전체 파이프라인을
    /// 검증한다.
    /// foreground 복귀가 access status 갱신을 트리거하고, 성공 응답이 delegate까지 전달되는지 확인한다.
    /// - 검증 내용: appDidBecomeActive → accessStatusResponse → delegate(.unlocked)
    /// - 사전 조건: hasAccountSession=true, fetchAccessStatus가 .coreLicenseActive 반환
    /// - 기대 결과: fetchGeneration=1, status=.coreLicenseActive, delegate(.unlocked) 수신
    func testIntegrationAppDidBecomeActiveToUnlockedFullPipeline() async {
        nonisolated(unsafe) var fetchCallCount = 0
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.sessionExpiresAt = sessionExpiry

        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCallCount += 1
                    return AccessStatusResponse(hasAccess: true, status: "active", ownershipStatus: "owned", updateStatus: "active", reason: "active_entitlement",
                    productKey: "core",
                    source: "polar",)
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )
        store.exhaustivity = .off

        // Step 1: appDidBecomeActive → fetchGeneration 증가
        await store.send(.appDidBecomeActive)
        await receiveValidForegroundRevalidation(
            from: store,
            sessionExpiry: sessionExpiry,
        )

        // Step 2: fetchAccessStatus 성공 응답 → status/snapshot 갱신
        let expectedSnapshot = expectedSnapshot(status: .coreLicenseActive, sessionExpiry: sessionExpiry)
        store.exhaustivity = .off
        await store.receive(\.sessionSyncRequested)
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted)
        await store.receive(\.delegate.unlocked)
        XCTAssertEqual(store.state.status, .coreLicenseActive)
        XCTAssertEqual(store.state.snapshot?.status, expectedSnapshot.status)
        XCTAssertTrue(store.state.isComplete)
        await store.skipInFlightEffects()

        XCTAssertEqual(fetchCallCount, 1, "fetchAccessStatus는 정확히 1회 호출되어야 함")
    }
}

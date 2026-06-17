// swiftlint:disable force_unwrapping

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

    private func makeTestStore(
        accountSessionClient: AccountSessionClient = .testValue,
        authNetworkClient: AuthNetworkClient = .testValue,
        snapshotClient: AccessStatusSnapshotClient = .testValue,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.accessStatusSnapshotClient = snapshotClient
            $0.date = .constant(referenceDate)
        }
    }

    // MARK: - ACC-002-handle_entitlement_change

    // MARK: Pattern A — 순수 상태 전환 (computed property)

    /// ACC-002-handle_entitlement_change: 구매 완료 시 accountAccessStepState가 .complete로 전환된다.
    /// status가 .none에서 .coreLicenseActive로 변경될 때 step state가 올바르게 계산되는지 검증한다.
    /// - 검증 내용: .coreLicenseActive → accountAccessStepState == .complete
    /// - 사전 조건: hasAccountSession=true, status=.none
    /// - 기대 결과: status 변경 후 accountAccessStepState == .complete
    func testPurchaseCompleteStepState() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        // AccessStatus.none을 명시적으로 지정 (`.none`은 Optional.none= nil로 해석됨)
        state.status = AccessStatus.none

        XCTAssertEqual(state.accountAccessStepState, .blocked)

        state.status = .coreLicenseActive

        XCTAssertEqual(state.accountAccessStepState, .complete)
    }

    /// ACC-002-handle_entitlement_change: beta trial 만료 시 accountAccessStepState가 .blocked로 전환된다.
    /// status가 .betaTrialActive에서 .trialExpired로 변경될 때 step state가 올바르게 계산되는지 검증한다.
    /// - 검증 내용: .trialExpired → accountAccessStepState == .blocked
    /// - 사전 조건: hasAccountSession=true, status=.betaTrialActive
    /// - 기대 결과: status 변경 후 accountAccessStepState == .blocked
    func testExpirationStepState() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = .betaTrialActive

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
        state.status = .betaTrialActive
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
                    return AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )
        // store.exhaustivity = .off: appDidBecomeActive 이후 fetchAccessStatusEffect의 응답인
        // accessStatusResponse는 검증 범위 밖 (fetchGeneration 증가만 확인)
        store.exhaustivity = .off

        XCTAssertEqual(store.state.fetchGeneration, 0)

        await store.send(.appDidBecomeActive)

        XCTAssertEqual(store.state.fetchGeneration, 1)
        XCTAssertTrue(fetchCalled)
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
                    return AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
        )

        XCTAssertEqual(store.state.hasAccountSession, false)
        XCTAssertEqual(store.state.fetchGeneration, 0)

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
                    AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )
        store.exhaustivity = .off

        XCTAssertEqual(store.state.fetchGeneration, 0)

        await store.send(.appDidBecomeActive)
        XCTAssertEqual(store.state.fetchGeneration, 1)

        await store.send(.appDidBecomeActive)
        XCTAssertEqual(store.state.fetchGeneration, 2)

        await store.send(.appDidBecomeActive)
        XCTAssertEqual(store.state.fetchGeneration, 3)
    }

    /// ACC-002-handle_entitlement_change: appDidBecomeActive 후 fetch 성공 시 status가 갱신된다.
    /// foreground 복귀 후 fetchAccessStatus 응답이 올바르게 state에 반영되는지 검증한다.
    /// - 검증 내용: accessStatusResponse → state.status 업데이트
    /// - 사전 조건: hasAccountSession=true, fetchAccessStatus가 .betaTrialActive 반환
    /// - 기대 결과: status == .betaTrialActive, isComplete == true
    func testFetchSucceedsAfterAppDidBecomeActiveUpdatesStatus() async {
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true

        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    AccessStatusResponse(status: .betaTrialActive, entitlements: [.betaTrial])
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )

        await store.send(.appDidBecomeActive) { state in
            state.fetchGeneration = 1
        }

        let expectedSnapshot = AccessStatusSnapshot(
            status: .betaTrialActive,
            expiresAt: nil,
            entitlements: [.betaTrial],
            fetchedAt: referenceDate,
        )

        await store.receive(\.accessStatusResponse) { state in
            state.status = .betaTrialActive
            state.snapshot = expectedSnapshot
            state.isComplete = true
            state.errorMessage = nil
        }

        await store.receive(\.delegate.unlocked)
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
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true

        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCallCount += 1
                    return AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )

        // Step 1: appDidBecomeActive → fetchGeneration 증가
        await store.send(.appDidBecomeActive) { state in
            state.fetchGeneration = 1
        }

        // Step 2: fetchAccessStatus 성공 응답 → status/snapshot 갱신
        let expectedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            expiresAt: nil,
            entitlements: [.coreLicense],
            fetchedAt: referenceDate,
        )
        await store.receive(\.accessStatusResponse) { state in
            state.status = .coreLicenseActive
            state.snapshot = expectedSnapshot
            state.isComplete = true
            state.errorMessage = nil
        }

        // Step 3: delegate(.unlocked) 전달
        await store.receive(\.delegate.unlocked)
        await store.finish()

        XCTAssertEqual(fetchCallCount, 1, "fetchAccessStatus는 정확히 1회 호출되어야 함")
    }
}

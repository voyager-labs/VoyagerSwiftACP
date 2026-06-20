// swiftlint:disable force_unwrapping

@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-002-check_entitlement_status spec-owner 테스트

 interaction_id: ACC-002-check_entitlement_status

 fetchAccessStatus 호출 및 응답 처리 검증:
 - onAppear에서 session 복원 후 fetchAccessStatus 자동 트리거
 - 성공 응답 → status 갱신, snapshot 저장, delegate 전달
 - 실패 응답 → error 상태 설정
 - generation guard: stale 응답 무시
 - retryTapped: generation 증가 후 재시도
 */

@MainActor
final class ACC002CheckEntitlementStatusTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTestStore(
        accountSessionClient: AccountSessionClient = .testValue,
        authNetworkClient: AuthNetworkClient = .testValue,
        snapshotClient: AccessStatusSnapshotClient = .testValue,
        checkoutURLClient: CheckoutURLClient = .testValue,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.accessStatusSnapshotClient = snapshotClient
            $0.checkoutURLClient = checkoutURLClient
            $0.date = .constant(referenceDate)
        }
    }

    // MARK: - ACC-002-check_entitlement_status

    /// ACC-002-check_entitlement_status: onAppear에서 session 복원 후 fetchAccessStatus가 자동 트리거된다.
    /// session 복원 시 fetchGeneration이 증가하고 fetchAccessStatusEffect가 실행되는지 검증한다.
    /// - 검증 내용: onAppear → session 복원 → fetchGeneration 증가, fetchAccessStatus 호출
    /// - 사전 조건: sessionClient.read가 유효한 AccountSession 반환
    /// - 기대 결과: hasAccountSession=true, fetchGeneration=1, fetchAccessStatus 호출됨
    func testOnAppearSessionRestoredTriggersFetch() async {
        nonisolated(unsafe) var fetchCalled = false
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: {
                    AccountSession(accessToken: "valid-token", status: .coreLicenseActive)
                },
                persist: { _ in },
                delete: {},
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
        )
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\._onAppearSessionRestored)

        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertEqual(store.state.fetchGeneration, 1)
        XCTAssertTrue(fetchCalled)
    }

    /// ACC-002-check_entitlement_status: pricing URL 설정 누락은 앱 crash가 아니라 error projection으로 처리된다.
    /// PUBLIC_WEB_BASE_URL missing/invalid 상황에서 fatalError 없이 Retry 가능한 오류 상태로 남는지 검증한다.
    /// - 검증 내용: `.openPricingTapped` → `._webURLResult(.failure(.notConfigured))`, status=nil, errorMessage 설정.
    /// - 사전 조건: 세션 있음, entitlement none 상태에서 Web Pricing CTA 실행.
    /// - 기대 결과: accountAccessStepState=.error, isComplete=false.
    func testOpenPricingMissingURLConfigProjectsErrorWithoutCrash() async {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.status = AccessStatus.none

        let store = makeTestStore(
            checkoutURLClient: CheckoutURLClient(
                openURL: { _ in XCTFail("URL 설정 실패 시 브라우저를 열면 안 됨") },
                checkoutURL: { throw AccessError.notConfigured },
                pricingURL: { throw AccessError.notConfigured },
                supportURL: { throw AccessError.notConfigured },
                accountURL: { throw AccessError.notConfigured },
            ),
            initialState: state,
        )

        await store.send(.openPricingTapped)
        await store.receive(\._webURLResult) { state in
            state.status = nil
            state.isComplete = false
            state.errorMessage = "Access service is not configured."
        }

        XCTAssertEqual(store.state.accountAccessStepState, .error)
        XCTAssertTrue(store.state.canRetry)
    }

    /// ACC-002-check_entitlement_status: invalid PUBLIC_WEB_BASE_URL 값은 fatalError가 아니라 구성 오류로 처리된다.
    /// live URL validator가 잘못된 scheme/host를 process crash 없이 `AccessError.notConfigured`로 접는지 검증한다.
    /// - 검증 내용: invalid web URL 값 → `AccessError.notConfigured` throw.
    /// - 사전 조건: required public web URL 값이 http/https host URL이 아님.
    /// - 기대 결과: fatalError 없이 구성 오류가 throw된다.
    func testInvalidWebURLConfigThrowsNotConfiguredWithoutCrash() {
        let invalidValues = [
            "not a url",
            "ftp://voyager.fm",
            "https://",
        ]

        for value in invalidValues {
            XCTAssertThrowsError(try CheckoutURLClient.validatedWebURL(
                for: "PUBLIC_WEB_BASE_URL",
                value: value,
            )) { error in
                XCTAssertEqual(error as? AccessError, .notConfigured)
            }
        }
    }

    /// ACC-002-check_entitlement_status: fetchAccessStatus 성공 시 status와 snapshot이 갱신된다.
    /// active 상태 응답을 받으면 state.status와 state.snapshot이 올바르게 설정되는지 검증한다.
    /// - 검증 내용: success 응답 → status 갱신, snapshot 생성, isComplete=true
    /// - 사전 조건: fetchGeneration=1, active 상태의 AccessStatusResponse
    /// - 기대 결과: status=.coreLicenseActive, snapshot!=nil, isComplete=true, errorMessage=nil
    func testFetchAccessStatusSuccessUpdatesStatusAndSnapshot() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        let store = makeTestStore(initialState: state)
        store.exhaustivity = .off

        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response)))

        XCTAssertEqual(store.state.status, .coreLicenseActive)
        XCTAssertNotNil(store.state.snapshot)
        XCTAssertEqual(store.state.snapshot?.status, .coreLicenseActive)
        XCTAssertTrue(store.state.isComplete)
        XCTAssertNil(store.state.errorMessage)
    }

    /// ACC-002-check_entitlement_status: fetchAccessStatus 성공 시 delegate(.unlocked)가 전달된다.
    /// active 상태 응답에 대해 delegate(.unlocked)가 전송되고 isComplete=true가 되는지 검증한다.
    /// - 검증 내용: success 응답 → delegate(.unlocked) 수신, isComplete=true
    /// - 사전 조건: fetchGeneration=1, active 상태의 AccessStatusResponse
    /// - 기대 결과: delegate(.unlocked) 수신, isComplete=true
    func testFetchAccessStatusSuccessActiveSendsDelegateUnlocked() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        let store = makeTestStore(initialState: state)

        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response))) { state in
            state.status = .coreLicenseActive
            state.snapshot = AccessStatusSnapshot(
                status: .coreLicenseActive,
                currentPeriodEnd: nil,
                fetchedAt: self.referenceDate,
            )
            state.isComplete = true
            state.errorMessage = nil
        }

        await store.receive(\.delegate)
    }

    /// ACC-002-check_entitlement_status: fetchAccessStatus networkFailure 시 error 상태로 전환된다.
    /// networkFailure 응답을 받으면 status=.networkFailure, errorMessage가 설정되는지 검증한다.
    /// - 검증 내용: failure(.networkFailure) → status=.networkFailure, errorMessage 설정, isComplete=false
    /// - 사전 조건: fetchGeneration=1
    /// - 기대 결과: status=.networkFailure, errorMessage!=nil, isComplete=false
    func testFetchAccessStatusNetworkFailureSetsErrorState() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        let store = makeTestStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.accessStatusResponse(generation: 1, result: .failure(.networkFailure)))

        XCTAssertEqual(store.state.status, .networkFailure)
        XCTAssertNotNil(store.state.errorMessage)
        XCTAssertFalse(store.state.isComplete)
    }

    /// ACC-002-check_entitlement_status: fetchAccessStatus decoding 실패 시 errorMessage만 설정된다.
    /// networkFailure 외 에러는 status를 변경하지 않고 errorMessage만 설정하는지 검증한다.
    /// - 검증 내용: failure(.decodingFailure) → status 유지, errorMessage 설정, isComplete=false
    /// - 사전 조건: fetchGeneration=1, status는 nil
    /// - 기대 결과: status=nil (변경 없음), errorMessage!=nil, isComplete=false
    func testFetchAccessStatusDecodingFailureSetsErrorMessage() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        let store = makeTestStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.accessStatusResponse(generation: 1, result: .failure(.decodingFailure)))

        XCTAssertNil(store.state.status)
        XCTAssertNotNil(store.state.errorMessage)
        XCTAssertFalse(store.state.isComplete)
    }

    /// ACC-002-check_entitlement_status: stale generation 응답은 무시된다.
    /// 현재 fetchGeneration과 다른 generation의 응답은 state를 변경하지 않는지 검증한다.
    /// - 검증 내용: generation 불일치 → 상태 변화 없음
    /// - 사전 조건: fetchGeneration=2, 이전 generation(1)의 응답
    /// - 기대 결과: status=nil, errorMessage=nil, isComplete=false, snapshot=nil
    func testStaleGenerationResponseIgnored() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 2
        let store = makeTestStore(initialState: state)

        await store.send(.accessStatusResponse(generation: 1, result: .success(
            AccessStatusResponse(
                hasAccess: true,
                status: "active",
                reason: "active_entitlement",
                productKey: "core",
                source: "polar",
            ),
        )))

        XCTAssertNil(store.state.status)
        XCTAssertNil(store.state.errorMessage)
        XCTAssertFalse(store.state.isComplete)
        XCTAssertNil(store.state.snapshot)
    }

    /// ACC-002-check_entitlement_status: retryTapped 시 fetchGeneration이 증가하고 재시도된다.
    /// retryTapped 액션으로 fetchGeneration이 증가하고 fetchAccessStatus가 재호출되는지 검증한다.
    /// - 검증 내용: retryTapped → fetchGeneration 증가, fetchAccessStatus 재호출
    /// - 사전 조건: 기본 상태 (fetchGeneration=0)
    /// - 기대 결과: fetchGeneration=1, fetchAccessStatus 호출됨
    func testRetryTappedIncrementsGenerationAndTriggersFetch() async {
        nonisolated(unsafe) var fetchCalled = false
        let store = makeTestStore(
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
        )
        store.exhaustivity = .off

        await store.send(.retryTapped)

        XCTAssertEqual(store.state.fetchGeneration, 1)
        XCTAssertTrue(fetchCalled)
    }

    /// ACC-002-check_entitlement_status: inactive 상태 응답은 delegate unlock 없이 isComplete=false를 유지한다.
    /// trialExpired 등 inactive 상태 응답을 받으면 delegate 없이 error 상태로 전환되는지 검증한다.
    /// - 검증 내용: inactive 응답 → isComplete=false, delegate 미전송, errorMessage 설정, snapshot 저장
    /// - 사전 조건: fetchGeneration=1, inactive 상태(trialExpired)의 AccessStatusResponse
    /// - 기대 결과: isComplete=false, status=.trialExpired, errorMessage!=nil, snapshot!=nil
    func testFetchAccessStatusInactiveDoesNotUnlock() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        let store = makeTestStore(initialState: state)
        store.exhaustivity = .off

        let response = AccessStatusResponse(
            hasAccess: false,
            status: "expired",
            reason: "expired_entitlement",
            productKey: "trial",
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response)))

        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.status, .trialExpired)
        XCTAssertNotNil(store.state.errorMessage)
        XCTAssertNotNil(store.state.snapshot)
    }

    // MARK: - ACC-002-cached-snapshot-fallback

    /// ACC-002: fetchAccessStatus 3회 실패 후 캐시된 snapshot이 복원된다.
    /// networkFailure가 3회 누적되면 캐시된 snapshot을 불러와 status/snapshot/isComplete를 복원한다.
    /// - 검증 내용: fetchRetryCount >= 3 + networkFailure → cached snapshot 복원
    /// - 사전 조건: fetchRetryCount=3, fetchGeneration=1, snapshotClient.load가 유효한 snapshot 반환
    /// - 기대 결과: status/snapshot/isComplete가 캐시된 값으로 복원, errorMessage=한국어 메시지
    func testCachedSnapshotRestoredAfterThreeFailures() async {
        let cachedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
        )
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.fetchRetryCount = 3
        let store = makeTestStore(
            snapshotClient: AccessStatusSnapshotClient(
                load: { cachedSnapshot },
                save: { _ in },
                remove: {},
            ),
            initialState: state,
        )

        await store.send(.accessStatusResponse(generation: 1, result: .failure(.networkFailure))) { state in
            state.isComplete = false
            state.errorMessage = "Network error. Please check your connection and try again."
            state.status = .networkFailure
            state.fetchRetryCount = 0
        }
        await store.receive(\._cachedSnapshotRestored) { state in
            state.status = .coreLicenseActive
            state.snapshot = cachedSnapshot
            state.isComplete = true
            state.errorMessage = "일시적인 네트워크 오류"
        }
    }

    /// ACC-002: fetchAccessStatus 3회 실패 후 캐시된 snapshot이 없으면 error 상태를 유지한다.
    /// networkFailure가 3회 누적되었지만 저장된 snapshot이 없으면 status를 .networkFailure로 유지하고
    /// errorMessage로 error projection을 제공한다. status가 .none으로 collapse되지 않음을 검증한다.
    /// - 검증 내용: fetchRetryCount >= 3 + networkFailure + load()=nil → error 상태 유지 (status collapse 방지)
    /// - 사전 조건: fetchRetryCount=3, fetchGeneration=1, snapshotClient.load()=nil
    /// - 기대 결과: status=.networkFailure (NOT .none), isComplete=false, accountAccessStepState=.error
    func testConservativeFallbackAfterThreeFailuresNoCache() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.fetchRetryCount = 3
        state.hasAccountSession = true
        let store = makeTestStore(initialState: state)

        await store.send(.accessStatusResponse(generation: 1, result: .failure(.networkFailure))) { state in
            state.isComplete = false
            state.errorMessage = "Network error. Please check your connection and try again."
            state.status = .networkFailure
            state.fetchRetryCount = 0
        }
        await store.receive(\._cachedSnapshotRestored)

        XCTAssertEqual(store.state.status, .networkFailure)
        XCTAssertNotEqual(store.state.status, AccessStatus.none)
        XCTAssertEqual(store.state.accountAccessStepState, .error)
        XCTAssertTrue(store.state.canRetry)
    }

    /// ACC-002: retryable networkFailure는 status를 .none으로 collapse하지 않고 .networkFailure로 유지한다.
    /// 첫 번째 networkFailure (retry budget 남음)가 error 상태를 정확히 도출하는지 검증한다.
    /// - 검증 내용: networkFailure (retryCount=0) → status=.networkFailure, stepState=.error
    /// - 사전 조건: fetchGeneration=1, fetchRetryCount=0, hasAccountSession=true
    /// - 기대 결과: status=.networkFailure (NOT .none), accountAccessStepState=.error
    func testRetryableNetworkFailureStaysErrorNotNone() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.fetchRetryCount = 0
        state.hasAccountSession = true
        let store = makeTestStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.accessStatusResponse(generation: 1, result: .failure(.networkFailure)))

        XCTAssertEqual(store.state.status, .networkFailure)
        XCTAssertNotEqual(store.state.status, AccessStatus.none)
        XCTAssertEqual(store.state.accountAccessStepState, .error)
        XCTAssertTrue(store.state.canRetry)
    }

    /// ACC-002: trial_active 응답의 currentPeriodEnd가 trialExpiresAt로 보존된다.
    /// trial entitlement가 full access로 평가될 때 trial 만료 시점 정보가 유지되는지 검증한다.
    /// - 검증 내용: success(trial_active + currentPeriodEnd) → status=.trialActive, trialExpiresAt 보존
    /// - 사전 조건: fetchGeneration=1
    /// - 기대 결과: status=.trialActive, trialExpiresAt==응답의 currentPeriodEnd, isComplete=true
    func testTrialActivePreservesTrialExpiresAtDetail() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        let store = makeTestStore(initialState: state)
        store.exhaustivity = .off

        let trialEndDate = Date(timeIntervalSince1970: 1_700_010_000)
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "trial",
            productKey: "trial",
            currentPeriodEnd: trialEndDate,
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response)))

        XCTAssertEqual(store.state.status, .trialActive)
        XCTAssertEqual(store.state.trialExpiresAt, trialEndDate)
        XCTAssertTrue(store.state.isComplete)
    }

    /// ACC-002: 만료된 snapshot은 복원 시 거부된다 (entitlement bypass 방지).
    /// networkFailure 3회 + 캐시된 snapshot의 expiresAt이 과거 → status는 .networkFailure로 유지 (error/retry).
    /// - 검증 내용: 만료 snapshot + retry 소진 → status collapse 방지, error projection 유지
    /// - 사전 조건: fetchRetryCount=3, fetchGeneration=1, snapshot 만료
    /// - 기대 결과: status=.networkFailure (NOT .none), isComplete=false, accountAccessStepState=.error
    func testExpiredSnapshotRejectedOnRestore() async {
        let expiredSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate.addingTimeInterval(-3600),
            fetchedAt: referenceDate,
        )
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.fetchRetryCount = 3
        state.hasAccountSession = true
        let store = makeTestStore(
            snapshotClient: AccessStatusSnapshotClient(
                load: { expiredSnapshot },
                save: { _ in },
                remove: {},
            ),
            initialState: state,
        )

        await store.send(.accessStatusResponse(generation: 1, result: .failure(.networkFailure))) { state in
            state.isComplete = false
            state.errorMessage = "Network error. Please check your connection and try again."
            state.status = .networkFailure
            state.fetchRetryCount = 0
        }
        await store.receive(\._cachedSnapshotRestored)

        XCTAssertEqual(store.state.status, .networkFailure)
        XCTAssertNotEqual(store.state.status, AccessStatus.none)
        XCTAssertEqual(store.state.accountAccessStepState, .error)
    }

    /// ACC-002: 성공적인 fetch 후 fetchRetryCount가 0으로 리셋된다.
    /// 연속 실패 후 성공하면 retry count를 초기화하여 다음 실패 사이클을 올바르게 시작한다.
    /// - 검증 내용: success 응답 → fetchRetryCount=0
    /// - 사전 조건: fetchRetryCount=3, fetchGeneration=1
    /// - 기대 결과: fetchRetryCount=0
    func testFetchRetryCountResetOnSuccess() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.fetchRetryCount = 3
        let store = makeTestStore(initialState: state)
        store.exhaustivity = .off

        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response)))

        XCTAssertEqual(store.state.fetchRetryCount, 0)
        XCTAssertEqual(store.state.status, .coreLicenseActive)
    }

    // MARK: - ACC-002-check_entitlement_status (retry logic)

    /// ACC-002-check_entitlement_status: networkFailure 시 fetchRetryCount가 increase되고
    /// _fetchRetryScheduled가 발송되는지 검증한다.
    /// - 검증 내용: 첫 번째 networkFailure → fetchRetryCount=1, _fetchRetryScheduled 발송
    /// - 사전 조건: fetchGeneration=1, fetchRetryCount=0, networkFailure 에러
    /// - 기대 결과: fetchRetryCount=1, status=.networkFailure, isComplete=false
    func testFetchAccessStatusRetryScheduledOnNetworkFailure() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        let store = makeTestStore(initialState: state)

        // fetchRetryCount increment is now in handleAccessStatusResponse
        await store.send(.accessStatusResponse(generation: 1, result: .failure(.networkFailure))) { state in
            state.isComplete = false
            state.errorMessage = "Network error. Please check your connection and try again."
            state.status = .networkFailure
            state.fetchRetryCount = 1
        }

        // handleFetchRetryScheduled no longer increments (already done in send handler)
        await store.receive(\._fetchRetryScheduled)

        // Skip remaining async effects (sleep + fetch)
        store.exhaustivity = .off
    }

    /// ACC-002-check_entitlement_status: notConfigured 영구 에러는 retry되지 않는지 검증한다.
    /// - 검증 내용: .notConfigured → fetchRetryCount 유지, retry 미발송
    /// - 사전 조건: fetchGeneration=1, fetchRetryCount=0, notConfigured 에러
    /// - 기대 결과: fetchRetryCount=0 (변경 없음), status=nil, isComplete=false
    func testFetchAccessStatusPermanentErrorNoRetry() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        let store = makeTestStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.accessStatusResponse(generation: 1, result: .failure(.notConfigured)))

        XCTAssertEqual(store.state.fetchRetryCount, 0)
        XCTAssertNil(store.state.status)
        XCTAssertNotNil(store.state.errorMessage)
        XCTAssertFalse(store.state.isComplete)
    }

    // MARK: - Integration

    /// ACC-002 Integration: onAppear → session restore → fetchAccessStatus → delegate(.unlocked) 전체 파이프라인을 검증한다.
    /// 저장된 유효 session으로 onAppear부터 delegate(.unlocked)까지 모든 단계가 순차적으로 실행되는지 확인한다.
    /// - 검증 내용: onAppear → _onAppearSessionRestored → accessStatusResponse → delegate
    /// - 사전 조건: 유효 session, 성공 fetchAccessStatus
    /// - 기대 결과: status=.coreLicenseActive, isComplete=true, delegate(.unlocked) 수신
    func testIntegrationOnAppearToUnlockedFullPipeline() async {
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: {
                    AccountSession(accessToken: "valid-token", status: .coreLicenseActive)
                },
                persist: { _ in },
                delete: {},
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    AccessStatusResponse(
                        hasAccess: true,
                        status: "active",
                        reason: "active_entitlement",
                        productKey: "core",
                        source: "polar",
                    )
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
        )
        // TTL 타이머 pending 효과를 생략 (60초 타이머)
        store.exhaustivity = .off

        // Step 1: onAppear → session restore
        await store.send(.onAppear)
        await store.receive(\._onAppearSessionRestored) { state in
            state.hasAccountSession = true
            state.fetchGeneration = 1
        }

        // Step 2: fetchAccessStatus 성공 응답
        let expectedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
        )
        await store.receive(\.accessStatusResponse) { state in
            state.status = .coreLicenseActive
            state.snapshot = expectedSnapshot
            state.isComplete = true
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }

        // Step 3: delegate(.unlocked) 전달
        await store.receive(\.delegate)

        XCTAssertEqual(store.state.status, .coreLicenseActive)
        XCTAssertTrue(store.state.isComplete)
    }

    /// ACC-002 Integration: networkFailure 4회 누적으로 retry budget 소진 후 cached snapshot이 복원되는 전체 파이프라인을 검증한다.
    /// 네트워크 실패가 누적될 때 fetchRetryCount가 올바르게 증가하고, budget 소진 시 cached snapshot이 복원되는지 확인한다.
    /// - 검증 내용: 4회 networkFailure → fetchRetryCount 누적 → cached snapshot 복원
    /// - 사전 조건: fetchGeneration=0, snapshotClient.load가 유효 snapshot 반환
    /// - 기대 결과: fetchRetryCount=0→1→2→3→0, _cachedSnapshotRestored에서 status/snapshot 복원
    func testIntegrationFetchFailureRetryChainToCachedFallback() async {
        let cachedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
        )
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    throw AccessError.networkFailure
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
            snapshotClient: AccessStatusSnapshotClient(
                load: { cachedSnapshot },
                save: { _ in },
                remove: {},
            ),
        )
        // 각 networkFailure 후 _fetchRetryScheduled가 반환하는 sleep+fetch async 효과는 검증 범위 밖
        store.exhaustivity = .off

        // Failure 1: retryCount 0→1, _fetchRetryScheduled(0) 발송
        await store.send(.accessStatusResponse(generation: 0, result: .failure(.networkFailure)))
        XCTAssertEqual(store.state.fetchRetryCount, 1)
        XCTAssertEqual(store.state.status, .networkFailure)

        // Failure 2: retryCount 1→2, _fetchRetryScheduled(1) 발송
        await store.send(.accessStatusResponse(generation: 0, result: .failure(.networkFailure)))
        XCTAssertEqual(store.state.fetchRetryCount, 2)

        // Failure 3: retryCount 2→3, _fetchRetryScheduled(2) 발송
        await store.send(.accessStatusResponse(generation: 0, result: .failure(.networkFailure)))
        XCTAssertEqual(store.state.fetchRetryCount, 3)

        // Failure 4: retryBudget 소진 → _cachedSnapshotRestored로 fallback
        await store.send(.accessStatusResponse(generation: 0, result: .failure(.networkFailure))) { state in
            state.isComplete = false
            state.errorMessage = "Network error. Please check your connection and try again."
            state.fetchRetryCount = 0
        }
        await store.receive(\._cachedSnapshotRestored) { state in
            state.status = .coreLicenseActive
            state.snapshot = cachedSnapshot
            state.isComplete = true
            state.errorMessage = "일시적인 네트워크 오류"
        }
    }

    /// ACC-002 Integration: retryTapped → fetchGeneration 증가 → fetchAccessStatus → delegate(.unlocked) 전체 파이프라인을 검증한다.
    /// 수동 retry가 fetchGeneration을 증가시키고, 성공 응답이 delegate까지 전달되는지 확인한다.
    /// - 검증 내용: retryTapped → accessStatusResponse → delegate(.unlocked)
    /// - 사전 조건: fetchGeneration=0, fetchAccessStatus 성공
    /// - 기대 결과: fetchGeneration=1, status=.coreLicenseActive, delegate(.unlocked) 수신
    func testIntegrationRetryTappedToUnlockedFullPipeline() async {
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    AccessStatusResponse(
                        hasAccess: true,
                        status: "active",
                        reason: "active_entitlement",
                        productKey: "core",
                        source: "polar",
                    )
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
        )

        await store.send(.retryTapped) { state in
            state.fetchGeneration = 1
        }

        let expectedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
        )
        await store.receive(\.accessStatusResponse) { state in
            state.status = .coreLicenseActive
            state.snapshot = expectedSnapshot
            state.isComplete = true
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }
        await store.receive(\.delegate.unlocked)
        await store.finish()
    }
}

// swiftlint:enable force_unwrapping

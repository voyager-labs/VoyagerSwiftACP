// swiftlint:disable force_unwrapping

import Clocks
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

    private static let deviceBindingSuccessAuthNetworkClient = AuthNetworkClient(
        exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
        fetchAccessStatus: { throw AccessError.notConfigured },
        bindDevice: { _ in DeviceBindingResponse(ok: true) },
        refreshToken: { throw AccessError.notConfigured },
    )

    private func makeTestStore(
        accountSessionClient: AccountSessionClient = .testValue,
        authNetworkClient: AuthNetworkClient = ACC002CheckEntitlementStatusTests.deviceBindingSuccessAuthNetworkClient,
        snapshotClient: AccessStatusSnapshotClient = .testValue,
        checkoutURLClient: CheckoutURLClient = .testValue,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        let clock = TestClock()
        return TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.accessStatusSnapshotClient = snapshotClient
            $0.checkoutURLClient = checkoutURLClient
            $0.date = .constant(referenceDate)
            $0.continuousClock = clock
        }
    }

    private func assertTerminalAccessFailure(
        error: AccessError,
        errorMessage: String,
    ) async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let trialExpiry = referenceDate.addingTimeInterval(7200)
        var state = AccountAccessFeature.State()
        state.status = .coreLicenseActive
        state.snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: trialExpiry,
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
            deviceBindingVerifiedAt: referenceDate,
        )
        state.isComplete = true
        state.trialExpiresAt = trialExpiry
        state.hasAccountSession = true
        state.didBootstrap = true
        state.fetchGeneration = 41
        state.sessionExpiresAt = sessionExpiry
        let store = makeTestStore(initialState: state)
        await store.send(.accessStatusResponse(generation: 41, result: .failure(error))) { state in
            state.status = nil
            state.snapshot = nil
            state.isComplete = false
            state.trialExpiresAt = nil
            state.errorMessage = errorMessage
        }
        await store.receive(\.delegate.recoveryRequired.accessFailure)

        XCTAssertNil(store.state.status)
        XCTAssertNil(store.state.snapshot)
        XCTAssertNil(store.state.trialExpiresAt)
        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.errorMessage, errorMessage)
        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertEqual(store.state.sessionExpiresAt, sessionExpiry)
        XCTAssertEqual(store.state.fetchGeneration, 41)
        XCTAssertTrue(store.state.didBootstrap)
        XCTAssertEqual(store.state.accessUnlockPrimaryCTA, .retry)
        XCTAssertTrue(store.state.canRetry)
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
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
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

    func testOnAppearIsIdempotentOnReentry() async throws {
        nonisolated(unsafe) var sessionReadCount = 0
        nonisolated(unsafe) var fetchCount = 0
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: {
                    sessionReadCount += 1
                    return AccountSession(accessToken: "valid-token", status: .coreLicenseActive)
                },
                persist: { _ in },
                delete: { _ in },
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCount += 1
                    return AccessStatusResponse(
                        hasAccess: true,
                        status: "active",
                        reason: "active_entitlement",
                        productKey: "core",
                        source: "polar",
                    )
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
        )
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\._onAppearSessionRestored)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(sessionReadCount, 1)
        XCTAssertEqual(fetchCount, 1)

        await store.send(.onAppear)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(sessionReadCount, 1)
        XCTAssertEqual(fetchCount, 1)
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
                accountURL: { URL(string: "http://test.test/account")! },
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

    /// ACC-002-check_entitlement_status: active fetchAccessStatus 성공 후 device binding 성공 시 snapshot이 갱신된다.
    /// active 상태 응답만으로는 complete가 되지 않고 binding 성공 뒤 완료되는지 검증한다.
    /// - 검증 내용: success 응답 → binding pending → binding success → snapshot 생성, isComplete=true
    /// - 사전 조건: fetchGeneration=1, active 상태의 AccessStatusResponse
    /// - 기대 결과: status=.coreLicenseActive, snapshot!=nil, isComplete=true, errorMessage=nil
    func testFetchAccessStatusSuccessUpdatesStatusAndSnapshot() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        state.sessionExpiresAt = sessionExpiry
        let store = makeTestStore(initialState: state)
        store.exhaustivity = .off

        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response))) { state in
            state.status = .coreLicenseActive
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }

        await store.receive(\.deviceBindingResponse) { state in
            state.snapshot = AccessStatusSnapshot(
                status: .coreLicenseActive,
                currentPeriodEnd: nil,
                fetchedAt: self.referenceDate,
                sessionExpiresAt: sessionExpiry,
                deviceBindingVerifiedAt: self.referenceDate,
            )
            state.isSubmitting = false
            state.isComplete = true
            state.errorMessage = nil
        }

        XCTAssertEqual(store.state.status, .coreLicenseActive)
        XCTAssertNotNil(store.state.snapshot)
        XCTAssertEqual(store.state.snapshot?.status, .coreLicenseActive)
        XCTAssertEqual(store.state.snapshot?.deviceBindingVerifiedAt, referenceDate)
        XCTAssertTrue(store.state.isComplete)
        XCTAssertNil(store.state.errorMessage)
    }

    /// ACC-002-check_entitlement_status: active fetchAccessStatus + binding 성공 시 delegate(.unlocked)가 전달된다.
    /// active 상태 응답만으로는 delegate를 보내지 않고 binding 성공 뒤 전송되는지 검증한다.
    /// - 검증 내용: success 응답 → binding success → delegate(.unlocked) 수신, isComplete=true
    /// - 사전 조건: fetchGeneration=1, active 상태의 AccessStatusResponse
    /// - 기대 결과: delegate(.unlocked) 수신, isComplete=true
    func testFetchAccessStatusSuccessActiveSendsDelegateUnlocked() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        state.sessionExpiresAt = sessionExpiry
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
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }

        await store.receive(\.deviceBindingResponse) { state in
            state.snapshot = AccessStatusSnapshot(
                status: .coreLicenseActive,
                currentPeriodEnd: nil,
                fetchedAt: self.referenceDate,
                sessionExpiresAt: sessionExpiry,
                deviceBindingVerifiedAt: self.referenceDate,
            )
            state.isSubmitting = false
            state.isComplete = true
            state.errorMessage = nil
        }

        await store.receive(\.delegate)
    }
}

extension ACC002CheckEntitlementStatusTests {
    /// ACC-002-check_entitlement_status: active access여도 device binding 실패 시 unlock되지 않는다.
    /// seat capacity 초과는 signed-in blocked state와 Account CTA로 투영된다.
    func testActiveAccessDeviceBindingSeatCapacityDoesNotUnlock() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.seatCapacityExceeded },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: state,
        )

        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response))) { state in
            state.status = .coreLicenseActive
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }

        await store.receive(\.deviceBindingResponse) { state in
            state.isSubmitting = false
            state.snapshot = nil
            state.deviceBindingFailure = .seatCapacityExceeded
            state.isComplete = false
            state.errorMessage = "This license has reached its device limit. Manage devices or contact support."
        }
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(store.state.accountAccessStepState, .blocked)
        XCTAssertEqual(store.state.accessUnlockPrimaryCTA, .account)
        XCTAssertFalse(store.state.isComplete)
    }

    /// ACC-002-check_entitlement_status: device binding network/5xx 실패는 retry 가능한 error 상태다.
    func testActiveAccessDeviceBindingTransientFailureIsRetryable() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.serverFailure },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: state,
        )

        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response))) { state in
            state.status = .coreLicenseActive
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }

        await store.receive(\.deviceBindingResponse) { state in
            state.status = .networkFailure
            state.isSubmitting = false
            state.snapshot = nil
            state.deviceBindingFailure = .retryable
            state.deviceBindingRetryCount = 1
            state.isComplete = false
            state.errorMessage = "Could not bind this Mac. Please try again."
        }
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(store.state.accountAccessStepState, .error)
        XCTAssertEqual(store.state.accessUnlockPrimaryCTA, .retry)
        XCTAssertTrue(store.state.canRetry)
    }

    /// ACC-002-check_entitlement_status: 반복 device binding 실패는 account/support 경로로 escalates.
    func testRepeatedDeviceBindingTransientFailureEscalatesToAccountSupport() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        state.isSubmitting = true
        state.deviceBindingRetryCount = 2
        let store = makeTestStore(initialState: state)

        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
        )
        await store.send(.deviceBindingResponse(
            generation: 1,
            snapshot: snapshot,
            result: .failure(.serverFailure),
        )) { state in
            state.status = .networkFailure
            state.isSubmitting = false
            state.snapshot = nil
            state.errorMessage = "Could not bind this Mac. Please try again."
            state.deviceBindingFailure = .retryable
            state.deviceBindingRetryCount = 3
            state.isComplete = false
        }
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(store.state.accountAccessStepState, .error)
        XCTAssertEqual(store.state.accessUnlockPrimaryCTA, .account)
        XCTAssertFalse(store.state.canRetry)
    }

    /// ACC-002-check_entitlement_status: stale generation의 device binding 성공은 unlock을 커밋하지 않는다.
    func testStaleDeviceBindingSuccessIgnored() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 2
        state.hasAccountSession = true
        state.isSubmitting = true
        let store = makeTestStore(initialState: state)

        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
        )
        await store.send(.deviceBindingResponse(
            generation: 1,
            snapshot: snapshot,
            result: .success(DeviceBindingResponse(ok: true)),
        ))

        XCTAssertNil(store.state.snapshot)
        XCTAssertFalse(store.state.isComplete)
        XCTAssertTrue(store.state.isSubmitting)
    }

    /// ACC-002-check_entitlement_status: device binding 401은 세션 만료 복구로 전환된다.
    func testDeviceBindingUnauthorizedTriggersSessionExpired() async {
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        state.isSubmitting = true
        let store = makeTestStore(initialState: state)

        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
        )
        await store.send(.deviceBindingResponse(
            generation: 1,
            snapshot: snapshot,
            result: .failure(.unauthorized),
        )) { state in
            state.isSubmitting = false
        }
        await store.receive(\._sessionExpiredDetected) { state in
            state.hasAccountSession = false
            state.didSignInFail = true
            state.isSessionExpired = true
            state.status = nil
            state.snapshot = nil
            state.trialExpiresAt = nil
            state.deviceBindingFailure = nil
            state.isSubmitting = false
            state.isComplete = false
            state.errorMessage = nil
            state.fetchGeneration = 2
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.consecutiveRefreshFailures = 0
        }
        await store.receive(\.delegate.recoveryRequired)
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

    /// ACC-002-check_entitlement_status: notConfigured terminal failure는 stale verified access fact를 제거한다.
    /// access status를 확정할 수 없는 구성 오류가 기존 unlock 사실을 재사용하지 않도록 검증한다.
    /// - 검증 내용: verified active 상태에서 failure(.notConfigured) → entitlement fact 제거, session fact 및 recovery payload 보존
    /// - 사전 조건: signed-in, device binding 검증 완료, isComplete=true, didBootstrap=true, fetchGeneration=41
    /// - 기대 결과: status/snapshot/trialExpiresAt=nil, isComplete=false, retry CTA, accessFailure delegate 1회
    func testFetchAccessStatusNotConfiguredFailureClearsStaleActiveEntitlementFacts() async {
        await assertTerminalAccessFailure(
            error: .notConfigured,
            errorMessage: "Access service is not configured.",
        )
    }

    /// ACC-002-check_entitlement_status: decodingFailure terminal failure는 stale verified access fact를 제거한다.
    /// access status를 해석할 수 없는 응답이 기존 unlock 사실을 재사용하지 않도록 검증한다.
    /// - 검증 내용: verified active 상태에서 failure(.decodingFailure) → entitlement fact 제거, session fact 및 recovery payload
    /// 보존
    /// - 사전 조건: signed-in, device binding 검증 완료, isComplete=true, didBootstrap=true, fetchGeneration=41
    /// - 기대 결과: status/snapshot/trialExpiresAt=nil, isComplete=false, retry CTA, accessFailure delegate 1회
    func testFetchAccessStatusDecodingFailureClearsStaleActiveEntitlementFacts() async {
        await assertTerminalAccessFailure(
            error: .decodingFailure,
            errorMessage: "Failed to process the response.",
        )
    }

    /// ACC-002-check_entitlement_status: unknownGatewayCode terminal failure는 stale verified access fact를 제거한다.
    /// gateway의 알 수 없는 오류 코드가 기존 unlock 사실을 재사용하지 않도록 검증한다.
    /// - 검증 내용: verified active 상태에서 failure(.unknownGatewayCode) → entitlement fact 제거, session fact 및 recovery
    /// payload 보존
    /// - 사전 조건: signed-in, device binding 검증 완료, isComplete=true, didBootstrap=true, fetchGeneration=41
    /// - 기대 결과: status/snapshot/trialExpiresAt=nil, isComplete=false, retry CTA, accessFailure delegate 1회
    func testFetchAccessStatusUnknownGatewayCodeFailureClearsStaleActiveEntitlementFacts() async {
        await assertTerminalAccessFailure(
            error: .unknownGatewayCode("unexpected_gateway_code"),
            errorMessage: "An unexpected error occurred.",
        )
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
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
        )
        store.exhaustivity = .off

        await store.send(.retryTapped)

        XCTAssertEqual(store.state.fetchGeneration, 1)
        XCTAssertTrue(fetchCalled)
    }

    /// ACC-002-check_entitlement_status: inactive 상태 응답은 unlock 없이 isComplete=false를 유지한다.
    /// trialExpired 등 inactive 상태 응답을 받으면 recovery delegate와 함께 error 상태로 전환되는지 검증한다.
    /// - 검증 내용: inactive 응답 → isComplete=false, errorMessage 설정, snapshot 저장
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

    /// ACC-002-check_entitlement_status: inactive access는 앱 경계에 복구 필요 상태를 전달한다.
    /// 유효한 세션에서 inactive entitlement가 확정되면 AppLifecycle이 private status를 해석하지 않아도 되는지 검증한다.
    /// - 검증 내용: inactive access snapshot 저장 뒤 semantic delegate가 정확히 한 번 전달된다.
    /// - 사전 조건: fetchGeneration=1, sessionExpiresAt가 있는 trialExpired 응답.
    /// - 기대 결과: isComplete=false이며 recovery delegate가 수신된다.
    func testInactiveAccessSendsTerminalRecoveryDelegate() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        state.sessionExpiresAt = sessionExpiry
        let store = makeTestStore(initialState: state)

        let response = AccessStatusResponse(
            hasAccess: false,
            status: "expired",
            reason: "expired_entitlement",
            productKey: "trial",
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response))) { state in
            state.status = .trialExpired
            state.snapshot = AccessStatusSnapshot(
                status: .trialExpired,
                fetchedAt: self.referenceDate,
                sessionExpiresAt: sessionExpiry,
            )
            state.isComplete = false
            state.errorMessage = "This trial has expired."
            state.fetchRetryCount = 0
        }
        await store.receive(\.delegate.recoveryRequired)
    }

    /// ACC-002-check_entitlement_status: device binding failure는 후보 snapshot과 함께 복구 결과를 전달한다.
    /// 기기 좌석 제한으로 verified unlock이 불가능할 때 AppLifecycle이 binding 오류를 직접 해석하지 않는지 검증한다.
    /// - 검증 내용: binding failure 뒤 semantic delegate가 정확히 한 번 전달된다.
    /// - 사전 조건: fetchGeneration=1, signed-in active access, bindDevice가 seatCapacityExceeded를 반환한다.
    /// - 기대 결과: isComplete=false이며 recovery delegate가 수신된다.
    func testDeviceBindingFailureSendsTerminalRecoveryDelegate() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        state.sessionExpiresAt = sessionExpiry
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.seatCapacityExceeded },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: state,
        )

        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response))) { state in
            state.status = .coreLicenseActive
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }
        await store.receive(\.deviceBindingResponse) { state in
            state.isSubmitting = false
            state.deviceBindingFailure = .seatCapacityExceeded
            state.isComplete = false
            state.errorMessage = "This license has reached its device limit. Manage devices or contact support."
        }
        await store.receive(\.delegate.recoveryRequired)
    }

    // MARK: - ACC-002-cached-snapshot-fallback

    /// ACC-002: fetchAccessStatus 3회 실패 후 캐시된 snapshot이 복원된다.
    /// networkFailure가 3회 누적되면 캐시된 snapshot을 불러와 status/snapshot/isComplete를 복원한다.
    /// - 검증 내용: fetchRetryCount >= 3 + networkFailure → cached snapshot 복원
    /// - 사전 조건: fetchRetryCount=3, fetchGeneration=1, snapshotClient.load가 유효한 snapshot 반환
    /// - 기대 결과: status/snapshot/isComplete가 캐시된 값으로 복원, errorMessage=한국어 메시지
    func testCachedSnapshotRestoredAfterThreeFailures() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let cachedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
            deviceBindingVerifiedAt: referenceDate,
        )
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.fetchRetryCount = 3
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: {
                    AccountSession(
                        accessToken: "cached-session",
                        status: .coreLicenseActive,
                        expiresAt: sessionExpiry,
                    )
                },
                persist: { _ in },
                delete: { _ in },
            ),
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
            state.hasAccountSession = true
            state.sessionExpiresAt = sessionExpiry
            state.didBootstrap = true
        }
        await store.receive(\.delegate.unlocked)
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
        await store.receive(\.delegate.recoveryRequired)

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
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        state.sessionExpiresAt = sessionExpiry
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
        await store.receive(\.deviceBindingResponse)

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
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(store.state.status, .networkFailure)
        XCTAssertNotEqual(store.state.status, AccessStatus.none)
        XCTAssertEqual(store.state.accountAccessStepState, .error)
    }

    /// ACC-002: 캐시 복원 시 snapshot.sessionExpiresAt가 있으면 session 축이 복원된다.
    /// networkFailure 3회 + 캐시 수락 → hasAccountSession=true, sessionExpiresAt=snapshot 값, didBootstrap=true.
    /// - 검증 내용: sessionExpiresAt 있는 snapshot → session 축 복원
    /// - 사전 조건: fetchRetryCount=3, fetchGeneration=1, snapshot.sessionExpiresAt=과거 미래 어느 쪽이든 non-nil
    /// - 기대 결과: hasAccountSession=true, sessionExpiresAt==snapshot.sessionExpiresAt, didBootstrap=true
    func testCachedSnapshotRestoredWithSessionExpiresAtRestoresSessionAxis() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let cachedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
            deviceBindingVerifiedAt: referenceDate,
        )
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.fetchRetryCount = 3
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: {
                    AccountSession(
                        accessToken: "cached-session",
                        status: .coreLicenseActive,
                        expiresAt: sessionExpiry,
                    )
                },
                persist: { _ in },
                delete: { _ in },
            ),
            snapshotClient: AccessStatusSnapshotClient(
                load: { cachedSnapshot },
                save: { _ in },
                remove: {},
            ),
            initialState: state,
        )
        store.exhaustivity = .off

        await store.send(.accessStatusResponse(generation: 1, result: .failure(.networkFailure)))
        await store.receive(\._cachedSnapshotRestored)

        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertEqual(store.state.sessionExpiresAt, sessionExpiry)
        XCTAssertTrue(store.state.didBootstrap)
        XCTAssertEqual(store.state.status, .coreLicenseActive)
        XCTAssertEqual(store.state.snapshot, cachedSnapshot)
        XCTAssertTrue(store.state.isComplete)
        XCTAssertEqual(store.state.errorMessage, "일시적인 네트워크 오류")
    }

    /// ACC-002: 캐시 복원 시 snapshot.sessionExpiresAt가 nil이면 session 축을 만들지 않는다.
    /// access status가 active여도 sessionExpiresAt == nil이면 hasAccountSession=false.
    /// isActive가 가짜 세션을 주입하지 않는지 검증 (signed-in = session 기반, not status 기반).
    /// - 검증 내용: active snapshot + sessionExpiresAt=nil → hasAccountSession=false, sessionExpiresAt=nil
    /// - 사전 조건: fetchRetryCount=3, fetchGeneration=1, snapshot(active, sessionExpiresAt=nil)
    /// - 기대 결과: hasAccountSession=false, sessionExpiresAt=nil, didBootstrap=true, isComplete=snapshot.isActive
    func testCachedSnapshotRestoredWithoutSessionDoesNotFakeSession() async {
        let cachedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
            sessionExpiresAt: nil,
            deviceBindingVerifiedAt: referenceDate,
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
        store.exhaustivity = .off

        await store.send(.accessStatusResponse(generation: 1, result: .failure(.networkFailure)))
        await store.receive(\._cachedSnapshotRestored)

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertNil(store.state.sessionExpiresAt)
        XCTAssertTrue(store.state.didBootstrap)
        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.status, .coreLicenseActive)
    }

    /// ACC-002: 성공적인 fetch 후 fetchRetryCount가 0으로 리셋된다.
    /// 연속 실패 후 성공하면 retry count를 초기화하여 다음 실패 사이클을 올바르게 시작한다.
    /// - 검증 내용: success 응답 → fetchRetryCount=0
    /// - 사전 조건: fetchRetryCount=3, fetchGeneration=1
    /// - 기대 결과: fetchRetryCount=0
    func testFetchRetryCountResetOnSuccess() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.fetchRetryCount = 3
        state.hasAccountSession = true
        state.sessionExpiresAt = sessionExpiry
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
        await store.receive(\.deviceBindingResponse)

        XCTAssertEqual(store.state.fetchRetryCount, 0)
        XCTAssertEqual(store.state.status, .coreLicenseActive)
    }

    /// ACC-002: 성공 snapshot 저장 시 sessionExpiresAt를 보존한다.
    /// 이후 networkFailure fallback이 저장 snapshot의 session 축을 사용하므로 TTL 소유권을 잃지 않는다.
    /// - 검증 내용: success 응답 → snapshotClient.save(snapshot.sessionExpiresAt == state.sessionExpiresAt)
    /// - 사전 조건: fetchGeneration=1, sessionExpiresAt가 있는 signed-in 상태
    /// - 기대 결과: 저장 snapshot에 sessionExpiresAt 보존, fallback signed-in semantics 유지 가능
    func testAccessStatusSuccessPersistsSessionExpiryInSnapshot() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        nonisolated(unsafe) var savedSnapshot: AccessStatusSnapshot?
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        state.sessionExpiresAt = sessionExpiry
        let store = makeTestStore(
            snapshotClient: AccessStatusSnapshotClient(
                load: { nil },
                save: { snapshot in savedSnapshot = snapshot },
                remove: {},
            ),
            initialState: state,
        )
        store.exhaustivity = .off

        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            reason: "active_entitlement",
            productKey: "core",
            source: "polar",
        )
        await store.send(.accessStatusResponse(generation: 1, result: .success(response)))
        await store.receive(\.deviceBindingResponse)

        XCTAssertEqual(savedSnapshot?.sessionExpiresAt, sessionExpiry)
        XCTAssertEqual(savedSnapshot?.status, .coreLicenseActive)
        XCTAssertEqual(savedSnapshot?.deviceBindingVerifiedAt, referenceDate)
        XCTAssertEqual(store.state.snapshot?.sessionExpiresAt, sessionExpiry)
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

    // MARK: - ACC-002-check_entitlement_status (hydration mapping)

    /// ACC-002-check_entitlement_status: `.trialExpired + sessionExpiresAt` snapshot hydration 시
    /// session 축은 signedIn을 유지하면서 entitlement 축은 inactive/blocked 상태로 파생된다.
    /// launch snapshot hydration이 session 축과 entitlement 축을 독립적으로 매핑하는지 검증한다.
    /// - 검증 내용: hydrateLaunchSnapshot(.trialExpired + sessionExpiresAt) →
    ///   hasAccountSession == true, status == .trialExpired,
    ///   accountAccessStepState == .blocked, accountAccessAuthAxis == .signedIn
    /// - 사전 조건: 빈 초기 상태
    /// - 기대 결과: auth signedIn이면서 entitlement inactive — session 기반 auth 단언 (status.isActive에서 추론하지 않음)
    func testHydrateLaunchSnapshotWithTrialExpiredSessionMapsToBlockedAndSignedIn() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let snapshot = AccessStatusSnapshot(
            status: .trialExpired,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
        )

        let store = makeTestStore()
        store.exhaustivity = .off

        await store.send(.hydrateLaunchSnapshot(snapshot))

        // session 축: sessionExpiresAt != nil → signedIn 파생 (상태와 무관)
        XCTAssertTrue(store.state.hasAccountSession, "session 존재 → hasAccountSession=true")
        XCTAssertEqual(store.state.sessionExpiresAt, sessionExpiry)
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signedIn)
        // entitlement 축: trialExpired → blocked
        XCTAssertEqual(store.state.status, .trialExpired)
        XCTAssertEqual(store.state.accountAccessStepState, .blocked)
        XCTAssertFalse(store.state.status?.isActive == true, "trialExpired는 active가 아님")
        await store.finish()
    }

    /// ACC-002-check_entitlement_status: `.networkFailure + sessionExpiresAt` snapshot hydration 시
    /// session 축은 signedIn을 유지하면서 entitlement 축은 error 상태로 파생된다.
    /// auth signedIn과 error 표시가 독립적으로 동작하는지 검증한다.
    /// - 검증 내용: hydrateLaunchSnapshot(.networkFailure + sessionExpiresAt) →
    ///   hasAccountSession == true, status == .networkFailure,
    ///   accountAccessStepState == .error, accountAccessAuthAxis == .signedIn,
    ///   showsRetry == true
    /// - 사전 조건: 빈 초기 상태
    /// - 기대 결과: auth signedIn이면서 entitlement error — retry 가능 상태 유지
    func testHydrateLaunchSnapshotWithNetworkFailureSessionMapsToErrorAndSignedIn() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let snapshot = AccessStatusSnapshot(
            status: .networkFailure,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
        )

        let store = makeTestStore()
        store.exhaustivity = .off

        await store.send(.hydrateLaunchSnapshot(snapshot))

        // session 축: sessionExpiresAt != nil → signedIn 파생 (상태와 무관)
        XCTAssertTrue(store.state.hasAccountSession, "session 존재 → hasAccountSession=true")
        XCTAssertEqual(store.state.sessionExpiresAt, sessionExpiry)
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signedIn)
        // entitlement 축: networkFailure → error + retry
        XCTAssertEqual(store.state.status, .networkFailure)
        XCTAssertEqual(store.state.accountAccessStepState, .error)
        XCTAssertTrue(store.state.showsRetry)
        XCTAssertFalse(store.state.status?.isActive == true, "networkFailure는 active가 아님")
        await store.finish()
    }

    // MARK: - Integration

    /// ACC-002 Integration: onAppear → session restore → fetchAccessStatus → delegate(.unlocked) 전체 파이프라인을 검증한다.
    /// 저장된 유효 session으로 onAppear부터 delegate(.unlocked)까지 모든 단계가 순차적으로 실행되는지 확인한다.
    /// - 검증 내용: onAppear → _onAppearSessionRestored → accessStatusResponse → delegate
    /// - 사전 조건: 유효 session, 성공 fetchAccessStatus
    /// - 기대 결과: status=.coreLicenseActive, isComplete=true, delegate(.unlocked) 수신
    func testIntegrationOnAppearToUnlockedFullPipeline() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: {
                    AccountSession(
                        accessToken: "valid-token",
                        status: .coreLicenseActive,
                        expiresAt: sessionExpiry,
                    )
                },
                persist: { _ in },
                delete: { _ in },
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
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
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

        // Step 2: fetchAccessStatus 성공 응답 → device binding pending
        let expectedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
            deviceBindingVerifiedAt: referenceDate,
        )
        await store.receive(\.accessStatusResponse) { state in
            state.status = .coreLicenseActive
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }

        // Step 3: device binding 성공 후 unlock 커밋
        await store.receive(\.deviceBindingResponse) { state in
            state.snapshot = expectedSnapshot
            state.isSubmitting = false
            state.isComplete = true
            state.errorMessage = nil
        }

        // Step 4: delegate(.unlocked) 전달
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
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let cachedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
            deviceBindingVerifiedAt: referenceDate,
        )
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: {
                    AccountSession(
                        accessToken: "cached-session",
                        status: .coreLicenseActive,
                        expiresAt: sessionExpiry,
                    )
                },
                persist: { _ in },
                delete: { _ in },
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    throw AccessError.networkFailure
                },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
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
            state.hasAccountSession = true
            state.sessionExpiresAt = sessionExpiry
            state.didBootstrap = true
        }
        await store.receive(\.delegate.unlocked)
    }

    /// ACC-002-check_entitlement_status: fresh verified cache는 현재 세션 만료 시각을 반영한 뒤 unlock한다.
    /// network fallback이 cached access/binding facts를 보존하면서 재확인한 session expiry만 갱신하는지 검증한다.
    /// - 검증 내용: cache restore가 status, period, fetchedAt, binding proof를 보존하고 unlocked delegate를 한 번 전달한다.
    /// - 사전 조건: fresh active+binding-verified cache와 더 늦은 현재 AccountSession expiry가 존재한다.
    /// - 기대 결과: cache는 다시 저장되지 않고 state와 unlocked snapshot의 sessionExpiresAt만 현재 expiry가 된다.
    func testFreshVerifiedCacheRefreshesSessionExpiryBeforeUnlock() async {
        let cachedExpiry = referenceDate.addingTimeInterval(600)
        let currentExpiry = referenceDate.addingTimeInterval(3600)
        let periodEnd = referenceDate.addingTimeInterval(86400)
        let cachedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: periodEnd,
            fetchedAt: referenceDate,
            sessionExpiresAt: cachedExpiry,
            deviceBindingVerifiedAt: referenceDate,
        )
        nonisolated(unsafe) var savedSnapshots: [AccessStatusSnapshot] = []
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.fetchRetryCount = 3
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: {
                    AccountSession(
                        accessToken: "current-session",
                        status: .coreLicenseActive,
                        expiresAt: currentExpiry,
                    )
                },
                persist: { _ in },
                delete: { _ in },
            ),
            snapshotClient: AccessStatusSnapshotClient(
                load: { cachedSnapshot },
                save: { savedSnapshots.append($0) },
                remove: {},
            ),
            initialState: state,
        )

        await store.send(.accessStatusResponse(generation: 1, result: .failure(.networkFailure))) { state in
            state.status = .networkFailure
            state.errorMessage = "Network error. Please check your connection and try again."
            state.fetchRetryCount = 0
        }
        let expectedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: periodEnd,
            fetchedAt: referenceDate,
            sessionExpiresAt: currentExpiry,
            deviceBindingVerifiedAt: referenceDate,
        )
        await store.receive(\._cachedSnapshotRestored) { state in
            state.status = .coreLicenseActive
            state.snapshot = expectedSnapshot
            state.isComplete = true
            state.errorMessage = "일시적인 네트워크 오류"
            state.hasAccountSession = true
            state.sessionExpiresAt = currentExpiry
            state.didBootstrap = true
        }
        await store.receive(\.delegate.unlocked)

        XCTAssertTrue(savedSnapshots.isEmpty)
        XCTAssertEqual(store.state.snapshot, expectedSnapshot)
    }

    /// ACC-002-check_entitlement_status: binding failure는 기존 verified cache를 덮어쓰지 않는다.
    /// 새 binding 검증이 실패해도 이전 verified snapshot persistence가 유지되는지 검증한다.
    /// - 검증 내용: deviceBindingFailure recovery가 발생해도 snapshotClient.save 호출은 없다.
    /// - 사전 조건: 이미 저장된 verified snapshot, fetchGeneration=1, late binding failure 후보 snapshot.
    /// - 기대 결과: 저장 recorder에는 기존 snapshot만 남고 recovery delegate가 한 번 수신된다.
    func testDeviceBindingFailureDoesNotOverwriteVerifiedCache() async {
        let verifiedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: referenceDate,
            sessionExpiresAt: referenceDate.addingTimeInterval(3600),
            deviceBindingVerifiedAt: referenceDate,
        )
        nonisolated(unsafe) var savedSnapshots = [verifiedSnapshot]
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        state.isSubmitting = true
        let store = makeTestStore(
            snapshotClient: AccessStatusSnapshotClient(
                load: { nil },
                save: { savedSnapshots.append($0) },
                remove: {},
            ),
            initialState: state,
        )

        await store.send(.deviceBindingResponse(
            generation: 1,
            snapshot: AccessStatusSnapshot(
                status: .coreLicenseActive,
                fetchedAt: referenceDate,
                sessionExpiresAt: verifiedSnapshot.sessionExpiresAt,
            ),
            result: .failure(.seatCapacityExceeded),
        )) { state in
            state.isSubmitting = false
            state.deviceBindingFailure = .seatCapacityExceeded
            state.isComplete = false
            state.errorMessage = "This license has reached its device limit. Manage devices or contact support."
        }
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertEqual(savedSnapshots, [verifiedSnapshot])
    }

    /// ACC-002 Integration: retryTapped → fetchGeneration 증가 → fetchAccessStatus → delegate(.unlocked) 전체 파이프라인을 검증한다.
    /// 수동 retry가 fetchGeneration을 증가시키고, 성공 응답이 delegate까지 전달되는지 확인한다.
    /// - 검증 내용: retryTapped → accessStatusResponse → delegate(.unlocked)
    /// - 사전 조건: fetchGeneration=0, fetchAccessStatus 성공
    /// - 기대 결과: fetchGeneration=1, status=.coreLicenseActive, delegate(.unlocked) 수신
    func testIntegrationRetryTappedToUnlockedFullPipeline() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        var initialState = AccountAccessFeature.State()
        initialState.hasAccountSession = true
        initialState.sessionExpiresAt = sessionExpiry
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
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )

        await store.send(.retryTapped) { state in
            state.fetchGeneration = 1
        }

        let expectedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: nil,
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
            deviceBindingVerifiedAt: referenceDate,
        )
        await store.receive(\.accessStatusResponse) { state in
            state.status = .coreLicenseActive
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }
        await store.receive(\.deviceBindingResponse) { state in
            state.snapshot = expectedSnapshot
            state.isSubmitting = false
            state.isComplete = true
            state.errorMessage = nil
        }
        await store.receive(\.delegate.unlocked)
        await store.finish()
    }
}

// swiftlint:enable force_unwrapping

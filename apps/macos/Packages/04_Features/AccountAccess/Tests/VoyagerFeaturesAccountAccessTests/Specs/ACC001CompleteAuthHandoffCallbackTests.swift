// swiftlint:disable force_unwrapping

@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-001-complete_auth_handoff_callback spec-owner 테스트

 interaction_id: ACC-001-complete_auth_handoff_callback
 spec: docs/canonical/PRODUCT/05_FEATURE_SPECS/acc/ACC-001-manage_account_auth/ACC-001-complete_auth_handoff_callback.md

 deep link callback 검증 + exchange_handoff_token 전달을 테스트한다.
 AppHandoffCallback 파식 테스트와 reducer 통합 테스트를 모두 포함한다.
 */

private let activeAccessStatusResponse = AccessStatusResponse(
    hasAccess: true,
    status: "active",
    reason: "active_entitlement",
    productKey: "core",
    source: "polar",
)

@MainActor
final class ACC001CompleteAuthHandoffCallbackTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static let validTicket = "abc123"
    private static let validState = "xyz789"
    private static let validContext = "onboarding"
    private static let persistedSessionExpiry = Date(timeIntervalSince1970: 1_700_003_600)

    private static var validCallbackURL: URL {
        URL(string: "voyager://auth/callback?ticket=\(validTicket)&state=\(validState)&context=\(validContext)")!
    }

    private func callbackURL(
        ticket: String = validTicket,
        state: String = validState,
        context: String = validContext,
        extraParams: String = "",
    ) -> URL {
        var query = "ticket=\(ticket)&state=\(state)&context=\(context)"
        if !extraParams.isEmpty { query += "&\(extraParams)" }
        return URL(string: "voyager://auth/callback?\(query)")!
    }

    private func makeTestStore(
        accountSessionClient: AccountSessionClient = .testValue,
        authNetworkClient: AuthNetworkClient = .testValue,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
        appHandoffTarget: AppHandoffTarget = .voyager,
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.date = .constant(referenceDate)
            $0.appHandoffTarget = appHandoffTarget
        }
    }

    private func canonicalSessionClient(accessToken: String) -> AccountSessionClient {
        let session = AccountSession(
            accessToken: accessToken,
            status: .none,
            refreshToken: "persisted-refresh-token",
            expiresAt: Self.persistedSessionExpiry,
        )
        return AccountSessionClient(
            read: { session },
            persist: { _ in },
            delete: { _ in },
        )
    }

    /// handoffPendingState가 설정된 signInInProgress 상태 (callback 대기 중)
    private func awaitingCallbackState(
        pendingState: String = ACC001CompleteAuthHandoffCallbackTests.validState,
        handoffContext: AppHandoffContext = .onboarding,
    ) -> AccountAccessFeature.State {
        var state = AccountAccessFeature.State()
        state.isSignInInProgress = true
        state.handoffPendingState = pendingState
        state.handoffContext = handoffContext
        return state
    }

    // MARK: - ACC-001-complete_auth_handoff_callback

    /// ACC-001-complete_auth_handoff_callback: 유효한 callback URL에서 ticket/state/context를 정상 파싱한다.
    /// AppHandoffCallback 파서가 올바른 deep link URL에서 인증 정보를 올바르게 추출하는지 검증한다.
    /// - 검증 내용: callback의 ticket, state, context 프로퍼티가 입력값과 일치한다.
    /// - 사전 조건: 유효한 scheme(voyager://), host(auth), path(callback), query에 ticket/state/context가 포함된 URL
    /// - 기대 결과: AppHandoffCallback이 nil이 아니며 각 프로퍼티가 올바른 값과 일치한다.
    func testValidCallbackParsesIntegrity() {
        let callback = AppHandoffCallback(url: Self.validCallbackURL, expectedScheme: "voyager")
        XCTAssertEqual(callback?.ticket, Self.validTicket)
        XCTAssertEqual(callback?.state, Self.validState)
        XCTAssertEqual(callback?.context, .onboarding)
    }

    /// ACC-001-complete_auth_handoff_callback: 잘못된 scheme의 callback URL을 파싱 거부한다.
    /// AppHandoffCallback 파서가 https scheme의 URL을 안전하게 거부하는지 검증한다.
    /// - 검증 내용: https scheme의 callback URL이 nil을 반환한다.
    /// - 사전 조건: scheme이 https이고 host, path, query가 유효한 URL
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsWrongScheme() throws {
        let url = try XCTUnwrap(URL(string: "https://auth/callback?ticket=abc&state=xyz&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: 잘못된 host의 callback URL을 파싱 거부한다.
    /// AppHandoffCallback 파서가 올바르지 않은 host의 URL을 안전하게 거부하는지 검증한다.
    /// - 검증 내용: host가 "other"인 callback URL이 nil을 반환한다.
    /// - 사전 조건: scheme(voyager://), path(/callback)는 유효하나 host가 "other"인 URL
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsWrongHost() throws {
        let url = try XCTUnwrap(URL(string: "voyager://other/callback?ticket=abc&state=xyz&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: 잘못된 path의 callback URL을 파싱 거부한다.
    /// AppHandoffCallback 파서가 올바르지 않은 path의 URL을 안전하게 거부하는지 검증한다.
    /// - 검증 내용: path가 "/other"인 callback URL이 nil을 반환한다.
    /// - 사전 조건: scheme(voyager://), host(auth)는 유효하나 path가 "/other"인 URL
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsWrongPath() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/other?ticket=abc&state=xyz&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: access_token 파라미터가 포함된 callback을 보안상 거부한다.
    /// AppHandoffCallback 파서가 access_token 파라미터를 보안 위험으로 감지하고 거부하는지 검증한다.
    /// - 검증 내용: access_token 파라미터가 포함된 URL이 nil을 반환한다.
    /// - 사전 조건: query에 정상 ticket/state/context 외에 access_token=secret이 추가된 URL
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsAccessTokenParam() {
        let url = callbackURL(extraParams: "access_token=secret")
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: refresh_token 파라미터가 포함된 callback을 보안상 거부한다.
    /// AppHandoffCallback 파서가 refresh_token 파라미터를 보안 위험으로 감지하고 거부하는지 검증한다.
    /// - 검증 내용: refresh_token 파라미터가 포함된 URL이 nil을 반환한다.
    /// - 사전 조건: query에 정상 ticket/state/context 외에 refresh_token=secret이 추가된 URL
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsRefreshTokenParam() {
        let url = callbackURL(extraParams: "refresh_token=secret")
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: code 파라미터가 포함된 callback을 보안상 거부한다.
    /// AppHandoffCallback 파서가 OAuth code 파라미터를 보안 위험으로 감지하고 거부하는지 검증한다.
    /// - 검증 내용: code 파라미터가 포함된 URL이 nil을 반환한다.
    /// - 사전 조건: query에 정상 ticket/state/context 외에 code=oauth_code가 추가된 URL
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsCodeParam() {
        let url = callbackURL(extraParams: "code=oauth_code")
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: 알 수 없는 context 값의 callback을 파싱 거부한다.
    /// AppHandoffCallback 파서가 allowlist에 없는 context 값의 URL을 거부하는지 검증한다.
    /// - 검증 내용: "malicious" context의 callback URL이 nil을 반환한다.
    /// - 사전 조건: query에 context=malicious가 포함된 URL (allowlist 외 값)
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsUnknownContext() {
        let url = callbackURL(context: "malicious")
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: ticket 파라미터가 누락된 callback을 파싱 거부한다.
    /// AppHandoffCallback 파서가 필수 파라미터 누락 URL을 안전하게 거부하는지 검증한다.
    /// - 검증 내용: ticket 파라미터가 없는 URL이 nil을 반환한다.
    /// - 사전 조건: state와 context만 있고 ticket이 없는 URL
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsMissingTicket() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?state=xyz&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: state 파라미터가 누락된 callback을 파싱 거부한다.
    /// AppHandoffCallback 파서가 state 없는 URL을 안전하게 거부하는지 검증한다.
    /// - 검증 내용: state 파라미터가 없는 URL이 nil을 반환한다.
    /// - 사전 조건: ticket과 context만 있고 state가 없는 URL
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsMissingState() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?ticket=abc&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: context 파라미터가 누락된 callback을 파싱 거부한다.
    /// AppHandoffCallback 파서가 context 없는 URL을 안전하게 거부하는지 검증한다.
    /// - 검증 내용: context 파라미터가 없는 URL이 nil을 반환한다.
    /// - 사전 조건: ticket과 state만 있고 context가 없는 URL
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsMissingContext() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?ticket=abc&state=xyz"))
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: 빈 ticket 값의 callback을 파싱 거부한다.
    /// AppHandoffCallback 파서가 빈 문자열 ticket을 유효하지 않은 값으로 처리하는지 검증한다.
    /// - 검증 내용: ticket이 빈 문자열인 URL이 nil을 반환한다.
    /// - 사전 조건: ticket=""인 URL (나머지 파라미터는 정상)
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsEmptyTicket() {
        let url = callbackURL(ticket: "")
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: 빈 state 값의 callback을 파싱 거부한다.
    /// AppHandoffCallback 파서가 빈 문자열 state를 유효하지 않은 값으로 처리하는지 검증한다.
    /// - 검증 내용: state가 빈 문자열인 URL이 nil을 반환한다.
    /// - 사전 조건: state=""인 URL (나머지 파라미터는 정상)
    /// - 기대 결과: AppHandoffCallback이 nil이다.
    func testRejectsEmptyState() {
        let url = callbackURL(state: "")
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// ACC-001-complete_auth_handoff_callback: 유효한 인증 흐름의 callback이 정상 처리된다.
    /// handoffPendingState와 일치하는 state의 callback이 정상적으로 exchange 경로로 진입하는지 검증한다.
    /// - 검증 내용: state 일치 시 exchangeAppHandoff 호출, context는 onboarding으로 전달
    /// - 사전 조건: handoffPendingState="xyz789"인 awaitingCallbackState에서 동일한 state의 callback URL 수신
    /// - 기대 결과: exchangeAppHandoff가 호출되고 _handoffExchangeCompleted 수신, hasAccountSession=true
    func testValidFlowCallbackProcessedNormally() async {
        nonisolated(unsafe) var exchangeCalled = false
        let store = makeTestStore(
            accountSessionClient: canonicalSessionClient(accessToken: "valid-flow-token"),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in
                    exchangeCalled = true
                    return AccountSession(accessToken: "valid-flow-token", status: .coreLicenseActive)
                },
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
            initialState: awaitingCallbackState(pendingState: "xyz789"),
        )

        let callbackURL = Self.validCallbackURL

        await store.send(.loginCallbackReceived(callbackURL)) { state in
            state.handoffPendingState = nil
        }

        await store.receive(\._handoffExchangeCompleted) { state in
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.sessionExpiresAt = Self.persistedSessionExpiry
            state.ttlTimerActive = true
            state.fetchGeneration = 1
        }

        XCTAssertTrue(exchangeCalled, "유효한 흐름의 callback 정상 처리 → exchange 호출")
        // store.exhaustivity = .off: _handoffExchangeCompleted가 다수 상태를 갱신한 이후 accessStatusResponse 처리 중 추가 상태 변경이 있을 수
        // 있으나 검증은 action 수신만 확인
        store.exhaustivity = .off
        await store.receive(\.accessStatusResponse)
        await store.receive(\.delegate.unlocked)
        await store.finish()
    }

    /// ACC-001-complete_auth_handoff_callback: pending context와 다른 callback context는 exchange를 차단한다.
    /// pending handoff가 paywall context로 시작된 경우 onboarding callback이 거부되는지 검증한다.
    /// - 검증 내용: exchangeAppHandoff 미호출, didSignInFail=true, handoffPendingState=nil
    /// - 사전 조건: handoffContext=.paywall 상태에서 context=onboarding callback URL 수신
    /// - 기대 결과: exchangeAppHandoff 미호출, didSignInFail=true
    func testMismatchedCallbackContextRejectedAgainstPendingContext() async {
        nonisolated(unsafe) var exchangeCalled = false
        let store = makeTestStore(
            accountSessionClient: canonicalSessionClient(accessToken: "paywall-token"),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in
                    exchangeCalled = true
                    return AccountSession(accessToken: "should-not-reach", status: .coreLicenseActive)
                },
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
            initialState: awaitingCallbackState(handoffContext: .paywall),
        )

        let mismatchedCallbackURL = callbackURL(context: "onboarding")

        await store.send(.loginCallbackReceived(mismatchedCallbackURL)) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.handoffPendingState = nil
        }

        XCTAssertFalse(exchangeCalled, "pending context와 다른 callback은 exchange를 차단해야 함")
        await store.finish()
    }

    /// ACC-001-complete_auth_handoff_callback: pending context와 일치하는 callback context는 정상 exchange로 이어진다.
    /// paywall 경로에서 시작된 handoff가 paywall callback을 받을 때 기존 onboarding 흐름과 동일하게 성공하는지 검증한다.
    /// - 검증 내용: state/context 일치 시 exchangeAppHandoff 호출, hasAccountSession=true
    /// - 사전 조건: handoffContext=.paywall 상태에서 context=paywall callback URL 수신
    /// - 기대 결과: exchangeAppHandoff 호출, _handoffExchangeCompleted 수신, hasAccountSession=true
    func testMatchingPendingCallbackContextProcessedNormally() async {
        nonisolated(unsafe) var exchangeCalled = false
        let store = makeTestStore(
            accountSessionClient: canonicalSessionClient(accessToken: "obh-token"),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { ticket, state, context in
                    exchangeCalled = true
                    XCTAssertEqual(ticket, "abc123")
                    XCTAssertEqual(state, "xyz789")
                    XCTAssertEqual(context, .paywall)
                    return AccountSession(accessToken: "paywall-token", status: .coreLicenseActive)
                },
                fetchAccessStatus: { activeAccessStatusResponse },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: awaitingCallbackState(handoffContext: .paywall),
        )

        let callback = callbackURL(context: "paywall")

        await store.send(.loginCallbackReceived(callback)) { state in
            state.handoffPendingState = nil
        }

        await store.receive(\._handoffExchangeCompleted) { state in
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.sessionExpiresAt = Self.persistedSessionExpiry
            state.ttlTimerActive = true
            state.fetchGeneration = 1
        }

        XCTAssertTrue(exchangeCalled, "matching callback context should reach exchange")
        store.exhaustivity = .off
        await store.receive(\.accessStatusResponse)
        await store.receive(\.delegate.unlocked)
        await store.finish()
    }

    /// ACC-001-complete_auth_handoff_callback: state 불일치 callback이 인증 흐름을 중단시킨다.
    /// 무효화된(재실행으로 대체된) 인증 흐름의 callback이 exchange 미호출 및 실패 처리되는지 검증한다.
    /// - 검증 내용: exchangeAppHandoff 미호출, didSignInFail=true, handoffPendingState=nil
    /// - 사전 조건: handoffPendingState="new-state-456"인 상태에서 state="old-state-123"인 callback URL 수신
    /// - 기대 결과: exchangeAppHandoff가 호출되지 않고 didSignInFail=true, isSignInInProgress=false
    func testInvalidatedFlowCallbackRejectedByCurrentImpl() async {
        nonisolated(unsafe) var exchangeCalled = false
        let store = makeTestStore(
            accountSessionClient: canonicalSessionClient(accessToken: "obh-token"),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in
                    exchangeCalled = true
                    return AccountSession(accessToken: "should-not-reach", status: .coreLicenseActive)
                },
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
            initialState: awaitingCallbackState(pendingState: "new-state-456"),
        )

        // old-state callback (무효화된 이전 흐름)
        let oldCallbackURL = callbackURL(state: "old-state-123")

        await store.send(.loginCallbackReceived(oldCallbackURL)) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.handoffPendingState = nil
        }

        XCTAssertFalse(exchangeCalled, "무효화된 흐름의 callback → exchange 미호출")
        await store.finish()
    }

    /// ACC-003-guard_session_lapse.md:66, 74, 89 / SessionLapseGuardView.swift:101-106
    /// signInHandoffCompleted(.failure) 는 네트워크 안내 메시지를 설정하고 실패 상태를 고정한다.
    func testSignInHandoffCompletedFailureSetsNetworkErrorMessage() async {
        let store = makeTestStore(initialState: awaitingCallbackState())

        await store.send(.signInHandoffCompleted(.failure)) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.errorMessage = "Check your network connection and try again."
        }

        await store.finish()
    }

    /// ACC-003-guard_session_lapse.md:66, 74, 89 / SessionLapseGuardView.swift:101-106
    /// signInHandoffCompleted(.cancelled) 는 errorMessage 없이 현재 취소 상태만 반영한다.
    func testSignInHandoffCompletedCancelledKeepsErrorMessageNil() async {
        let store = makeTestStore(initialState: awaitingCallbackState())

        await store.send(.signInHandoffCompleted(.cancelled)) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.errorMessage = nil
        }

        await store.finish()
    }

    /// voyager-onboarding-host:// scheme 콜백이 올바르게 파싱되는지 검증한다.
    func testOnboardingHostSchemeParsesSuccessfully() throws {
        let url =
            try XCTUnwrap(
                URL(string: "voyager-onboarding-host://auth/callback?ticket=abc&state=xyz&context=onboarding"),
            )
        let callback = AppHandoffCallback(url: url, expectedScheme: "voyager-onboarding-host")
        XCTAssertEqual(callback?.ticket, "abc")
        XCTAssertEqual(callback?.state, "xyz")
        XCTAssertEqual(callback?.context, .onboarding)
    }

    /// voyager:// URL이 voyager-onboarding-host expectedScheme에서 거부되는지 검증한다.
    func testCrossSchemeVoyagerUrlRejectedByOnboardingHostScheme() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?ticket=abc&state=xyz&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager-onboarding-host"))
    }

    /// voyager-onboarding-host:// URL이 voyager expectedScheme에서 거부되는지 검증한다.
    func testCrossSchemeOnboardingHostUrlRejectedByVoyagerScheme() throws {
        let url =
            try XCTUnwrap(
                URL(string: "voyager-onboarding-host://auth/callback?ticket=abc&state=xyz&context=onboarding"),
            )
        XCTAssertNil(AppHandoffCallback(url: url, expectedScheme: "voyager"))
    }

    /// onboardingHost target 환경에서 voyager:// callback이 거부되는지 검증한다.
    func testOnboardingHostTargetRejectsVoyagerCallback() async {
        nonisolated(unsafe) var exchangeCalled = false
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { nil },
                persist: { _ in },
                delete: { _ in },
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in
                    exchangeCalled = true
                    return AccountSession(accessToken: "should-not-reach", status: .coreLicenseActive)
                },
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
            initialState: awaitingCallbackState(),
            appHandoffTarget: .onboardingHost,
        )

        let voyagerURL = Self.validCallbackURL

        await store.send(.loginCallbackReceived(voyagerURL)) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
            state.handoffPendingState = nil
        }

        XCTAssertFalse(exchangeCalled, "onboardingHost target + voyager callback → 거부")
        await store.finish()
    }
}

extension ACC001CompleteAuthHandoffCallbackTests {
    /// ACC-001-complete_auth_handoff_callback: 유효한 callback 수신 시 exchangeAppHandoff가 자동 호출된다.
    /// callback 검증 성공 후 exchange_handoff_token 플로우가 자동으로 트리거되는지 검증한다.
    /// - 검증 내용: exchangeAppHandoff 호출, _handoffExchangeCompleted 수신, hasAccountSession=true 전환
    /// - 사전 조건: awaitingCallbackState에서 유효한 callback URL 수신, exchangeAppHandoff가 성공 응답 반환
    /// - 기대 결과: handoffPendingState가 해제되고 hasAccountSession=true, isSignInInProgress=false, fetchGeneration=1
    func testValidCallbackAutoTriggersExchange() async {
        let store = makeTestStore(
            accountSessionClient: canonicalSessionClient(accessToken: "exchanged-token"),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { ticket, state, context in
                    XCTAssertEqual(ticket, "abc123")
                    XCTAssertEqual(state, "xyz789")
                    XCTAssertEqual(context, .onboarding)
                    return AccountSession(accessToken: "exchanged-token", status: .coreLicenseActive)
                },
                fetchAccessStatus: { activeAccessStatusResponse },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: awaitingCallbackState(),
        )

        await store.send(.loginCallbackReceived(Self.validCallbackURL)) { state in
            state.handoffPendingState = nil
        }

        await store.receive(\._handoffExchangeCompleted) { state in
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.sessionExpiresAt = Self.persistedSessionExpiry
            state.ttlTimerActive = true
            state.fetchGeneration = 1
        }

        await store.receive(\.accessStatusResponse) { state in
            state.status = .coreLicenseActive
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }
        await store.receive(\.deviceBindingResponse) { state in
            state.snapshot = AccessStatusSnapshot(
                status: .coreLicenseActive,
                fetchedAt: referenceDate,
                sessionExpiresAt: Self.persistedSessionExpiry,
                deviceBindingVerifiedAt: referenceDate,
            )
            state.isSubmitting = false
            state.isComplete = true
            state.errorMessage = nil
        }
        await store.receive(\.delegate.unlocked)
        XCTAssertTrue(store.state.hasAccountSession)
        // TTL 타이머가 in-flight 상태이므로 finish 전에 exhaustivity를 끈다.
        store.exhaustivity = .off
        await store.finish()
    }

    /// ACC-001-complete_auth_handoff_callback: 만료 시각 없는 handoff session도 persisted fallback으로 unlock한다.
    /// exchange 응답의 nil expiry가 token store의 canonical fallback expiry로 정규화된 뒤 binding success까지 이어지는지 검증한다.
    /// - 검증 내용: persisted session의 fallback expiry 반영, active access 확인, device binding success, delegate unlocked 수신
    /// - 사전 조건: expiresAt=nil과 refresh token을 가진 handoff session, TemporaryHomeFixture 기반 live AccountSessionClient
    /// - 기대 결과: sessionExpiresAt이 nil이 아니고 verified snapshot으로 unlocked delegate가 전송
    func testNilExpiryHandoffSessionUsesPersistedFallbackBeforeUnlock() async throws {
        let fixture = try TemporaryHomeFixture()
        let tokenStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let accountSessionClient = AccountSessionClient.live(store: tokenStore)
        let store = makeTestStore(
            accountSessionClient: accountSessionClient,
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in
                    AccountSession(
                        accessToken: "nil-expiry-access-token",
                        status: .coreLicenseActive,
                        refreshToken: "nil-expiry-refresh-token",
                    )
                },
                fetchAccessStatus: { activeAccessStatusResponse },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: awaitingCallbackState(),
        )
        // store.exhaustivity = .off: TTL timer가 장기 실행되므로 handoff-to-unlock 체인만 소비한다.
        store.exhaustivity = .off

        await store.send(.loginCallbackReceived(Self.validCallbackURL))
        await store.receive(\._handoffExchangeCompleted)
        XCTAssertNotNil(store.state.sessionExpiresAt)
        await store.receive(\.accessStatusResponse)
        await store.receive(\.deviceBindingResponse)
        await store.receive(\.delegate.unlocked)

        XCTAssertTrue(store.state.isComplete)
        XCTAssertNotNil(store.state.snapshot?.sessionExpiresAt)
        XCTAssertNotNil(store.state.snapshot?.deviceBindingVerifiedAt)
        await store.skipInFlightEffects()
        await store.finish()
    }

    /// onboardingHost target 환경에서 voyager-onboarding-host:// callback이 정상 처리되는지 검증한다.
    func testOnboardingHostTargetAcceptsOnboardingHostCallback() async throws {
        nonisolated(unsafe) var exchangeCalled = false
        let store = makeTestStore(
            accountSessionClient: canonicalSessionClient(accessToken: "obh-token"),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in
                    exchangeCalled = true
                    return AccountSession(accessToken: "obh-token", status: .coreLicenseActive)
                },
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
            initialState: awaitingCallbackState(),
            appHandoffTarget: .onboardingHost,
        )

        let obhURL =
            try XCTUnwrap(
                URL(string: "voyager-onboarding-host://auth/callback?ticket=abc123&state=xyz789&context=onboarding"),
            )

        await store.send(.loginCallbackReceived(obhURL)) { state in
            state.handoffPendingState = nil
        }

        await store.receive(\._handoffExchangeCompleted) { state in
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.sessionExpiresAt = Self.persistedSessionExpiry
            state.ttlTimerActive = true
            state.fetchGeneration = 1
        }

        XCTAssertTrue(exchangeCalled, "onboardingHost target + onboardingHost callback → exchange 호출")
        store.exhaustivity = .off
        await store.receive(\.accessStatusResponse)
        await store.receive(\.delegate.unlocked)
        await store.finish()
    }
}

// swiftlint:enable force_unwrapping

// swiftlint:disable force_unwrapping

@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-001-exchange_handoff_token spec-owner 테스트

 interaction_id: ACC-001-exchange_handoff_token

 ticket·state·context로 /auth/app-handoff/exchange 호출 → AccountSession 획득 → 토큰 저장을 검증한다.
 파일 영속성(file persistence), 실패 시 미저장, ticket replay 방지 등 통합 시나리오를 포함한다.
 */

@MainActor
final class ACC001ExchangeHandoffTokenTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static let validTicket = "exchange-ticket-001"
    private static let validState = "handoff-state-789"

    private static var validCallbackURL: URL {
        URL(string: "voyager://auth/callback?ticket=\(validTicket)&state=\(validState)&context=onboarding")!
    }

    /// live session client + mock exchange client로 exchange → persist flow 검증용 helper.
    /// AccountSessionClient.live(store:)로 실제 파일 I/O를 수행하고,
    /// AuthNetworkClient의 exchangeHandoff만 mock 처리한다.
    private func makeWiredClients(
        exchangeHandoff: @escaping @Sendable (
            _ ticket: String, _ state: String, _ context: AppHandoffContext,
        ) async throws -> AccountSession,
        store: AccountTokenFileStore,
    ) -> (authNetwork: AuthNetworkClient, sessionClient: AccountSessionClient) {
        (
            authNetwork: AuthNetworkClient(
                exchangeHandoff: exchangeHandoff,
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            sessionClient: AccountSessionClient.live(store: store),
        )
    }

    private func makeTestStore(
        accountSessionClient: AccountSessionClient = .testValue,
        authNetworkClient: AuthNetworkClient = .testValue,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.date = .constant(referenceDate)
        }
    }

    private func canonicalSessionClient(expiresAt: Date) -> AccountSessionClient {
        let session = AccountSession(
            accessToken: "ac1-token",
            status: .none,
            refreshToken: "ac1-refresh",
            expiresAt: expiresAt,
        )
        return AccountSessionClient(
            read: { session },
            persist: { _ in },
            delete: { _ in },
        )
    }

    /// handoffPendingState가 설정된 signInInProgress 상태 (callback 대기 중)
    private func awaitingCallbackState(pendingState: String = ACC001ExchangeHandoffTokenTests
        .validState) -> AccountAccessFeature.State
    {
        var state = AccountAccessFeature.State()
        state.isSignInInProgress = true
        state.handoffPendingState = pendingState
        return state
    }

    // MARK: - ACC-001-exchange_handoff_token

    /// ACC-001-exchange_handoff_token: exchange 성공 시 hasAccountSession=true로 전환된다.
    /// 유효한 callback 수신 후 exchangeAppHandoff 성공 시 인증 세션이 설정되는지 검증한다.
    /// - 검증 내용: exchangeAppHandoff 호출, _handoffExchangeCompleted 수신, hasAccountSession=true
    /// - 사전 조건: awaitingCallbackState에서 유효한 callback URL 수신, exchangeAppHandoff가 session 반환
    /// - 기대 결과: hasAccountSession=true, isSignInInProgress=false, didSignInFail=false, fetchGeneration=1
    func testExchangeSuccessSetsLoggedIn() async {
        nonisolated(unsafe) var exchangeCalled = false
        let persistedSessionExpiry = Date(timeIntervalSince1970: 1_700_003_600)
        let store = makeTestStore(
            accountSessionClient: canonicalSessionClient(expiresAt: persistedSessionExpiry),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { ticket, state, context in
                    exchangeCalled = true
                    XCTAssertEqual(ticket, "exchange-ticket-001")
                    XCTAssertEqual(state, "handoff-state-789")
                    XCTAssertEqual(context, .onboarding)
                    return AccountSession(
                        accessToken: "ac1-token",
                        status: .coreLicenseActive,
                        refreshToken: "ac1-refresh",
                    )
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
        )

        await store.send(.loginCallbackReceived(Self.validCallbackURL)) { state in
            state.handoffPendingState = nil
        }

        await store.receive(\._handoffExchangeCompleted) { state in
            state.isSignInInProgress = false
            state.hasAccountSession = true
            state.didSignInFail = false
            state.sessionExpiresAt = persistedSessionExpiry
            state.ttlTimerActive = true
            state.fetchGeneration = 1
        }

        XCTAssertTrue(exchangeCalled, "exchangeAppHandoff 호출됨")
        XCTAssertTrue(store.state.hasAccountSession, "교환 성공 → logged_in")
        // store.exhaustivity = .off: _handoffExchangeCompleted가 다수 상태를 갱신한 이후 accessStatusResponse 처리 중 추가 상태 변경이 있을 수
        // 있으나 검증은 action 수신만 확인
        store.exhaustivity = .off
        await store.receive(\.accessStatusResponse)
        await store.receive(\.delegate.unlocked)
        await store.finish()
    }

    /// ACC-001-exchange_handoff_token: 네트워크 오류 시 didSignInFail=true로 전환된다.
    /// exchangeAppHandoff가 networkFailure를 throw할 때 인증 실패 상태로 전환되는지 검증한다.
    /// - 검증 내용: exchangeAppHandoff 실패 시 didSignInFail=true
    /// - 사전 조건: awaitingCallbackState에서 exchangeAppHandoff가 networkFailure throw
    /// - 기대 결과: isSignInInProgress=false, didSignInFail=true, isSessionExpired=false (sign-in 실패이지 session 만료가 아님)
    func testNetworkErrorSetsSignInFail() async {
        let store = makeTestStore(
            accountSessionClient: .testValue,
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in
                    throw AppHandoffExchangeError.networkFailure
                },
                fetchAccessStatus: { throw AccessError.notConfigured },
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
            state.didSignInFail = true
            state.hasAccountSession = false
        }

        XCTAssertTrue(store.state.didSignInFail, "네트워크 오류 → 인증 실패")
        XCTAssertFalse(store.state.isSignInInProgress)
        XCTAssertFalse(store.state.isSessionExpired, "네트워크 오류는 session expired가 아님")
        await store.finish()
    }

    /// ACC-001-exchange_handoff_token: 서버 거부 시 didSignInFail=true 및 canStartLogin=true로 전환된다.
    /// exchangeAppHandoff가 ticketAlreadyUsed를 throw할 때 재인증 가능 상태로 전환되는지 검증한다.
    /// - 검증 내용: ticketAlreadyUsed 에러 시 didSignInFail=true, canStartLogin=true
    /// - 사전 조건: awaitingCallbackState에서 exchangeAppHandoff가 ticketAlreadyUsed throw
    /// - 기대 결과: isSignInInProgress=false, didSignInFail=true, canStartLogin=true (session expired 아님)
    func testServerRejectionSetsSignInFailAndCanRestart() async {
        let store = makeTestStore(
            accountSessionClient: .testValue,
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in
                    throw AppHandoffExchangeError.ticketAlreadyUsed
                },
                fetchAccessStatus: { throw AccessError.notConfigured },
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
            state.didSignInFail = true
            state.hasAccountSession = false
        }

        XCTAssertTrue(store.state.didSignInFail, "서버 거부 → 즉시 실패")
        XCTAssertTrue(store.state.canStartLogin, "재인증 안내: Login CTA 활성화")
        XCTAssertFalse(store.state.isSessionExpired, "서버 거부는 session expired가 아님")
        await store.finish()
    }

    /// ACC-001-exchange_handoff_token: exchange 성공 시 토큰이 디스크에 영속 저장된다.
    /// makeWiredClient로 wiring된 client에서 exchange 성공 후 토큰 파일이 디스크에 저장되는지 검증한다.
    /// - 검증 내용: store.read()로 읽은 accessToken/refreshToken이 교환 결과와 일치
    /// - 사전 조건: TemporaryHomeFixture로 생성된 임시 홈 디렉터리, successExchangeClient
    /// - 기대 결과: 토큰 파일이 디스크에 존재하고 accessToken/refreshToken이 일치한다.
    func testExchangeSuccessPersistsTokensToDisk() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        let expectedSession = AccountSession(
            accessToken: "ac4-access-token",
            status: .coreLicenseActive,
            refreshToken: "ac4-refresh-token",
        )

        let clients = makeWiredClients(
            exchangeHandoff: { _, _, _ in expectedSession },
            store: store,
        )

        let returnedSession = try await clients.authNetwork.exchangeHandoff(
            Self.validTicket, Self.validState, .onboarding,
        )
        try? await clients.sessionClient.persist(returnedSession)

        XCTAssertEqual(returnedSession.accessToken, "ac4-access-token")

        let snapshot = fixture.snapshotFile(at: fixture.accountTokensFileURL)
        XCTAssertTrue(snapshot.exists, "교환 성공 시 토큰 파일이 디스크에 저장됨")

        let readFile = try await store.read()
        XCTAssertNotNil(readFile, "파일에서 토큰 읽기 성공")
        XCTAssertEqual(readFile?.accessToken, "ac4-access-token")
        XCTAssertEqual(readFile?.refreshToken, "ac4-refresh-token")
    }

    /// ACC-001-exchange_handoff_token: exchange 실패 시 토큰이 디스크에 저장되지 않는다.
    /// exchangeAppHandoff 실패 시 토큰 파일이 생성되지 않는지 검증한다.
    /// - 검증 내용: exchange 실패 후 store.read()가 nil 반환, 파일 존재하지 않음
    /// - 사전 조건: TemporaryHomeFixture(createVoyagerDirectory: false), networkFailure throw client
    /// - 기대 결과: AppHandoffExchangeError.networkFailure throw, 토큰 파일 미존재, read()=nil
    func testExchangeFailureNoFileWritten() async throws {
        let fixture = try TemporaryHomeFixture(createVoyagerDirectory: false)
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        let clients = makeWiredClients(
            exchangeHandoff: { _, _, _ in
                throw AppHandoffExchangeError.networkFailure
            },
            store: store,
        )

        do {
            _ = try await clients.authNetwork.exchangeHandoff(
                Self.validTicket, Self.validState, .onboarding,
            )
            XCTFail("교환 실패 시 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AppHandoffExchangeError, .networkFailure)
        }

        let snapshot = fixture.snapshotFile(at: fixture.accountTokensFileURL)
        XCTAssertFalse(snapshot.exists, "교환 실패 시 토큰 파일 미저장")

        let readFile = try await store.read()
        XCTAssertNil(readFile, "파일 없음 → read()=nil")
    }

    /// ACC-001-exchange_handoff_token: paywall context로 exchange 호출 시 성공 및 토큰 저장된다.
    /// paywall context로 exchangeAppHandoff를 호출할 때 정상 처리되는지 검증한다.
    /// - 검증 내용: paywall context가 exchange client에 전달되고 토큰이 저장됨
    /// - 사전 조건: TemporaryHomeFixture, successExchangeClient, paywall context 파라미터
    /// - 기대 결과: capturedContext=.paywall, accessToken/refreshToken 일치, 토큰 파일 저장됨
    func testPaywallContextExchangeSucceedsAndPersists() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        let expectedSession = AccountSession(
            accessToken: "ac6-paywall-access",
            status: .coreLicenseActive,
            refreshToken: "ac6-paywall-refresh",
        )

        nonisolated(unsafe) var capturedContext: AppHandoffContext?
        let clients = makeWiredClients(
            exchangeHandoff: { _, _, context in
                capturedContext = context
                return expectedSession
            },
            store: store,
        )

        let returnedSession = try await clients.authNetwork.exchangeHandoff(
            "paywall-ticket", "paywall-state", .paywall,
        )
        try? await clients.sessionClient.persist(returnedSession)

        XCTAssertEqual(capturedContext, .paywall, "paywall context로 exchange 호출")
        XCTAssertEqual(returnedSession.accessToken, "ac6-paywall-access")

        let readFile = try await store.read()
        XCTAssertNotNil(readFile, "paywall 경로에서도 토큰 저장됨")
        XCTAssertEqual(readFile?.refreshToken, "ac6-paywall-refresh")
    }

    /// ACC-001-exchange_handoff_token: 동일 ticket 재교환 시 ticketAlreadyUsed 에러가 발생한다.
    /// ticket replay 방지를 위해 동일 ticket으로 재교환 시 서버에서 거부되는지 검증한다.
    /// - 검증 내용: 첫 교환 성공, 두 번째 교환 시 ticketAlreadyUsed 에러 throw
    /// - 사전 조건: TemporaryHomeFixture, 동일 ticket/state/context로 두 번 연속 exchangeAppHandoff 호출
    /// - 기대 결과: 첫 번째는 session 반환 성공, 두 번째는 ticketAlreadyUsed 에러
    func testTicketReplayPreventionSecondExchangeFails() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        nonisolated(unsafe) var callCount = 0
        let clients = makeWiredClients(
            exchangeHandoff: { _, _, _ in
                callCount += 1
                if callCount == 1 {
                    return AccountSession(
                        accessToken: "first-access",
                        status: .coreLicenseActive,
                        refreshToken: "first-refresh",
                    )
                }
                throw AppHandoffExchangeError.ticketAlreadyUsed
            },
            store: store,
        )

        // 첫 번째 교환: 성공
        let firstSession = try await clients.authNetwork.exchangeHandoff(
            "replay-ticket", "replay-state", .onboarding,
        )
        try? await clients.sessionClient.persist(firstSession)
        XCTAssertEqual(firstSession.accessToken, "first-access")
        XCTAssertEqual(callCount, 1)

        // 첫 교환 후 토큰 파일 존재
        let firstRead = try await store.read()
        XCTAssertNotNil(firstRead, "첫 교환 후 토큰 저장됨")

        // 두 번째 교환 (동일 ticket): ticketAlreadyUsed 에러
        do {
            _ = try await clients.authNetwork.exchangeHandoff(
                "replay-ticket", "replay-state", .onboarding,
            )
            XCTFail("티켓 재사용 시 에러가 throw되어야 함")
        } catch {
            XCTAssertEqual(error as? AppHandoffExchangeError, .ticketAlreadyUsed)
        }
        XCTAssertEqual(callCount, 2, "두 번째 exchange 시도됨")
    }

    /// ACC-001-exchange_handoff_token: redacted() 호출 시 token 값이 마스킹되고 메타데이터는 보존된다.
    /// AccountTokensFile.redacted()가 accessToken/refreshToken을 ***REDACTED***로 치환하는지 검증한다.
    /// - 검증 내용: redacted accessToken/refreshToken == "***REDACTED***", 메타데이터 유지
    /// - 사전 조건: 유효한 AccountTokensFile
    /// - 기대 결과: accessToken/refreshToken 마스킹, 나머지 필드 원본 유지
    func testRedactedMasksTokensAndPreservesMetadata() {
        let original = AccountTokensFile(
            updatedAtMs: 1_718_000_000_000,
            accessToken: "access-abc",
            accessTokenExpiresAtMs: 1_718_000_900_000,
            accessTokenExpiresIn: 900,
            refreshToken: "refresh-xyz",
            refreshTokenExpiresAtMs: 1_718_090_000_000,
        )

        let redacted = original.redacted()

        XCTAssertEqual(redacted.accessToken, "***REDACTED***")
        XCTAssertEqual(redacted.refreshToken, "***REDACTED***")
        XCTAssertEqual(redacted.schemaVersion, original.schemaVersion)
        XCTAssertEqual(redacted.updatedAtMs, original.updatedAtMs)
        XCTAssertEqual(redacted.accessTokenExpiresAtMs, original.accessTokenExpiresAtMs)
        XCTAssertEqual(redacted.accessTokenExpiresIn, original.accessTokenExpiresIn)
        XCTAssertEqual(redacted.refreshTokenExpiresAtMs, original.refreshTokenExpiresAtMs)
    }

    /// ACC-001-exchange_handoff_token: 동시 파일 접근 시 actor 직렬화로 crash 없이 안전하게 처리된다.
    /// 동시 write/read가 actor 직렬화를 통해 안전하게 처리되는지 검증한다.
    /// - 검증 내용: 동시 write×2 + read×2 호출 후 최종 read가 정상 값을 반환
    /// - 사전 조건: TemporaryHomeFixture, 유효한 AccountTokensFile
    /// - 기대 결과: 최종 read가 nil이 아니고 accessToken이 일치함
    func testConcurrentWriteReadDoesNotCrash() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        let tokens = AccountTokensFile(
            updatedAtMs: 42,
            accessToken: "concurrent-access",
            accessTokenExpiresAtMs: 100,
            accessTokenExpiresIn: 58,
            refreshToken: "concurrent-refresh",
            refreshTokenExpiresAtMs: 200,
        )

        async let write1: Void = store.write(tokens)
        async let write2: Void = store.write(tokens)
        async let read1: AccountTokensFile? = store.read()
        async let read2: AccountTokensFile? = store.read()

        _ = try await (write1, write2, read1, read2)

        let finalRead = try await store.read()
        XCTAssertNotNil(finalRead)
        XCTAssertEqual(finalRead?.accessToken, "concurrent-access")
    }
}

// swiftlint:enable force_unwrapping

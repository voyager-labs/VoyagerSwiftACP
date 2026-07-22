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
    private struct TerminalCommitFailure: Error {}

    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static let validTicket = "exchange-ticket-001"
    private static let validState = "handoff-state-789"

    private actor PersistenceCancellationProbe {
        private var didStartPersisting = false
        private var didCommit = false
        private var didDiscard = false
        private var persistedSession: AccountSession?
        private var didPrepare = false
        private var prepareContinuation: CheckedContinuation<Void, Never>?
        private var commitContinuation: CheckedContinuation<Void, Never>?
        private var didFinishCommit = false

        func persist(_ session: AccountSession) async throws {
            didStartPersisting = true
            persistedSession = session
            try await ContinuousClock().sleep(for: .seconds(60))
        }

        func discard() {
            didDiscard = true
            persistedSession = nil
        }

        func prepare(_ session: AccountSession) -> AccountSession {
            persistedSession = session
            return session
        }

        func prepareAndWait(_ session: AccountSession) async -> AccountSession {
            persistedSession = session
            didPrepare = true
            await withCheckedContinuation { continuation in
                prepareContinuation = continuation
            }
            return session
        }

        func finishPrepare() {
            prepareContinuation?.resume()
            prepareContinuation = nil
        }

        func commit() async throws {
            didCommit = true
            await withCheckedContinuation { continuation in
                commitContinuation = continuation
            }
            didFinishCommit = true
        }

        func finishCommit() {
            commitContinuation?.resume()
            commitContinuation = nil
        }

        func isPersisting() -> Bool {
            didStartPersisting
        }

        func isDiscarded() -> Bool {
            didDiscard
        }

        func isCommitted() -> Bool {
            didCommit
        }

        func isPrepared() -> Bool {
            didPrepare
        }

        func didFinishTerminalCommit() -> Bool {
            didFinishCommit
        }

        func storedSession() -> AccountSession? {
            persistedSession
        }
    }

    private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
        for _ in 0 ..< 1000 {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private static var validCallbackURL: URL {
        var components = URLComponents()
        components.scheme = "voyager"
        components.host = "auth"
        components.path = "/callback"
        components.queryItems = [
            URLQueryItem(name: "ticket", value: validTicket),
            URLQueryItem(name: "state", value: validState),
            URLQueryItem(name: "context", value: "onboarding"),
        ]
        guard let url = components.url else {
            preconditionFailure("고정된 handoff callback URL을 생성할 수 없습니다.")
        }
        return url
    }

    override func setUp() async throws {
        try await super.setUp()
        _ = await AppHandoffStateStore.shared.clear(expectedState: Self.validState, owner: .onboarding)
        let admitted = await AppHandoffStateStore.shared.begin(
            PendingAppHandoff(
                state: Self.validState,
                context: .onboarding,
                owner: .onboarding,
                createdAt: referenceDate,
            ),
        )
        XCTAssertTrue(admitted)
    }

    override func tearDown() async throws {
        _ = await AppHandoffStateStore.shared.clear(expectedState: Self.validState, owner: .onboarding)
        try await super.tearDown()
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
        signInHandoffClient: SignInHandoffClient = .testValue,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
        continuousClock: TestClock<Duration> = TestClock(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.signInHandoffClient = signInHandoffClient
            $0.date = .constant(referenceDate)
            $0.continuousClock = continuousClock
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
            read: { _ in session },
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
        state.handoffTransaction = AccountAccessHandoffTransaction(context: .onboarding, scope: .onboarding)
        return state
    }

    private func terminalCommitSessionClient(
        probe: PersistenceCancellationProbe,
        session: AccountSession,
    ) -> AccountSessionClient {
        AccountSessionClient(
            read: { _ in session },
            persist: { _ in },
            prepareHandoffPersistence: { handoffSession in await probe.prepare(handoffSession) },
            commitHandoffPersistence: { _ in try await probe.commit() },
            delete: { _ in },
            discardPersistedSession: { _ in await probe.discard() },
        )
    }

    private func ordinaryHandoffCommitFailureFixture() async throws -> (
        temporaryHome: TemporaryHomeFixture,
        tokenStore: AccountTokenFileStore,
        sessionClient: AccountSessionClient,
        canonicalToken: AccountTokensFile,
    ) {
        let temporaryHome = try TemporaryHomeFixture()
        let tokenStore = AccountTokenFileStore.withCustomHome(homeURL: temporaryHome.homeURL, appEnv: .dev)
        let canonicalToken = AccountTokensFile(
            updatedAtMs: 1,
            accessToken: "canonical-access-token",
            accessTokenExpiresAtMs: 1_700_003_600_000,
            accessTokenExpiresIn: 3_600_000,
            refreshToken: "canonical-refresh-token",
            refreshTokenExpiresAtMs: 1_702_592_000_000,
            sessionBindingID: UUID(),
        )
        try await tokenStore.write(canonicalToken)
        let liveClient = AccountSessionClient.live(store: tokenStore)
        let sessionClient = AccountSessionClient(
            read: liveClient.read,
            persist: liveClient.persist,
            prepareHandoffPersistence: liveClient.prepareHandoffPersistence,
            commitHandoffPersistence: { _ in throw TerminalCommitFailure() },
            delete: liveClient.delete,
            discardPersistedSession: liveClient.discardPersistedSession,
        )
        return (temporaryHome, tokenStore, sessionClient, canonicalToken)
    }

    private func claimedHandoffAction(
        ticket: String = ACC001ExchangeHandoffTokenTests.validTicket,
        state: String = ACC001ExchangeHandoffTokenTests.validState,
        generation: UInt64 = 0,
    ) -> AccountAccessAction {
        ._handoffClaimCompleted(.init(
            ticket: ticket,
            state: state,
            context: .onboarding,
            scope: .onboarding,
            generation: generation,
            claimed: true,
        ))
    }

    // MARK: - ACC-001-exchange_handoff_token

    /// ACC-001-exchange_handoff_token: exchange 성공 시 hasAccountSession=true로 전환된다.
    /// 유효한 callback 수신 후 exchangeAppHandoff 성공 시 인증 세션이 설정되는지 검증한다.
    /// - 검증 내용: exchangeAppHandoff 호출, _handoffExchangeCompleted 수신, hasAccountSession=true
    /// - 사전 조건: awaitingCallbackState에서 유효한 callback URL 수신, exchangeAppHandoff가 session 반환
    /// - 기대 결과: hasAccountSession=true, isSignInInProgress=false, didSignInFail=false, fetchGeneration=1
    func testExchangeSuccessSetsLoggedIn() {
        let persistedSessionExpiry = Date(timeIntervalSince1970: 1_700_003_600)
        let sessionBindingID = UUID()
        let persistedSession = AccountSession(
            accessToken: "persisted-access-token",
            status: .coreLicenseActive,
            expiresAt: persistedSessionExpiry,
            sessionBindingID: sessionBindingID,
        )
        var state = awaitingCallbackState()
        state.handoffPendingState = nil
        state.handoffExchangeState = Self.validState

        withDependencies {
            $0.date = .constant(referenceDate)
        } operation: {
            _ = AccountAccessFeature().reduce(
                into: &state,
                action: ._handoffExchangeCompleted(
                    state: Self.validState,
                    generation: 0,
                    result: .success(AccountAccessHandoffCompletion(
                        expiresAt: persistedSession.expiresAt,
                        sessionBindingID: persistedSession.sessionBindingID,
                    )),
                ),
            )
        }

        XCTAssertTrue(state.hasAccountSession)
        XCTAssertFalse(state.isSignInInProgress)
        XCTAssertFalse(state.didSignInFail)
        XCTAssertEqual(state.sessionExpiresAt, persistedSessionExpiry)
        XCTAssertEqual(state.sessionBindingID, sessionBindingID)
        XCTAssertTrue(state.ttlTimerActive)
    }

    /// ACC-001-exchange_handoff_token: 이전 generation의 handoff 완료는 새 handoff 상태를 변경하지 않는다.
    /// 늦게 도착한 canonical session이 새 handoff의 binding과 expiry를 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: generation과 pending state guard가 실패하면 sessionExpiresAt과 sessionBindingID를 변경하지 않는다.
    /// - 사전 조건: generation=2의 새 handoff exchange가 진행 중이고 generation=1 완료 action이 도착한다.
    /// - 기대 결과: 새 handoff의 state와 기존 session expiry/binding이 그대로 유지된다.
    func testStaleExchangeCompletionPreservesCurrentSessionBinding() {
        let currentBinding = UUID()
        let staleBinding = UUID()
        let currentExpiry = referenceDate.addingTimeInterval(3600)
        var state = awaitingCallbackState()
        state.handoffGeneration = 2
        state.handoffPendingState = nil
        state.handoffExchangeState = "new-handoff-state"
        state.sessionExpiresAt = currentExpiry
        state.sessionBindingID = currentBinding

        _ = AccountAccessFeature().reduce(
            into: &state,
            action: ._handoffExchangeCompleted(
                state: Self.validState,
                generation: 1,
                result: .success(AccountAccessHandoffCompletion(
                    expiresAt: referenceDate.addingTimeInterval(7200),
                    sessionBindingID: staleBinding,
                )),
            ),
        )

        XCTAssertEqual(state.handoffExchangeState, "new-handoff-state")
        XCTAssertEqual(state.sessionExpiresAt, currentExpiry)
        XCTAssertEqual(state.sessionBindingID, currentBinding)
    }

    /// ACC-001-exchange_handoff_token: 이전 generation의 claim completion은 새 handoff exchange를 시작하지 않는다.
    /// - 검증 내용: generation N completion이 N+1 transaction의 pending/exchange state를 변경하지 않고 network exchange를 호출하지 않는다.
    /// - 사전 조건: onboarding transaction generation=2가 callback 대기 중이며 generation=1 claim completion이 늦게 도착한다.
    /// - 기대 결과: generation=2 transaction과 pending state가 유지되고 exchange 호출 수는 0이다.
    func testStaleClaimCompletionCannotStartNewHandoffExchange() async {
        let exchangeCallCount = LockIsolated(0)
        var initialState = awaitingCallbackState(pendingState: "new-handoff-state")
        initialState.handoffGeneration = 2
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in
                    exchangeCallCount.withValue { $0 += 1 }
                    return AccountSession(accessToken: "unexpected", status: .coreLicenseActive)
                },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: initialState,
        )

        await store.send(claimedHandoffAction(
            ticket: "stale-ticket",
            state: "new-handoff-state",
            generation: 1,
        ))

        XCTAssertEqual(exchangeCallCount.value, 0)
        XCTAssertEqual(store.state.handoffGeneration, 2)
        XCTAssertEqual(store.state.handoffPendingState, "new-handoff-state")
        XCTAssertEqual(
            store.state.handoffTransaction,
            AccountAccessHandoffTransaction(context: .onboarding, scope: .onboarding),
        )
        await store.finish()
    }
}

extension ACC001ExchangeHandoffTokenTests {
    /// ACC-001-exchange_handoff_token: terminal commit authorization 뒤 termination은 disk transaction을 취소하지 않는다.
    /// - 검증 내용: authorization이 시작한 blocked terminal commit은 termination 뒤에도 끝나며 rollback되지 않는다.
    /// - 사전 조건: onboarding handoff가 authorization을 수락하고 commitHandoffPersistence가 gate에서 대기한다.
    /// - 기대 결과: termination은 generation을 증가시키고, commit 완료 뒤 stale completion은 session state를 변경하지 않는다.
    func testAppTerminationDoesNotCancelTerminalPersistenceAndIgnoresLateCompletion() async {
        let probe = PersistenceCancellationProbe()
        let persistedSession = AccountSession(
            accessToken: "termination-access-token",
            status: .coreLicenseActive,
            refreshToken: "termination-refresh-token",
            expiresAt: referenceDate.addingTimeInterval(3600),
        )
        let sessionClient = terminalCommitSessionClient(probe: probe, session: persistedSession)
        let store = makeTestStore(
            accountSessionClient: sessionClient,
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in persistedSession },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: awaitingCallbackState(),
        )

        await store.send(claimedHandoffAction()) { state in
            state.handoffPendingState = nil
            state.handoffExchangeState = Self.validState
        }
        await store.receive(\._handoffCommitAuthorized) { state in
            state.isSignInInProgress = false
        }
        let didStartCommit = await waitUntil { await probe.isCommitted() }
        XCTAssertTrue(didStartCommit)

        await store.send(.appWillTerminate) { state in
            state.fetchGeneration = 1
            state.syncGeneration = 1
            state.revalidationGeneration = 1
            state.handoffGeneration = 1
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
            state.refreshDeadlineGeneration = 1
        }
        let didDiscardAfterTermination = await probe.isDiscarded()
        XCTAssertFalse(didDiscardAfterTermination)

        await probe.finishCommit()
        let didFinishCommit = await waitUntil { await probe.didFinishTerminalCommit() }
        XCTAssertTrue(didFinishCommit)
        let didDiscardAfterCommit = await probe.isDiscarded()
        let storedSession = await probe.storedSession()
        XCTAssertFalse(didDiscardAfterCommit)
        XCTAssertEqual(storedSession, persistedSession)

        await store.receive(\._handoffExchangeCompleted)

        XCTAssertFalse(store.state.hasAccountSession)
        await store.finish()
    }
}

extension ACC001ExchangeHandoffTokenTests {
    /// ACC-001-exchange_handoff_token: persist 도중 로그인을 취소하면 저장 세션을 rollback한다.
    /// - 검증 내용: persist 시작 후 cancelSignIn → exchange 취소 → silent discard
    /// - 기대 결과: 로그인 상태는 signed out으로 유지되고 저장 세션이 제거된다.
    func testCancelDuringPersistenceDiscardsPersistedSession() async {
        let probe = PersistenceCancellationProbe()
        let persistedSession = AccountSession(
            accessToken: "cancelled-access-token",
            status: .coreLicenseActive,
            refreshToken: "cancelled-refresh-token",
            expiresAt: referenceDate.addingTimeInterval(3600),
        )
        let sessionClient = AccountSessionClient(
            read: { _ in persistedSession },
            persist: { session in try await probe.persist(session) },
            delete: { _ in },
            discardPersistedSession: { _ in await probe.discard() },
        )
        let store = makeTestStore(
            accountSessionClient: sessionClient,
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in persistedSession },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: awaitingCallbackState(),
        )

        await store.send(claimedHandoffAction()) { state in
            state.handoffPendingState = nil
            state.handoffExchangeState = Self.validState
        }
        let didStartPersisting = await waitUntil { await probe.isPersisting() }
        XCTAssertTrue(didStartPersisting)

        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.handoffExchangeState = nil
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
        }
        let didDiscard = await waitUntil { await probe.isDiscarded() }
        XCTAssertTrue(didDiscard)

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertFalse(store.state.isSignInInProgress)
        let storedSession = await probe.storedSession()
        XCTAssertNil(storedSession)
        await store.finish()
    }

    /// ACC-001-exchange_handoff_token: prepare-authorization 경계 취소는 staged session을 rollback한다.
    /// - 검증 내용: prepare gate가 열린 뒤 cancellation check가 authorization action보다 먼저 discard를 선택한다.
    /// - 사전 조건: prepareHandoffPersistence가 staging을 기록하고, cancelSignIn이 gate 해제 전에 exchange effect를 취소한다.
    /// - 기대 결과: _handoffCommitAuthorized가 수신되지 않고 staging session이 discard된다.
    func testCancelAfterPrepareBeforeAuthorizationDiscardsPersistedSession() async {
        let probe = PersistenceCancellationProbe()
        let persistedSession = AccountSession(
            accessToken: "prepare-window-access-token",
            status: .coreLicenseActive,
            refreshToken: "prepare-window-refresh-token",
            expiresAt: referenceDate.addingTimeInterval(3600),
        )
        let sessionClient = AccountSessionClient(
            read: { _ in persistedSession },
            persist: { _ in },
            prepareHandoffPersistence: { session in
                await probe.prepareAndWait(session)
            },
            commitHandoffPersistence: { _ in },
            delete: { _ in },
            discardPersistedSession: { _ in await probe.discard() },
        )
        let store = makeTestStore(
            accountSessionClient: sessionClient,
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in persistedSession },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: awaitingCallbackState(),
        )

        await store.send(claimedHandoffAction()) { state in
            state.handoffPendingState = nil
            state.handoffExchangeState = Self.validState
        }
        let didPrepare = await waitUntil { await probe.isPrepared() }
        XCTAssertTrue(didPrepare)

        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
        }
        await probe.finishPrepare()
        let didDiscard = await waitUntil { await probe.isDiscarded() }
        XCTAssertTrue(didDiscard)
        let storedSession = await probe.storedSession()
        XCTAssertNil(storedSession)
        await store.finish()
    }

    /// ACC-001-exchange_handoff_token: authorization 뒤 취소는 terminal commit을 rollback하지 않는다.
    func testCancelAfterAuthorizationAllowsTerminalCommitWithoutRollback() async {
        let probe = PersistenceCancellationProbe()
        let persistedSession = AccountSession(
            accessToken: "commit-window-access-token",
            status: .coreLicenseActive,
            refreshToken: "commit-window-refresh-token",
            expiresAt: referenceDate.addingTimeInterval(3600),
        )
        let sessionClient = AccountSessionClient(
            read: { _ in persistedSession },
            persist: { _ in },
            prepareHandoffPersistence: { session in await probe.prepare(session) },
            commitHandoffPersistence: { _ in try await probe.commit() },
            delete: { _ in },
            discardPersistedSession: { _ in await probe.discard() },
        )
        let store = makeTestStore(
            accountSessionClient: sessionClient,
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in persistedSession },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: awaitingCallbackState(),
        )

        await store.send(claimedHandoffAction()) { state in
            state.handoffPendingState = nil
            state.handoffExchangeState = Self.validState
        }
        await store.receive(\._handoffCommitAuthorized) { state in
            state.isSignInInProgress = false
        }
        let didCommit = await waitUntil { await probe.isCommitted() }
        XCTAssertTrue(didCommit)

        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
        }
        let didDiscard = await probe.isDiscarded()
        XCTAssertFalse(didDiscard)
        await probe.finishCommit()
        await store.receive(\._handoffExchangeCompleted)
        await store.finish()
    }

    /// ACC-001-exchange_handoff_token: 취소 rollback 실패는 사용자 복구 오류로 노출한다.
    /// - 검증 내용: persist 시작 후 cancelSignIn → discard 실패 → rollback failure action
    /// - 기대 결과: 저장 세션 정리 실패를 숨기지 않고 sign-in failure 상태로 전환한다.
    func testCancelDuringPersistenceSurfacesRollbackFailure() async {
        let probe = PersistenceCancellationProbe()
        let persistedSession = AccountSession(
            accessToken: "rollback-failure-access-token",
            status: .coreLicenseActive,
            refreshToken: "rollback-failure-refresh-token",
            expiresAt: referenceDate.addingTimeInterval(3600),
        )
        let sessionClient = AccountSessionClient(
            read: { _ in persistedSession },
            persist: { session in try await probe.persist(session) },
            delete: { _ in },
            discardPersistedSession: { _ in
                throw AccountSessionPersistenceError.discardUnavailable
            },
        )
        let store = makeTestStore(
            accountSessionClient: sessionClient,
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in persistedSession },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: awaitingCallbackState(),
        )

        await store.send(claimedHandoffAction()) { state in
            state.handoffPendingState = nil
            state.handoffExchangeState = Self.validState
        }
        let didStartPersisting = await waitUntil { await probe.isPersisting() }
        XCTAssertTrue(didStartPersisting)

        await store.send(.cancelSignIn) { state in
            state.isSignInInProgress = false
            state.handoffExchangeState = nil
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
        }
        await store.receive(\._handoffPersistenceRollbackFailed) { state in
            state.didSignInFail = true
            state.errorMessage = "Saved sign-in data could not be cleared. Quit Voyager and try again."
        }

        XCTAssertTrue(store.state.didSignInFail)
        XCTAssertNotNil(store.state.errorMessage)
        await store.finish()
    }

    /// ACC-001-exchange_handoff_token: 이전 rollback 실패는 새 handoff generation을 덮지 않는다.
    func testStaleRollbackFailureDoesNotOverwriteNewHandoff() async {
        var initialState = awaitingCallbackState(pendingState: "new-handoff-state")
        initialState.handoffGeneration = 2
        let store = makeTestStore(initialState: initialState)

        await store.send(._handoffPersistenceRollbackFailed(generation: 1))

        XCTAssertTrue(store.state.isSignInInProgress)
        XCTAssertFalse(store.state.didSignInFail)
        XCTAssertEqual(store.state.handoffPendingState, "new-handoff-state")
    }
}

extension ACC001ExchangeHandoffTokenTests {
    /// ACC-001-exchange_handoff_token: ordinary handoff terminal commit 실패는 staging을 rollback하고 canonical credential을
    /// 보존한다.
    /// - 검증 내용: authorization 뒤 commit failure가 signed-out/sign-in-failed 상태와 staging/marker 정리로 끝난다.
    /// - 사전 조건: callback 대기 중 ordinary handoff와 기존 canonical token, 실패하는 commitHandoffPersistence.
    /// - 기대 결과: 새 candidate는 저장되지 않고 기존 canonical token은 그대로 읽힌다.
    func testOrdinaryHandoffCommitFailureRollsBackStagingAndPreservesCanonicalCredential() async throws {
        let fixture = try await ordinaryHandoffCommitFailureFixture()
        let candidateSession = AccountSession(
            accessToken: "candidate-access-token",
            status: .coreLicenseActive,
            refreshToken: "candidate-refresh-token",
            expiresAt: referenceDate.addingTimeInterval(7200),
            sessionBindingID: UUID(),
        )
        let store = makeTestStore(
            accountSessionClient: fixture.sessionClient,
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in candidateSession },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            ),
            initialState: awaitingCallbackState(),
        )

        await store.send(claimedHandoffAction()) { state in
            state.handoffPendingState = nil
            state.handoffExchangeState = Self.validState
        }
        await store.receive(\._handoffCommitAuthorized) { state in
            state.isSignInInProgress = false
        }
        await store.receive(\._handoffExchangeCompleted) { state in
            state.didSignInFail = true
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
        }

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertTrue(store.state.didSignInFail)
        let stagingURL = AccountTokenFSLocation.handoffStagingFileURL(
            homeDirectoryURL: fixture.temporaryHome.homeURL,
            appEnv: .dev,
        )
        let markerURL = AccountTokenFSLocation.rollbackMarkerFileURL(
            homeDirectoryURL: fixture.temporaryHome.homeURL,
            appEnv: .dev,
        )
        XCTAssertFalse(fixture.temporaryHome.snapshotFile(at: stagingURL).exists)
        XCTAssertFalse(fixture.temporaryHome.snapshotFile(at: markerURL).exists)
        let canonicalToken = try await fixture.tokenStore.read()
        XCTAssertEqual(canonicalToken, fixture.canonicalToken)
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

        await store.send(.loginCallbackReceived(Self.validCallbackURL))
        await store.receive(\._handoffClaimCompleted) { state in
            state.handoffPendingState = nil
            state.handoffExchangeState = Self.validState
        }

        await store.receive(\._handoffExchangeCompleted) { state in
            state.isSignInInProgress = false
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
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

        await store.send(.loginCallbackReceived(Self.validCallbackURL))
        await store.receive(\._handoffClaimCompleted) { state in
            state.handoffPendingState = nil
            state.handoffExchangeState = Self.validState
        }

        await store.receive(\._handoffExchangeCompleted) { state in
            state.isSignInInProgress = false
            state.handoffExchangeState = nil
            state.handoffTransaction = nil
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
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL, appEnv: .dev)

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

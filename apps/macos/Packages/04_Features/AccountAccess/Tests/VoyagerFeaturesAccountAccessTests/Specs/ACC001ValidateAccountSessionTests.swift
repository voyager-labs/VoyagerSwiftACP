import Clocks
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC001ValidateAccountSessionTests: XCTestCase {
    nonisolated private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(
        initialState: AccountAccessFeature.State,
        syncResult: @escaping @Sendable (SessionSyncIntent) async throws -> SessionSyncResult,
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) { AccountAccessFeature() } withDependencies: {
            $0.accountSessionClient = .testValue
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { intent, _ in try await syncResult(intent) },
            )
            $0.date = .constant(Self.referenceDate)
            $0.continuousClock = TestClock()
        }
    }

    private func signedInState() -> AccountAccessFeature.State {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionExpiresAt = Self.referenceDate.addingTimeInterval(3600)
        state.sessionBindingID = UUID()
        return state
    }

    nonisolated private static var completeResult: SessionSyncResult {
        SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(hasAccess: true, status: "active"),
            deviceBindingOutcome: .notAttempted,
            connectedDeviceAvailability: .unknown,
            sessionExpiresAt: referenceDate.addingTimeInterval(3600),
        )
    }

    // MARK: - ACC-001-validate_account_session

    /// ACC-001-validate_account_session: validate 요청은 session sync를 실행한다.
    /// 현재 세션에 대한 validate intent와 complete 결과를 처리하는지 검증한다.
    /// - 검증 내용: activation, sync completion, lastCompleteSyncAt, isSubmitting
    /// - 사전 조건: 유효한 persisted account session
    /// - 기대 결과: validate 호출과 complete sync timestamp 기록
    func testValidateSessionRecordsCompleteSync() async {
        let store = makeStore(initialState: signedInState()) { intent in
            precondition(intent == .validate)
            return Self.completeResult
        }

        await store.send(.sessionSyncRequested(intent: .validate, reason: .manual)) { state in
            state.isSubmitting = true
            state.syncGeneration = 1
            state.inFlightSyncReason = .manual
        }
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted) { state in
            state.isSubmitting = false
            state.lastCompleteSyncAt = Self.referenceDate
            state.inFlightSyncReason = nil
            state.ttlTimerActive = true
            state.refreshDeadlineGeneration = 1
        }
        await store.skipInFlightEffects()
    }

    /// ACC-001-validate_account_session: invalid credential은 session expiry로 라우팅된다.
    /// sync 응답이 인증 만료를 나타낼 때 세션 만료 action으로 전환하는지 검증한다.
    /// - 검증 내용: invalidCredential 결과 후 _sessionExpiredDetected
    /// - 사전 조건: 유효한 account session과 validate 요청
    /// - 기대 결과: hasAccountSession=false, isSessionExpired=true
    func testInvalidCredentialExpiresSession() async {
        let store = makeStore(initialState: signedInState()) { _ in throw SessionSyncError.invalidCredential }

        await store.send(.sessionSyncRequested(intent: .validate, reason: .manual)) { state in
            state.isSubmitting = true
            state.syncGeneration = 1
            state.inFlightSyncReason = .manual
        }
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted) { state in
            state.isSubmitting = false
            state.inFlightSyncReason = nil
        }
        await store.receive(\._sessionExpiredDetected) { state in
            state.hasAccountSession = false
            state.isSessionExpired = true
            state.didSignInFail = true
            state.fetchGeneration = 1
            state.syncGeneration = 2
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
            state.sessionExpiresAt = nil
            state.sessionBindingID = nil
        }
        await store.finish()
    }

    /// ACC-001-validate_account_session: 일반 sync 실패는 세션을 만료시키지 않는다.
    /// 인증 오류가 아닌 upstream 오류가 errorMessage만 갱신하는지 검증한다.
    /// - 검증 내용: isSessionExpired 및 hasAccountSession 보존
    /// - 사전 조건: 네트워크 실패를 반환하는 sync client
    /// - 기대 결과: signed-in 상태 유지 및 오류 메시지 기록
    func testUpstreamFailurePreservesSession() async {
        let store = makeStore(initialState: signedInState()) { _ in throw SessionSyncError.upstream(503) }

        await store.send(.sessionSyncRequested(intent: .validate, reason: .manual)) { state in
            state.isSubmitting = true
            state.syncGeneration = 1
            state.inFlightSyncReason = .manual
        }
        await store.receive(\._sessionSyncActivationCompleted)
        await store.receive(\._sessionSyncCompleted) { state in
            state.isSubmitting = false
            state.inFlightSyncReason = nil
            state.errorMessage = "Network error. Please check your connection and try again."
        }
        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertFalse(store.state.isSessionExpired)
    }
}

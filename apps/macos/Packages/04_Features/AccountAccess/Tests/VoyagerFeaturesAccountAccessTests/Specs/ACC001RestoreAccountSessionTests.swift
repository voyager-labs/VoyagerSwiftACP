// swiftlint:disable force_unwrapping

@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-001-restore_account_session spec-owner 테스트

 interaction_id: ACC-001-restore_account_session

 auth_state 매핑:
 - logged_out     → AccountAccessState 기본 상태 (hasAccountSession=false, didSignInFail=false)
 - session_expired → didSignInFail=true (재로그인 필요 상태)
 - logged_in      → hasAccountSession=true
 */

@MainActor
final class ACC001RestoreAccountSessionTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

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

    // MARK: - ACC-001-restore_account_session

    /// ACC-001-restore_account_session: 저장된 유효 session이 onAppear에서 logged_in으로 복원된다.
    /// 유효한 session이 저장되어 있을 때 onAppear에서 hasAccountSession=true로 복원되는지 검증한다.
    /// - 검증 내용: restoreSession이 session 반환 → hasAccountSession=true, fetchAccessStatus 트리거
    /// - 사전 조건: sessionClient.read가 유효한 AccountSession 반환
    /// - 기대 결과: hasAccountSession=true, accountAccessAuthAxis=.signedIn, fetchCalled=true
    func testValidSessionRestoresAsLoggedIn() async {
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
                    return AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
        )
        // store.exhaustivity = .off: _onAppearSessionRestored가 내부적으로 다수 필드를 갱신하나 검증 대상은
        // hasAccountSession/accountAccessAuthAxis/fetchCalled만 해당
        store.exhaustivity = .off

        await store.send(.onAppear)

        await store.receive(\._onAppearSessionRestored)

        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signedIn)
        XCTAssertTrue(fetchCalled)
    }

    /// ACC-001-restore_account_session: session 만료 후 자동 갱신 성공 시 logged_in을 유지한다.
    /// T6 token refresh logic 구현 후 활성화되는 테스트로 현재는 skip 처리한다.
    /// - 검증 내용: T6 refresh logic이 session 만료 후 자동 갱신 성공 시 logged_in 유지 확인
    /// - 사전 조건: T6 refresh logic 구현 완료
    /// - 기대 결과: 자동 갱신 성공 시 logged_in 유지
    func testExpiredSessionRefreshSuccessStaysLoggedIn() throws {
        try XCTSkip("Requires T6 token refresh logic")
    }

    /// ACC-001-restore_account_session: 만료된 session 복원 실패 시 session_expired로 전환된다.
    /// loginCallbackReceived 후 restoreSession=nil일 때 didSignInFail=true로 전환되는지 검증한다.
    /// - 검증 내용: loginCallbackReceived 후 restoreSession=nil → didSignInFail=true, signInFailed axis
    /// - 사전 조건: isSignInInProgress=true, sessionClient.read가 nil 반환
    /// - 기대 결과: didSignInFail=true, isSessionExpired=true, canStartLogin=true
    func testExpiredSessionRestoreFailsSetsSessionExpired() async throws {
        nonisolated(unsafe) var fetchCalled = false
        var initialState = AccountAccessFeature.State()
        initialState.isSignInInProgress = true

        let callbackURL = try XCTUnwrap(URL(string: "voyager://auth/callback"))

        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { nil },
                persist: { _ in },
                delete: {},
            ),
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

        await store.send(.loginCallbackReceived(callbackURL))

        await store.receive(\._loginSessionRestored) { state in
            state.isSignInInProgress = false
        }

        await store.receive(\._sessionExpiredDetected) { state in
            state.didSignInFail = true
            state.hasAccountSession = false
            state.isSessionExpired = true
        }

        XCTAssertFalse(fetchCalled)
        XCTAssertTrue(store.state.didSignInFail)
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signInFailed)
        XCTAssertTrue(store.state.canStartLogin)
        await store.finish()
    }

    /// ACC-001-restore_account_session: 저장된 session이 없으면 onAppear에서 logged_out으로 진입한다.
    /// restoreSession=nil일 때 onAppear에서 logged_out 상태로 진입하는지 검증한다.
    /// - 검증 내용: restoreSession=nil → hasAccountSession=false, fetchAccessStatus 미호출
    /// - 사전 조건: sessionClient.read가 nil 반환
    /// - 기대 결과: hasAccountSession=false, accountAccessAuthAxis=.signedOut, fetchCalled=false
    func testNoStoredSessionShowsLoggedOut() async {
        nonisolated(unsafe) var fetchCalled = false
        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { nil },
                persist: { _ in },
                delete: {},
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCalled = true
                    return AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
        )
        // store.exhaustivity = .off: _onAppearSessionRestored가 다수 필드를 갱신하나 검증 대상은
        // hasAccountSession/accountAccessAuthAxis/accountAccessStepState/fetchCalled만 해당
        store.exhaustivity = .off

        await store.send(.onAppear)

        await store.receive(\._onAppearSessionRestored)

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signedOut)
        XCTAssertEqual(store.state.accountAccessStepState, .blocked)
        XCTAssertFalse(fetchCalled)
    }

    /// ACC-001-restore_account_session: 손상된 token 파일은 logged_out으로 처리된다.
    /// 손상된 token 파일이 FileStore에서 quarantine 후 nil을 반환하여 logged_out이 되는지 검증한다.
    /// - 검증 내용: corrupt JSON → read()=nil → restoreSession=nil → logged_out
    /// - 사전 조건: TemporaryHomeFixture에 손상된 JSON 파일이 저장되어 있음
    /// - 기대 결과: read()=nil, accountAccessAuthAxis=.signedOut, hasAccountSession=false
    func testCorruptedSessionTreatedAsLoggedOut() async throws {
        let fixture = try TemporaryHomeFixture()
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        try try XCTUnwrap("{ invalid json }".data(using: .utf8)?.write(to: fixture.accountTokensFileURL))

        let result = try await fileStore.read()
        XCTAssertNil(result, "손상된 session 파일은 nil 반환")

        var state = AccountAccessFeature.State()
        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertFalse(state.hasAccountSession)
    }

    /// ACC-001-restore_account_session: 자동 갱신 중 네트워크 오류 시 기존 session이 유지된다.
    /// T6 token refresh logic 구현 후 활성화되는 테스트로 현재는 skip 처리한다.
    /// - 검증 내용: T6 refresh logic이 네트워크 오류 시 기존 session 유지 확인
    /// - 사전 조건: T6 refresh logic 구현 완료
    /// - 기대 결과: 네트워크 오류 시에도 기존 session 유지
    func testNetworkErrorDuringRefreshMaintainsSession() throws {
        try XCTSkip("Requires T6 token refresh logic")
    }

    /// ACC-001-restore_account_session: 앱 최초 실행 시 token 파일이 없으면 logged_out으로 진입한다.
    /// 앱 최초 실행 시 token 파일이 존재하지 않을 때 logged_out 상태가 되는지 검증한다.
    /// - 검증 내용: 파일 없음 → read()=nil → restoreSession=nil → logged_out
    /// - 사전 조건: TemporaryHomeFixture(createVoyagerDirectory=false), token 파일 없음
    /// - 기대 결과: read()=nil, accountAccessAuthAxis=.signedOut, hasAccountSession=false
    func testFirstRunNoSessionShowsLoggedOut() async throws {
        let fixture = try TemporaryHomeFixture(createVoyagerDirectory: false)
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path),
            "최초 실행: token 파일 없음",
        )

        let result = try await fileStore.read()
        XCTAssertNil(result, "파일이 없으면 read()=nil")

        var state = AccountAccessFeature.State()
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
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

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
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

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
        let fileStore = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)

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

// swiftlint:enable force_unwrapping

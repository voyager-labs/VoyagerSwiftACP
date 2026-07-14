@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-004-account_session_client spec-owner 테스트

 AccountSessionClient가 file I/O(읽기/쓰기/삭제)와 만료 검증을 올바르게 처리하는지 검증한다.
 */

@MainActor
final class ACC004AccountSessionClientTests: XCTestCase {
    // MARK: - ACC-004-account_session_client

    /// ACC-004-account_session_client: 파일이 없으면 read()가 nil을 반환한다.
    /// token 파일이 존재하지 않을 때 read()가 nil을 반환하는지 검증한다.
    /// - 검증 내용: read()가 nil 반환
    /// - 사전 조건: TemporaryHomeFixture, AccountTokenFileStore(withCustomHome), AccountSessionClient.live
    /// - 기대 결과: read()가 nil 반환
    func testReadReturnsNilWhenFileMissing() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)

        let session = try await client.read()

        XCTAssertNil(session)
    }

    /// ACC-004-account_session_client: 유효(미만료) 토큰이 있을 때 read()가 session을 반환한다.
    /// 만료되지 않은 token 파일이 저장되어 있을 때 read()가 유효한 AccountSession을 반환하는지 검증한다.
    /// - 검증 내용: read()가 AccountSession 반환, accessToken/refreshToken 일치
    /// - 사전 조건: TemporaryHomeFixture, AccountTokenFileStore에 미래 만료 시각의 AccountTokensFile 저장
    /// - 기대 결과: read()가 nil이 아닌 session 반환, accessToken="valid-token", refreshToken="refresh-token"
    func testReadReturnsSessionWhenValidToken() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)

        let futureMs = Int64(Date().timeIntervalSince1970 * 1000) + 86_400_000
        let tokensFile = AccountTokensFile(
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            accessToken: "valid-token",
            accessTokenExpiresAtMs: futureMs,
            accessTokenExpiresIn: 86_400_000,
            refreshToken: "refresh-token",
            refreshTokenExpiresAtMs: futureMs + 2_592_000_000,
        )
        try await store.write(tokensFile)

        let session = try await client.read()

        XCTAssertNotNil(session)
        XCTAssertEqual(session?.accessToken, "valid-token")
        XCTAssertEqual(session?.refreshToken, "refresh-token")
    }

    /// ACC-004-account_session_client: 만료된 토큰이 있을 때 read()가 nil을 반환한다.
    /// 만료된 token 파일이 저장되어 있을 때 read()가 nil을 반환하는지 검증한다.
    /// - 검증 내용: read()가 nil 반환
    /// - 사전 조건: TemporaryHomeFixture, AccountTokenFileStore에 과거 만료 시각의 AccountTokensFile 저장
    /// - 기대 결과: read()가 nil 반환
    func testReadReturnsNilWhenExpired() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)

        let pastMs = Int64(Date().timeIntervalSince1970 * 1000) - 86_400_000
        let tokensFile = AccountTokensFile(
            updatedAtMs: pastMs,
            accessToken: "expired-token",
            accessTokenExpiresAtMs: pastMs,
            accessTokenExpiresIn: 0,
            refreshToken: "old-refresh",
            refreshTokenExpiresAtMs: pastMs,
        )
        try await store.write(tokensFile)

        let session = try await client.read()

        XCTAssertNil(session)
    }

    /// ACC-004-account_session_client: persist()가 session을 파일에 쓴다.
    /// AccountSession을 persist()로 저장했을 때 AccountTokenFileStore에서 읽을 수 있는지 검증한다.
    /// - 검증 내용: persist() 후 store.read()가 동일한 accessToken/refreshToken의 AccountTokensFile 반환
    /// - 사전 조건: TemporaryHomeFixture, AccountTokenFileStore, 유효한 AccountSession
    /// - 기대 결과: store.read()가 nil이 아닌 file 반환, file.accessToken="new-token", file.refreshToken="new-refresh"
    func testPersistWritesSessionToFile() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)

        let session = AccountSession(
            accessToken: "new-token",
            status: .none,
            refreshToken: "new-refresh",
            expiresAt: Date().addingTimeInterval(86400),
        )
        try await client.persist(session)

        let file = try await store.read()
        XCTAssertNotNil(file)
        XCTAssertEqual(file?.accessToken, "new-token")
        XCTAssertEqual(file?.refreshToken, "new-refresh")
    }

    /// ACC-004-account_session_client: delete()가 token 파일을 삭제한다.
    /// persist() 후 delete()를 호출했을 때 파일이 삭제되는지 검증한다.
    /// - 검증 내용: persist 후 read()!=nil, delete 후 read()==nil
    /// - 사전 조건: TemporaryHomeFixture, AccountTokenFileStore, persist로 세션 저장
    /// - 기대 결과: delete 후 read()가 nil 반환
    func testDeleteRemovesTokenFile() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)

        let session = AccountSession(
            accessToken: "token-to-delete",
            status: .none,
            refreshToken: "refresh-to-delete",
        )
        try await client.persist(session)

        var file = try await store.read()
        XCTAssertNotNil(file)

        try await client.delete(.explicitSignOut)

        file = try await store.read()
        XCTAssertNil(file)
    }

    /// ACC-004-account_session_client: 파일이 없어도 delete()가 성공한다.
    /// token 파일이 존재하지 않을 때 delete()가 throw하지 않는지 검증한다.
    /// - 검증 내용: delete()가 throw하지 않음
    /// - 사전 조건: TemporaryHomeFixture, AccountTokenFileStore, 파일 없음
    /// - 기대 결과: delete() 정상 종료
    func testDeleteSucceedsWhenFileMissing() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)

        try await client.delete(.explicitSignOut)
    }

    /// ACC-004-account_session_client: CAS는 요청 전 credential snapshot과 일치할 때만 교체한다.
    func testReplaceIfCurrentMatchesRejectsDeletedOrReplacedCredentials() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let expected = AccountTokensFile(
            updatedAtMs: 1,
            accessToken: "expected-access",
            accessTokenExpiresAtMs: 2,
            accessTokenExpiresIn: 1,
            refreshToken: "expected-refresh",
            refreshTokenExpiresAtMs: 3,
        )
        let rotated = AccountTokensFile(
            updatedAtMs: 4,
            accessToken: "rotated-access",
            accessTokenExpiresAtMs: 5,
            accessTokenExpiresIn: 1,
            refreshToken: "rotated-refresh",
            refreshTokenExpiresAtMs: 6,
        )
        let replacement = AccountTokensFile(
            updatedAtMs: 7,
            accessToken: "replacement-access",
            accessTokenExpiresAtMs: 8,
            accessTokenExpiresIn: 1,
            refreshToken: "replacement-refresh",
            refreshTokenExpiresAtMs: 9,
        )
        try await store.write(expected)

        let didReplace = try await store.replaceIfCurrentMatches(rotated, expected: expected)

        XCTAssertTrue(didReplace)
        let rotatedFile = try await store.read()
        XCTAssertEqual(rotatedFile, rotated)

        try await store.delete()
        let didReplaceDeletedFile = try await store.replaceIfCurrentMatches(rotated, expected: expected)

        XCTAssertFalse(didReplaceDeletedFile)
        let deletedFile = try await store.read()
        XCTAssertNil(deletedFile)

        try await store.write(replacement)
        let didReplaceReplacement = try await store.replaceIfCurrentMatches(rotated, expected: expected)

        XCTAssertFalse(didReplaceReplacement)
        let replacementFile = try await store.read()
        XCTAssertEqual(replacementFile, replacement)
    }

    /// ACC-004-account_session_client: 이전 handoff rollback은 새 세션을 삭제하지 않는다.
    func testDiscardDoesNotDeleteDifferentSession() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)
        let previousSession = AccountSession(
            accessToken: "previous-token",
            status: .none,
            refreshToken: "previous-refresh",
        )
        let currentSession = AccountSession(
            accessToken: "current-token",
            status: .none,
            refreshToken: "current-refresh",
        )
        try await client.persist(currentSession)

        try await client.discardPersistedSession(previousSession)

        let restoredSession = try await client.read()
        XCTAssertEqual(restoredSession?.accessToken, currentSession.accessToken)
        XCTAssertEqual(restoredSession?.refreshToken, currentSession.refreshToken)
    }

    /// ACC-004-account_session_client: 준비 중인 handoff 취소는 기존 canonical session을 보존한다.
    func testDiscardPreparedHandoffPreservesCanonicalSession() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)
        let canonicalSession = AccountSession(
            accessToken: "canonical-token",
            status: .none,
            refreshToken: "canonical-refresh",
            expiresAt: Date().addingTimeInterval(86400),
        )
        let preparedSession = AccountSession(
            accessToken: "prepared-token",
            status: .none,
            refreshToken: "prepared-refresh",
            expiresAt: Date().addingTimeInterval(86400),
        )
        try await client.persist(canonicalSession)
        _ = try await client.prepareHandoffPersistence(preparedSession)

        try await client.discardPersistedSession(preparedSession)
        let restoredSession = try await client.read()

        XCTAssertEqual(restoredSession?.accessToken, canonicalSession.accessToken)
        XCTAssertEqual(restoredSession?.refreshToken, canonicalSession.refreshToken)
    }

    /// ACC-004-account_session_client: marker 없는 stale staging은 기존 canonical session을 변경하지 않는다.
    func testPrepareReplacesStaleStagingWithoutDeletingCanonicalSession() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)
        let canonicalSession = AccountSession(
            accessToken: "canonical-token",
            status: .none,
            refreshToken: "canonical-refresh",
            expiresAt: Date().addingTimeInterval(86400),
        )
        let staleSession = AccountSession(
            accessToken: "stale-token",
            status: .none,
            refreshToken: "stale-refresh",
            expiresAt: Date().addingTimeInterval(86400),
        )
        let replacementSession = AccountSession(
            accessToken: "replacement-token",
            status: .none,
            refreshToken: "replacement-refresh",
            expiresAt: Date().addingTimeInterval(86400),
        )
        try await client.persist(canonicalSession)
        _ = try await client.prepareHandoffPersistence(staleSession)
        let markerURL = AccountTokenFSLocation.rollbackMarkerFileURL(
            homeDirectoryURL: fixture.homeURL,
        )
        try FileManager.default.removeItem(at: markerURL)

        _ = try await client.prepareHandoffPersistence(replacementSession)
        try await client.discardPersistedSession(replacementSession)
        let restoredSession = try await client.read()

        XCTAssertEqual(restoredSession?.accessToken, canonicalSession.accessToken)
        XCTAssertEqual(restoredSession?.refreshToken, canonicalSession.refreshToken)
    }

    /// ACC-004-account_session_client: partial commit rollback은 새 canonical credential을 제거한다.
    func testDiscardPartialCommitRemovesMatchingCanonicalSession() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)
        let preparedSession = AccountSession(
            accessToken: "partial-commit-token",
            status: .none,
            refreshToken: "partial-commit-refresh",
            expiresAt: Date().addingTimeInterval(86400),
        )
        _ = try await client.prepareHandoffPersistence(preparedSession)
        let stagingURL = AccountTokenFSLocation.handoffStagingFileURL(
            homeDirectoryURL: fixture.homeURL,
        )
        let stagedData = try Data(contentsOf: stagingURL)
        try stagedData.write(to: fixture.accountTokensFileURL, options: .atomic)

        try await client.discardPersistedSession(preparedSession)
        let restoredSession = try await client.read()

        XCTAssertNil(restoredSession)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path))
    }

    /// ACC-004-account_session_client: 미완료 rollback marker가 있으면 저장 세션을 복원하지 않는다.
    func testReadRejectsSessionWithPendingRollbackMarker() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)
        let session = AccountSession(
            accessToken: "cancelled-token",
            status: .none,
            refreshToken: "cancelled-refresh",
        )
        try await client.persist(session)
        let markerURL = AccountTokenFSLocation.rollbackMarkerFileURL(
            homeDirectoryURL: fixture.homeURL,
        )
        try Data("rollback-pending".utf8).write(to: markerURL, options: .atomic)

        let restoredSession = try await client.read()

        XCTAssertNil(restoredSession)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
    }

    /// ACC-004-account_session_client: 일반 read는 handoff 준비 저장을 삭제하지 않는다.
    func testReadDoesNotDestroyPreparedHandoffSession() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)
        let session = AccountSession(
            accessToken: "prepared-token",
            status: .none,
            refreshToken: "prepared-refresh",
            expiresAt: Date().addingTimeInterval(86400),
        )

        _ = try await client.prepareHandoffPersistence(session)
        let restoredSession = try await client.read()

        XCTAssertNil(restoredSession)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.accountTokensFileURL.path))
        let stagingURL = AccountTokenFSLocation.handoffStagingFileURL(
            homeDirectoryURL: fixture.homeURL,
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingURL.path))

        try await client.commitHandoffPersistence(session)
        try await client.finalizeHandoffPersistence()
        let committedSession = try await client.read()
        XCTAssertEqual(committedSession?.accessToken, session.accessToken)
    }

    /// ACC-004-account_session_client: commit된 handoff 준비 저장은 정상 복원된다.
    func testCommittedHandoffSessionCanBeRestored() async throws {
        let fixture = try TemporaryHomeFixture()
        let store = AccountTokenFileStore.withCustomHome(homeURL: fixture.homeURL)
        let client = AccountSessionClient.live(store: store)
        let session = AccountSession(
            accessToken: "committed-token",
            status: .none,
            refreshToken: "committed-refresh",
            expiresAt: Date().addingTimeInterval(86400),
        )

        _ = try await client.prepareHandoffPersistence(session)
        try await client.commitHandoffPersistence(session)
        try await client.finalizeHandoffPersistence()
        let restoredSession = try await client.read()

        XCTAssertEqual(restoredSession?.accessToken, session.accessToken)
        XCTAssertEqual(restoredSession?.refreshToken, session.refreshToken)
    }

    /// ACC-004-account_session_client: testValue가 안전한 기본값(read=nil, persist/delete=no-op)을 제공한다.
    /// testValue의 read/persist/delete가 throw하지 않고 기본값을 반환하는지 검증한다.
    /// - 검증 내용: read()=nil, persist/delete throw 없음
    /// - 사전 조건: AccountSessionClient.testValue
    /// - 기대 결과: 모든 메서드가 throw 없이 정상 동작, read()=nil
    func testTestValueIsSafeDefault() async throws {
        let client = AccountSessionClient.testValue

        let session = try await client.read()
        XCTAssertNil(session)

        let anySession = AccountSession(accessToken: "any-token", status: .none)
        try await client.persist(anySession)

        try await client.delete(.explicitSignOut)
    }
}

// swiftlint:disable force_unwrapping

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

    /// ACC-004-account_session_client: testValue가 안전한 기본값(read=nil, persist=no-op, delete=no-op)을 제공한다.
    /// testValue의 read/persist/delete가 throw하지 않고 기본값을 반환하는지 검증한다.
    /// - 검증 내용: read()=nil, persist() throw 없음, delete() throw 없음
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

// swiftlint:enable force_unwrapping

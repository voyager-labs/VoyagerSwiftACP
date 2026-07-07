import Dependencies
@testable import VoyagerShared
import XCTest

final class AccessCredentialClientTests: XCTestCase {
    /// given
    private func makeClient() -> AccessCredentialClient {
        withDependencies {
            $0.accessCredentialClient = .testValue
        } operation: {
            @Dependency(\.accessCredentialClient)
            var client
            return client
        }
    }

    func testSaveAndLoadAccessToken() throws {
        let client = makeClient()
        // when
        try client.saveAccessToken("test-access-token")
        let loaded = try client.loadAccessToken()
        // then
        XCTAssertEqual(loaded, "test-access-token")
    }

    func testSaveAndLoadRefreshToken() throws {
        let client = makeClient()
        // when
        try client.saveRefreshToken("test-refresh-token")
        let loaded = try client.loadRefreshToken()
        // then
        XCTAssertEqual(loaded, "test-refresh-token")
    }

    func testDeleteAccessTokenRemovesValue() throws {
        let client = makeClient()
        // given
        try client.saveAccessToken("to-be-deleted")
        // when
        try client.deleteAccessToken()
        let loaded = try client.loadAccessToken()
        // then
        XCTAssertNil(loaded)
    }

    func testDeleteRefreshTokenRemovesValue() throws {
        let client = makeClient()
        // given
        try client.saveRefreshToken("to-be-deleted")
        // when
        try client.deleteRefreshToken()
        let loaded = try client.loadRefreshToken()
        // then
        XCTAssertNil(loaded)
    }

    func testLoadReturnsNilInitially() throws {
        let client = makeClient()
        // when
        let access = try client.loadAccessToken()
        let refresh = try client.loadRefreshToken()
        // then
        XCTAssertNil(access)
        XCTAssertNil(refresh)
    }
}

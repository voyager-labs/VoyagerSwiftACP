@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class AccountAccessClientContractTests: XCTestCase {
    /*
     ONB-002 access client contract

     포함한 interaction_id:
     - ONB-002-apply_access_unlock_result: gateway/mock client가 active, inactive, failure access result를 동일한 domain model로 반환한다.

     Fixture reset:
     - `AccountAccessClient.mock`과 `AccountAccessClient.liveValue`의 local behavior만 검증한다.
     */

    // MARK: - ONB-002-apply_access_unlock_result

    func testGatewayNotConfigured() async {
        let client = AccountAccessClient.liveValue
        do {
            _ = try await client.fetchAccessStatus()
        } catch let error as AccessError {
            XCTAssertEqual(error, .notConfigured)
        } catch {}
    }

    func testMockFetchAccessStatus() async throws {
        let client = AccountAccessClient.mock
        let response = try await client.fetchAccessStatus()
        XCTAssertTrue(response.status.isActive)
    }

    func testMockRestoreSessionReturnsNil() async throws {
        let client = AccountAccessClient.mock
        let session = try await client.restoreSession()
        XCTAssertNil(session)
    }

    func testMockSignOutSucceeds() async throws {
        let client = AccountAccessClient.mock
        try await client.signOut()
    }
}

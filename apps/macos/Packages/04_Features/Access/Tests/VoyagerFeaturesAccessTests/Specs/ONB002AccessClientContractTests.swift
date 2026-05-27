@testable import VoyagerFeaturesAccess
import XCTest

@MainActor
final class ONB002AccessClientContractTests: XCTestCase {
    /*
     ONB-002 access client contract

     포함한 interaction_id:
     - ONB-002-apply_access_unlock_result: gateway/mock client가 active, inactive, failure access result를 동일한 domain model로 반환한다.

     Fixture reset:
     - `AccessClient.mock`과 `AccessClient.liveValue`의 local behavior만 검증한다.
     */

    // MARK: - ONB-002-apply_access_unlock_result

    func testActiveMockClaims() async throws {
        let client = AccessClient.mock

        let licenseResponse = try await client.claimLicense("VOYAGER-CORE-VALID")
        XCTAssertEqual(licenseResponse.status, .coreLicenseActive)
        XCTAssertTrue(licenseResponse.status.isActive)

        let betaResponse = try await client.redeemBetaCode("VOYAGER-BETA-TRIAL")
        XCTAssertEqual(betaResponse.status, .betaTrialActive)
        XCTAssertTrue(betaResponse.status.isActive)
        XCTAssertNotNil(betaResponse.expiresAt)

        let internalResponse = try await client.claimLicense("VOYAGER-INTERNAL")
        XCTAssertEqual(internalResponse.status, .internalTestActive)
        XCTAssertTrue(internalResponse.status.isActive)
    }

    func testInactiveAndFailureMockClaims() async throws {
        let client = AccessClient.mock

        let expired = try await client.claimLicense("VOYAGER-EXPIRED")
        XCTAssertEqual(expired.status, .trialExpired)
        XCTAssertFalse(expired.status.isActive)

        let revoked = try await client.claimLicense("VOYAGER-REVOKED")
        XCTAssertEqual(revoked.status, .revoked)
        XCTAssertFalse(revoked.status.isActive)

        let refunded = try await client.claimLicense("VOYAGER-REFUNDED")
        XCTAssertEqual(refunded.status, .refunded)
        XCTAssertFalse(refunded.status.isActive)
    }

    func testUnknownInputThrows() async {
        let client = AccessClient.mock
        do {
            _ = try await client.claimLicense("UNKNOWN-KEY")
            XCTFail("Should have thrown")
        } catch {}
    }

    func testEmptyInputThrows() async {
        let client = AccessClient.mock
        do {
            _ = try await client.claimLicense("")
            XCTFail("Should have thrown for empty input")
        } catch {}
    }

    func testGatewayNotConfigured() async {
        let client = AccessClient.liveValue
        do {
            _ = try await client.fetchAccessStatus()
        } catch let error as AccessError {
            XCTAssertEqual(error, .notConfigured)
        } catch {}
    }

    func testMockFetchAccessStatus() async throws {
        let client = AccessClient.mock
        let response = try await client.fetchAccessStatus()
        XCTAssertTrue(response.status.isActive)
    }

    func testMockRestoreSessionReturnsNil() async throws {
        let client = AccessClient.mock
        let session = try await client.restoreSession()
        XCTAssertNil(session)
    }

    func testMockSignOutSucceeds() async throws {
        let client = AccessClient.mock
        try await client.signOut()
    }
}

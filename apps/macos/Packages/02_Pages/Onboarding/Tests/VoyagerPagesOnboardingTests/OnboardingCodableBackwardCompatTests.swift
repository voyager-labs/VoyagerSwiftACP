import Foundation
@testable import VoyagerPagesOnboarding
import XCTest

final class OnboardingCodableBackwardCompatTests: XCTestCase {
    // MARK: - OnboardingStep backward compat

    func testDecodeLegacyBetaAccessRawValue() throws {
        let json = "\"betaAccess\""
        let data = try XCTUnwrap(json.data(using: .utf8))
        let step = try JSONDecoder().decode(OnboardingStep.self, from: data)
        XCTAssertEqual(step, .accessUnlock)
    }

    func testDecodeNewAccessUnlockRawValue() throws {
        let json = "\"accessUnlock\""
        let data = try XCTUnwrap(json.data(using: .utf8))
        let step = try JSONDecoder().decode(OnboardingStep.self, from: data)
        XCTAssertEqual(step, .accessUnlock)
    }

    func testEncodeAccessUnlockUsesNewRawValue() throws {
        let data = try JSONEncoder().encode(OnboardingStep.accessUnlock)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(jsonString, "\"accessUnlock\"")
    }

    // MARK: - OnboardingStepState backward compat

    func testDecodeLegacyBetaAccessComplete() throws {
        let json = """
        {
            "betaAccessComplete": true,
            "welcomeComplete": true,
            "permissionsComplete": false,
            "aiProviderSetupComplete": false,
            "aiProviderSetupSkipped": false,
            "aiProviderSetupChoice": "none",
            "aiProviderSetupStatus": "blocked",
            "completeComplete": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let stepState = try JSONDecoder().decode(OnboardingStepState.self, from: data)
        XCTAssertTrue(stepState.accessUnlockComplete)
    }

    func testDecodeNewAccessUnlockComplete() throws {
        let json = """
        {
            "accessUnlockComplete": true,
            "welcomeComplete": true,
            "permissionsComplete": false,
            "aiProviderSetupComplete": false,
            "aiProviderSetupSkipped": false,
            "aiProviderSetupChoice": "none",
            "aiProviderSetupStatus": "blocked",
            "completeComplete": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let stepState = try JSONDecoder().decode(OnboardingStepState.self, from: data)
        XCTAssertTrue(stepState.accessUnlockComplete)
    }

    func testDecodeMissingAccessUnlockDefaultsToFalse() throws {
        let json = """
        {
            "welcomeComplete": true,
            "permissionsComplete": false,
            "aiProviderSetupComplete": false,
            "aiProviderSetupSkipped": false,
            "aiProviderSetupChoice": "none",
            "aiProviderSetupStatus": "blocked",
            "completeComplete": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let stepState = try JSONDecoder().decode(OnboardingStepState.self, from: data)
        XCTAssertFalse(stepState.accessUnlockComplete)
    }

    func testRoundTripEncodeDecodeAccessUnlockComplete() throws {
        // Given
        let original = OnboardingStepState(
            welcomeComplete: true,
            accessUnlockComplete: true,
            permissionsComplete: true,
            aiProviderSetupComplete: true,
            aiProviderSetupSkipped: true,
            aiProviderSetupChoice: .setUpLater,
            aiProviderSetupStatus: .skipped,
            completeComplete: true,
        )

        // When — encode then decode
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OnboardingStepState.self, from: data)

        // Then
        XCTAssertEqual(original, decoded)
        XCTAssertTrue(decoded.accessUnlockComplete)
    }

    func testEncodeAccessUnlockCompleteUsesNewKey() throws {
        // Given
        let state = OnboardingStepState(accessUnlockComplete: true)

        // When
        let data = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Then — new key is used, old key is NOT present
        XCTAssertNotNil(json["accessUnlockComplete"])
        XCTAssertNil(json["betaAccessComplete"])
    }
}

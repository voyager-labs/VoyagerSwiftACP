import Dependencies
import Foundation
@testable import VoyagerPagesOnboarding
import VoyagerShared
import XCTest

final class ONB001OnboardingCodableBackwardCompatTests: XCTestCase {
    func testLiveLoadClearsLegacyAccessSnapshotAtCurrentVersion() throws {
        let userDefaults = try makePersistedDefaults(version: 1.3, step: "aiProviderSetup")
        userDefaults.setObject(Data([1, 2, 3]), "onboardingAccessSnapshot")
        let result = load(using: userDefaults)

        guard case let .success(snapshot) = result else {
            return XCTFail("Expected live load success, got \(result)")
        }
        XCTAssertEqual(snapshot.currentStep, .aiProviderSetup)
        XCTAssertNil(userDefaults.object("onboardingAccessSnapshot"))
    }

    func testLiveLoadMapsPersistedAccessUnlockRawValueDuringVersion12Migration() throws {
        let userDefaults = try makePersistedDefaults(version: 1.2, step: "accessUnlock")
        guard case let .success(snapshot) = load(using: userDefaults) else { return XCTFail("Expected success") }
        XCTAssertEqual(snapshot.currentStep, .permissions)
        XCTAssertTrue(snapshot.stepState.permissionsComplete)
    }

    func testLiveLoadMapsPersistedBetaAccessRawValueDuringVersion12Migration() throws {
        let userDefaults = try makePersistedDefaults(version: 1.2, step: "betaAccess")
        guard case let .success(snapshot) = load(using: userDefaults) else { return XCTFail("Expected success") }
        XCTAssertEqual(snapshot.currentStep, .permissions)
        XCTAssertTrue(snapshot.stepState.permissionsComplete)
    }

    func testLiveLoadPreservesVersion12AIProviderAndCompleteProgress() throws {
        for step in ["aiProviderSetup", "complete"] {
            let userDefaults = try makePersistedDefaults(version: 1.2, step: step)
            guard case let .success(snapshot) = load(using: userDefaults) else { return XCTFail("Expected success") }
            XCTAssertEqual(snapshot.currentStep.rawValue, step)
        }
    }

    func testLiveLoadUnknownFutureVersionReturnsResetRequired() throws {
        let userDefaults = try makePersistedDefaults(version: 9.0, step: "complete")
        XCTAssertEqual(load(using: userDefaults), .resetRequired)
    }

    func testLiveLoadSaveLoadIsIdempotentAfterVersion12Migration() throws {
        let userDefaults = try makePersistedDefaults(version: 1.2, step: "betaAccess")
        guard case let .success(firstSnapshot) = load(using: userDefaults)
        else { return XCTFail("Expected first success") }
        let saveResult = withDependencies {
            $0.userDefaultsClient = userDefaults
        } operation: {
            OnboardingProgressClient.liveValue.save(firstSnapshot)
        }
        XCTAssertEqual(saveResult, .success)
        XCTAssertEqual(load(using: userDefaults), .success(firstSnapshot))
    }

    private func makePersistedDefaults(version: Double, step: String) throws -> UserDefaultsClient {
        let userDefaults = UserDefaultsClient.testValue
        userDefaults.setObject(version, "onboardingProgressVersion")
        userDefaults.setString(step, "onboardingCurrentStep")
        try userDefaults.setObject(
            JSONEncoder().encode(OnboardingStepState(welcomeComplete: true)),
            "onboardingStepState",
        )
        return userDefaults
    }

    private func load(using userDefaults: UserDefaultsClient) -> OnboardingProgressClient.LoadResult {
        withDependencies {
            $0.userDefaultsClient = userDefaults
        } operation: {
            OnboardingProgressClient.liveValue.load()
        }
    }

    func testMigrateVersion12AccessUnlockToPermissions() {
        let snapshot = OnboardingProgressClient.migratedSnapshot(
            version: 1.2,
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                permissionsComplete: false,
            ),
            rawStepValue: "accessUnlock",
        )

        XCTAssertEqual(snapshot?.currentStep, .permissions)
        XCTAssertEqual(snapshot?.stepState.permissionsComplete, true)
    }

    func testMigrateVersion12LegacyBetaAccessToPermissions() throws {
        let data = Data("\"betaAccess\"".utf8)
        let legacyStep = try JSONDecoder().decode(OnboardingStep.self, from: data)
        let snapshot = OnboardingProgressClient.migratedSnapshot(
            version: 1.2,
            currentStep: legacyStep,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                permissionsComplete: false,
            ),
            rawStepValue: "betaAccess",
        )

        XCTAssertEqual(snapshot?.currentStep, .permissions)
        XCTAssertEqual(snapshot?.stepState.permissionsComplete, true)
    }

    func testMigrateVersion11CompletePreservesCompletion() {
        let snapshot = OnboardingProgressClient.migratedSnapshot(
            version: 1.1,
            currentStep: .complete,
            stepState: OnboardingStepState(completeComplete: true),
        )
        XCTAssertEqual(snapshot?.currentStep, .complete)
        XCTAssertEqual(snapshot?.stepState.aiProviderSetupComplete, true)
        XCTAssertEqual(snapshot?.stepState.completeComplete, true)
    }

    func testUnknownFutureVersionCannotMigrate() {
        XCTAssertNil(
            OnboardingProgressClient.migratedSnapshot(
                version: 9.0,
                currentStep: .complete,
                stepState: OnboardingStepState(completeComplete: true),
            ),
        )
    }

    // MARK: - OnboardingStep backward compat

    func testDecodeLegacyBetaAccessRawValue() throws {
        let json = "\"betaAccess\""
        let data = try XCTUnwrap(json.data(using: .utf8))
        let step = try JSONDecoder().decode(OnboardingStep.self, from: data)
        XCTAssertEqual(step, .permissions)
    }

    func testDecodeNewAccessUnlockRawValue() throws {
        let json = "\"accessUnlock\""
        let data = try XCTUnwrap(json.data(using: .utf8))
        let step = try JSONDecoder().decode(OnboardingStep.self, from: data)
        XCTAssertEqual(step, .permissions)
    }

    func testEncodePermissionsUsesCurrentRawValue() throws {
        let data = try JSONEncoder().encode(OnboardingStep.permissions)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(jsonString, "\"permissions\"")
    }

    // MARK: - OnboardingStepState backward compat

    func testDecodeLegacyBetaAccessCompleteDoesNotOverridePermissionsComplete() throws {
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
        XCTAssertFalse(stepState.permissionsComplete)
    }

    func testDecodeLegacyAccessUnlockCompleteDoesNotOverridePermissionsComplete() throws {
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
        XCTAssertFalse(stepState.permissionsComplete)
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
        XCTAssertFalse(stepState.permissionsComplete)
    }

    func testRoundTripEncodeDecodeAccessUnlockComplete() throws {
        // Given
        let original = OnboardingStepState(
            welcomeComplete: true,
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
        XCTAssertTrue(decoded.permissionsComplete)
    }

    func testEncodePermissionsCompleteUsesCurrentKey() throws {
        // Given
        let state = OnboardingStepState(permissionsComplete: true)

        // When
        let data = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Then — new key is used, old key is NOT present
        XCTAssertNotNil(json["permissionsComplete"])
        XCTAssertNil(json["betaAccessComplete"])
    }
}

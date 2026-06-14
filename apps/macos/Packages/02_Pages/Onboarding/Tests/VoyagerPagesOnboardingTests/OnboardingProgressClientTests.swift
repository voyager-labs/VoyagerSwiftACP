import Dependencies
@testable import VoyagerPagesOnboarding
import VoyagerShared
import XCTest

final class OnboardingProgressClientTests: XCTestCase {
    func testLoadMigratesLegacyCompletedSnapshotWithoutResettingSession() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let legacyStepState = OnboardingStepState(
            welcomeComplete: true,
            betaAccessComplete: true,
            permissionsComplete: true,
            completeComplete: true,
        )
        let legacyData = try JSONEncoder().encode(legacyStepState)

        userDefaultsClient.setObject(1.1, "onboardingProgressVersion")
        userDefaultsClient.setObject(OnboardingStep.complete.rawValue, "onboardingCurrentStep")
        userDefaultsClient.setObject(legacyData, "onboardingStepState")

        let result = withDependencies {
            $0.userDefaultsClient = userDefaultsClient
        } operation: {
            OnboardingProgressClient.liveValue.load()
        }

        guard case let .success(snapshot) = result else {
            return XCTFail("1.1 completed snapshot must migrate instead of requiring reset")
        }

        XCTAssertEqual(snapshot.currentStep, .complete)
        XCTAssertTrue(snapshot.stepState.aiProviderSetupComplete)
        XCTAssertTrue(snapshot.stepState.aiProviderSetupSkipped)
        XCTAssertEqual(snapshot.stepState.aiProviderSetupChoice, .setUpLater)
        XCTAssertEqual(snapshot.stepState.aiProviderSetupStatus, .skipped)
        XCTAssertTrue(snapshot.stepState.completeComplete)
        XCTAssertEqual(
            userDefaultsClient.object("onboardingProgressVersion") as? Double,
            OnboardingProgressClient.currentVersion,
        )

        let migratedData = try XCTUnwrap(userDefaultsClient.object("onboardingStepState") as? Data)
        let migratedStepState = try JSONDecoder().decode(OnboardingStepState.self, from: migratedData)
        XCTAssertTrue(migratedStepState.aiProviderSetupComplete)
        XCTAssertTrue(migratedStepState.aiProviderSetupSkipped)
        XCTAssertEqual(migratedStepState.aiProviderSetupChoice, .setUpLater)
        XCTAssertEqual(migratedStepState.aiProviderSetupStatus, .skipped)
    }
}

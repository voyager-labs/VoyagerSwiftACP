import ComposableArchitecture
@testable import SettingsHost
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerPagesSettings
import XCTest

final class SettingsHostSandboxTests: XCTestCase {
    @MainActor
    private func scenario(
        accountAuth: AccountAuthScenario = .signedOut,
        aiConnection: AIConnectionScenario = .notConfigured,
        permissions: PermissionScenario = .allGranted,
        persistence: PersistenceScenario = .clean,
        failureLatency: FailureLatencyScenario = .none,
    ) -> SettingsHostScenario {
        SettingsHostScenario(
            accountAuth: accountAuth,
            aiConnection: aiConnection,
            permissions: permissions,
            persistence: persistence,
            failureLatency: failureLatency,
        )
    }

    @MainActor
    func testAINotConfiguredProducesEmptyConnections() async throws {
        let deps = SettingsHostSandbox.dependencies(for: scenario(aiConnection: .notConfigured))
        let file = try await deps.aiConnectionsFileClient.load()
        XCTAssertTrue(file.providers.isEmpty, "notConfigured should yield empty providers")
    }

    @MainActor
    func testAIConnectedProducesNonEmptyConnections() async throws {
        let deps = SettingsHostSandbox.dependencies(for: scenario(aiConnection: .connected))
        let file = try await deps.aiConnectionsFileClient.load()
        XCTAssertFalse(file.providers.isEmpty, "connected should yield at least one provider")
    }

    @MainActor
    func testAIConnectionErrorFailsVerification() async {
        let deps = SettingsHostSandbox.dependencies(
            for: scenario(aiConnection: .connectionError, failureLatency: .error),
        )
        let result = await deps.aiProviderVerificationClient.verify(.openai, nil)
        XCTAssertNotEqual(result, .valid, "connectionError verification must not be .valid")
    }

    @MainActor
    func testPermissionsAllGrantedProducesDeterministicPath() async {
        let deps = SettingsHostSandbox.dependencies(for: scenario(permissions: .allGranted))
        let path = await deps.directorySelectionClient.pickDirectory()
        XCTAssertEqual(path, "/tmp/voyager-settingshost-sandbox", "allGranted should yield a deterministic path")
    }

    @MainActor
    func testPermissionsDeniedProducesNilPath() async {
        let deps = SettingsHostSandbox.dependencies(for: scenario(permissions: .denied))
        let path = await deps.directorySelectionClient.pickDirectory()
        XCTAssertNil(path, "denied should yield nil path")
    }

    @MainActor
    func testPersistenceCleanHasDefaultTheme() {
        let deps = SettingsHostSandbox.dependencies(for: scenario(persistence: .clean))
        XCTAssertEqual(deps.appearanceSettingsClient.loadTheme(), .system, "clean should yield default theme")
    }

    @MainActor
    func testPersistencePopulatedHasSeededTheme() {
        let deps = SettingsHostSandbox.dependencies(for: scenario(persistence: .populated))
        XCTAssertEqual(deps.appearanceSettingsClient.loadTheme(), .dark, "populated should yield seeded .dark theme")
    }

    @MainActor
    func testFailureLatencyErrorThrowsOnModelList() async {
        let deps = SettingsHostSandbox.dependencies(for: scenario(failureLatency: .error))
        do {
            _ = try await deps.aiProviderModelListClient.loadModels(.openai, nil)
            XCTFail("failureLatency .error model list should throw")
        } catch {
            // expected
        }
    }

    @MainActor
    func testAIConnectionsDeterministicAcrossRuns() async throws {
        let scenario = scenario(aiConnection: .connected)
        let first = try await SettingsHostSandbox.dependencies(for: scenario).aiConnectionsFileClient.load()
        let second = try await SettingsHostSandbox.dependencies(for: scenario).aiConnectionsFileClient.load()
        XCTAssertEqual(first, second, "connected AI file must be deterministic")
    }

    @MainActor
    func testDefaultSandboxDoesNotTouchProductionDefaults() throws {
        let defaults = SettingsHostSandbox.defaultDependencies
        try defaults.launchAtLoginClient.setEnabled(true)
        try defaults.launchAtLoginClient.setEnabled(false)
        XCTAssertNil(defaults.userDefaultsClient.string(SettingsKeys.theme), "default sandbox must start clean")
    }

    @MainActor
    func testConfigureAppliesScenarioToInoutValues() {
        var values = DependencyValues()
        SettingsHostSandbox.configure(&values, for: scenario(permissions: .denied))
        let path = values.directorySelectionClient.defaultHomePath()
        XCTAssertNotNil(path, "configure should install a functioning directorySelectionClient")
    }
}

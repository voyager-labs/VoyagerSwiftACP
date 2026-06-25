import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesSettings
import XCTest

final class SettingsHostSandboxTests: XCTestCase {
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

    // MARK: - Account / Auth axis

    func testSignedInProducesActiveSession() async throws {
        let deps = SettingsHostSandbox.dependencies(for: scenario(accountAuth: .signedIn))
        let session = try await deps.accountSessionClient.read()
        XCTAssertEqual(session?.status.isActive, true, "signedIn should yield an active session")
        XCTAssertEqual(session?.accessToken.isEmpty, false, "signedIn session should carry a deterministic token")
    }

    func testSignedOutProducesNilSession() async throws {
        let deps = SettingsHostSandbox.dependencies(for: scenario(accountAuth: .signedOut))
        let session = try await deps.accountSessionClient.read()
        XCTAssertNil(session, "signedOut should yield no session")
    }

    func testAuthExpiredProducesSessionWithPastExpiry() async throws {
        let deps = SettingsHostSandbox.dependencies(for: scenario(accountAuth: .authExpired))
        let session = try await deps.accountSessionClient.read()
        let expiry = try XCTUnwrap(session?.expiresAt)
        XCTAssertLessThan(expiry.timeIntervalSince1970, 0, "authExpired session should be rooted at epoch (past)")
    }

    func testAccountErrorThrowsOnRead() async {
        let deps = SettingsHostSandbox.dependencies(
            for: scenario(accountAuth: .error, failureLatency: .error),
        )
        do {
            _ = try await deps.accountSessionClient.read()
            XCTFail("accountAuth .error should throw on read")
        } catch {
            // expected
        }
    }

    // MARK: - AI connection axis

    func testAINotConfiguredProducesEmptyConnections() async throws {
        let deps = SettingsHostSandbox.dependencies(for: scenario(aiConnection: .notConfigured))
        let file = try await deps.aiConnectionsFileClient.load()
        XCTAssertTrue(file.providers.isEmpty, "notConfigured should yield empty providers")
    }

    func testAIConnectedProducesNonEmptyConnections() async throws {
        let deps = SettingsHostSandbox.dependencies(for: scenario(aiConnection: .connected))
        let file = try await deps.aiConnectionsFileClient.load()
        XCTAssertFalse(file.providers.isEmpty, "connected should yield at least one provider")
    }

    func testAIConnectionErrorFailsVerification() async {
        let deps = SettingsHostSandbox.dependencies(
            for: scenario(aiConnection: .connectionError, failureLatency: .error),
        )
        let result = await deps.aiProviderVerificationClient.verify(.openai, nil)
        XCTAssertNotEqual(result, .valid, "connectionError verification must not be .valid")
    }

    // MARK: - Permission axis

    func testPermissionsAllGrantedProducesDeterministicPath() async {
        let deps = SettingsHostSandbox.dependencies(for: scenario(permissions: .allGranted))
        let path = await deps.directorySelectionClient.pickDirectory()
        XCTAssertEqual(path, "/tmp/voyager-settingshost-sandbox", "allGranted should yield a deterministic path")
    }

    func testPermissionsDeniedProducesNilPath() async {
        let deps = SettingsHostSandbox.dependencies(for: scenario(permissions: .denied))
        let path = await deps.directorySelectionClient.pickDirectory()
        XCTAssertNil(path, "denied should yield nil path")
    }

    // MARK: - Persistence axis

    func testPersistenceCleanHasDefaultTheme() {
        let deps = SettingsHostSandbox.dependencies(for: scenario(persistence: .clean))
        XCTAssertEqual(deps.appearanceSettingsClient.loadTheme(), .system, "clean should yield default theme")
    }

    func testPersistencePopulatedHasSeededTheme() {
        let deps = SettingsHostSandbox.dependencies(for: scenario(persistence: .populated))
        XCTAssertEqual(deps.appearanceSettingsClient.loadTheme(), .dark, "populated should yield seeded .dark theme")
    }

    // MARK: - Failure / latency axis

    func testFailureLatencyErrorThrowsOnModelList() async {
        let deps = SettingsHostSandbox.dependencies(for: scenario(failureLatency: .error))
        do {
            _ = try await deps.aiProviderModelListClient.loadModels(.openai, nil)
            XCTFail("failureLatency .error model list should throw")
        } catch {
            // expected
        }
    }

    // MARK: - Determinism

    func testAccountSessionDeterministicAcrossRuns() async throws {
        let scenario = scenario(accountAuth: .signedIn)
        let first = try await SettingsHostSandbox.dependencies(for: scenario).accountSessionClient.read()
        let second = try await SettingsHostSandbox.dependencies(for: scenario).accountSessionClient.read()
        XCTAssertEqual(first?.accessToken, second?.accessToken, "signedIn token must be deterministic")
    }

    func testAIConnectionsDeterministicAcrossRuns() async throws {
        let scenario = scenario(aiConnection: .connected)
        let first = try await SettingsHostSandbox.dependencies(for: scenario).aiConnectionsFileClient.load()
        let second = try await SettingsHostSandbox.dependencies(for: scenario).aiConnectionsFileClient.load()
        XCTAssertEqual(first, second, "connected AI file must be deterministic")
    }

    // MARK: - No real side effects

    func testDefaultSandboxDoesNotTouchProductionDefaults() throws {
        let defaults = SettingsHostSandbox.defaultDependencies
        try defaults.launchAtLoginClient.setEnabled(true)
        try defaults.launchAtLoginClient.setEnabled(false)
        XCTAssertNil(defaults.userDefaultsClient.string(SettingsKeys.theme), "default sandbox must start clean")
    }

    func testConfigureAppliesScenarioToInoutValues() {
        var values = DependencyValues()
        SettingsHostSandbox.configure(&values, for: scenario(permissions: .denied))
        let path = values.directorySelectionClient.defaultHomePath()
        XCTAssertNotNil(path, "configure should install a functioning directorySelectionClient")
    }
}

// FLOW-ID: set.ai_provider_connection
import ComposableArchitecture
import Dependencies
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class AiProviderConnectionFlowTests: XCTestCase {
    // FLOW-PATH: happy_path

    /// set.ai_provider_connection: happy_path
    func testBootstrapConnectAndPersistProviderThroughSettingsComposition() async {
        let staleFile = AIConnectionsFile.testFixture(providers: [
            ProviderRecordFile(
                providerId: .openai,
                authMethod: .apiKey,
                credential: .apiKey(APIKeyCredentialFile.testFixture()),
                snapshot: ProviderSnapshotFile(
                    lastKnownStatus: .connectionFailed,
                    lastErrorCode: .expired,
                ),
            ),
        ])
        let expectedFile = AIConnectionsFile.testFixture(providers: [
            ProviderRecordFile(
                providerId: .openai,
                authMethod: .apiKey,
                credential: .apiKey(APIKeyCredentialFile.testFixture()),
                snapshot: ProviderSnapshotFile(
                    lastKnownStatus: .connected,
                    lastVerifiedAtMs: staleFile.updatedAtMs,
                    lastErrorCode: .none,
                ),
            ),
        ])
        let savedFiles = LockIsolated<[AIConnectionsFile]>([])
        let store = makeStore(
            file: staleFile,
            savedFiles: savedFiles,
            verification: { _, _ in .valid },
        )

        await store.send(.ai(.onAppear))
        await store.receive(\.ai.bootstrapCompleted)
        await store.receive(\.ai.delegate.connectionsFileUpdated)
        await store.receive(\.delegate.aiConnectionsFileUpdated)
        await store.receive(\.ai.bootstrapVerificationCompleted)
        await store.finish()

        XCTAssertEqual(savedFiles.withValue { $0 }, [expectedFile])
    }

    // FLOW-PATH: connection_failure

    /// set.ai_provider_connection: connection_failure
    func testConnectionFailureAllowsRetryWithoutCorruptingOtherRows() async {
        let file = AIConnectionsFile.testFixture(providers: [
            ProviderRecordFile(
                providerId: .openai,
                authMethod: .apiKey,
                credential: .apiKey(APIKeyCredentialFile.testFixture(secret: "sk-expired")),
                snapshot: ProviderSnapshotFile(
                    lastKnownStatus: .connectionFailed,
                    lastErrorCode: .invalidAPIKey,
                ),
            ),
            .testFixture(provider: .anthropic, authMethod: .apiKey),
        ])
        let savedFiles = LockIsolated<[AIConnectionsFile]>([])
        let verificationCalls = LockIsolated<[AiProvider]>([])
        let store = makeStore(
            file: file,
            savedFiles: savedFiles,
            verification: { provider, _ in
                verificationCalls.withValue { $0.append(provider) }
                return provider == .openai ? .invalid(.invalidAPIKey) : .valid
            },
        )

        await store.send(.ai(.onAppear))
        await store.receive(\.ai)
        await store.receive(\.ai)
        await store.finish()

        await store.send(.ai(.retryBootstrapTapped))
        await store.receive(\.ai)
        await store.receive(\.ai)
        await store.finish()

        XCTAssertEqual(savedFiles.withValue { $0 }, [file, file])
        XCTAssertEqual(verificationCalls.withValue { $0 }, [.openai, .anthropic, .openai, .anthropic])
    }

    // FLOW-PATH: unavailable

    /// set.ai_provider_connection: unavailable
    func testUnavailableProviderRemainsDisabledThroughSettingsComposition() async {
        let staleFile = AIConnectionsFile.testFixture(providers: [
            .testFixture(provider: .chatgptCodex, authMethod: .oauth),
        ])
        let expectedFile = AIConnectionsFile.testFixture(providers: [
            ProviderRecordFile(
                providerId: .chatgptCodex,
                authMethod: .oauth,
                credential: .oauth(OAuthCredentialFile.testFixture()),
                snapshot: ProviderSnapshotFile(
                    lastKnownStatus: .unavailable,
                    lastErrorCode: .providerUnsupportedInBuild,
                ),
            ),
        ])
        let savedFiles = LockIsolated<[AIConnectionsFile]>([])
        let store = makeStore(
            file: staleFile,
            savedFiles: savedFiles,
            verification: { _, _ in .unsupportedProvider },
        )

        await store.send(.ai(.onAppear))
        await store.receive(\.ai.bootstrapCompleted)
        await store.receive(\.ai.delegate.connectionsFileUpdated)
        await store.receive(\.delegate.aiConnectionsFileUpdated)
        await store.receive(\.ai.bootstrapVerificationCompleted)
        await store.finish()

        XCTAssertEqual(savedFiles.withValue { $0 }, [expectedFile])
    }

    private func makeStore(
        file: AIConnectionsFile,
        savedFiles: LockIsolated<[AIConnectionsFile]>,
        verification: @escaping @Sendable (AiProvider, StoredCredentialPayload?) async -> AiProviderVerificationResult,
    ) -> TestStore<SettingsFeature.State, SettingsFeature.Action> {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiConnectionsFileClient.atomicUpdate = { transform in
                let updatedFile = try transform(file)
                savedFiles.withValue { $0.append(updatedFile) }
                return .success(updatedFile)
            }
            $0.aiProviderVerificationClient.verify = verification
        }
        // store.exhaustivity = .off: Settings 부모와 AI 자식의 합성 결과만 검증한다.
        store.exhaustivity = .off
        return store
    }
}

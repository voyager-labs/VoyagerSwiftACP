import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

// MARK: - Restore / Bootstrap Regression Tests (SET-007)

@MainActor
final class AiConnectionRestoreTests: XCTestCase {
    // MARK: 1. Valid stored credential → checkingStatus → connected

    // MARK: 2. Missing credential → notVerified (.missingCredential reason)

    // MARK: 3. No provider record → notVerified (.none reason)

    func testRestore_noProviderRecord_mapsToNotVerified() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
        }

        await store.finish()

        for row in store.state.rows {
            XCTAssertEqual(row.connectionState, .notVerified)
            XCTAssertEqual(row.statusReason, .none)
            XCTAssertEqual(row.primaryAction, .connect)
        }
    }

    // MARK: 4. connectionFailed snapshot → checkingStatus → .connectionFailed with reason + retry action

    // MARK: 5. Corrupted/network failure (load throws) → all notVerified

    func testRestore_corruptedOrNetworkFailure_mapsToNotVerified() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                throw NSError(domain: "test", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Simulated network failure",
                ])
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .failed)
    }

    // MARK: 6. unavailable snapshot → checkingStatus → .unavailable with disabled action

    func testRestore_unavailableSnapshot_entersCheckingStatusThenUnavailable() async {
        let file = AIConnectionsFile.singleProvider(
            .anthropic,
            state: .unavailable,
            errorCode: .providerUnsupportedInBuild,
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiProviderVerificationClient.verify = { provider, credential in
                XCTAssertEqual(provider, .anthropic)
                XCTAssertNotNil(credential)
                return .unsupportedProvider
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .anthropic]?.connectionState = .checkingStatus
            state.rows[id: .anthropic]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .anthropic]?.connectionState = .unavailable
            state.rows[id: .anthropic]?.statusReason = .providerUnsupportedInBuild
        }

        await store.finish()

        let anthropicRow = store.state.rows[id: .anthropic]
        XCTAssertEqual(anthropicRow?.connectionState, .unavailable)
        XCTAssertEqual(anthropicRow?.statusReason, .providerUnsupportedInBuild)
        XCTAssertEqual(anthropicRow?.primaryAction, .disabled)
    }

    // MARK: 7. connectInProgress snapshot → resets to notVerified (stale in-progress)

    func testRestore_connectInProgress_resetsToNotVerified() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "chatgptCodex": ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectInProgress),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        // connectInProgress with nil credential → credential guard fires first → .notVerified + .missingCredential
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.statusReason = .missingCredential
        }

        await store.finish()

        let codexRow = store.state.rows[id: .chatgptCodex]
        XCTAssertEqual(codexRow?.connectionState, .notVerified)
        XCTAssertEqual(codexRow?.primaryAction, .connect)
    }

    func testRestore_connectInProgressWithCredential_resetsToNotVerifiedWithoutMissingCredentialReason() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "chatgptCodex": ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectInProgress),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.statusReason = .none
        }

        await store.finish()

        let codexRow = store.state.rows[id: .chatgptCodex]
        XCTAssertEqual(codexRow?.connectionState, .notVerified)
        XCTAssertEqual(codexRow?.statusReason, ProviderStatusReason.none)
        XCTAssertEqual(codexRow?.primaryAction, .connect)
    }

    // MARK: 8. disconnecting snapshot → maps to disconnected (mid-disconnect from previous session)

    func testRestore_disconnectingSnapshot_mapsToDisconnected() async {
        let file = AIConnectionsFile.singleProvider(
            .anthropic,
            state: .disconnecting,
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .anthropic]?.connectionState = .disconnected
            state.rows[id: .anthropic]?.statusReason = .none
        }

        await store.finish()

        let anthropicRow = store.state.rows[id: .anthropic]
        XCTAssertEqual(anthropicRow?.connectionState, .disconnected)
        XCTAssertEqual(anthropicRow?.statusReason, ProviderStatusReason.none)
        XCTAssertEqual(anthropicRow?.primaryAction, .connect)
    }

    // MARK: 9. disconnected snapshot → .disconnected with connect action

    func testRestore_disconnectedSnapshot_mapsToDisconnected() async {
        let file = AIConnectionsFile.singleProvider(
            .openai,
            state: .disconnected,
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .disconnected
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.finish()

        let openaiRow = store.state.rows[id: .openai]
        XCTAssertEqual(openaiRow?.connectionState, .disconnected)
        XCTAssertEqual(openaiRow?.statusReason, ProviderStatusReason.none)
        XCTAssertEqual(openaiRow?.primaryAction, .connect)
    }

    // MARK: 10. Multiple providers with mixed states

    // swiftlint:disable:next function_body_length
    func testRestore_multipleProviders_mixedStates() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "chatgptCodex": ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-expired")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connectionFailed,
                        lastErrorCode: .expired,
                    ),
                ),
                // anthropic has no record → notVerified
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiProviderVerificationClient.verify = { provider, _ in
                switch provider {
                case .chatgptCodex: .valid
                case .openai: .invalid(.expired)
                case .anthropic: .valid
                }
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
            // anthropic has no record, so no mutation — stays at initial notVerified
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .expired
        }

        await store.finish()

        let codexRow = store.state.rows[id: .chatgptCodex]
        let openaiRow = store.state.rows[id: .openai]
        let anthropicRow = store.state.rows[id: .anthropic]

        XCTAssertEqual(codexRow?.connectionState, .connected)
        XCTAssertEqual(codexRow?.primaryAction, .disconnect)

        XCTAssertEqual(openaiRow?.connectionState, .connectionFailed)
        XCTAssertEqual(openaiRow?.statusReason, .expired)
        XCTAssertEqual(openaiRow?.primaryAction, .retry)

        XCTAssertEqual(anthropicRow?.connectionState, .notVerified)
        XCTAssertEqual(anthropicRow?.statusReason, ProviderStatusReason.none)
        XCTAssertEqual(anthropicRow?.primaryAction, .connect)
    }
}

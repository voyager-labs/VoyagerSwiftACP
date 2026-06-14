import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection
@testable import VoyagerPagesSettings
import XCTest

private final class APIKeyConnectionController: @unchecked Sendable {
    private var continuation: CheckedContinuation<AiProviderConnectionResult, Never>?

    func connect(
        provider _: AiProvider,
        connectionState _: ProviderConnectionState,
    ) async -> AiProviderConnectionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: AiProviderConnectionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private final class ConnectionsFileSaveSpy: @unchecked Sendable {
    private(set) var savedFiles: [AIConnectionsFile] = []

    func save(_ file: AIConnectionsFile) async throws -> AiConnectionMutationResult {
        savedFiles.append(file)
        return .success(file)
    }
}

private final class ConnectionsFileLoadSpy: @unchecked Sendable {
    private var files: [AIConnectionsFile]

    init(files: [AIConnectionsFile]) {
        self.files = files
    }

    func load() async throws -> AIConnectionsFile {
        guard files.count > 1 else { return files[0] }
        return files.removeFirst()
    }
}

@MainActor
final class AiSettingsFeatureTests: XCTestCase {
    func testConnectionResponseEmitsConnectionsFileUpdatedDelegate() async {
        let updatedFile = AIConnectionsFile.singleProvider(.chatgptCodex, state: .connected)
        let store = TestStore(
            initialState: AiSettingsState(rows: [
                AiConnectionRowState(
                    provider: .chatgptCodex,
                    connectionState: .connectInProgress,
                    flowState: .browserLoginInProgress,
                ),
            ]),
        ) {
            AiSettingsFeature()
        }

        await store.send(.row(.element(
            id: .chatgptCodex,
            action: .connectionResponse(AiProviderConnectionResult(
                provider: .chatgptCodex,
                state: .connected,
                reason: .none,
                updatedFile: updatedFile,
            )),
        ))) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .chatgptCodex]?.flowState = .idle
        }

        await store.receive(.delegate(.connectionsFileUpdated(updatedFile)))
    }

    func testBootstrapVerificationSuccessPersistsAndEmitsConnectionsFileUpdatedDelegate() async {
        let staleFile = AIConnectionsFile.singleProvider(
            .openai,
            state: .connectionFailed,
            errorCode: .expired,
        )
        let expectedFile = AIConnectionsFile(
            updatedAtMs: staleFile.updatedAtMs,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: staleFile.providers[AiProvider.openai.rawValue]?.credential,
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connected,
                        lastVerifiedAtMs: staleFile.updatedAtMs,
                        lastErrorCode: .none,
                    ),
                ),
            ],
        )
        let saveSpy = ConnectionsFileSaveSpy()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { staleFile }
            $0.aiConnectionsFileClient.save = { try await saveSpy.save($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.receive(.delegate(.connectionsFileUpdated(expectedFile)))
        await store.finish()

        XCTAssertEqual(saveSpy.savedFiles, [expectedFile])
    }

    func testDisconnectResponseEmitsConnectionsFileUpdatedDelegate() async {
        let updatedFile = AIConnectionsFile.singleProvider(.openai, state: .notVerified, credential: nil)
        let store = TestStore(
            initialState: AiSettingsState(rows: [
                AiConnectionRowState(
                    provider: .openai,
                    connectionState: .disconnecting,
                ),
            ]),
        ) {
            AiSettingsFeature()
        }

        await store.send(.row(.element(
            id: .openai,
            action: .disconnectResponse(AiProviderConnectionResult(
                provider: .openai,
                state: .notVerified,
                reason: .none,
                updatedFile: updatedFile,
            )),
        ))) { state in
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .openai]?.flowState = .idle
        }

        await store.receive(.delegate(.connectionsFileUpdated(updatedFile)))
    }

    func testBootstrapVerificationUnsupportedProviderPersistsAndEmitsConnectionsFileUpdatedDelegate() async {
        let staleFile = AIConnectionsFile.singleProvider(
            .chatgptCodex,
            state: .connected,
            errorCode: .none,
        )
        let expectedFile = AIConnectionsFile(
            updatedAtMs: staleFile.updatedAtMs,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: staleFile.providers[AiProvider.chatgptCodex.rawValue]?.credential,
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .unavailable,
                        lastVerifiedAtMs: nil,
                        lastErrorCode: .providerUnsupportedInBuild,
                    ),
                ),
            ],
        )
        let saveSpy = ConnectionsFileSaveSpy()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { staleFile }
            $0.aiConnectionsFileClient.save = { try await saveSpy.save($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .unsupportedProvider }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .unavailable
            state.rows[id: .chatgptCodex]?.statusReason = .providerUnsupportedInBuild
        }

        await store.receive(.delegate(.connectionsFileUpdated(expectedFile)))
        await store.finish()

        XCTAssertEqual(saveSpy.savedFiles, [expectedFile])
    }

    func testBootstrapVerificationSkipsPersistWhenLatestCredentialChanged() async {
        let staleFile = AIConnectionsFile.singleProvider(
            .openai,
            state: .connectionFailed,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-old")),
            errorCode: .expired,
        )
        let latestFile = AIConnectionsFile.singleProvider(
            .openai,
            state: .connected,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-new")),
        )
        let loadSpy = ConnectionsFileLoadSpy(files: [staleFile, latestFile])
        let saveSpy = ConnectionsFileSaveSpy()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { try await loadSpy.load() }
            $0.aiConnectionsFileClient.save = { try await saveSpy.save($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.finish()

        XCTAssertTrue(saveSpy.savedFiles.isEmpty)
    }

    // MARK: - Fresh Install (No Auth File)

    func testOnAppear_freshInstall_showsAllNotVerified() async {
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

        let storeState = store.state
        XCTAssertEqual(storeState.rows.count, 3)
        for row in storeState.rows {
            XCTAssertEqual(row.connectionState, .notVerified)
            XCTAssertEqual(row.primaryAction, .connect)
        }
    }

    // MARK: - Valid Stored Auth → Connected

    // MARK: - Connection Failed (Corrupt/Expired)

    func testOnAppear_invalidAPIKeySnapshot_restoresFailed() async {
        let failedFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "anthropic": ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "bad-key")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connectionFailed,
                        lastErrorCode: .invalidAPIKey,
                    ),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { failedFile }
            $0.aiProviderVerificationClient.verify = { _, _ in .invalid(.invalidAPIKey) }
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
            state.rows[id: .anthropic]?.connectionState = .connectionFailed
            state.rows[id: .anthropic]?.statusReason = .invalidAPIKey
        }

        await store.finish()

        let anthropicRow = store.state.rows[id: .anthropic]
        XCTAssertEqual(anthropicRow?.connectionState, .connectionFailed)
        XCTAssertEqual(anthropicRow?.statusReason, .invalidAPIKey)
        XCTAssertEqual(anthropicRow?.primaryAction, .retry)
    }

    // MARK: - Load Error → Failed Bootstrap

    func testOnAppear_loadError_setsFailedBootstrapPhase() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { throw NSError(domain: "test", code: -1) }
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
        XCTAssertEqual(store.state.rows.count, 3)
    }

    // MARK: - Idempotent Bootstrap

    func testOnAppear_calledTwice_onlyBootstrapsOnce() async {
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

        await store.send(.onAppear)
        await store.finish()
    }

    // MARK: - Missing Credential → Not Verified

    // MARK: - Provider List Rendering State

    // MARK: - Disconnected State

    func testOnAppear_disconnectedSnapshot_restoresDisconnected() async {
        let disconnectedFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .disconnected),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { disconnectedFile }
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
        XCTAssertEqual(openaiRow?.primaryAction, .connect)
    }

    // MARK: - ConnectInProgress Resets to NotVerified

    func testOnAppear_connectInProgress_resetsToNotVerified() async {
        let inProgressFile = AIConnectionsFile(
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
            $0.aiConnectionsFileClient.load = { inProgressFile }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.statusReason = .missingCredential
        }

        await store.finish()
    }

    // MARK: - Disconnecting Resets to Disconnected

    func testOnAppear_disconnecting_resetsToDisconnected() async {
        let disconnectingFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "anthropic": ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .disconnecting),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { disconnectingFile }
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
    }

    func testSubmitAPIKey_cancelAfterVerificationPreventsConnectionCompletion() async {
        let controller = APIKeyConnectionController()
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
            $0.aiProviderConnectionClient.connectAPIKey = { provider, _, connectionState in
                await controller.connect(provider: provider, connectionState: connectionState)
            }
        }

        await store.send(.submitAPIKey("sk-test-valid-key")) { state in
            state.enteredKey = "sk-test-valid-key"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
        }

        await store.send(.cancelButtonTapped) { state in
            state.flowState = .idle
            state.isVerifying = false
            state.connectionState = .notVerified
        }

        controller.resume(with: AiProviderConnectionResult(
            provider: .openai,
            state: .connected,
            reason: .none,
            updatedFile: AIConnectionsFile.empty(),
        ))

        await Task.yield()
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .notVerified)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    func testSubmitAPIKey_networkError_showsConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .networkError }
        }

        await store.send(.submitAPIKey("sk-test")) { state in
            state.enteredKey = "sk-test"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.connectionState = .connectionFailed
            state.statusReason = .networkUnavailable
            state.flowState = .idle
        }

        await store.finish()
    }

    func testSubmitAPIKey_emptyKey_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.submitAPIKey(""))
        await store.finish()
    }

    func testSubmitAPIKey_whitespaceOnlyKey_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.submitAPIKey("   "))
        await store.finish()
    }

    func testCancelDuringConnect_resetsToIdle() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .connectInProgress,
                flowState: .connecting,
                isVerifying: true,
            ),
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.cancelButtonTapped) { state in
            state.flowState = .idle
            state.isVerifying = false
            state.connectionState = .notVerified
        }

        await store.finish()
    }

    func testSubmitAPIKey_trimWhitespace() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
            $0.aiProviderConnectionClient.connectAPIKey = { provider, _, connectionState in
                AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty(),
                )
            }
        }

        await store.send(.submitAPIKey("  sk-trimmed  ")) { state in
            state.enteredKey = "sk-trimmed"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
        }

        await store.receive(\.connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
            state.enteredKey = ""
        }

        await store.finish()
    }
}

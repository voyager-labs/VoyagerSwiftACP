import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiProviderConnection
@testable import VoyagerPagesSettings
import XCTest

private actor SavedConnectionsFile {
    private var files: [AIConnectionsFile] = []

    func record(_ file: AIConnectionsFile) {
        files.append(file)
    }

    func value() -> AIConnectionsFile? {
        files.last
    }

    func values() -> [AIConnectionsFile] {
        files
    }
}

private actor BootstrapVerificationController {
    private var callCount = 0
    private var firstCallStarted = false
    private var firstCallCancelled = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var cancellationContinuation: CheckedContinuation<Void, Never>?

    func verify(
        credential: StoredCredentialPayload?,
    ) async throws -> AiProviderVerificationOutcome {
        callCount += 1
        guard callCount == 1 else {
            return AiProviderVerificationOutcome(
                result: .valid,
                sourceCredential: credential,
                effectiveCredential: credential,
            )
        }

        firstCallStarted = true
        startContinuation?.resume()
        startContinuation = nil
        await withTaskCancellationHandler {
            await waitForCancellation()
        } onCancel: {
            Task { await self.cancelFirstCall() }
        }
        throw URLError(.cancelled)
    }

    func waitUntilFirstCallStarts() async {
        if firstCallStarted { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    private func waitForCancellation() async {
        if firstCallCancelled { return }
        await withCheckedContinuation { cancellationContinuation = $0 }
    }

    private func cancelFirstCall() {
        firstCallCancelled = true
        cancellationContinuation?.resume()
        cancellationContinuation = nil
    }
}

private actor BootstrapConnectionsStore {
    private var file: AIConnectionsFile

    init(file: AIConnectionsFile) {
        self.file = file
    }

    func load() -> AIConnectionsFile {
        file
    }

    func set(_ file: AIConnectionsFile) {
        self.file = file
    }

    func update(
        _ transform: AIConnectionsFileClient.AtomicUpdateTransform,
    ) throws -> AIConnectionsFile {
        file = try transform(file)
        return file
    }
}

private actor LoadedCredentialRecorder {
    private var credentials: [StoredCredentialPayload] = []

    func record(_ credential: StoredCredentialPayload) {
        credentials.append(credential)
    }

    func values() -> [StoredCredentialPayload] {
        credentials
    }
}

@MainActor
final class SET007SettingsAIConnectionsTests: XCTestCase {
    // MARK: - SET-007-codex_oauth_runtime

    /// SET-007-codex_oauth_runtime: bootstrap result carries effective OAuth metadata.
    /// Bootstrap must retain the credential actually verified so rotated refresh credentials can be persisted.
    /// - 검증 내용: result exposes source/effective credential metadata.
    /// - 사전 조건: a connected Codex bootstrap result is created.
    /// - 기대 결과: result contains the effective credential field required for CAS persistence.
    func testBootstrapResult_exposesEffectiveCredentialForPersistence() {
        let result = AIProviderBootstrapResult(
            provider: .chatgptCodex,
            connectionState: .connected,
        )

        let labels = Set(Mirror(reflecting: result).children.compactMap(\.label))

        XCTAssertTrue(labels.contains("sourceCredential"))
        XCTAssertTrue(labels.contains("effectiveCredential"))
    }

    /// SET-007-codex_oauth_runtime: live bootstrap resolves the overridden Codex refresh dependency.
    /// The verification dependency must not retain its default refresh transport when TCA overrides native auth.
    /// - 검증 내용: live verification client, injected refresh invocation, network-free expired result.
    /// - 사전 조건: bootstrap loads an expired Codex credential and refresh returns invalidGrant.
    /// - 기대 결과: injected refresh runs once and the row becomes connectionFailed/expired.
    func testLiveBootstrapExpiredCodexUsesOverriddenRefreshDependency() async throws {
        let credential = OAuthCredentialFile(
            accessToken: "expired-access",
            refreshToken: "refresh-token",
            expiresAtMs: 0,
        )
        let file = AIConnectionsFile.singleProvider(
            .chatgptCodex,
            state: .connectionFailed,
            credential: .oauth(credential),
        )
        let refreshCount = LoadCounter()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiConnectionsFileClient.atomicUpdate = { transform in
                try .success(transform(file))
            }
            $0.codexNativeAuthClient.refreshCredential = { _ in
                _ = await refreshCount.increment()
                throw CodexCredentialRefreshError.invalidGrant
            }
            $0.aiProviderVerificationClient = .liveValue
        }

        await store.send(.onAppear) {
            $0.didBootstrap = true
            $0.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) {
            $0.bootstrapPhase = .loaded
            $0.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
        }
        let persistedFile = try expiredCodexFile(file, credential: credential)
        await store.receive(.delegate(.connectionsFileUpdated(persistedFile)))
        await store.receive(\.bootstrapVerificationCompleted) {
            $0.rows[id: .chatgptCodex]?.connectionState = .connectionFailed
            $0.rows[id: .chatgptCodex]?.statusReason = .expired
            $0.rows[id: .chatgptCodex]?.tokenExpiresAtMs = 0
        }
        await store.finish()

        let refreshes = await refreshCount.currentValue()
        XCTAssertEqual(refreshes, 1)
    }

    private func expiredCodexFile(
        _ file: AIConnectionsFile,
        credential: OAuthCredentialFile,
    ) throws -> AIConnectionsFile {
        try XCTUnwrap(AIProviderConnectionBootstrap.updatedConnectionsFile(
            verificationSourceFile: file,
            latestFile: file,
            applying: [
                AIProviderBootstrapResult(
                    provider: .chatgptCodex,
                    connectionState: .connectionFailed,
                    statusReason: .expired,
                    sourceCredential: .oauth(credential),
                    effectiveCredential: .oauth(credential),
                ),
            ],
        ))
    }

    /// SET-007-codex_oauth_runtime: bootstrap persistence preserves a competing credential write.
    /// Verification persistence must compare and replace credentials inside one atomic mutation.
    /// - 검증 내용: a competitor write after source capture is not overwritten by stale verification output.
    /// - 사전 조건: the file client returns the source file, then a save boundary observes a competing credential.
    /// - 기대 결과: the persisted result retains the competing credential and skips stale snapshot replacement.
    func testBootstrapPersistence_competingCredentialWriteSurvivesVerification() async {
        let sourceCredential = OAuthCredentialFile(
            accessToken: "source-access",
            refreshToken: "source-refresh",
            expiresAtMs: 1,
        )
        let competingCredential = OAuthCredentialFile(
            accessToken: "competing-access",
            refreshToken: "competing-refresh",
            expiresAtMs: 2,
        )
        let sourceFile = AIConnectionsFile(
            updatedAtMs: 1,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(sourceCredential),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectionFailed),
                ),
            ],
        )
        let competingFile = AIConnectionsFile(
            updatedAtMs: 2,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(competingCredential),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        let savedConnectionsFile = SavedConnectionsFile()
        let client = AIConnectionsFileClient(
            load: { sourceFile },
            save: { file in
                await savedConnectionsFile.record(file)
                return .success(file)
            },
            deleteCredential: { _ in .success(competingFile) },
            atomicUpdate: { (transform: AIConnectionsFileClient.AtomicUpdateTransform) in
                let updated = try transform(competingFile)
                await savedConnectionsFile.record(updated)
                return .success(updated)
            },
        )
        let result = AIProviderBootstrapResult(
            provider: .chatgptCodex,
            connectionState: .connected,
            sourceCredential: .oauth(sourceCredential),
            effectiveCredential: .oauth(OAuthCredentialFile(
                accessToken: "effective-access",
                refreshToken: "effective-refresh",
                expiresAtMs: 3,
            )),
        )

        _ = await AIProviderConnectionBootstrap.persistVerificationResults(
            [result],
            file: sourceFile,
            connectionsFileClient: client,
        )

        let savedFile = await savedConnectionsFile.value()
        XCTAssertEqual(
            savedFile?.providers[AiProvider.chatgptCodex.rawValue]?.credential,
            .oauth(competingCredential),
        )
        XCTAssertEqual(
            savedFile?.providers[AiProvider.chatgptCodex.rawValue]?.snapshot.lastKnownStatus,
            .connected,
        )
        XCTAssertEqual(savedFile?.updatedAtMs, competingFile.updatedAtMs)
    }

    /// SET-007-codex_oauth_runtime: unchanged connected snapshot still persists a refreshed credential.
    /// Credential rotation and snapshot transitions are independent bootstrap mutations.
    /// - 검증 내용: connected snapshot이 이미 동일한 경우에도 effective OAuth credential 저장 여부를 확인한다.
    /// - 사전 조건: source/latest snapshot은 connected이고 verification 결과만 갱신된 credential을 포함한다.
    /// - 기대 결과: snapshot은 보존되고 credential은 refreshed value로 교체된다.
    func testBootstrapPersistence_credentialOnlyRotationPersistsEffectiveCredential() async {
        let sourceCredential = OAuthCredentialFile(
            accessToken: "expired-access",
            refreshToken: "source-refresh",
            expiresAtMs: 1,
        )
        let effectiveCredential = OAuthCredentialFile(
            accessToken: "refreshed-access",
            refreshToken: "rotated-refresh",
            expiresAtMs: 3,
        )
        let snapshot = ProviderSnapshotFile(
            lastKnownStatus: .connected,
            lastVerifiedAtMs: 2,
            lastErrorCode: .none,
        )
        let sourceFile = AIConnectionsFile(
            updatedAtMs: 2,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(sourceCredential),
                    snapshot: snapshot,
                ),
            ],
        )
        let savedConnectionsFile = SavedConnectionsFile()
        let client = AIConnectionsFileClient(
            load: { sourceFile },
            save: { file in
                await savedConnectionsFile.record(file)
                return .success(file)
            },
            deleteCredential: { _ in .success(sourceFile) },
            atomicUpdate: { (transform: AIConnectionsFileClient.AtomicUpdateTransform) in
                let updated = try transform(sourceFile)
                await savedConnectionsFile.record(updated)
                return .success(updated)
            },
        )
        let result = AIProviderBootstrapResult(
            provider: .chatgptCodex,
            connectionState: .connected,
            sourceCredential: .oauth(sourceCredential),
            effectiveCredential: .oauth(effectiveCredential),
        )

        _ = await AIProviderConnectionBootstrap.persistVerificationResults(
            [result],
            file: sourceFile,
            connectionsFileClient: client,
        )

        let savedRecord = await savedConnectionsFile.value()?.providers[AiProvider.chatgptCodex.rawValue]
        XCTAssertEqual(savedRecord?.credential, .oauth(effectiveCredential))
        XCTAssertEqual(savedRecord?.snapshot, snapshot)
    }

    /// SET-007-codex_oauth_runtime: refreshed credential persists before model reload begins.
    /// Connected bootstrap state must not trigger model loading from the expired source credential.
    /// - 검증 내용: atomic credential persistence, delegate ordering, Chat model loader credential.
    /// - 사전 조건: expired Codex credential verifies with a refreshed effective credential.
    /// - 기대 결과: model reload receives only the refreshed persisted credential.
    func testBootstrapRefreshPersistsCredentialBeforeChatModelReload() async {
        let sourceCredential = OAuthCredentialFile(
            accessToken: "expired-access",
            refreshToken: "source-refresh",
            expiresAtMs: 0,
        )
        let effectiveCredential = OAuthCredentialFile(
            accessToken: "refreshed-access",
            refreshToken: "rotated-refresh",
            expiresAtMs: Int64.max,
        )
        let sourceFile = AIConnectionsFile(
            updatedAtMs: 1,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(sourceCredential),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectionFailed),
                ),
            ],
        )
        let connectionsStore = BootstrapConnectionsStore(file: sourceFile)
        let credentialRecorder = LoadedCredentialRecorder()
        let model = AiProviderModel(
            id: AiModelHandle(provider: .chatgptCodex, rawValue: "gpt-5"),
            provider: .chatgptCodex,
            rawModelID: "gpt-5",
            displayName: "GPT-5",
            providerDisplayName: "ChatGPT Codex",
            thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "test")),
        )
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { await connectionsStore.load() },
                save: { .success($0) },
                deleteCredential: { _ in .success(sourceFile) },
                atomicUpdate: { transform in
                    try await .success(connectionsStore.update(transform))
                },
            )
            $0.aiProviderVerificationClient.verifyWithCredential = { _, credential in
                AiProviderVerificationOutcome(
                    result: .valid,
                    sourceCredential: credential,
                    effectiveCredential: .oauth(effectiveCredential),
                )
            }
            $0.aiChatDefaultSettingsClient.load = {
                AiChatDefaultSettings(
                    provider: PersistedAIProviderSelection(rawValue: AiProvider.chatgptCodex.rawValue),
                    model: nil,
                    thinking: .providerDefault,
                )
            }
            $0.aiProviderModelListClient.loadModels = { _, credential in
                try await credentialRecorder.record(XCTUnwrap(credential))
                return [model]
            }
            $0.uuid = .incrementing
        }

        await store.send(.onAppear) {
            $0.didBootstrap = true
            $0.bootstrapPhase = .loading
            $0.chatDefaultSettings = AiChatDefaultSettings(
                provider: PersistedAIProviderSelection(rawValue: AiProvider.chatgptCodex.rawValue),
                model: nil,
                thinking: .providerDefault,
            )
        }
        await store.receive(\.bootstrapCompleted) {
            $0.bootstrapPhase = .loaded
            $0.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
        }
        let savedFile = await connectionsStore.load()
        await store.receive(.delegate(.connectionsFileUpdated(savedFile)))
        await store.receive(\.bootstrapVerificationCompleted) {
            $0.rows[id: .chatgptCodex]?.connectionState = .connected
            $0.rows[id: .chatgptCodex]?.tokenExpiresAtMs = Int64.max
            $0.chatModelCatalogPhase = .loading
            $0.chatModelRequestID = UUID(0)
        }
        await store.receive(\.chatModelsLoaded) {
            $0.chatModelsByProvider[.chatgptCodex] = [model]
            $0.chatModelCatalogPhase = .loaded
            $0.chatModelRequestID = nil
        }
        await store.finish()

        let loadedCredentials = await credentialRecorder.values()
        XCTAssertEqual(loadedCredentials, [.oauth(effectiveCredential)])
        XCTAssertEqual(
            savedFile.providers[AiProvider.chatgptCodex.rawValue]?.credential,
            .oauth(effectiveCredential),
        )
    }

    /// SET-007-codex_oauth_runtime: persistence failure suppresses verified success state.
    /// A verified refreshed credential is not usable until its atomic persistence succeeds.
    /// - 검증 내용: atomic persistence failure, completion suppression, model reload suppression.
    /// - 사전 조건: Codex verification succeeds but atomic update reports a file-system error.
    /// - 기대 결과: row remains checking and no verification completion or model load is emitted.
    func testBootstrapPersistenceFailureSuppressesVerificationSuccessAndModelReload() async {
        let credential = OAuthCredentialFile(
            accessToken: "expired-access",
            refreshToken: "source-refresh",
            expiresAtMs: 0,
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(credential),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectionFailed),
                ),
            ],
        )
        let modelLoadCount = LoadCounter()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiConnectionsFileClient.atomicUpdate = { _ in
                .fileSystemError(.fileSystemError("test"))
            }
            $0.aiProviderVerificationClient.verifyWithCredential = { _, source in
                AiProviderVerificationOutcome(
                    result: .valid,
                    sourceCredential: source,
                    effectiveCredential: .oauth(credential),
                )
            }
            $0.aiChatDefaultSettingsClient.load = {
                AiChatDefaultSettings(
                    provider: PersistedAIProviderSelection(rawValue: AiProvider.chatgptCodex.rawValue),
                    model: nil,
                    thinking: .providerDefault,
                )
            }
            $0.aiProviderModelListClient.loadModels = { _, _ in
                _ = await modelLoadCount.increment()
                return []
            }
        }

        await store.send(.onAppear) {
            $0.didBootstrap = true
            $0.bootstrapPhase = .loading
            $0.chatDefaultSettings = AiChatDefaultSettings(
                provider: PersistedAIProviderSelection(rawValue: AiProvider.chatgptCodex.rawValue),
                model: nil,
                thinking: .providerDefault,
            )
        }
        await store.receive(\.bootstrapCompleted) {
            $0.bootstrapPhase = .loaded
            $0.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
        }
        await store.finish()

        let modelLoads = await modelLoadCount.currentValue()
        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.connectionState, .checkingStatus)
        XCTAssertEqual(modelLoads, 0)
    }

    /// SET-007-codex_oauth_runtime: concurrent reconnect suppresses stale bootstrap success.
    /// Verification for the old account must not replace or project a newer credential.
    /// - 검증 내용: atomic CAS miss after credential replacement and model reload suppression.
    /// - 사전 조건: verification starts with one credential and another account reconnects before persistence.
    /// - 기대 결과: latest credential remains and no stale connected completion or model load is emitted.
    func testBootstrapConcurrentCredentialReplacementSuppressesStaleSuccess() async {
        await assertBootstrapCASMissSuppressesSuccess(replacementCredential: .oauth(OAuthCredentialFile(
            accessToken: "replacement-access",
            refreshToken: "replacement-refresh",
            expiresAtMs: Int64.max,
        )))
    }

    /// SET-007-codex_oauth_runtime: concurrent deletion suppresses stale bootstrap success.
    /// Verification for a deleted credential must not restore connected state or start model loading.
    /// - 검증 내용: atomic CAS miss after credential deletion and model reload suppression.
    /// - 사전 조건: verification starts with a credential that is deleted before persistence.
    /// - 기대 결과: credential stays deleted and no stale connected completion or model load is emitted.
    func testBootstrapConcurrentCredentialDeletionSuppressesStaleSuccess() async {
        await assertBootstrapCASMissSuppressesSuccess(replacementCredential: nil)
    }

    private func assertBootstrapCASMissSuppressesSuccess(
        replacementCredential: StoredCredentialPayload?,
    ) async {
        let sourceFile = bootstrapSourceFile()
        let replacementFile = bootstrapReplacementFile(credential: replacementCredential)
        let connectionsStore = BootstrapConnectionsStore(file: sourceFile)
        let modelLoadCount = LoadCounter()
        let store = bootstrapCASMissStore(
            connectionsStore: connectionsStore,
            replacementFile: replacementFile,
            modelLoadCount: modelLoadCount,
        )

        await store.send(.onAppear) {
            $0.didBootstrap = true
            $0.bootstrapPhase = .loading
            $0.chatDefaultSettings = AiChatDefaultSettings(
                provider: PersistedAIProviderSelection(rawValue: AiProvider.chatgptCodex.rawValue),
                model: nil,
                thinking: .providerDefault,
            )
        }
        await store.receive(\.bootstrapCompleted) {
            $0.bootstrapPhase = .loaded
            $0.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
        }
        await store.finish()

        let latestFile = await connectionsStore.load()
        let modelLoads = await modelLoadCount.currentValue()
        XCTAssertEqual(
            latestFile.providers[AiProvider.chatgptCodex.rawValue]?.credential,
            replacementCredential,
        )
        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.connectionState, .checkingStatus)
        XCTAssertEqual(modelLoads, 0)
    }

    private func bootstrapSourceFile() -> AIConnectionsFile {
        AIConnectionsFile.singleProvider(
            .chatgptCodex,
            state: .connectionFailed,
            credential: .oauth(OAuthCredentialFile(
                accessToken: "source-access",
                refreshToken: "source-refresh",
                expiresAtMs: 0,
            )),
        )
    }

    private func bootstrapReplacementFile(
        credential: StoredCredentialPayload?,
    ) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 2,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: credential,
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: credential == nil ? .notVerified : .connected,
                    ),
                ),
            ],
        )
    }

    private func bootstrapCASMissStore(
        connectionsStore: BootstrapConnectionsStore,
        replacementFile: AIConnectionsFile,
        modelLoadCount: LoadCounter,
    ) -> TestStoreOf<AiSettingsFeature> {
        TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { await connectionsStore.load() },
                save: { .success($0) },
                deleteCredential: { _ in .success(replacementFile) },
                atomicUpdate: { transform in
                    try await .success(connectionsStore.update(transform))
                },
            )
            $0.aiProviderVerificationClient.verifyWithCredential = { _, credential in
                await connectionsStore.set(replacementFile)
                return AiProviderVerificationOutcome(
                    result: .valid,
                    sourceCredential: credential,
                    effectiveCredential: credential,
                )
            }
            $0.aiChatDefaultSettingsClient.load = { AiChatDefaultSettings(
                provider: PersistedAIProviderSelection(rawValue: AiProvider.chatgptCodex.rawValue),
                model: nil,
                thinking: .providerDefault,
            )
            }
            $0.aiProviderModelListClient.loadModels = { _, _ in
                _ = await modelLoadCount.increment()
                return []
            }
        }
    }

    /// SET-007-codex_oauth_runtime: retry cancels an expired Codex refresh without stale persistence.
    /// The cancelled bootstrap must not emit a verification completion or save a network failure.
    /// - 검증 내용: suspended refresh cancellation, retry completion ordering, persisted snapshot count.
    /// - 사전 조건: first Codex verification suspends until cancellation and second verification succeeds.
    /// - 기대 결과: only the retried connected result is emitted and persisted once.
    func testRetryBootstrapCancelsExpiredCodexRefreshWithoutPersistingStaleFailure() async throws {
        let credential = OAuthCredentialFile(
            accessToken: "expired-access",
            refreshToken: "refresh-token",
            expiresAtMs: 0,
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(credential),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectionFailed),
                ),
            ],
        )
        let verificationController = BootstrapVerificationController()
        let savedConnectionsFile = SavedConnectionsFile()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiConnectionsFileClient.save = { savedFile in
                await savedConnectionsFile.record(savedFile)
                return .success(savedFile)
            }
            $0.aiProviderVerificationClient.verifyWithCredential = { _, credential in
                try await verificationController.verify(credential: credential)
            }
        }

        await store.send(.onAppear) {
            $0.didBootstrap = true
            $0.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) {
            $0.bootstrapPhase = .loaded
            $0.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            $0.rows[id: .chatgptCodex]?.statusReason = .none
        }
        await verificationController.waitUntilFirstCallStarts()

        await store.send(.retryBootstrapTapped) {
            $0.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) {
            $0.bootstrapPhase = .loaded
        }
        let recordedFile = await savedConnectionsFile.value()
        let savedFile = try XCTUnwrap(recordedFile)
        await store.receive(.delegate(.connectionsFileUpdated(savedFile)))
        await store.receive(\.bootstrapVerificationCompleted) {
            $0.rows[id: .chatgptCodex]?.connectionState = .connected
            $0.rows[id: .chatgptCodex]?.tokenExpiresAtMs = 0
        }
        await store.finish()

        let savedFileCount = await savedConnectionsFile.values().count
        XCTAssertEqual(savedFileCount, 1)
        XCTAssertEqual(
            savedFile.providers[AiProvider.chatgptCodex.rawValue]?.snapshot.lastKnownStatus,
            .connected,
        )
    }

    // MARK: - SET-007-show_ai_provider_list

    /// SET-007-show_ai_provider_list: 지원 provider row는 연결 방식과 primary action을 노출하고 기본/최근 사용 UI를 만들지 않는다.
    /// Settings AI 탭의 provider 목록이 현재 빌드의 지원 provider와 계약상 허용된 연결 방식만 표시하는지 검증한다.
    /// - 검증 내용: ChatGPT Codex/OAuth, OpenAI/API Key, Anthropic/API Key, fresh action, connected/retry action
    /// - 사전 조건: Settings AI provider catalog를 기본 상태로 구성한다.
    /// - 기대 결과: 3개 provider row가 정해진 순서와 method label/action으로 노출되고 default/last-used 상태는 없다.
    func testProviderRowsExposeSupportedProvidersMethodsAndActions() {
        let rows = AiSettingsState.catalogRows()

        XCTAssertEqual(rows.map(\.provider), [.chatgptCodex, .openai, .anthropic])
        XCTAssertEqual(rows.map(\.displayName), ["ChatGPT Codex", "OpenAI", "Anthropic"])
        XCTAssertEqual(rows.map(\.authMethodLabel), ["OAuth", "API Key", "API Key"])
        XCTAssertTrue(rows.allSatisfy { $0.connectionState == .notVerified })
        XCTAssertTrue(rows.allSatisfy { $0.primaryAction == .connect })
        XCTAssertEqual(AiConnectionRowState(provider: .openai, connectionState: .connected).primaryAction, .disconnect)
        XCTAssertEqual(
            AiConnectionRowState(provider: .anthropic, connectionState: .connectionFailed).primaryAction,
            .retry,
        )
    }

    // MARK: - SET-007-connect_ai_provider

    // MARK: - SET-007-connect_ai_provider

    // MARK: - SET-007-disconnect_ai_provider

    /// SET-007-disconnect_ai_provider: confirmation success는 credential 제거 file update를 전달하고 not_verified로 돌아간다.
    /// Settings 소유 범위에서 연결 해제 결과가 row state와 저장 파일의 credential 제거 사실을 함께 갱신하는지 검증한다.
    /// - 검증 내용: disconnecting transition, disconnect response, credential nil updatedFile delegate, connect action
    /// - 사전 조건: OpenAI row가 connected이고 confirmation이 표시되어 있다.
    /// - 기대 결과: row는 not_verified가 되고 delegate payload의 OpenAI credential은 nil이다.
    func testDisconnectConfirmationSuccessRemovesCredentialAndEmitsFileUpdate() async {
        let updatedFile = openAIDisconnectedFile()
        let result = AiProviderConnectionResult(
            provider: .openai,
            state: .notVerified,
            reason: .none,
            updatedFile: updatedFile,
        )
        let store = TestStore(initialState: AiSettingsState(rows: [
            AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                enteredKey: "sk-preserved",
                isShowingDisconnectConfirmation: true,
            ),
        ])) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiProviderConnectionClient.disconnect = { _ in result }
        }

        await store.send(.row(.element(id: .openai, action: .disconnectConfirm))) { state in
            state.rows[id: .openai]?.isShowingDisconnectConfirmation = false
            state.rows[id: .openai]?.flowState = .disconnecting
            state.rows[id: .openai]?.connectionState = .disconnecting
        }
        await store.receive(.row(.element(id: .openai, action: .disconnectResponse(result)))) { state in
            state.rows[id: .openai]?.flowState = .idle
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .openai]?.enteredKey = ""
        }
        await store.receive(.delegate(.connectionsFileUpdated(updatedFile)))
        await store.finish()

        XCTAssertNil(updatedFile.providers[AiProvider.openai.rawValue]?.credential)
        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .connect)
    }

    // MARK: - SET-007-restore_ai_provider_connection_status

    /// SET-007-restore_ai_provider_connection_status: 저장 credential은 checking_status를 거쳐 connected로 복원된다.
    /// Settings AI 탭 진입 시 저장된 credential을 즉시 connected로 단정하지 않고 verification 이후 확정하는지 검증한다.
    /// - 검증 내용: onAppear bootstrap, checking_status initial result, verification completed result
    /// - 사전 조건: OpenAI credential이 저장되어 있고 verification은 valid를 반환한다.
    /// - 기대 결과: OpenAI row가 checking_status를 거쳐 connected가 된다.
    func testStoredCredentialRestoresFromCheckingStatusToConnected() async {
        let store = settingsStore(file: .singleProvider(.openai, state: .connected)) {
            $0.aiProviderVerificationClient.verify = { provider, credential in
                XCTAssertEqual(provider, .openai)
                XCTAssertNotNil(credential)
                return .valid
            }
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
    }

    /// SET-007-restore_ai_provider_connection_status: credential이 없으면 not_verified와 missingCredential reason으로 복원된다.
    /// 저장 row는 있으나 credential payload가 누락된 경우 연결된 것으로 오인하지 않는지 검증한다.
    /// - 검증 내용: missing credential bootstrap result, no verification request, connect action
    /// - 사전 조건: OpenAI provider record는 있지만 credential은 nil이다.
    /// - 기대 결과: row는 not_verified/missingCredential이고 primary action은 connect다.
    func testMissingCredentialRestoresToNotVerified() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        let store = settingsStore(file: file)

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .missingCredential
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: failed snapshot은 checking_status 이후 connection_failed로 복원된다.
    /// 만료된 저장 credential이 recoverable retry 상태로 표현되는지 검증한다.
    /// - 검증 내용: connectionFailed snapshot, verification invalid response, retry action
    /// - 사전 조건: OpenAI snapshot이 connectionFailed/expired이고 verification도 expired를 반환한다.
    /// - 기대 결과: row는 connection_failed/expired이고 primary action은 retry다.
    func testFailedSnapshotRestoresToConnectionFailedWithRetry() async {
        let store = settingsStore(file: .singleProvider(.openai, state: .connectionFailed, errorCode: .expired)) {
            $0.aiProviderVerificationClient.verify = { _, _ in .invalid(.expired) }
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
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .expired
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .retry)
    }

    /// SET-007-restore_ai_provider_connection_status: provider record가 없으면 모든 row는 not_verified로 복원된다.
    /// 저장 파일이 비어 있는 fresh 상태를 연결 실패나 missing credential로 오인하지 않는지 검증한다.
    /// - 검증 내용: empty connections file bootstrap, default rows, connect primary action
    /// - 사전 조건: AI connections file에 provider record가 없다.
    /// - 기대 결과: 모든 row가 not_verified/none 상태이고 primary action은 connect다.
    func testNoProviderRecordRestoresAllRowsToNotVerified() async {
        let store = settingsStore(file: .empty())

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

    /// SET-007-restore_ai_provider_connection_status: stale connect_in_progress snapshot은 credential이 있어도 not_verified로
    /// 낮춘다.
    /// 이전 세션에서 중단된 연결 시도를 재시작하지 않고 사용자가 명시적으로 다시 연결하도록 만드는지 검증한다.
    /// - 검증 내용: persisted connect_in_progress snapshot, credential present, no missingCredential reason
    /// - 사전 조건: ChatGPT Codex OAuth credential이 있지만 snapshot은 connect_in_progress다.
    /// - 기대 결과: row는 not_verified/none 상태이고 primary action은 connect다.
    func testConnectInProgressSnapshotWithCredentialRestoresToNotVerified() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectInProgress),
                ),
            ],
        )
        let store = settingsStore(file: file)

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

        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: disconnecting snapshot은 disconnected로 복원된다.
    /// 이전 세션에서 연결 해제 중 종료된 provider가 계속 disconnecting으로 고정되지 않는지 검증한다.
    /// - 검증 내용: persisted disconnecting snapshot, loaded restore state, connect primary action
    /// - 사전 조건: Anthropic provider snapshot이 disconnecting이다.
    /// - 기대 결과: row는 disconnected/none 상태이고 primary action은 connect다.
    func testDisconnectingSnapshotRestoresToDisconnected() async {
        let store = settingsStore(file: .singleProvider(.anthropic, state: .disconnecting))

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

        XCTAssertEqual(store.state.rows[id: .anthropic]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: disconnected snapshot은 disconnected 상태와 connect action을 유지한다.
    /// 명시적으로 연결 해제된 provider가 fresh not_verified와 구분되어 복원되는지 검증한다.
    /// - 검증 내용: persisted disconnected snapshot, status reason, primary action
    /// - 사전 조건: OpenAI provider snapshot이 disconnected다.
    /// - 기대 결과: row는 disconnected/none 상태이고 primary action은 connect다.
    func testDisconnectedSnapshotRestoresToDisconnected() async {
        let store = settingsStore(file: .singleProvider(.openai, state: .disconnected))

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

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: 여러 provider snapshot은 독립적으로 복원된다.
    /// connected/failed/no-record provider가 한 bootstrap에서 서로의 상태를 오염시키지 않는지 검증한다.
    /// - 검증 내용: mixed provider records, verification fan-out, connected/retry/connect actions
    /// - 사전 조건: ChatGPT Codex는 connected, OpenAI는 expired failure, Anthropic은 record가 없다.
    /// - 기대 결과: Codex는 connected, OpenAI는 connection_failed/expired, Anthropic은 not_verified다.
    func testMixedProviderSnapshotsRestoreIndependently() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-expired")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connectionFailed,
                        lastErrorCode: .expired,
                    ),
                ),
            ],
        )
        let store = settingsStore(file: file) {
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
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .expired
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.primaryAction, .disconnect)
        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .retry)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.connectionState, .notVerified)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.statusReason, ProviderStatusReason.none)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: catalog load failure는 rows를 보존하고 retry로 복구된다.
    /// provider catalog/load 오류가 빈 목록으로 보이지 않고 사용자가 재시도할 수 있는 상태로 남는지 검증한다.
    /// - 검증 내용: bootstrap failed phase, rows preserved, retry bootstrap success
    /// - 사전 조건: 첫 load는 실패하고 두 번째 load는 OpenAI credential file을 반환한다.
    /// - 기대 결과: failed phase 후 retry가 loaded/connected 상태로 회복된다.
    func testCatalogLoadFailureShowsRetryAndCanRecover() async {
        let loadCounter = LoadCounter()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                let count = await loadCounter.increment()
                if count == 1 { throw NSError(domain: "SET007", code: -1) }
                return AIConnectionsFile.singleProvider(.openai, state: .connected)
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })

        await store.send(.retryBootstrapTapped) { state in
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
            state.bootstrapPhase = .loaded
        }
        await store.finish()
    }

    /// SET-007-restore_ai_provider_connection_status: catalog load 실패 뒤 onAppear 재진입은 자동 retry를 실행하지 않는다.
    /// 실패 상태에서 사용자의 명시적 retry 없이 catalog load를 반복하지 않는지 검증한다.
    /// - 검증 내용: initial onAppear failure, second onAppear ignored, load call count
    /// - 사전 조건: AI connections file load가 항상 실패한다.
    /// - 기대 결과: load는 1회만 호출되고 bootstrapPhase는 failed로 유지된다.
    func testCatalogLoadFailureDoesNotRetryAutomaticallyOnAppear() async {
        let loadCounter = LoadCounter()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                _ = await loadCounter.increment()
                throw NSError(domain: "SET007", code: -1)
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        await store.send(.onAppear)
        await store.finish()

        let loadCalls = await loadCounter.currentValue()
        XCTAssertEqual(loadCalls, 1)
        XCTAssertEqual(store.state.bootstrapPhase, .failed)
    }

    /// SET-007-restore_ai_provider_connection_status: unavailable snapshot은 verification 후 disabled 상태로 복원된다.
    /// 저장된 provider가 현재 build에서 지원되지 않을 때 연결 가능한 상태로 오인하지 않는지 검증한다.
    /// - 검증 내용: persisted unavailable snapshot, checking status, unsupported verification, disabled primary action
    /// - 사전 조건: OpenAI provider snapshot이 unavailable/providerUnsupportedInBuild 상태다.
    /// - 기대 결과: OpenAI row는 unavailable/providerUnsupportedInBuild이고 primary action은 disabled다.
    func testUnavailableSnapshotRestoresWithDisabledAction() async {
        let store = settingsStore(file: .singleProvider(
            .openai,
            state: .unavailable,
            errorCode: .providerUnsupportedInBuild,
        )) {
            $0.aiProviderVerificationClient.verify = { _, _ in .unsupportedProvider }
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
            state.rows[id: .openai]?.connectionState = .unavailable
            state.rows[id: .openai]?.statusReason = .providerUnsupportedInBuild
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .disabled)
    }

    // MARK: - SET-007-connect_ai_provider

    /// SET-007-connect_ai_provider: connection response는 connectionsFileUpdated delegate를 방출한다.
    /// row reducer 결과가 Settings feature의 저장 파일 갱신 delegate로 이어지는지 검증한다.
    /// - 검증 내용: row connectionResponse, connected state, delegate payload
    /// - 사전 조건: ChatGPT Codex row가 connect_in_progress/browserLoginInProgress 상태다.
    /// - 기대 결과: row는 connected/idle이 되고 updated file delegate가 방출된다.
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

    /// SET-007-restore_ai_provider_connection_status: bootstrap verification 성공은 저장 파일과 delegate를 갱신한다.
    /// stale failed snapshot이 valid verification 후 connected snapshot으로 저장되는지 검증한다.
    /// - 검증 내용: bootstrap verification, AI connections file save, delegate emission
    /// - 사전 조건: OpenAI snapshot이 connection_failed/expired이고 verification은 valid다.
    /// - 기대 결과: connected snapshot 파일이 저장되고 동일 payload delegate가 방출된다.
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

        await store.receive(.delegate(.connectionsFileUpdated(expectedFile)))
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(saveSpy.savedFiles, [expectedFile])
    }

    // MARK: - SET-007-disconnect_ai_provider

    /// SET-007-disconnect_ai_provider: disconnect response는 connectionsFileUpdated delegate를 방출한다.
    /// 연결 해제 결과가 Settings feature 경계에서 저장 파일 갱신 이벤트로 전달되는지 검증한다.
    /// - 검증 내용: row disconnectResponse, not_verified state, delegate payload
    /// - 사전 조건: OpenAI row가 disconnecting 상태다.
    /// - 기대 결과: row는 not_verified/idle이 되고 updated file delegate가 방출된다.
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

    /// SET-007-restore_ai_provider_connection_status: unsupported provider verification은 unavailable snapshot을 저장한다.
    /// 현재 build에서 지원되지 않는 provider가 connected로 남지 않고 저장 파일과 delegate에 반영되는지 검증한다.
    /// - 검증 내용: unsupported verification, unavailable snapshot save, delegate emission
    /// - 사전 조건: ChatGPT Codex snapshot은 connected이고 verification은 unsupportedProvider다.
    /// - 기대 결과: unavailable/providerUnsupportedInBuild snapshot이 저장되고 delegate가 방출된다.
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

        await store.receive(.delegate(.connectionsFileUpdated(expectedFile)))
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .unavailable
            state.rows[id: .chatgptCodex]?.statusReason = .providerUnsupportedInBuild
        }
        await store.finish()

        XCTAssertEqual(saveSpy.savedFiles, [expectedFile])
    }

    /// SET-007-restore_ai_provider_connection_status: 최신 credential이 바뀌면 stale verification 결과를 저장하지 않는다.
    /// bootstrap 중 사용자가 credential을 갱신한 경우 이전 credential 검증 결과가 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: stale file load, latest file reload, save suppression
    /// - 사전 조건: 첫 load는 오래된 OpenAI credential, 두 번째 load는 새 credential을 반환한다.
    /// - 기대 결과: stale row success와 save 모두 방출되지 않는다.
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

        await store.finish()

        XCTAssertTrue(saveSpy.savedFiles.isEmpty)
        XCTAssertEqual(store.state.rows[id: .openai]?.connectionState, .checkingStatus)
    }

    /// SET-007-restore_ai_provider_connection_status: fresh install은 모든 provider를 not_verified로 표시한다.
    /// 저장 파일이 비어 있는 첫 실행 상태에서 기본 provider row가 연결 가능한 상태로 준비되는지 검증한다.
    /// - 검증 내용: empty connections file, default row count, connect primary action
    /// - 사전 조건: AI connections file이 비어 있다.
    /// - 기대 결과: 세 provider row가 not_verified이고 primary action은 connect다.
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

    /// SET-007-restore_ai_provider_connection_status: invalid API key snapshot은 retry 가능한 실패로 복원된다.
    /// 저장된 invalid credential 상태가 bootstrap verification 후 connection_failed로 유지되는지 검증한다.
    /// - 검증 내용: invalidAPIKey snapshot, verification invalid response, retry action
    /// - 사전 조건: Anthropic snapshot이 connection_failed/invalidAPIKey다.
    /// - 기대 결과: row는 connection_failed/invalidAPIKey이고 primary action은 retry다.
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

    /// SET-007-restore_ai_provider_connection_status: load error는 bootstrapPhase를 failed로 둔다.
    /// connections file load 실패가 빈 목록 성공으로 오인되지 않는지 검증한다.
    /// - 검증 내용: load throw, bootstrapFailed action, row preservation
    /// - 사전 조건: aiConnectionsFileClient.load가 오류를 던진다.
    /// - 기대 결과: bootstrapPhase는 failed이고 기본 row 3개는 유지된다.
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

    /// SET-007-restore_ai_provider_connection_status: onAppear 재진입은 bootstrap을 중복 실행하지 않는다.
    /// 이미 bootstrap이 완료된 Settings AI 탭에서 재진입이 추가 load effect를 만들지 않는지 검증한다.
    /// - 검증 내용: first onAppear bootstrap, second onAppear ignored
    /// - 사전 조건: AI connections file이 비어 있고 첫 bootstrap이 완료됐다.
    /// - 기대 결과: 두 번째 onAppear는 state/effect를 만들지 않는다.
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

    /// SET-007-restore_ai_provider_connection_status: disconnected snapshot은 disconnected로 복원된다.
    /// 명시적으로 연결 해제된 provider가 fresh not_verified와 구분되는지 검증한다.
    /// - 검증 내용: persisted disconnected snapshot, primary action
    /// - 사전 조건: OpenAI snapshot이 disconnected다.
    /// - 기대 결과: row는 disconnected이고 primary action은 connect다.
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

    /// SET-007-restore_ai_provider_connection_status: credential 없는 connect_in_progress snapshot은 missingCredential로
    /// 복원된다.
    /// 이전 세션의 중단된 연결 시도가 credential 없이 connected로 이어지지 않는지 검증한다.
    /// - 검증 내용: connectInProgress snapshot, nil credential guard, missingCredential reason
    /// - 사전 조건: ChatGPT Codex snapshot은 connect_in_progress이고 credential은 nil이다.
    /// - 기대 결과: row는 not_verified/missingCredential 상태가 된다.
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

    /// SET-007-restore_ai_provider_connection_status: disconnecting snapshot은 disconnected로 복원된다.
    /// 이전 세션에서 연결 해제 중 종료된 상태가 계속 진행 중으로 남지 않는지 검증한다.
    /// - 검증 내용: persisted disconnecting snapshot, disconnected state
    /// - 사전 조건: Anthropic snapshot이 disconnecting이다.
    /// - 기대 결과: row는 disconnected/none 상태가 된다.
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

    // MARK: - SET-007-bootstrap_phase

    /// `.idle` 초기 상태에서 rows는 `catalogRows()`로 즉시 채워진다.
    /// UI가 spinner 없이 placeholder rows를 표시할 수 있음을 보장.
    func testIdleState_hasNonEmptyRows_allNotVerified() {
        let state = AiSettingsState()

        XCTAssertEqual(state.bootstrapPhase, .idle)
        XCTAssertEqual(state.rows.count, 3)
        XCTAssertEqual(state.rows.map(\.provider), [.chatgptCodex, .openai, .anthropic])
        XCTAssertTrue(state.rows.allSatisfy { $0.connectionState == .notVerified })
    }

    /// `.loading` 상태를 직접 주입해도 rows는 유지된다.
    /// onAppear 직후, `.bootstrapCompleted` 수신 전 first paint가 rows를 표시할 수 있음을 보장.
    func testLoadingState_withExplicitPhase_preservesRows() {
        let rows = AiSettingsState.catalogRows()
        let state = AiSettingsState(
            didBootstrap: true,
            bootstrapPhase: .loading,
            rows: rows,
        )

        XCTAssertEqual(state.bootstrapPhase, .loading)
        XCTAssertEqual(state.rows.count, 3)
        XCTAssertTrue(state.rows.allSatisfy { $0.connectionState == .notVerified })
    }

    /// onAppear 직후 `.loading` phase에서 rows가 유지되는지 TestStore로 단언.
    /// `.bootstrapCompleted`가 도착하기 전 first paint 시점의 상태 검증.
    func testOnAppear_setsLoadingPhase_rowsRemainNonEmpty() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        XCTAssertEqual(store.state.bootstrapPhase, .loading)
        XCTAssertEqual(store.state.rows.count, 3)

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
        }
        await store.finish()
    }

    /// `bootstrapCompleted`가 notVerified/checkingStatus/connected 혼합 initial results를
    /// 정확히 row에 반영하고 phase를 `.loaded`로 전환하는지 검증.
    /// verification pending은 row의 `connectionState`(`.checkingStatus`)로 표현됨.
    func testBootstrapCompleted_appliesMixedInitialResults_setsLoadedPhase() async {
        let mixedResults = [
            AIProviderBootstrapResult(
                provider: .chatgptCodex,
                connectionState: .connected,
                statusReason: .none,
            ),
            AIProviderBootstrapResult(
                provider: .openai,
                connectionState: .checkingStatus,
                statusReason: .none,
            ),
            AIProviderBootstrapResult(
                provider: .anthropic,
                connectionState: .notVerified,
                statusReason: .missingCredential,
            ),
        ]
        let store = TestStore(
            initialState: AiSettingsState(
                didBootstrap: true,
                bootstrapPhase: .loading,
            ),
        ) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.bootstrapCompleted(mixedResults)) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .anthropic]?.connectionState = .notVerified
            state.rows[id: .anthropic]?.statusReason = .missingCredential
        }

        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.connectionState, .connected)
        XCTAssertEqual(store.state.rows[id: .openai]?.connectionState, .checkingStatus)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.connectionState, .notVerified)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.statusReason, .missingCredential)
    }

    /// `bootstrapVerificationCompleted`는 `.loaded` phase를 유지하면서 row만 갱신.
    /// verification 결과가 첫 paint phase를 다시 `.loading`으로 되돌리지 않음을 보장.
    func testBootstrapVerificationCompleted_keepsLoadedPhase_updatesRows() async {
        let verificationResults = [
            AIProviderBootstrapResult(
                provider: .openai,
                connectionState: .connected,
                statusReason: .none,
            ),
        ]
        let store = TestStore(
            initialState: AiSettingsState(
                didBootstrap: true,
                bootstrapPhase: .loaded,
                rows: [
                    AiConnectionRowState(
                        provider: .openai,
                        connectionState: .checkingStatus,
                    ),
                    AiConnectionRowState(provider: .anthropic),
                    AiConnectionRowState(provider: .chatgptCodex),
                ],
            ),
        ) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
        }

        await store.send(.bootstrapVerificationCompleted(verificationResults)) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
        }

        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertEqual(store.state.rows[id: .openai]?.connectionState, .connected)
    }

    /// bootstrap file load 실패 시 `.failed` phase로 전환되지만 rows는 보존됨.
    func testBootstrapFailed_setsFailedPhase_preservesRows() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                throw NSError(domain: "test", code: -1)
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
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })
    }

    // MARK: - SET-007-bootstrap_end_to_end

    /// End-to-end: onAppear → file load → `.bootstrapCompleted`(initial) →
    /// `.bootstrapVerificationCompleted` → 최종 `.loaded`. 3 provider 각각 다른
    /// verification 결과(connected/expired/connected)가 row에 정확히 반영되는지 검증.
    /// - 검증 내용: full pipeline, rows 3개 보존, 최종 connectionState, phase `.loaded`
    /// - 사전 조건: 3 provider 모두 credential 보유, snapshot이 verification 결과와 동일
    /// - 기대 결과: chatgpt=connected, openai=connectionFailed/expired, anthropic=connected
    func testOnAppear_fullBootstrapPipeline_appliesInitialAndVerificationResults_setsLoadedPhase() async {
        let file = Self.threeProviderFileMatchingOutcomes()
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

        XCTAssertEqual(store.state.bootstrapPhase, .idle)
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        XCTAssertEqual(store.state.rows.count, 3)

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .anthropic]?.connectionState = .checkingStatus
            state.rows[id: .anthropic]?.statusReason = .none
        }
        XCTAssertEqual(store.state.rows.count, 3)

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .expired
            state.rows[id: .anthropic]?.connectionState = .connected
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.connectionState, .connected)
        XCTAssertEqual(store.state.rows[id: .openai]?.connectionState, .connectionFailed)
        XCTAssertEqual(store.state.rows[id: .openai]?.statusReason, .expired)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.connectionState, .connected)
    }

    /// Launch-like no-credential 상태: 모든 provider record에 credential이 없을 때
    /// bootstrap은 `.loaded`로 종료되며 rows는 처음부터 끝까지 3개 notVerified 상태로 유지.
    /// verification 단계가 생략되고도 spinner-only 상태로 떨어지지 않음을 보장.
    /// - 검증 내용: no-credential initial, verification 미실행, terminal `.loaded`, rows 보존
    /// - 사전 조건: 3 provider record 모두 credential=nil
    /// - 기대 결과: 모든 row notVerified/missingCredential, primaryAction=.connect, phase=.loaded
    func testNoCredentialLaunchState_keepsThreeRowsNotVerified_throughEntireBootstrap() async {
        let file = Self.threeProviderFileAllMissingCredentials()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiProviderVerificationClient.verify = { provider, _ in
                XCTFail("Verification should not run when credential is nil: \(provider)")
                return .valid
            }
        }

        XCTAssertEqual(store.state.bootstrapPhase, .idle)
        XCTAssertEqual(store.state.rows.count, 3)

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        XCTAssertEqual(store.state.rows.count, 3)

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.statusReason = .missingCredential
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .missingCredential
            state.rows[id: .anthropic]?.connectionState = .notVerified
            state.rows[id: .anthropic]?.statusReason = .missingCredential
        }
        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })
        XCTAssertTrue(store.state.rows.allSatisfy { $0.statusReason == .missingCredential })
        XCTAssertTrue(store.state.rows.allSatisfy { $0.primaryAction == .connect })
    }

    /// File load 실패 → `.failed` phase + rows 3개 보존 → retry 시도 → bootstrap 재실행 성공.
    /// 실패 상태에서 rows가 사라지지 않고 명시적 retry로 전체 파이프라인이 회복되는지 검증.
    /// - 검증 내용: load throw, `.failed` 전이, rows 보존, retry → `.loading` → `.loaded` 회복
    /// - 사전 조건: 첫 load는 throw, 두 번째 load는 3 provider connected file 반환
    /// - 기대 결과: retry 후 모든 row 최종 connected, phase=`.loaded`
    func testFileLoadFailure_setsFailedPhase_preservesRows_retryRecoversAllThreeProviders() async {
        let loadCounter = LoadCounter()
        let recoveryFile = Self.threeProviderFileMatchingOutcomes(
            openaiStatus: .connected,
            openaiErrorCode: .none,
        )
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                let count = await loadCounter.increment()
                if count == 1 { throw NSError(domain: "e2e", code: -1) }
                return recoveryFile
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        XCTAssertEqual(store.state.rows.count, 3)

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        XCTAssertEqual(store.state.bootstrapPhase, .failed)
        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })

        await store.send(.retryBootstrapTapped) { state in
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .anthropic]?.connectionState = .checkingStatus
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .anthropic]?.connectionState = .connected
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .loaded)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .connected })
    }

    /// 단일 provider verification 결과가 networkError(timeout-style)여도 다른 provider
    /// row가 정상적으로 갱신됨을 보장. Task 4 병렬화의 회귀 방지 증거.
    /// - 검증 내용: networkError 결과가 형제 provider 갱신을 차단하지 않음, rows 보존
    /// - 사전 조건: 3 provider credential 보유, openai verification이 networkError 반환
    /// - 기대 결과: chatgpt/anthropic=connected, openai=connectionFailed/networkUnavailable
    func testOneProviderNetworkErrorResult_doesNotBlockOtherProviderRows() async {
        let file = Self.threeProviderFileMatchingOutcomes(
            openaiStatus: .connectionFailed,
            openaiErrorCode: .networkUnavailable,
        )
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiProviderVerificationClient.verify = { provider, _ in
                switch provider {
                case .chatgptCodex: .valid
                case .openai: .networkError
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
            state.rows[id: .anthropic]?.connectionState = .checkingStatus
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .networkUnavailable
            state.rows[id: .anthropic]?.connectionState = .connected
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.connectionState, .connected)
        XCTAssertEqual(store.state.rows[id: .openai]?.connectionState, .connectionFailed)
        XCTAssertEqual(store.state.rows[id: .openai]?.statusReason, .networkUnavailable)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.connectionState, .connected)
    }
}

// MARK: - Bootstrap fixtures

private extension SET007SettingsAIConnectionsTests {
    /// 3 provider가 모두 credential을 가지며 snapshot이 verification 결과와 일치하는 파일.
    /// 기본: chatgpt/anthropic=`.connected`, openai=`.connectionFailed/.expired`.
    /// snapshot이 결과와 동일하므로 persist 단계가 생략되어
    /// `.delegate(.connectionsFileUpdated)` 수신 예측이 불필요하다.
    static func threeProviderFileMatchingOutcomes(
        openaiStatus: ProviderConnectionState = .connectionFailed,
        openaiErrorCode: ProviderStatusReason = .expired,
    ) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: openaiStatus,
                        lastErrorCode: openaiErrorCode,
                    ),
                ),
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
    }

    /// 3 provider record가 모두 credential=nil인 파일. launch-like no-credential 상태.
    static func threeProviderFileAllMissingCredentials() -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
    }
}

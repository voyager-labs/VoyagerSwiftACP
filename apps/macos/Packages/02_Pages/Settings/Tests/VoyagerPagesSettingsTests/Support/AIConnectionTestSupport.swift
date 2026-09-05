import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection
@testable import VoyagerPagesSettings

// SET AI connection specs에서 공유하는 provider connection fixture와 dependency double support.

func makeCredential(
    accessToken: String = "test-access-token",
    refreshToken: String? = "test-refresh-token",
    expiresAtMs: Int64? = nil,
) -> OAuthCredentialFile {
    OAuthCredentialFile(
        accessToken: accessToken,
        refreshToken: refreshToken,
        tokenType: "Bearer",
        scopes: ["openid", "profile", "email", "offline_access"],
        expiresAtMs: expiresAtMs,
    )
}

final class APIKeyConnectionController: @unchecked Sendable {
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

final class ConnectionsFileSaveSpy: @unchecked Sendable {
    private(set) var savedFiles: [AIConnectionsFile] = []

    func save(_ file: AIConnectionsFile) async throws -> AiConnectionMutationResult {
        savedFiles.append(file)
        return .success(file)
    }
}

final class ConnectionsFileLoadSpy: @unchecked Sendable {
    private var files: [AIConnectionsFile]

    init(files: [AIConnectionsFile]) {
        self.files = files
    }

    func load() async throws -> AIConnectionsFile {
        guard files.count > 1 else { return files[0] }
        return files.removeFirst()
    }
}

final class BrowserLoginStreamController: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<BrowserLoginState, Error>.Continuation?

    func stream() -> AsyncThrowingStream<BrowserLoginState, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            continuation.yield(.inProgress)
        }
    }

    func complete(_ credential: OAuthCredentialFile) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.yield(.completed(credential))
        continuation?.finish()
    }
}

actor OAuthEventLog {
    private var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

actor SuspensionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
func rowStore(
    state: AiConnectionRowState,
    dependencies: (inout DependencyValues) -> Void = { _ in },
) -> TestStore<AiConnectionRowState, AiConnectionRowAction> {
    TestStore(initialState: state) {
        AiConnectionRowReducer()
    } withDependencies: {
        dependencies(&$0)
    }
}

@MainActor
func apiKeyRowStore(
    provider: AiProvider,
    verificationResult: AiProviderVerificationResult,
) -> TestStore<AiConnectionRowState, AiConnectionRowAction> {
    rowStore(state: AiConnectionRowState(provider: provider)) {
        $0.aiProviderVerificationClient.verify = { _, _ in verificationResult }
        $0.aiProviderConnectionClient.connectAPIKey = { provider, _, connectionState in
            .connectSuccess(provider: provider, state: connectionState)
        }
    }
}

@MainActor
func settingsStore(
    file: AIConnectionsFile,
    dependencies: (inout DependencyValues) -> Void = { _ in },
) -> TestStore<AiSettingsState, AiSettingsAction> {
    TestStore(initialState: AiSettingsState()) {
        AiSettingsFeature()
    } withDependencies: {
        $0.aiConnectionsFileClient.load = { file }
        $0.aiProviderVerificationClient = AIProviderVerificationClient(
            verify: { _, _ in .valid },
        )
        dependencies(&$0)
    }
}

func openAIDisconnectedFile() -> AIConnectionsFile {
    AIConnectionsFile(
        updatedAtMs: 1_760_000_000_000,
        providers: [
            AiProvider.openai.rawValue: ProviderRecordFile(
                providerId: .openai,
                authMethod: .apiKey,
                credential: nil,
                snapshot: ProviderSnapshotFile(lastKnownStatus: .notVerified),
            ),
        ],
    )
}

actor LoadCounter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }

    func currentValue() -> Int {
        value
    }
}

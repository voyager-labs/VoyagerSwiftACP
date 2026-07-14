import Foundation
import VoyagerEntitiesAi

extension SettingsHostSandbox {
    static func makeAIConnectionsFileClient(
        aiConnection: AIConnectionScenario,
        failureLatency: FailureLatencyScenario,
    ) -> AIConnectionsFileClient {
        AIConnectionsFileClient(
            load: {
                await maybeDelay(failureLatency)
                if failureLatency == .error {
                    throw AiConnectionStoreError.fileSystemError("sandbox failure")
                }

                switch aiConnection {
                case .notConfigured:
                    return .empty()
                case .connected:
                    return sandboxConnectionsFile()
                case .connectionError:
                    return sandboxConnectionsFile()
                }
            },
            save: { file in
                await maybeDelay(failureLatency)
                if failureLatency == .error || aiConnection == .connectionError {
                    throw AiConnectionStoreError.fileSystemError("sandbox failure")
                }
                return .success(file)
            },
            deleteCredential: { _ in
                await maybeDelay(failureLatency)
                if failureLatency == .error || aiConnection == .connectionError {
                    throw AiConnectionStoreError.fileSystemError("sandbox failure")
                }
                return .success(.empty())
            },
        )
    }

    static func makeAIProviderVerificationClient(
        aiConnection: AIConnectionScenario,
        failureLatency: FailureLatencyScenario,
    ) -> AIProviderVerificationClient {
        AIProviderVerificationClient(
            verify: { _, _ in
                await maybeDelay(failureLatency)
                if aiConnection == .connectionError || failureLatency == .error {
                    return .networkError
                }
                switch aiConnection {
                case .notConfigured:
                    return .unsupportedProvider
                case .connected:
                    return .valid
                case .connectionError:
                    return .invalid(.verificationFailed)
                }
            },
        )
    }

    static func makeAIProviderModelListClient(
        aiConnection: AIConnectionScenario,
        failureLatency: FailureLatencyScenario,
    ) -> AiProviderModelListClient {
        AiProviderModelListClient(
            loadModels: { provider, _ in
                await maybeDelay(failureLatency)
                if aiConnection == .connectionError || failureLatency == .error {
                    throw AiProviderModelListError.networkError(
                        provider: provider,
                        description: "sandbox connection error",
                    )
                }

                switch aiConnection {
                case .notConfigured:
                    throw AiProviderModelListError.unsupportedProvider(provider)
                case .connected:
                    return sandboxModels(for: provider)
                case .connectionError:
                    throw AiProviderModelListError.networkError(
                        provider: provider,
                        description: "sandbox connection error",
                    )
                }
            },
        )
    }

    nonisolated private static func sandboxConnectionsFile() -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1_700_000_000_000,
            lastUsedProviderId: .openai,
            lastUsedAtMs: 1_700_000_000_123,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sandbox-openai-secret")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected, lastVerifiedAtMs: 1_700_000_000_456),
                ),
            ],
        )
    }

    nonisolated private static func sandboxModels(for provider: AiProvider) -> [AiProviderModel] {
        switch provider {
        case .openai:
            [
                AiProviderModel(
                    id: AiModelHandle(provider: .openai, rawValue: "gpt-4.1"),
                    provider: .openai,
                    rawModelID: "gpt-4.1",
                    displayName: "GPT-4.1",
                    providerDisplayName: "OpenAI",
                    thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "sandbox")),
                ),
            ]
        case .chatgptCodex:
            [
                AiProviderModel(
                    id: AiModelHandle(provider: .chatgptCodex, rawValue: "codex-sandbox"),
                    provider: .chatgptCodex,
                    rawModelID: "codex-sandbox",
                    displayName: "Codex Sandbox",
                    providerDisplayName: "ChatGPT Codex",
                    thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "sandbox")),
                ),
            ]
        case .anthropic:
            [
                AiProviderModel(
                    id: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-sandbox"),
                    provider: .anthropic,
                    rawModelID: "claude-sonnet-sandbox",
                    displayName: "Claude Sonnet Sandbox",
                    providerDisplayName: "Anthropic",
                    thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "sandbox")),
                ),
            ]
        }
    }

    nonisolated static func maybeDelay(_ failureLatency: FailureLatencyScenario) async {
        guard failureLatency == .latency else { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}

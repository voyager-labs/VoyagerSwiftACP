import ComposableArchitecture
import Foundation

public struct AIProviderVerificationClient: Sendable {
    public var verifyWithCredential: (@Sendable (AiProvider, StoredCredentialPayload?) async throws
        -> AiProviderVerificationOutcome)?
    public var verify: @Sendable (AiProvider, StoredCredentialPayload?) async
        -> AiProviderVerificationResult

    nonisolated public init(
        verify: @escaping @Sendable (AiProvider, StoredCredentialPayload?) async
            -> AiProviderVerificationResult,
        verifyWithCredential: (@Sendable (AiProvider, StoredCredentialPayload?) async throws
            -> AiProviderVerificationOutcome)? = nil,
    ) {
        self.verify = verify
        self.verifyWithCredential = verifyWithCredential
    }
}

extension AIProviderVerificationClient: DependencyKey {
    nonisolated public static var liveValue: AIProviderVerificationClient {
        AIProviderVerificationClient(
            verify: { provider, credential in
                let runtimeClient = runtimeClient()
                return await runtimeClient.verifyProvider(provider, credential)
            },
            verifyWithCredential: { provider, credential in
                let runtimeClient = runtimeClient()
                if let verifyWithCredential = runtimeClient.verifyProviderWithCredential {
                    return try await verifyWithCredential(provider, credential)
                }
                return await AiProviderVerificationOutcome(
                    result: runtimeClient.verifyProvider(provider, credential),
                    sourceCredential: credential,
                    effectiveCredential: credential,
                )
            },
        )
    }

    private static func runtimeClient() -> AiConnectionRuntimeClient {
        @Dependency(\.codexNativeAuthClient)
        var nativeAuthClient
        @Dependency(\.aiProviderModelListClient)
        var modelListClient
        return AiConnectionRuntimeClient.live(
            refreshCredential: nativeAuthClient.refreshCredential,
            loadModels: modelListClient.loadModels,
        )
    }

    nonisolated public static var testValue: AIProviderVerificationClient {
        AIProviderVerificationClient(
            verify: { _, _ in .valid },
        )
    }

    nonisolated public static var previewValue: AIProviderVerificationClient {
        AIProviderVerificationClient(
            verify: { provider, _ in
                switch provider {
                case .openai: .valid
                case .chatgptCodex: .valid
                case .anthropic: .valid
                }
            },
        )
    }
}

public extension DependencyValues {
    nonisolated var aiProviderVerificationClient: AIProviderVerificationClient {
        get { self[AIProviderVerificationClient.self] }
        set { self[AIProviderVerificationClient.self] = newValue }
    }
}

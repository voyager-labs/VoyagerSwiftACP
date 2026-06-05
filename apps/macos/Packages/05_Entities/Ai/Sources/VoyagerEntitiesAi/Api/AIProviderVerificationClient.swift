import ComposableArchitecture
import Foundation

public struct AIProviderVerificationClient: Sendable {
    public var verify: @Sendable (AiProvider, StoredCredentialPayload?) async
        -> AiProviderVerificationResult

    public nonisolated init(
        verify: @escaping @Sendable (AiProvider, StoredCredentialPayload?) async
            -> AiProviderVerificationResult
    ) {
        self.verify = verify
    }
}

extension AIProviderVerificationClient: DependencyKey {
    public nonisolated static var liveValue: AIProviderVerificationClient {
        let runtimeClient = AiConnectionRuntimeClient.live()
        return AIProviderVerificationClient(
            verify: { provider, credential in
                await runtimeClient.verifyProvider(provider, credential)
            }
        )
    }

    public nonisolated static var testValue: AIProviderVerificationClient {
        AIProviderVerificationClient(
            verify: { _, _ in .valid }
        )
    }

    public nonisolated static var previewValue: AIProviderVerificationClient {
        AIProviderVerificationClient(
            verify: { provider, _ in
                switch provider {
                case .openai: .valid
                case .chatgptCodex: .valid
                case .anthropic: .valid
                }
            }
        )
    }
}

public extension DependencyValues {
    nonisolated var aiProviderVerificationClient: AIProviderVerificationClient {
        get { self[AIProviderVerificationClient.self] }
        set { self[AIProviderVerificationClient.self] = newValue }
    }
}

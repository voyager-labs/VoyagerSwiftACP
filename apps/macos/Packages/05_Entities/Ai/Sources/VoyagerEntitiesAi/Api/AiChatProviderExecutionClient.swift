import ComposableArchitecture
import Foundation

public enum AiChatProviderExecutionClientError: Error, Equatable, Sendable {
    case missingCredential(AiProvider)
    case invalidCredential(provider: AiProvider, expected: ProviderAuthMethod)
    case unsupportedProvider(AiProvider)
    case loweringFailed(AiChatProviderRequestLoweringError)
}

public enum AiChatProviderExecutionEvent: Equatable, Sendable {
    case requestPrepared(AiChatProviderRequestPayload)
    case started(context: AiChatRequestContextSnapshot)
    case delta(context: AiChatRequestContextSnapshot, text: String)
    case final(response: AiChatResponse)
    case failed(context: AiChatRequestContextSnapshot, reason: AiChatExecutionFailure)
}

public struct AiChatProviderExecutionClient: Sendable {
    public var execute: @Sendable (AiChatRequest, StoredCredentialPayload?) throws
        -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error>

    public nonisolated init(
        execute: @escaping @Sendable (AiChatRequest, StoredCredentialPayload?) throws
            -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error>,
    ) {
        self.execute = execute
    }
}

extension AiChatProviderExecutionClient: DependencyKey {
    public nonisolated static var liveValue: AiChatProviderExecutionClient {
        live()
    }

    public nonisolated static var testValue: AiChatProviderExecutionClient {
        AiChatProviderExecutionClient(
            execute: { request, credential in
                let result = try AiChatProviderPreflight.prepare(request, credential: credential)
                return preparedStream(result.payload)
            },
        )
    }

    public nonisolated static var previewValue: AiChatProviderExecutionClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var aiChatProviderExecutionClient: AiChatProviderExecutionClient {
        get { self[AiChatProviderExecutionClient.self] }
        set { self[AiChatProviderExecutionClient.self] = newValue }
    }
}

public extension AiChatProviderExecutionClient {
    nonisolated static func live(
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) },
    ) -> AiChatProviderExecutionClient {
        live(session: session, now: now, codexExecutor: executeCodexCLI)
    }

    internal nonisolated static func live(
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) },
        codexExecutor: @escaping @Sendable (
            _ model: String,
            _ prompt: String,
            _ credential: OAuthCredentialFile,
            _ onDelta: @escaping @Sendable (String) -> Void,
        ) async throws -> String,
    ) -> AiChatProviderExecutionClient {
        AiChatProviderExecutionClient(
            execute: { request, credential in
                let result: AiChatProviderPreflightResult
                do {
                    result = try AiChatProviderPreflight.prepare(request, credential: credential)
                } catch let error as AiChatProviderPreflightError {
                    throw mapPreflightError(error)
                }

                switch result.payload.provider {
                case .openai:
                    return openAIStream(
                        context: request.context,
                        preflight: result,
                        session: session,
                        now: now,
                    )
                case .anthropic:
                    return anthropicStream(
                        context: request.context,
                        preflight: result,
                        session: session,
                        now: now,
                    )
                case .chatgptCodex:
                    return codexStream(
                        context: request.context,
                        preflight: result,
                        now: now,
                        executor: codexExecutor,
                    )
                }
            },
        )
    }
}

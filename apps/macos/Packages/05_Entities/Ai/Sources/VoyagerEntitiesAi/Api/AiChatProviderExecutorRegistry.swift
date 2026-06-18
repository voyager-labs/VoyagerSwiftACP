import Foundation

typealias AiChatProviderCodexExecutor = @Sendable (
    _ model: String,
    _ prompt: String,
    _ thinking: AiChatProviderThinkingPayload?,
    _ credential: OAuthCredentialFile,
    _ onDelta: @escaping @Sendable (String) -> Void,
) async throws -> String

struct AiChatProviderExecutionInput {
    let preflight: AiChatProviderPreflightResult
    let session: URLSession
    let now: @Sendable () -> Int64
    let codexExecutor: AiChatProviderCodexExecutor
}

struct AiChatProviderExecutor {
    var execute: @Sendable (AiChatProviderExecutionInput) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error>

    init(
        execute: @escaping @Sendable (AiChatProviderExecutionInput) -> AsyncThrowingStream<
            AiChatProviderExecutionEvent,
            Error,
        >,
    ) {
        self.execute = execute
    }
}

struct AiChatProviderExecutorRegistry {
    private let executors: [AiProvider: AiChatProviderExecutor]

    var registeredProviders: Set<AiProvider> {
        Set(executors.keys)
    }

    init(executors: [AiProvider: AiChatProviderExecutor]) {
        self.executors = executors
    }

    func executor(for provider: AiProvider) throws -> AiChatProviderExecutor {
        guard let executor = executors[provider] else {
            throw AiChatProviderExecutionClientError.unsupportedProvider(provider)
        }
        return executor
    }

    static func `default`() -> AiChatProviderExecutorRegistry {
        AiChatProviderExecutorRegistry(executors: [
            .openai: AiChatProviderExecutor { input in
                let context = input.preflight.executionContext
                NSLog(
                    "[AiChatProviderExecution] Starting OpenAI stream requestID=%@",
                    context.requestID.rawValue.uuidString,
                )
                return AiChatProviderExecutionClient.openAIStream(
                    context: context,
                    preflight: input.preflight,
                    session: input.session,
                    now: input.now,
                )
            },
            .anthropic: AiChatProviderExecutor { input in
                let context = input.preflight.executionContext
                NSLog(
                    "[AiChatProviderExecution] Starting Anthropic stream requestID=%@",
                    context.requestID.rawValue.uuidString,
                )
                return AiChatProviderExecutionClient.anthropicStream(
                    context: context,
                    preflight: input.preflight,
                    session: input.session,
                    now: input.now,
                )
            },
            .chatgptCodex: AiChatProviderExecutor { input in
                let context = input.preflight.executionContext
                NSLog(
                    "[AiChatProviderExecution] Starting Codex execution requestID=%@",
                    context.requestID.rawValue.uuidString,
                )
                return AiChatProviderExecutionClient.codexStream(
                    context: context,
                    preflight: input.preflight,
                    now: input.now,
                    executor: input.codexExecutor,
                )
            },
        ])
    }
}

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
        codexExecutor: @escaping AiChatProviderCodexExecutor = executeCodexCLI,
        registry: AiChatProviderExecutorRegistry? = nil,
    ) -> AiChatProviderExecutionClient {
        let executorRegistry = registry ?? .default(session: session, now: now, codexExecutor: codexExecutor)
        return AiChatProviderExecutionClient(
            execute: { request, credential in
                NSLog(
                    "[AiChatProviderExecution] Preparing provider request provider=%@ model=%@ requestID=%@ credentialPresent=%@",
                    request.context.provider.rawValue,
                    request.context.selectedModel?.rawModelID ?? request.context.model.rawValue,
                    request.context.requestID.rawValue.uuidString,
                    String(credential != nil),
                )

                let result: AiChatProviderPreflightResult
                do {
                    result = try AiChatProviderPreflight.prepare(request, credential: credential)
                } catch let error as AiChatProviderPreflightError {
                    NSLog(
                        "[AiChatProviderExecution] Provider preflight failed provider=%@ model=%@ requestID=%@ reason=%@",
                        request.context.provider.rawValue,
                        request.context.selectedModel?.rawModelID ?? request.context.model.rawValue,
                        request.context.requestID.rawValue.uuidString,
                        preflightLogReason(error),
                    )
                    throw mapPreflightError(error)
                }

                NSLog(
                    "[AiChatProviderExecution] Provider request prepared provider=%@ model=%@ requestID=%@ parts=%ld messages=%ld",
                    result.payload.provider.rawValue,
                    result.payload.rawModelID,
                    request.context.requestID.rawValue.uuidString,
                    result.payload.context.requestContext.parts.count,
                    result.payload.messages.count,
                )

                let executor = try executorRegistry.executor(for: result.payload.provider)
                return executor.execute(AiChatProviderExecutionInput(
                    preflight: result,
                    session: session,
                    now: now,
                    codexExecutor: codexExecutor,
                ))
            },
        )
    }
}

private func preflightLogReason(_ error: AiChatProviderPreflightError) -> String {
    switch error {
    case let .missingCredential(provider):
        "missingCredential(\(provider.rawValue))"
    case let .invalidCredential(provider, expected):
        "invalidCredential(\(provider.rawValue), expected: \(expected.rawValue))"
    case let .loweringFailed(error):
        "loweringFailed(\(loweringLogReason(error)))"
    }
}

private func loweringLogReason(_ error: AiChatProviderRequestLoweringError) -> String {
    switch error {
    case let .modelProviderMismatch(requestProvider, modelProvider):
        "modelProviderMismatch(request: \(requestProvider.rawValue), model: \(modelProvider.rawValue))"
    case let .missingModelID(provider):
        "missingModelID(\(provider.rawValue))"
    }
}

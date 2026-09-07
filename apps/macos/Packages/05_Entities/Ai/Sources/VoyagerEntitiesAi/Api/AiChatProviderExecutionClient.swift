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
    case status(context: AiChatRequestContextSnapshot, signal: AiChatExecutionActivitySignal)
    case final(response: AiChatResponse)
    case failed(context: AiChatRequestContextSnapshot, reason: AiChatExecutionFailure)
}

public struct AiChatProviderExecutionClient: Sendable {
    public var execute: @Sendable (AiChatRequest, StoredCredentialPayload?) throws
        -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error>
    let codexControllerIdentity: ObjectIdentifier?

    nonisolated public init(
        execute: @escaping @Sendable (AiChatRequest, StoredCredentialPayload?) throws
            -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error>,
    ) {
        self.execute = execute
        codexControllerIdentity = nil
    }

    init(
        execute: @escaping @Sendable (AiChatRequest, StoredCredentialPayload?) throws
            -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error>,
        codexControllerIdentity: ObjectIdentifier,
    ) {
        self.execute = execute
        self.codexControllerIdentity = codexControllerIdentity
    }
}

extension AiChatProviderExecutionClient: DependencyKey {
    nonisolated public static var liveValue: AiChatProviderExecutionClient {
        live()
    }

    nonisolated public static var testValue: AiChatProviderExecutionClient {
        AiChatProviderExecutionClient(
            execute: { request, credential in
                let result = try AiChatProviderPreflight.prepare(request, credential: credential)
                return preparedStream(result.payload)
            },
        )
    }

    nonisolated public static var previewValue: AiChatProviderExecutionClient {
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
        live(session: session, now: now, codexExecutor: nil, composition: .live)
    }

    nonisolated internal static func live(
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) },
        codexExecutor: AiChatProviderCodexExecutor? = nil,
        registry: AiChatProviderExecutorRegistry? = nil,
        composition: CodexExecLiveComposition? = nil,
    ) -> AiChatProviderExecutionClient {
        let liveComposition = composition ?? .live
        let codexExecution = codexExecutor ?? liveComposition.executeLegacy
        let executorRegistry = registry ?? .default()
        let client = AiChatProviderExecutionClient(
            execute: { request, credential in
                NSLog(
                    "[AiChatProviderExecution] Preparing provider request provider=%@ model=%@ "
                        + "requestID=%@ credentialPresent=%@",
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
                        "[AiChatProviderExecution] Provider preflight failed provider=%@ model=%@ "
                            + "requestID=%@ reason=%@",
                        request.context.provider.rawValue,
                        request.context.selectedModel?.rawModelID ?? request.context.model.rawValue,
                        request.context.requestID.rawValue.uuidString,
                        preflightLogReason(error),
                    )
                    throw mapPreflightError(error)
                }

                NSLog(
                    "[AiChatProviderExecution] Provider request prepared provider=%@ model=%@ "
                        + "requestID=%@ parts=%ld messages=%ld",
                    result.payload.provider.rawValue,
                    result.payload.rawModelID,
                    request.context.requestID.rawValue.uuidString,
                    result.payload.context.requestContext.parts.count,
                    result.payload.messages.count,
                )

                let executor = try executorRegistry.executor(for: result.payload.provider)
                let providerStream = executor.execute(AiChatProviderExecutionInput(
                    preflight: result,
                    session: session,
                    now: now,
                    codexExecutor: codexExecution,
                ))
                return streamPreparedFirst(result.payload, providerStream: providerStream)
            },
        )
        guard let composition else { return client }
        return AiChatProviderExecutionClient(
            execute: client.execute,
            codexControllerIdentity: composition.controllerIdentity,
        )
    }
}

private func streamPreparedFirst(
    _ payload: AiChatProviderRequestPayload,
    providerStream: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>,
) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            continuation.yield(.requestPrepared(payload))
            do {
                for try await event in providerStream {
                    if Task.isCancelled { break }
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
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

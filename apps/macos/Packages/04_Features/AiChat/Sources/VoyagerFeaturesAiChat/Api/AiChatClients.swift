import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

public struct AiChatExecutionClient: Sendable {
    public var execute: @Sendable (AiChatRequest, StoredCredentialPayload?) -> AsyncStream<AiChatEvent>

    public init(execute: @escaping @Sendable (AiChatRequest, StoredCredentialPayload?) -> AsyncStream<AiChatEvent>) {
        self.execute = execute
    }

    public init(execute: @escaping @Sendable (AiChatRequest) -> AsyncStream<AiChatEvent>) {
        self.execute = { request, _ in execute(request) }
    }
}

extension AiChatExecutionClient: DependencyKey {
    public nonisolated static var liveValue: AiChatExecutionClient {
        live()
    }

    public nonisolated static var testValue: AiChatExecutionClient {
        AiChatExecutionClient(execute: { _, _ in AsyncStream { $0.finish() } })
    }

    public nonisolated static var previewValue: AiChatExecutionClient {
        AiChatExecutionClient(execute: { _, _ in AsyncStream { $0.finish() } })
    }
}

public extension AiChatExecutionClient {
    nonisolated static func live(
        providerExecutionClient: VoyagerEntitiesAi.AiChatProviderExecutionClient = .liveValue,
    ) -> AiChatExecutionClient {
        AiChatExecutionClient(execute: { request, credential in
            let providerStream: AsyncThrowingStream<VoyagerEntitiesAi.AiChatProviderExecutionEvent, Error>
            do {
                providerStream = try providerExecutionClient.execute(request, credential)
            } catch {
                return immediateFailureStream(context: request.context, error: error)
            }

            return AsyncStream { continuation in
                let task = Task {
                    do {
                        for try await event in providerStream {
                            if Task.isCancelled {
                                break
                            }

                            switch event {
                            case .requestPrepared:
                                continue
                            case let .started(context):
                                continuation.yield(.started(context: context))
                            case let .delta(context, text):
                                await emitDisplayDelta(
                                    context: context,
                                    text: text,
                                    continuation: continuation,
                                )
                            case let .final(response):
                                continuation.yield(.final(response: response))
                            case let .failed(context, reason):
                                continuation.yield(.failed(context: context, reason: reason))
                            }
                        }
                    } catch {
                        if !Task.isCancelled {
                            continuation.yield(.failed(context: request.context, reason: mapExecutionError(error)))
                        }
                    }
                    continuation.finish()
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        })
    }
}

private extension AiChatExecutionClient {
    static func immediateFailureStream(
        context: AiChatRequestContextSnapshot,
        error: Error,
    ) -> AsyncStream<AiChatEvent> {
        AsyncStream { continuation in
            continuation.yield(.failed(context: context, reason: mapExecutionError(error)))
            continuation.finish()
        }
    }

    static func emitDisplayDelta(
        context: AiChatRequestContextSnapshot,
        text: String,
        continuation: AsyncStream<AiChatEvent>.Continuation,
    ) async {
        guard context.provider == .anthropic else {
            continuation.yield(.delta(context: context, text: text))
            return
        }

        for chunk in anthropicDisplayChunks(from: text) {
            if Task.isCancelled { return }
            continuation.yield(.delta(context: context, text: chunk))
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
    }

    static func anthropicDisplayChunks(from text: String) -> [String] {
        let chunkSize = 24
        guard text.count > chunkSize else { return text.isEmpty ? [] : [text] }

        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start ..< end]))
            start = end
        }
        return chunks
    }

    static func mapExecutionError(_ error: Error) -> AiChatExecutionFailure {
        if error is CancellationError {
            return .cancelled
        }
        if let error = error as? VoyagerEntitiesAi.AiChatProviderExecutionClientError {
            switch error {
            case .missingCredential, .invalidCredential:
                return .authentication
            case .unsupportedProvider:
                return .unsupportedProvider
            case .loweringFailed:
                return .invalidRequest
            }
        }
        return .unknown
    }
}

public extension DependencyValues {
    nonisolated var aiChatExecutionClient: AiChatExecutionClient {
        get { self[AiChatExecutionClient.self] }
        set { self[AiChatExecutionClient.self] = newValue }
    }
}

public struct AiChatSessionPersistenceClient: Sendable {
    public var loadSession: @Sendable (AiChatSessionID) async throws -> AiChatSessionSnapshot?
    public var saveSession: @Sendable (AiChatSessionSnapshot) async throws -> Void
    public var deleteSession: @Sendable (AiChatSessionID) async throws -> Void

    public init(
        loadSession: @escaping @Sendable (AiChatSessionID) async throws -> AiChatSessionSnapshot?,
        saveSession: @escaping @Sendable (AiChatSessionSnapshot) async throws -> Void,
        deleteSession: @escaping @Sendable (AiChatSessionID) async throws -> Void,
    ) {
        self.loadSession = loadSession
        self.saveSession = saveSession
        self.deleteSession = deleteSession
    }
}

extension AiChatSessionPersistenceClient: DependencyKey {
    public nonisolated static var liveValue: AiChatSessionPersistenceClient {
        AiChatSessionPersistenceClient(
            loadSession: { _ in nil },
            saveSession: { _ in },
            deleteSession: { _ in },
        )
    }

    public nonisolated static var testValue: AiChatSessionPersistenceClient {
        AiChatSessionPersistenceClient(
            loadSession: { _ in nil },
            saveSession: { _ in },
            deleteSession: { _ in },
        )
    }

    public nonisolated static var previewValue: AiChatSessionPersistenceClient {
        AiChatSessionPersistenceClient(
            loadSession: { _ in nil },
            saveSession: { _ in },
            deleteSession: { _ in },
        )
    }
}

public extension DependencyValues {
    nonisolated var aiChatSessionPersistenceClient: AiChatSessionPersistenceClient {
        get { self[AiChatSessionPersistenceClient.self] }
        set { self[AiChatSessionPersistenceClient.self] = newValue }
    }
}

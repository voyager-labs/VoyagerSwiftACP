import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerShared

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
    nonisolated public static var liveValue: AiChatExecutionClient {
        live()
    }

    nonisolated public static var testValue: AiChatExecutionClient {
        AiChatExecutionClient(execute: { _, _ in AsyncStream { $0.finish() } })
    }

    nonisolated public static var previewValue: AiChatExecutionClient {
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

                            if let mappedEvent = mapProviderEvent(event) {
                                continuation.yield(mappedEvent)
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
    static func mapProviderEvent(_ event: VoyagerEntitiesAi.AiChatProviderExecutionEvent) -> AiChatEvent? {
        switch event {
        case .requestPrepared:
            nil
        case let .started(context):
            .started(context: context)
        case let .delta(context, text):
            .delta(context: context, text: text)
        case let .status(context, signal):
            .status(context: context, signal: signal)
        case let .final(response):
            .final(response: response)
        case let .failed(context, reason):
            .failed(context: context, reason: reason)
        }
    }

    static func immediateFailureStream(
        context: AiChatRequestContextSnapshot,
        error: Error,
    ) -> AsyncStream<AiChatEvent> {
        AsyncStream { continuation in
            continuation.yield(.failed(context: context, reason: mapExecutionError(error)))
            continuation.finish()
        }
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

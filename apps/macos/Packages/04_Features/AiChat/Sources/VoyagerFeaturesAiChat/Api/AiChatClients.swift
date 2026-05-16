import ComposableArchitecture
import VoyagerEntitiesAi

public struct AiChatExecutionClient: Sendable {
    public var execute: @Sendable (AiChatRequest) -> AsyncStream<AiChatEvent>

    public init(execute: @escaping @Sendable (AiChatRequest) -> AsyncStream<AiChatEvent>) {
        self.execute = execute
    }
}

private let aiChatMockAssistantMessageContent = """
Voyager AI
Context checked.
Plan ready.
Provider later.
✓ Context
✓ Queued
★ Mock ready
"""

private func makeMockAiChatResponse(for request: AiChatRequest) -> AiChatResponse {
    AiChatResponse(
        context: request.context,
        assistantMessage: AiChatMessage(role: .assistant, content: aiChatMockAssistantMessageContent),
        completedAtMs: 0
    )
}

extension AiChatExecutionClient: DependencyKey {
    public nonisolated static var liveValue: AiChatExecutionClient {
        AiChatExecutionClient(execute: { request in
            AsyncStream { continuation in
                continuation.yield(.started(context: request.context))
                continuation.yield(.final(response: makeMockAiChatResponse(for: request)))
                continuation.finish()
            }
        })
    }

    public nonisolated static var testValue: AiChatExecutionClient {
        AiChatExecutionClient(execute: { _ in AsyncStream { $0.finish() } })
    }

    public nonisolated static var previewValue: AiChatExecutionClient {
        AiChatExecutionClient(execute: { _ in AsyncStream { $0.finish() } })
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
        deleteSession: @escaping @Sendable (AiChatSessionID) async throws -> Void
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
            deleteSession: { _ in }
        )
    }

    public nonisolated static var testValue: AiChatSessionPersistenceClient {
        AiChatSessionPersistenceClient(
            loadSession: { _ in nil },
            saveSession: { _ in },
            deleteSession: { _ in }
        )
    }

    public nonisolated static var previewValue: AiChatSessionPersistenceClient {
        AiChatSessionPersistenceClient(
            loadSession: { _ in nil },
            saveSession: { _ in },
            deleteSession: { _ in }
        )
    }
}

public extension DependencyValues {
    nonisolated var aiChatSessionPersistenceClient: AiChatSessionPersistenceClient {
        get { self[AiChatSessionPersistenceClient.self] }
        set { self[AiChatSessionPersistenceClient.self] = newValue }
    }
}

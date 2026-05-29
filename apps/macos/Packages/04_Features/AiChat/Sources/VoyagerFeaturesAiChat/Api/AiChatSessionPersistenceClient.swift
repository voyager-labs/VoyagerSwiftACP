import ComposableArchitecture
import VoyagerEntitiesAi

public extension DependencyValues {
    nonisolated var aiChatAttachmentResolverClient: AiChatAttachmentResolverClient {
        get { self[AiChatAttachmentResolverClient.self] }
        set { self[AiChatAttachmentResolverClient.self] = newValue }
    }
}

public struct AiChatSessionPersistenceClient: Sendable {
    public var listSessions: @Sendable (Int?, String?) async throws -> [AiChatSessionSummary]
    public var loadSession: @Sendable (AiChatSessionID) async throws -> AiChatSessionSnapshot?
    public var saveSession: @Sendable (AiChatSessionSnapshot) async throws -> Void
    public var deleteSession: @Sendable (AiChatSessionID) async throws -> Void

    public init(
        listSessions: @escaping @Sendable (Int?, String?) async throws -> [AiChatSessionSummary] = { _, _ in [] },
        loadSession: @escaping @Sendable (AiChatSessionID) async throws -> AiChatSessionSnapshot?,
        saveSession: @escaping @Sendable (AiChatSessionSnapshot) async throws -> Void,
        deleteSession: @escaping @Sendable (AiChatSessionID) async throws -> Void,
    ) {
        self.listSessions = listSessions
        self.loadSession = loadSession
        self.saveSession = saveSession
        self.deleteSession = deleteSession
    }
}

public extension AiChatSessionPersistenceClient {
    nonisolated static func live(
        persistenceClient: any VoyagerEntitiesAi.AiChatSessionPersistenceClientProtocol,
    ) -> AiChatSessionPersistenceClient {
        AiChatSessionPersistenceClient(
            listSessions: { limit, query in
                try await persistenceClient.listSessions(limit: limit, query: query)
            },
            loadSession: { id in
                try await persistenceClient.loadSession(id: id)
            },
            saveSession: { snapshot in
                try await persistenceClient.saveSession(snapshot)
            },
            deleteSession: { id in
                try await persistenceClient.deleteSession(id: id)
            },
        )
    }

    nonisolated static func unavailable(
        error: VoyagerEntitiesAi.AiChatSessionPersistenceClientError = .applicationSupportDirectoryUnavailable,
    ) -> AiChatSessionPersistenceClient {
        AiChatSessionPersistenceClient(
            listSessions: { _, _ in throw error },
            loadSession: { _ in throw error },
            saveSession: { _ in throw error },
            deleteSession: { _ in throw error },
        )
    }
}

extension AiChatSessionPersistenceClient: DependencyKey {
    public nonisolated static var liveValue: AiChatSessionPersistenceClient {
        do {
            return try .live(persistenceClient: VoyagerEntitiesAi.AiChatSessionFileStore())
        } catch let error as VoyagerEntitiesAi.AiChatSessionPersistenceClientError {
            return .unavailable(error: error)
        } catch {
            return .unavailable()
        }
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

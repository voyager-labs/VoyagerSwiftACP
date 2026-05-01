import Foundation

public protocol AiChatExecutionClientProtocol: Sendable {
    func execute(_ request: AiChatRequest) -> AsyncStream<AiChatEvent>
}

public protocol AiChatSessionPersistenceClientProtocol: Sendable {
    func loadSession(id: AiChatSessionID) async -> AiChatSessionSnapshot?
    func saveSession(_ snapshot: AiChatSessionSnapshot) async
    func deleteSession(id: AiChatSessionID) async
}

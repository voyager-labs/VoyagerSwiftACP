@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatSessionFileStoreTests: XCTestCase {
    func testSaveSessionKeepsNewerSnapshotWhenOlderRequestStartFinishesLater() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiChatSessionFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = try AiChatSessionFileStore(rootDirectoryURL: directoryURL)
        let sessionID = AiChatSessionID(rawValue: UUID())
        let model = AiModelHandle(provider: .openai, rawValue: "gpt-test")
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 2,
        )
        let olderRequestStartSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
            ],
            updatedAtMs: 1,
        )

        try await store.saveSession(finalSnapshot)
        try await store.saveSession(olderRequestStartSnapshot)

        let loadedSnapshot = try await store.loadSession(id: sessionID)
        let restored = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(restored.updatedAtMs, 2)
        XCTAssertEqual(restored.transcriptHistory.map(\.content), ["test", "done"])
    }
}

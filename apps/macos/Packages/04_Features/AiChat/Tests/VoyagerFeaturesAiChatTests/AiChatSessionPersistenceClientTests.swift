import Foundation
@testable import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

final class AiChatSessionPersistenceClientTests: XCTestCase {
    func testLiveAdapterDelegatesToEntityPersistenceClient() async throws {
        let stub = StubSessionPersistenceClient()
        let sessionID = AiChatSessionID(rawValue: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!)
        let snapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: .anthropic,
            model: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-20250514"),
            transcriptHistory: [AiChatMessage(role: .user, content: "Restore me")],
            updatedAtMs: 500
        )
        await stub.setLoadResult(snapshot)
        await stub.setListResult([AiChatSessionSummary(snapshot: snapshot)])

        let client = AiChatSessionPersistenceClient.live(persistenceClient: stub)

        let listed = try await client.listSessions(10, "restore")
        let loaded = try await client.loadSession(sessionID)
        try await client.saveSession(snapshot)
        try await client.deleteSession(sessionID)

        let listCalls = await stub.listCallsSnapshot()
        let savedSnapshots = await stub.savedSnapshotsSnapshot()
        let deletedIDs = await stub.deletedIDsSnapshot()

        XCTAssertEqual(listed, [AiChatSessionSummary(snapshot: snapshot)])
        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(listCalls, [.init(limit: 10, query: "restore")])
        XCTAssertEqual(savedSnapshots, [snapshot])
        XCTAssertEqual(deletedIDs, [sessionID])
    }
}

private actor StubSessionPersistenceClient: AiChatSessionPersistenceClientProtocol {
    struct ListCall: Equatable {
        let limit: Int?
        let query: String?
    }

    private var listCalls: [ListCall] = []
    private var savedSnapshots: [AiChatSessionSnapshot] = []
    private var deletedIDs: [AiChatSessionID] = []
    private var listResult: [AiChatSessionSummary] = []
    private var loadResult: AiChatSessionSnapshot?

    func setListResult(_ value: [AiChatSessionSummary]) {
        listResult = value
    }

    func setLoadResult(_ value: AiChatSessionSnapshot?) {
        loadResult = value
    }

    func listCallsSnapshot() -> [ListCall] {
        listCalls
    }

    func savedSnapshotsSnapshot() -> [AiChatSessionSnapshot] {
        savedSnapshots
    }

    func deletedIDsSnapshot() -> [AiChatSessionID] {
        deletedIDs
    }

    func listSessions(limit: Int?, query: String?) async throws -> [AiChatSessionSummary] {
        listCalls.append(.init(limit: limit, query: query))
        return listResult
    }

    func loadSession(id _: AiChatSessionID) async throws -> AiChatSessionSnapshot? {
        loadResult
    }

    func saveSession(_ snapshot: AiChatSessionSnapshot) async throws {
        savedSnapshots.append(snapshot)
    }

    func deleteSession(id: AiChatSessionID) async throws {
        deletedIDs.append(id)
    }
}

import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatSessionStoreTests: XCTestCase {
    func testAiChatSessionSummary_roundTripsAndDerivesFromSnapshot() throws {
        let snapshot = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            userPrompt: "   Summarize\nthese\tdiffs please   ",
            assistantReply: "Final answer with useful detail.",
            updatedAtMs: 1_700_000_000_123,
            status: .completed,
            contextSummary: "Workspace / Docs",
        )

        let derived = AiChatSessionSummary(snapshot: snapshot)
        let roundTripped = try JSONDecoder().decode(AiChatSessionSummary.self, from: JSONEncoder().encode(derived))

        XCTAssertEqual(roundTripped, derived)
        XCTAssertEqual(derived.sessionID, snapshot.sessionID)
        XCTAssertEqual(derived.title, "Summarize these diffs please")
        XCTAssertEqual(derived.preview, "Final answer with useful detail.")
        XCTAssertEqual(derived.messageCount, 2)
        XCTAssertEqual(derived.contextTitle, "Workspace / Docs")
        XCTAssertEqual(derived.searchText, "Summarize these diffs please Final answer with useful detail.")
        XCTAssertEqual(derived.provider, .openai)
        XCTAssertEqual(derived.model, snapshot.model)
        XCTAssertEqual(derived.createdAtMs, snapshot.updatedAtMs)
        XCTAssertEqual(derived.updatedAtMs, snapshot.updatedAtMs)
        XCTAssertEqual(derived.status, .completed)
    }

    func testAiChatSessionSummary_derivesShortAutomaticTitleWhileKeepingPromptPreview() throws {
        let longPrompt = """
        Can you explain how the sidebar session title should behave while the assistant response is still \
        streaming, especially when the history list reloads before the final answer is saved?
        """
        let snapshot = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")),
            userPrompt: longPrompt,
            assistantReply: "",
            updatedAtMs: 800,
            status: .active,
        )

        let summary = AiChatSessionSummary(snapshot: snapshot)

        XCTAssertEqual(summary.title, "Can you explain how the")
        XCTAssertEqual(summary.preview?.hasPrefix("Can you explain how the sidebar session title should behave"), true)
        XCTAssertNotEqual(summary.preview, summary.title)
        XCTAssertLessThanOrEqual(summary.title.count, 32)
    }

    func testAiChatSessionStore_saveThenListOrdersByUpdatedAtDescending() async throws {
        let store = try makeStore()
        let older = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            userPrompt: "Older question",
            assistantReply: "Older answer",
            updatedAtMs: 100,
        )
        let newer = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            userPrompt: "Newer question",
            assistantReply: "Newer answer",
            updatedAtMs: 200,
        )

        try await store.saveSession(older)
        try await store.saveSession(newer)

        let summaries = try await store.listSessions(limit: nil, query: nil)

        XCTAssertEqual(summaries.map(\.sessionID), [newer.sessionID, older.sessionID])
        XCTAssertEqual(summaries.map(\.updatedAtMs), [200, 100])
    }

    func testAiChatSessionStore_queryMatchesFullTranscriptContent() async throws {
        let store = try makeStore()
        let transcriptOnlyMatch = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "99999999-9999-9999-9999-999999999999")),
            userPrompt: "Initial question",
            assistantReply: "Final reply",
            updatedAtMs: 500,
            extraMessages: [
                AiChatMessage(role: .assistant, content: "The hidden migration keyword appears in the middle."),
            ],
        )
        let nonMatch = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")),
            userPrompt: "Design sync",
            assistantReply: "Spacing only",
            updatedAtMs: 400,
        )

        try await store.saveSession(transcriptOnlyMatch)
        try await store.saveSession(nonMatch)

        let summaries = try await store.listSessions(limit: nil, query: "  migration  ")

        XCTAssertEqual(summaries.map(\.sessionID), [transcriptOnlyMatch.sessionID])
    }

    func testAiChatSessionSummary_prefersCustomTitleOverDerivedTitle() throws {
        let snapshot = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")),
            userPrompt: "Original prompt",
            assistantReply: "Original answer",
            updatedAtMs: 600,
            customTitle: "  Renamed Release Chat  ",
        )

        let summary = AiChatSessionSummary(snapshot: snapshot)

        XCTAssertEqual(summary.title, "Renamed Release Chat")
    }

    func testAiChatSessionStore_queryMatchesCustomTitle() async throws {
        let store = try makeStore()
        let customTitleMatch = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")),
            userPrompt: "Original prompt",
            assistantReply: "Original answer",
            updatedAtMs: 700,
            customTitle: "Renamed migration chat",
        )
        let nonMatch = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")),
            userPrompt: "Design sync",
            assistantReply: "Spacing only",
            updatedAtMs: 650,
        )

        try await store.saveSession(customTitleMatch)
        try await store.saveSession(nonMatch)

        let summaries = try await store.listSessions(limit: nil, query: "migration")

        XCTAssertEqual(summaries.map(\.sessionID), [customTitleMatch.sessionID])
        XCTAssertEqual(summaries.first?.title, "Renamed migration chat")
    }

    func testAiChatSessionStore_saveUsesOwnerOnlyPermissions() async throws {
        let store = try makeStore()
        let snapshot = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")),
            userPrompt: "Protect me",
            assistantReply: "Stored safely",
            updatedAtMs: 250,
        )

        try await store.saveSession(snapshot)

        let fileURL = sessionFileURL(for: snapshot.sessionID)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)

        XCTAssertEqual(permissions.intValue, 0o600)
    }

    func testAiChatSessionStore_deleteIsIdempotentAndRemovesFromList() async throws {
        let store = try makeStore()
        let snapshot = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444")),
            userPrompt: "Delete me",
            assistantReply: "Okay",
            updatedAtMs: 300,
        )

        try await store.saveSession(snapshot)
        try await store.deleteSession(id: snapshot.sessionID)
        try await store.deleteSession(id: snapshot.sessionID)

        let summaries = try await store.listSessions(limit: nil, query: nil)
        let loaded = try await store.loadSession(id: snapshot.sessionID)

        XCTAssertTrue(summaries.isEmpty)
        XCTAssertNil(loaded)
    }

    func testAiChatSessionStore_listQuarantinesCorruptRecords() async throws {
        let store = try makeStore()
        let healthy = try makeSnapshot(
            sessionID: XCTUnwrap(UUID(uuidString: "55555555-5555-5555-5555-555555555555")),
            userPrompt: "Healthy",
            assistantReply: "Still here",
            updatedAtMs: 400,
        )
        let try corruptID =
            AiChatSessionID(rawValue: XCTUnwrap(UUID(uuidString: "66666666-6666-6666-6666-666666666666")))

        try await store.saveSession(healthy)
        let corruptFileURL = sessionFileURL(for: corruptID)
        try Data("not-json".utf8).write(to: corruptFileURL)

        let summaries = try await store.listSessions(limit: nil, query: nil)

        XCTAssertEqual(summaries.map(\.sessionID), [healthy.sessionID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptFileURL.path))

        let quarantinedURLs = try quarantineFileURLs(for: corruptID)
        XCTAssertEqual(quarantinedURLs.count, 1)
    }

    func testAiChatSessionStore_loadQuarantinesCorruptRecordAndThrowsCorruptedRecord() async throws {
        let store = try makeStore()
        let try corruptID =
            AiChatSessionID(rawValue: XCTUnwrap(UUID(uuidString: "77777777-7777-7777-7777-777777777777")))
        let corruptFileURL = sessionFileURL(for: corruptID)
        try FileManager.default.createDirectory(
            at: XCTUnwrap(storeRootURL),
            withIntermediateDirectories: true,
        )
        try Data("not-json".utf8).write(to: corruptFileURL)

        do {
            _ = try await store.loadSession(id: corruptID)
            XCTFail("Expected corruptedRecord failure")
        } catch let error as AiChatSessionPersistenceClientError {
            XCTAssertEqual(error, .corruptedRecord(corruptID))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptFileURL.path))

        let quarantinedURLs = try quarantineFileURLs(for: corruptID)
        XCTAssertEqual(quarantinedURLs.count, 1)
    }

    override func tearDownWithError() throws {
        if let storeRootURL {
            try? FileManager.default.removeItem(at: storeRootURL.deletingLastPathComponent())
        }
        storeRootURL = nil
    }

    private var storeRootURL: URL?

    private func makeStore() throws -> AiChatSessionFileStore {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("ai_chat_sessions", isDirectory: true)
        storeRootURL = rootURL
        return try AiChatSessionFileStore(rootDirectoryURL: rootURL)
    }

    private func sessionFileURL(for id: AiChatSessionID) -> URL {
        guard let root = storeRootURL else {
            XCTFail("storeRootURL is nil — makeStore() was not called")
            fatalError("unreachable after XCTFail")
        }
        return root
            .appendingPathComponent(id.rawValue.uuidString)
            .appendingPathExtension("json")
    }

    private func quarantineFileURLs(for id: AiChatSessionID) throws -> [URL] {
        let rootURL = try XCTUnwrap(storeRootURL)
        return try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )
        .filter {
            $0.lastPathComponent.hasPrefix("\(id.rawValue.uuidString).corrupted-")
                && $0.pathExtension == "json"
        }
    }

    private func makeSnapshot(
        sessionID: UUID,
        userPrompt: String,
        assistantReply: String,
        updatedAtMs: Int64,
        status: AiChatSessionStatus = .active,
        customTitle: String? = nil,
        extraMessages: [AiChatMessage] = [],
        contextSummary: String? = nil,
    ) -> AiChatSessionSnapshot {
        AiChatSessionSnapshot(
            sessionID: AiChatSessionID(rawValue: sessionID),
            status: status,
            customTitle: customTitle,
            provider: .openai,
            model: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
            selectedModelRow: AiModelCatalogRow(
                handle: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
                displayName: "GPT-4.1 Mini",
                authMethod: .apiKey,
                sortOrder: 0,
            ),
            transcriptHistory: [AiChatMessage(role: .user, content: userPrompt)]
                + extraMessages
                + [AiChatMessage(role: .assistant, content: assistantReply)],
            lastRequestContext: AiChatLockedRequestContextSnapshot(
                currentContext: AiChatCurrentContextSnapshot(summary: contextSummary),
            ),
            updatedAtMs: updatedAtMs,
        )
    }
}

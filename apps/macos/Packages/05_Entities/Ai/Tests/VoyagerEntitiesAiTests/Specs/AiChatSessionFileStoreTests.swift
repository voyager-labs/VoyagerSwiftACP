@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatSessionFileStoreTests: XCTestCase {
    func testSaveSessionKeepsFinalSnapshotWhenRequestStartHasSameTimestamp() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiChatSessionFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = try AiChatSessionFileStore(rootDirectoryURL: directoryURL)
        let sessionID = AiChatSessionID(rawValue: UUID())
        let requestID = AiChatRequestID(rawValue: UUID())
        let runID = AiChatRunID(rawValue: UUID())
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
            lastRequestID: requestID,
            lastRunID: runID,
            lastRequestContext: AiChatLockedRequestContextSnapshot(),
            updatedAtMs: 2,
        )
        let equalTimestampRequestStartSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
            ],
            lastRequestID: requestID,
            lastRunID: runID,
            updatedAtMs: 2,
        )

        try await store.saveSession(finalSnapshot)
        try await store.saveSession(equalTimestampRequestStartSnapshot)

        let loadedSnapshot = try await store.loadSession(id: sessionID)
        let restored = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(restored.updatedAtMs, 2)
        XCTAssertEqual(restored.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(restored.lastRunID, runID)
        XCTAssertNotNil(restored.lastRequestContext)
    }

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

    func testSaveSessionMergesCustomTitleIntoNewerSnapshotWhenRenameWriteIsStale() async throws {
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
        let staleRenamedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Renamed while generating",
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
            ],
            updatedAtMs: 1,
        )

        try await store.saveSession(finalSnapshot)
        try await store.saveSession(staleRenamedSnapshot)

        let loadedSnapshot = try await store.loadSession(id: sessionID)
        let restored = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(restored.updatedAtMs, 2)
        XCTAssertEqual(restored.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(restored.customTitle, "Renamed while generating")
    }

    func testSaveSessionMergesCustomTitleIntoNewerFinalSnapshotWithRequestMetadata() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiChatSessionFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = try AiChatSessionFileStore(rootDirectoryURL: directoryURL)
        let sessionID = AiChatSessionID(rawValue: UUID())
        let requestID = AiChatRequestID(rawValue: UUID())
        let runID = AiChatRunID(rawValue: UUID())
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
            lastRequestID: requestID,
            lastRunID: runID,
            lastRequestContext: AiChatLockedRequestContextSnapshot(),
            updatedAtMs: 2,
        )
        let staleRenamedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Renamed after final",
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
            ],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1,
        )

        try await store.saveSession(finalSnapshot)
        try await store.saveSession(staleRenamedSnapshot)

        let loadedSnapshot = try await store.loadSession(id: sessionID)
        let restored = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(restored.updatedAtMs, 2)
        XCTAssertEqual(restored.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(restored.lastRequestID, requestID)
        XCTAssertEqual(restored.lastRunID, runID)
        XCTAssertNotNil(restored.lastRequestContext)
        XCTAssertEqual(restored.customTitle, "Renamed after final")
    }

    func testSaveSessionMergesNilCustomTitleIntoNewerSnapshotWhenRenameClearIsStale() async throws {
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
            customTitle: "Old title",
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 2,
        )
        let staleClearedTitleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: nil,
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
            ],
            updatedAtMs: 1,
        )

        try await store.saveSession(finalSnapshot)
        try await store.saveSession(staleClearedTitleSnapshot)

        let loadedSnapshot = try await store.loadSession(id: sessionID)
        let restored = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(restored.updatedAtMs, 2)
        XCTAssertEqual(restored.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertNil(restored.customTitle)
    }

    func testSaveSessionKeepsIncomingCustomTitleForMetadataOnlyRename() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiChatSessionFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = try AiChatSessionFileStore(rootDirectoryURL: directoryURL)
        let sessionID = AiChatSessionID(rawValue: UUID())
        let originalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Old title",
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 2,
        )
        let renamedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "New title",
            provider: nil,
            model: nil,
            transcriptHistory: originalSnapshot.transcriptHistory,
            updatedAtMs: originalSnapshot.updatedAtMs,
        )

        try await store.saveSession(originalSnapshot)
        try await store.saveSession(renamedSnapshot)

        let loadedSnapshot = try await store.loadSession(id: sessionID)
        let restored = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(restored.customTitle, "New title")
        XCTAssertEqual(restored.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(restored.updatedAtMs, 2)
    }

    func testSaveSessionMergesExistingCustomTitleIntoLaterFinalSnapshot() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiChatSessionFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = try AiChatSessionFileStore(rootDirectoryURL: directoryURL)
        let sessionID = AiChatSessionID(rawValue: UUID())
        let requestID = AiChatRequestID(rawValue: UUID())
        let runID = AiChatRunID(rawValue: UUID())
        let model = AiModelHandle(provider: .openai, rawValue: "gpt-test")
        let requestContext = AiChatLockedRequestContextSnapshot()
        let renamedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Renamed while final saving",
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
            ],
            lastRequestID: requestID,
            lastRunID: runID,
            lastRequestContext: requestContext,
            updatedAtMs: 1,
        )
        let laterFinalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: nil,
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: requestID,
            lastRunID: runID,
            lastRequestContext: requestContext,
            updatedAtMs: 2,
        )

        try await store.saveSession(renamedSnapshot)
        try await store.saveSession(laterFinalSnapshot)

        let loadedSnapshot = try await store.loadSession(id: sessionID)
        let restored = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(restored.updatedAtMs, 2)
        XCTAssertEqual(restored.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(restored.customTitle, "Renamed while final saving")
        XCTAssertEqual(restored.lastRequestID, requestID)
        XCTAssertEqual(restored.lastRunID, runID)
        XCTAssertNotNil(restored.lastRequestContext)
    }

    func testSaveSessionDoesNotMergeStaleRequestStartCustomTitleIntoNewerSnapshot() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiChatSessionFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = try AiChatSessionFileStore(rootDirectoryURL: directoryURL)
        let sessionID = AiChatSessionID(rawValue: UUID())
        let requestID = AiChatRequestID(rawValue: UUID())
        let runID = AiChatRunID(rawValue: UUID())
        let model = AiModelHandle(provider: .openai, rawValue: "gpt-test")
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Renamed while generating",
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: requestID,
            lastRunID: runID,
            lastRequestContext: AiChatLockedRequestContextSnapshot(),
            updatedAtMs: 2,
        )
        let staleRequestStartSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: nil,
            provider: .openai,
            model: model,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
            ],
            lastRequestID: requestID,
            lastRunID: runID,
            lastRequestContext: AiChatLockedRequestContextSnapshot(),
            updatedAtMs: 1,
        )

        try await store.saveSession(finalSnapshot)
        let persistedSnapshot = try await store.saveSession(staleRequestStartSnapshot)

        XCTAssertEqual(persistedSnapshot.updatedAtMs, 2)
        XCTAssertEqual(persistedSnapshot.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(persistedSnapshot.customTitle, "Renamed while generating")

        let loadedSnapshot = try await store.loadSession(id: sessionID)
        let restored = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(restored.updatedAtMs, 2)
        XCTAssertEqual(restored.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(restored.customTitle, "Renamed while generating")
        XCTAssertEqual(restored.lastRequestID, requestID)
        XCTAssertEqual(restored.lastRunID, runID)
        XCTAssertNotNil(restored.lastRequestContext)
    }
}

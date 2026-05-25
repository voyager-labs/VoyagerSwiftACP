import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureSessionDeleteTests: XCTestCase {
    func testDeleteSessionSuccessRemovesRowFromAllRowsAndFilteredRows() async {
        let deletedSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
        let keptSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222"))
        let deletedRow = makeDeleteTestSessionSummary(
            sessionID: deletedSessionID,
            title: "Release notes follow-up"
        )
        let keptRow = makeDeleteTestSessionSummary(
            sessionID: keptSessionID,
            title: "Architecture review",
            preview: "Backend design",
            contextTitle: "Backend"
        )
        let deletedIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(
                allRows: [deletedRow, keptRow],
                query: "release",
                selectedSessionID: deletedSessionID
            )
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { id in
                    deletedIDs.withValue { $0.append(id) }
                }
            )
        }

        await store.send(.deleteSessionTapped(deletedSessionID))

        await store.receive(.sessionDeleteSucceeded(deletedSessionID)) { state in
            state.sessionList.allRows = [keptRow]
            state.sessionList.rows = []
            state.sessionList.selectedSessionID = nil
        }

        XCTAssertEqual(deletedIDs.value, [deletedSessionID])
    }

    func testDeleteSessionFailureLeavesRowAndSetsListError() async {
        let deletedSessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let deletedRow = makeDeleteTestSessionSummary(sessionID: deletedSessionID)

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [deletedRow], selectedSessionID: deletedSessionID)
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in throw AiChatSessionPersistenceClientError.applicationSupportDirectoryUnavailable }
            )
        }

        await store.send(.deleteSessionTapped(deletedSessionID))

        await store.receive(.sessionDeleteFailed(deletedSessionID, "That chat could not be deleted right now.")) { state in
            state.sessionList.errorMessage = "That chat could not be deleted right now."
        }

        XCTAssertEqual(store.state.sessionList.allRows, [deletedRow])
        XCTAssertEqual(store.state.sessionList.rows, [deletedRow])
        XCTAssertEqual(store.state.sessionList.selectedSessionID, deletedSessionID)
    }

    func testDeleteCurrentLoadedSessionFromSessionsModeLeavesChatStateIntact() async {
        let activeSessionID = AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444"))
        let activeRow = makeDeleteTestSessionSummary(sessionID: activeSessionID, title: "Live chat")
        let transcript = [
            AiChatMessage(role: .user, content: "What changed?"),
            AiChatMessage(role: .assistant, content: "Here is the summary.")
        ]
        let currentContext = makeContextSnapshot(summary: "Current docs")
        let catalogRows = makeCatalogRows()

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: activeSessionID,
            restoreOutcome: .restored(snapshot: AiChatSessionSnapshot(
                sessionID: activeSessionID,
                status: .active,
                provider: catalogRows[0].handle.provider,
                model: catalogRows[0].handle,
                selectedModelRow: catalogRows[0],
                transcriptHistory: transcript,
                updatedAtMs: 1
            )),
            mode: .sessions,
            sessionList: .init(allRows: [activeRow], selectedSessionID: activeSessionID),
            sessionID: activeSessionID,
            sessionStatus: .active,
            currentContext: currentContext,
            transcriptHistory: transcript,
            draftText: "Keep this draft",
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: catalogRows[0].handle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in }
            )
        }

        await store.send(.deleteSessionTapped(activeSessionID)) { state in
            state.sessionList.errorMessage = nil
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionList.selectedSessionID = nil
        }

        await store.receive(.sessionDeleteSucceeded(activeSessionID)) { state in
            state.sessionList.allRows = []
            state.sessionList.rows = []
        }

        XCTAssertEqual(store.state.mode, AiChatMode.sessions)
        XCTAssertEqual(store.state.sessionID, activeSessionID)
        XCTAssertEqual(store.state.sessionStatus, AiChatSessionStatus.active)
        XCTAssertEqual(store.state.transcriptHistory, transcript)
        XCTAssertEqual(store.state.draftText, "Keep this draft")
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[0].handle)
    }
    func testRenameSessionSuccessPersistsCustomTitleAndUpdatesFilteredRows() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555"))
        let originalRow = makeDeleteTestSessionSummary(sessionID: sessionID, title: "Original derived title")
        let snapshot = makeRenameTestSnapshot(sessionID: sessionID)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [originalRow], query: "renamed"),
            sessionID: sessionID,
            currentSessionCustomTitle: nil
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in id == sessionID ? snapshot : nil },
                saveSession: { snapshot in savedSnapshots.withValue { $0.append(snapshot) } },
                deleteSession: { _ in }
            )
        }

        await store.send(.renameSessionTapped(sessionID)) { state in
            state.sessionList.renamingSessionID = sessionID
            state.sessionList.renameDraftText = "Original derived title"
        }

        await store.send(.renameSessionTitleChanged("  Renamed chat  ")) { state in
            state.sessionList.renameDraftText = "  Renamed chat  "
        }

        let expectedSnapshot = makeRenamedSnapshot(snapshot, renamedTo: "  Renamed chat  ")
        let expectedSummary = AiChatSessionSummary(snapshot: expectedSnapshot)

        await store.send(.renameSessionConfirmed)

        await store.receive(.sessionRenameSucceeded(expectedSummary, customTitle: "Renamed chat")) { state in
            state.sessionList.allRows = [expectedSummary]
            state.sessionList.rows = [expectedSummary]
            state.sessionList.renamingSessionID = nil
            state.sessionList.renameDraftText = ""
            state.currentSessionCustomTitle = "Renamed chat"
        }

        XCTAssertEqual(savedSnapshots.value, [expectedSnapshot])
    }

    func testRenameSessionBlankTitleClearsCustomTitleAndFallsBackToDerivedTitle() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("66666666-6666-6666-6666-666666666666"))
        let originalRow = makeDeleteTestSessionSummary(sessionID: sessionID, title: "Custom title")
        let snapshot = makeRenameTestSnapshot(sessionID: sessionID, customTitle: "Custom title")
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [originalRow])
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in id == sessionID ? snapshot : nil },
                saveSession: { snapshot in savedSnapshots.withValue { $0.append(snapshot) } },
                deleteSession: { _ in }
            )
        }

        await store.send(.renameSessionTapped(sessionID)) { state in
            state.sessionList.renamingSessionID = sessionID
            state.sessionList.renameDraftText = "Custom title"
        }

        await store.send(.renameSessionTitleChanged("   ")) { state in
            state.sessionList.renameDraftText = "   "
        }

        let expectedSnapshot = makeRenamedSnapshot(snapshot, renamedTo: "   ")
        let expectedSummary = AiChatSessionSummary(snapshot: expectedSnapshot)

        await store.send(.renameSessionConfirmed)

        await store.receive(.sessionRenameSucceeded(expectedSummary, customTitle: nil)) { state in
            state.sessionList.allRows = [expectedSummary]
            state.sessionList.rows = [expectedSummary]
            state.sessionList.renamingSessionID = nil
            state.sessionList.renameDraftText = ""
        }

        XCTAssertNil(savedSnapshots.value.first?.customTitle)
        XCTAssertEqual(expectedSummary.title, "Original prompt")
    }

    func testRenameSessionFailureKeepsEditorOpenAndSetsListError() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("77777777-7777-7777-7777-777777777777"))
        let row = makeDeleteTestSessionSummary(sessionID: sessionID, title: "Original derived title")

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [row], renamingSessionID: sessionID, renameDraftText: "Rename fails")
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in throw AiChatSessionPersistenceClientError.applicationSupportDirectoryUnavailable },
                saveSession: { _ in },
                deleteSession: { _ in }
            )
        }

        await store.send(.renameSessionConfirmed)

        await store.receive(.sessionRenameFailed(sessionID, "That chat could not be renamed right now.")) { state in
            state.sessionList.errorMessage = "That chat could not be renamed right now."
        }

        XCTAssertEqual(store.state.sessionList.renamingSessionID, sessionID)
        XCTAssertEqual(store.state.sessionList.renameDraftText, "Rename fails")
    }

}


private func makeDeleteTestSessionSummary(
    sessionID: AiChatSessionID,
    title: String = "Release notes follow-up",
    preview: String? = "Need the latest diff summary.",
    messageCount: Int = 2,
    contextTitle: String? = "Release docs",
    provider: AiProvider = .openai,
    model: AiModelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
    createdAtMs: Int64 = 1_000,
    updatedAtMs: Int64 = 2_000,
    status: AiChatSessionStatus = .active
) -> AiChatSessionSummary {
    AiChatSessionSummary(
        sessionID: sessionID,
        title: title,
        preview: preview,
        messageCount: messageCount,
        contextTitle: contextTitle,
        provider: provider,
        model: model,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs,
        status: status
    )
}


private func makeRenameTestSnapshot(
    sessionID: AiChatSessionID,
    customTitle: String? = nil
) -> AiChatSessionSnapshot {
    let handle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
    return AiChatSessionSnapshot(
        sessionID: sessionID,
        status: .active,
        customTitle: customTitle,
        provider: .openai,
        model: handle,
        selectedModelRow: AiModelCatalogRow(
            handle: handle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 0
        ),
        transcriptHistory: [
            AiChatMessage(role: .user, content: "Original prompt"),
            AiChatMessage(role: .assistant, content: "Original answer")
        ],
        updatedAtMs: 3_000
    )
}


private func makeRenamedSnapshot(
    _ snapshot: AiChatSessionSnapshot,
    renamedTo title: String
) -> AiChatSessionSnapshot {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return AiChatSessionSnapshot(
        sessionID: snapshot.sessionID,
        status: snapshot.status,
        customTitle: trimmed.isEmpty ? nil : trimmed,
        provider: snapshot.provider,
        model: snapshot.model,
        selectedModelRow: snapshot.selectedModelRow,
        selectedThinking: snapshot.selectedThinking,
        transcriptHistory: snapshot.transcriptHistory,
        lastRequestID: snapshot.lastRequestID,
        lastRunID: snapshot.lastRunID,
        lastRequestContext: snapshot.lastRequestContext,
        updatedAtMs: snapshot.updatedAtMs
    )
}

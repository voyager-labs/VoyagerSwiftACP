import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureSessionListTests: XCTestCase {
    func testNewChatTappedKeepsModelUnselectedAndSavesDraftWhenNoSelectedModelIsSet() async {
        let catalogRows = makeCatalogRows()
        let currentContext = makeContextSnapshot(summary: "Release docs")
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            currentContext: currentContext,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: nil,
            selectedThinking: nil,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_000))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                },
                deleteSession: { _ in },
            )
        }

        await store.send(.newChatTapped) { state in
            applySessionListNewChatStarted(&state, sessionID: newSessionID)
        }

        let expectedSnapshot = makeSessionListEmptySnapshot(
            sessionID: newSessionID,
            updatedAtMs: 1_700_000_000_000,
        )
        await store.receive(.newChatCreated(expectedSnapshot)) { state in
            applySessionListNewChatCreated(&state, snapshot: expectedSnapshot)
        }

        XCTAssertEqual(savedSnapshots.value, [expectedSnapshot])
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertEqual(store.state.catalogRows, catalogRows)
    }

    // swiftlint:disable:next function_body_length
    func testNewChatTappedCancelsInFlightRequestBeforeStartingDraft() async {
        let oldSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111331"))
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000002"))
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let fixedMs: Int64 = 1_700_000_001_331
        let requestStarted = LockIsolated(false)
        let requestCancelled = LockIsolated(false)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(selectedSessionID: oldSessionID),
            sessionID: oldSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            draftText: "Question before new chat",
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: selectedHandle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { _ in
                requestStarted.setValue(true)
                return AsyncStream { continuation in
                    continuation.onTermination = { termination in
                        if case .cancelled = termination {
                            requestCancelled.setValue(true)
                        }
                    }
                }
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { _, _ in [] },
                loadSession: { _ in nil },
                saveSession: { snapshot in savedSnapshots.withValue { $0.append(snapshot) } },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { AIConnectionsFile.empty() },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped)
        await waitUntil { requestStarted.value }

        await store.send(.newChatTapped)

        let expectedSnapshot = AiChatSessionSnapshot(
            sessionID: newSessionID,
            status: .idle,
            customTitle: nil,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: fixedMs,
        )
        await store.receive(.newChatCreated(expectedSnapshot))
        await store.finish()

        XCTAssertTrue(requestCancelled.value)
        XCTAssertEqual(savedSnapshots.value.last, expectedSnapshot)
        XCTAssertEqual(store.state.sessionID, newSessionID)
        XCTAssertEqual(store.state.executionPhase, .idle)
    }

    // swiftlint:disable:next function_body_length
    func testTeardownRequestedCancelsSessionListDeleteAndRenameEffects() async {
        let renameSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111441"))
        let deleteSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222441"))
        let listStarted = LockIsolated(false)
        let listCancelled = LockIsolated(false)
        let renameStarted = LockIsolated(false)
        let renameCancelled = LockIsolated(false)
        let deleteStarted = LockIsolated(false)
        let deleteCancelled = LockIsolated(false)

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(
                allRows: [
                    makeSessionSummary(sessionID: renameSessionID, title: "Rename me"),
                    makeSessionSummary(sessionID: deleteSessionID, title: "Delete me"),
                ],
                renamingSessionID: renameSessionID,
                renameDraftText: "Renamed title",
            ),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { _, _ in
                    listStarted.setValue(true)
                    try await withTaskCancellationHandler {
                        while true {
                            try Task.checkCancellation()
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    } onCancel: {
                        listCancelled.setValue(true)
                    }
                    return []
                },
                loadSession: { _ in
                    renameStarted.setValue(true)
                    try await withTaskCancellationHandler {
                        while true {
                            try Task.checkCancellation()
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    } onCancel: {
                        renameCancelled.setValue(true)
                    }
                    return nil
                },
                saveSession: { _ in },
                deleteSession: { _ in
                    deleteStarted.setValue(true)
                    try await withTaskCancellationHandler {
                        while true {
                            try Task.checkCancellation()
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    } onCancel: {
                        deleteCancelled.setValue(true)
                    }
                },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.sessionsAppeared)
        await store.send(.renameSessionConfirmed)
        await store.send(.deleteSessionTapped(deleteSessionID))
        await waitUntil { listStarted.value && renameStarted.value && deleteStarted.value }

        await store.send(.teardownRequested)
        await store.finish()

        XCTAssertTrue(listCancelled.value)
        XCTAssertTrue(renameCancelled.value)
        XCTAssertTrue(deleteCancelled.value)
    }

    func testTeardownRequestedCancelsInFlightNewChatSave() async {
        await assertInFlightNewChatSaveCancelled(by: .teardown)
    }

    func testResetTappedCancelsInFlightNewChatSave() async {
        await assertInFlightNewChatSaveCancelled(by: .reset)
    }

    private func assertInFlightNewChatSaveCancelled(by trigger: NewChatCancellationTrigger) async {
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let saveStarted = LockIsolated(false)
        let saveCancelled = LockIsolated(false)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        let store = TestStore(initialState: AiChatFeature.State(mode: .sessions)) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_000))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    saveStarted.setValue(true)
                    try await withTaskCancellationHandler {
                        while true {
                            try Task.checkCancellation()
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    } onCancel: {
                        saveCancelled.setValue(true)
                    }
                },
                deleteSession: { _ in },
            )
        }

        await store.send(.newChatTapped) { state in
            applySessionListNewChatStarted(&state, sessionID: newSessionID)
        }

        await waitUntil { saveStarted.value }
        switch trigger {
        case .teardown:
            await store.send(.teardownRequested)
        case .reset:
            await store.send(.resetTapped) { state in
                applySessionListResetState(&state)
            }
        }
        await store.finish()

        XCTAssertTrue(saveCancelled.value)
        XCTAssertEqual(savedSnapshots.value.map(\.sessionID), [newSessionID])
        XCTAssertNil(store.state.sessionList.selectedSessionID)
    }
}

func applySessionListNewChatStarted(
    _ state: inout AiChatFeature.State,
    sessionID: AiChatSessionID,
) {
    state.sessionID = sessionID
    state.emptyDraftSessionID = sessionID
    state.sessionStatus = .idle
    state.mode = .chat
    state.restoreSessionID = nil
    state.restoreOutcome = nil
    state.restoreFailure = nil
    state.sessionList.selectedSessionID = nil
    state.sessionList.errorMessage = nil
    state.transcriptHistory = []
    state.draftText = ""
    state.streamingAssistantDraft = nil
    state.lockedModelHandle = nil
    state.lastExecutionFailure = nil
    state.lastRequestContext = nil
    state.lastRequestContextModelHandle = nil
    state.executionPhase = .idle
    state.selectedModelHandle = nil
    state.selectedThinking = nil
    state.unavailableSelectedModelHandle = nil
}

func applySessionListResetState(_ state: inout AiChatFeature.State) {
    state.emptyDraftSessionID = nil
    state.restoreSessionID = nil
    state.restoreOutcome = nil
    state.restoreFailure = nil
    state.draftText = ""
    state.transcriptHistory = []
    state.streamingAssistantDraft = nil
    state.lastExecutionFailure = nil
    state.lockedModelHandle = nil
    state.executionPhase = .idle
}

func applySessionListNewChatCreated(
    _ state: inout AiChatFeature.State,
    snapshot: AiChatSessionSnapshot,
) {
    state.sessionID = snapshot.sessionID
    state.emptyDraftSessionID = snapshot.sessionID
    state.sessionStatus = .idle
    state.transcriptHistory = []
    state.streamingAssistantDraft = nil
    state.lockedModelHandle = nil
    state.lastExecutionFailure = nil
    state.lastRequestContext = nil
    state.lastRequestContextModelHandle = nil
    state.executionPhase = .idle
    state.selectedModelHandle = nil
    state.selectedThinking = nil
    state.restoreSessionID = snapshot.sessionID
    state.restoreOutcome = nil
    state.restoreFailure = nil
    state.mode = .chat
    state.sessionList.selectedSessionID = snapshot.sessionID
    state.sessionList.errorMessage = nil
}

func makeSessionListEmptySnapshot(
    sessionID: AiChatSessionID,
    updatedAtMs: Int64,
) -> AiChatSessionSnapshot {
    AiChatSessionSnapshot(
        sessionID: sessionID,
        status: .idle,
        customTitle: nil,
        provider: nil,
        model: nil,
        selectedModelRow: nil,
        selectedThinking: nil,
        transcriptHistory: [],
        lastRequestID: nil,
        lastRunID: nil,
        lastRequestContext: nil,
        updatedAtMs: updatedAtMs,
    )
}

private enum NewChatCancellationTrigger {
    case teardown
    case reset
}

@MainActor
private func waitUntil(
    _ condition: @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line,
) async {
    for _ in 0 ..< 100 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("Condition was not fulfilled.", file: file, line: line)
}

private func makeSessionSummary(
    sessionID: AiChatSessionID,
    title: String = "Release notes follow-up",
    preview: String? = "Need the latest diff summary.",
    messageCount: Int = 2,
    contextTitle: String? = "Release docs",
    searchText: String? = nil,
    provider: AiProvider = .openai,
    model: AiModelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
    createdAtMs: Int64 = 1000,
    updatedAtMs: Int64 = 2000,
    status: AiChatSessionStatus = .active,
) -> AiChatSessionSummary {
    AiChatSessionSummary(
        sessionID: sessionID,
        title: title,
        preview: preview,
        messageCount: messageCount,
        contextTitle: contextTitle,
        searchText: searchText,
        provider: provider,
        model: model,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs,
        status: status,
    )
}

private struct SessionListCall: Equatable {
    var limit: Int?
    var query: String?
}

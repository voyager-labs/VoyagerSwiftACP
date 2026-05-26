import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureSessionListTests: XCTestCase {
    func testSessionsAppearedLoadsAndSetsRows() async {
        let first = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111")),
            title: "Release notes follow-up"
        )
        let second = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222")),
            title: "Architecture review"
        )
        let listCalls = LockIsolated<[SessionListCall]>([])

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { limit, query in
                    listCalls.withValue { $0.append(.init(limit: limit, query: query)) }
                    return [first, second]
                },
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in }
            )
        }

        await store.send(.sessionsAppeared) { state in
            state.mode = .sessions
            state.sessionList.isLoading = true
            state.sessionList.errorMessage = nil
        }

        await store.receive(.sessionListLoaded([first, second])) { state in
            state.sessionList.allRows = [first, second]
            state.sessionList.rows = [first, second]
            state.sessionList.isLoading = false
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(listCalls.value, [.init(limit: nil, query: nil)])
    }

    func testSessionSearchFiltersRowsDeterministically() async {
        let titleMatch = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111")),
            title: "Release notes follow-up",
            preview: "Need the latest diff summary.",
            contextTitle: "Release docs"
        )
        let previewMatch = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222")),
            title: "Architecture review",
            preview: "Compare RELEASE branches before merge.",
            contextTitle: "Backend"
        )
        let contextMatch = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333")),
            title: "Bug triage",
            preview: "Need a repro",
            contextTitle: "release checklist"
        )
        let transcriptMatch = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555")),
            title: "Backend cleanup",
            preview: "Discuss retries",
            contextTitle: "Operations",
            searchText: "Earlier conversation mentioned RELEASE blockers in detail."
        )
        let nonMatch = makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444")),
            title: "Design sync",
            preview: "Discuss spacing",
            contextTitle: "UI"
        )

        let store = TestStore(initialState: AiChatFeature.State(
            sessionList: .init(allRows: [titleMatch, previewMatch, contextMatch, transcriptMatch, nonMatch])
        )) {
            AiChatFeature()
        }

        await store.send(.sessionSearchQueryChanged("  rElEaSe  ")) { state in
            state.sessionList.query = "  rElEaSe  "
            state.sessionList.rows = [titleMatch, previewMatch, contextMatch, transcriptMatch]
        }

        XCTAssertEqual(store.state.sessionList.allRows, [titleMatch, previewMatch, contextMatch, transcriptMatch, nonMatch])
    }

    func testNewChatTappedStartsUnselectedDraftAndSavesDurableUnselectedSnapshot() async {
        let catalogRows = makeCatalogRows()
        let currentContext = makeContextSnapshot(summary: "Release docs")
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(
                rows: [makeSessionSummary(
                    sessionID: AiChatSessionID(rawValue: makeUUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
                )],
                errorMessage: "Previous error",
                selectedSessionID: AiChatSessionID(rawValue: makeUUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
            ),
            sessionStatus: .active,
            currentContext: currentContext,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "stale draft",
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: catalogRows[1].handle,
            selectedThinking: .effort(.high)
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
                deleteSession: { _ in }
            )
        }

        await store.send(.newChatTapped) { state in
            state.sessionID = newSessionID
            state.emptyDraftSessionID = newSessionID
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
            updatedAtMs: 1_700_000_000_000
        )

        await store.receive(.newChatCreated(expectedSnapshot)) { state in
            state.sessionID = newSessionID
            state.emptyDraftSessionID = newSessionID
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
            state.restoreSessionID = newSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.selectedSessionID = newSessionID
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(savedSnapshots.value, [expectedSnapshot])
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertEqual(store.state.catalogRows, catalogRows)
    }

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
            selectedThinking: nil
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
                deleteSession: { _ in }
            )
        }

        await store.send(.newChatTapped) { state in
            state.sessionID = newSessionID
            state.emptyDraftSessionID = newSessionID
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
            updatedAtMs: 1_700_000_000_000
        )

        await store.receive(.newChatCreated(expectedSnapshot)) { state in
            state.sessionID = newSessionID
            state.emptyDraftSessionID = newSessionID
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
            state.restoreSessionID = newSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.selectedSessionID = newSessionID
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(savedSnapshots.value, [expectedSnapshot])
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertEqual(store.state.catalogRows, catalogRows)
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
                deleteSession: { _ in }
            )
        }

        await store.send(.newChatTapped) { state in
            state.sessionID = newSessionID
            state.emptyDraftSessionID = newSessionID
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

        await waitUntil { saveStarted.value }
        switch trigger {
        case .teardown:
            await store.send(.teardownRequested)
        case .reset:
            await store.send(.resetTapped) { state in
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
        }
        await store.finish()

        XCTAssertTrue(saveCancelled.value)
        XCTAssertEqual(savedSnapshots.value.map(\.sessionID), [newSessionID])
        XCTAssertNil(store.state.sessionList.selectedSessionID)
    }
}

private enum NewChatCancellationTrigger {
    case teardown
    case reset
}

@MainActor
private func waitUntil(
    _ condition: @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<100 {
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
    status: AiChatSessionStatus = .active
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
        status: status
    )
}

private struct SessionListCall: Equatable {
    var limit: Int?
    var query: String?
}

import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW-005 session continuity specs에서 공유하는 session, navigation, delete/rename fixture support.

struct TeardownLockInput {
    let sessionID: AiChatSessionID
    let requestIDs: (requestID: AiChatRequestID, runID: AiChatRunID)
    let catalogRow: AiModelCatalogRow
    let selectedModel: AiProviderModel
    let summary: AiChatCurrentContextSnapshot
    let messages: [AiChatMessage]
}

func makeTeardownProcessingLock(input: TeardownLockInput) -> AiChatRequestLock {
    let context = AiChatRequestContextSnapshot(
        sessionID: input.sessionID,
        requestID: input.requestIDs.requestID,
        runID: input.requestIDs.runID,
        provider: input.catalogRow.handle.provider,
        model: input.catalogRow.handle,
        selectedModel: input.selectedModel,
        selectedModelRow: input.catalogRow,
        selectedThinking: .effort(.medium),
        sessionStatus: .active,
        currentContext: input.summary,
        promptSummary: "Keep this transcript",
        submittedAtMs: 1_700_000_000_600,
    )
    let request = AiChatRequest(context: context, messages: input.messages)

    return AiChatRequestLock(
        kind: .submit,
        requestID: input.requestIDs.requestID,
        runID: input.requestIDs.runID,
        context: context,
        request: request,
        selectedModelHandle: input.catalogRow.handle,
        selectedModelRow: input.catalogRow,
        assistantReplacementIndex: nil,
        historyTruncation: AiChatHistoryTruncationMetadata(
            includedMessageCount: 1,
            excludedMessageCount: 0,
            budget: 24000,
            truncationReason: nil,
        ),
        observabilitySummary: AiChatRequestObservabilitySummary(submittedAtMs: 1_700_000_000_600),
    )
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

enum NewChatCancellationTrigger {
    case teardown
    case reset
}

@MainActor
func assertInFlightNewChatSaveCancelled(by trigger: NewChatCancellationTrigger) async {
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

@MainActor
func waitUntil(
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

struct DeleteProcessingHarness {
    let capturedRequest = LockIsolated<AiChatRequest?>(nil)
    let requestStarted = LockIsolated(false)
    let requestCancelled = LockIsolated(false)
    let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
    let deletedIDs = LockIsolated<[AiChatSessionID]>([])
}

func makeDeleteProcessingHarness() -> DeleteProcessingHarness {
    DeleteProcessingHarness()
}

@MainActor
func makeDeleteLoadedSessionStore(
    activeSessionID: AiChatSessionID,
    activeRow: AiChatSessionSummary,
    transcript: [AiChatMessage],
    currentContext: AiChatCurrentContextSnapshot,
    catalogRows: [AiModelCatalogRow],
) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
    TestStore(initialState: AiChatFeature.State(
        restoreSessionID: activeSessionID,
        restoreOutcome: .restored(snapshot: AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: catalogRows[0].handle.provider,
            model: catalogRows[0].handle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: transcript,
            updatedAtMs: 1,
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
        selectedModelHandle: catalogRows[0].handle,
    )) {
        AiChatFeature()
    } withDependencies: {
        $0.aiChatSessionPersistenceClient = makeCBW005MissingPersistence()
    }
}

func makeDeleteLateSummaries(
    sessionID: AiChatSessionID,
    prompt: String,
) -> (start: AiChatSessionSummary, final: AiChatSessionSummary) {
    (
        makeDeleteTestSessionSummary(
            sessionID: sessionID,
            title: prompt,
            preview: prompt,
            messageCount: 1,
            updatedAtMs: 3000,
        ),
        makeDeleteTestSessionSummary(
            sessionID: sessionID,
            title: prompt,
            preview: "Late answer",
            messageCount: 2,
            updatedAtMs: 4000,
        ),
    )
}

@MainActor
func makeDeleteProcessingSessionStore(
    sessionID: AiChatSessionID,
    row: AiChatSessionSummary,
    catalogRows: [AiModelCatalogRow],
    fixedMs: Int64,
    harness: DeleteProcessingHarness,
) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
    TestStore(initialState: makeDeleteProcessingState(sessionID: sessionID, row: row, catalogRows: catalogRows)) {
        AiChatFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
        $0.aiChatExecutionClient = makeDeleteExecutionClient(
            capturedRequest: harness.capturedRequest,
            requestStarted: harness.requestStarted,
            requestCancelled: harness.requestCancelled,
        )
        $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
            loadSession: { _ in nil },
            saveSession: { snapshot in harness.savedSnapshots.withValue { $0.append(snapshot) } },
            deleteSession: { id in harness.deletedIDs.withValue { $0.append(id) } },
        )
        $0.aiConnectionsFileClient = AIConnectionsFileClient(
            load: { AIConnectionsFile.empty() },
            save: { .success($0) },
            deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
        )
    }
}

func makeDeleteProcessingState(
    sessionID: AiChatSessionID,
    row: AiChatSessionSummary,
    catalogRows: [AiModelCatalogRow],
) -> AiChatFeature.State {
    AiChatFeature.State(
        restoreSessionID: sessionID,
        mode: .sessions,
        sessionList: .init(allRows: [row], selectedSessionID: sessionID),
        sessionID: sessionID,
        sessionStatus: .active,
        currentContext: makeContextSnapshot(summary: "Current docs"),
        draftText: "Delete while processing",
        catalogRows: catalogRows,
        modelListState: .loaded(makeThinkingCapableProviderModels()),
        selectedModelHandle: catalogRows[0].handle,
    )
}

func makeDeleteExecutionClient(
    capturedRequest: LockIsolated<AiChatRequest?>,
    requestStarted: LockIsolated<Bool>,
    requestCancelled: LockIsolated<Bool>,
) -> AiChatExecutionClient {
    AiChatExecutionClient(execute: { request in
        capturedRequest.setValue(request)
        requestStarted.setValue(true)
        return AsyncStream { continuation in
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    requestCancelled.setValue(true)
                }
            }
        }
    })
}

func assertLoadedSessionStateIntact(
    _ state: AiChatFeature.State,
    sessionID: AiChatSessionID,
    transcript: [AiChatMessage],
    currentContext: AiChatCurrentContextSnapshot,
    selectedModelHandle: AiModelHandle,
) {
    XCTAssertEqual(state.mode, AiChatMode.sessions)
    XCTAssertEqual(state.sessionID, sessionID)
    XCTAssertEqual(state.sessionStatus, AiChatSessionStatus.active)
    XCTAssertEqual(state.transcriptHistory, transcript)
    XCTAssertEqual(state.draftText, "Keep this draft")
    XCTAssertEqual(state.currentContext, currentContext)
    XCTAssertEqual(state.selectedModelHandle, selectedModelHandle)
}

func makeDeleteTestRequest(
    sessionID: AiChatSessionID,
    requestID: AiChatRequestID,
    runID: AiChatRunID,
    selectedRow: AiModelCatalogRow,
    prompt: String,
) -> AiChatRequest {
    AiChatRequest(
        context: makeRequestContext(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            model: selectedRow.handle,
            selectedRow: selectedRow,
            promptSummary: prompt,
        ),
        messages: [AiChatMessage(role: .user, content: prompt)],
    )
}

func makeDeleteTestLock(
    request: AiChatRequest,
    selectedRow: AiModelCatalogRow,
) -> AiChatRequestLock {
    makeRequestLock(
        kind: .submit,
        request: request,
        selectedHandle: selectedRow.handle,
        selectedRow: selectedRow,
        assistantReplacementIndex: nil,
    )
}

func assertProcessingSessionDeleted(
    _ state: AiChatFeature.State,
    sessionID: AiChatSessionID,
    deletedIDs: [AiChatSessionID],
) {
    XCTAssertEqual(deletedIDs, [sessionID])
    XCTAssertTrue(state.sessionList.allRows.isEmpty)
    XCTAssertTrue(state.sessionList.rows.isEmpty)
    XCTAssertNil(state.sessionList.selectedSessionID)
    XCTAssertEqual(state.sessionList.deletedSessionIDs, [sessionID])
}

func applyDeleteProcessingSessionState(
    _ state: inout AiChatFeature.State,
    lock: AiChatRequestLock,
    fixedMs: Int64,
) {
    state.restoreSessionID = nil
    state.restoreOutcome = nil
    state.restoreFailure = nil
    state.sessionList.selectedSessionID = nil
    state.lockedModelHandle = nil
    state.streamingAssistantDraft = nil
    state.executionPhase = .cancelled(lock.recordingTerminal(
        at: fixedMs,
        failure: .cancelled,
        wasCancelled: true,
    ))
}

func assertDeletedProcessingRequest(
    deletedIDs: [AiChatSessionID],
    sessionID: AiChatSessionID,
    requestCancelled: Bool,
    savedSnapshots: [AiChatSessionSnapshot],
) {
    XCTAssertEqual(deletedIDs, [sessionID])
    XCTAssertTrue(requestCancelled)
    XCTAssertFalse(savedSnapshots.contains { snapshot in
        snapshot.transcriptHistory.contains(AiChatMessage(role: .assistant, content: "Late final"))
    })
}

func makeRenameTestSnapshot(
    sessionID: AiChatSessionID,
    customTitle: String? = nil,
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
            sortOrder: 0,
        ),
        transcriptHistory: [
            AiChatMessage(role: .user, content: "Original prompt"),
            AiChatMessage(role: .assistant, content: "Original answer"),
        ],
        updatedAtMs: 3000,
    )
}

func makeRenamedSnapshot(
    _ snapshot: AiChatSessionSnapshot,
    renamedTo title: String,
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
        updatedAtMs: snapshot.updatedAtMs,
    )
}

func makeDeleteTestSessionSummary(
    sessionID: AiChatSessionID,
    title: String = "Release notes follow-up",
    preview: String? = "Need the latest diff summary.",
    messageCount: Int = 2,
    contextTitle: String? = "Release docs",
    provider: AiProvider = .openai,
    model: AiModelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
    createdAtMs: Int64 = 1000,
    updatedAtMs: Int64 = 2000,
    status: AiChatSessionStatus = .active,
) -> AiChatSessionSummary {
    makeCBW005SessionSummary(
        sessionID: sessionID,
        title: title,
        preview: preview,
        messageCount: messageCount,
        contextTitle: contextTitle,
        searchText: nil,
        provider: provider,
        model: model,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs,
        status: status,
    )
}

func makeNavigationAttachment(path: String) -> AiChatAttachmentDraft {
    AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: path),
        source: .file,
        displayTitle: URL(fileURLWithPath: path).lastPathComponent,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: path),
    )
}

func makeNavigationFolderKey(_ path: String) -> AiChatCurrentContextFolderStructureKey {
    AiChatCurrentContextFolderStructureKey(source: .reference, canonicalPath: path)
}

func applyNavigationNewChatStarted(
    _ state: inout AiChatFeature.State,
    sessionID: AiChatSessionID,
) {
    applySessionListNewChatStarted(&state, sessionID: sessionID)
    state.addedAttachments = []
    state.currentContextFolderStructureModes = [:]
}

func applyNavigationNewChatCreated(
    _ state: inout AiChatFeature.State,
    snapshot: AiChatSessionSnapshot,
) {
    applySessionListNewChatCreated(&state, snapshot: snapshot)
    state.addedAttachments = []
}

func makeNavigationEmptySnapshot(sessionID: AiChatSessionID) -> AiChatSessionSnapshot {
    makeSessionListEmptySnapshot(sessionID: sessionID, updatedAtMs: 1_700_000_000_000)
}

struct CBW005SessionListCall: Equatable {
    var limit: Int?
    var query: String?
}

func makeCBW005SessionID(_ rawValue: String) -> AiChatSessionID {
    AiChatSessionID(rawValue: makeUUID(rawValue))
}

func makeCBW005EmptySnapshot(
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

func makeCBW005Snapshot(
    sessionID: AiChatSessionID,
    transcriptHistory: [AiChatMessage],
    status: AiChatSessionStatus = .active,
    provider: AiProvider? = nil,
    modelHandle: AiModelHandle? = nil,
    model row: AiModelCatalogRow? = nil,
    selectedThinking: AiThinkingSelection? = nil,
    lastRequestContext: AiChatLockedRequestContextSnapshot? = nil,
    updatedAtMs: Int64 = 0,
) -> AiChatSessionSnapshot {
    let resolvedModel = row?.handle ?? modelHandle
    return AiChatSessionSnapshot(
        sessionID: sessionID,
        status: status,
        provider: provider ?? resolvedModel?.provider,
        model: resolvedModel,
        selectedModelRow: row,
        selectedThinking: selectedThinking,
        transcriptHistory: transcriptHistory,
        lastRequestContext: lastRequestContext,
        updatedAtMs: updatedAtMs,
    )
}

func makeCBW005LockedContext(summary: String) -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: makeContextSnapshot(summary: summary),
        addedAttachments: [
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "restored-attachment"),
                source: .file,
                displayTitle: "Restored.txt",
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Restored.txt"),
                resolutionResult: .resolvedText(text: "Restored content", metadata: [:]),
            ),
        ],
    )
}

func makeCBW005RequestLock(
    sessionID: AiChatSessionID,
    modelRow: AiModelCatalogRow,
) -> AiChatRequestLock {
    makeRequestLock(
        kind: .submit,
        request: AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                model: modelRow.handle,
                selectedRow: modelRow,
            ),
            messages: [],
        ),
        selectedHandle: modelRow.handle,
        selectedRow: modelRow,
        assistantReplacementIndex: nil,
    )
}

func makeCBW005Attachment(path: String) -> AiChatAttachmentDraft {
    AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: path),
        source: .file,
        displayTitle: URL(fileURLWithPath: path).lastPathComponent,
        sourceLocation: AiChatAttachmentSourceLocation(
            fileURL: URL(fileURLWithPath: path),
            filePath: path,
        ),
    )
}

func makeCBW005SearchRows() -> [AiChatSessionSummary] {
    [
        makeCBW005SessionSummary(
            sessionID: makeCBW005SessionID("11111111-1111-1111-1111-111111111111"),
            title: "Release notes follow-up",
            preview: "Need the latest diff summary.",
            contextTitle: "Release docs",
        ),
        makeCBW005SessionSummary(
            sessionID: makeCBW005SessionID("22222222-2222-2222-2222-222222222222"),
            title: "Architecture review",
            preview: "Compare RELEASE branches before merge.",
            contextTitle: "Backend",
        ),
        makeCBW005SessionSummary(
            sessionID: makeCBW005SessionID("33333333-3333-3333-3333-333333333333"),
            title: "Bug triage",
            preview: "Need a repro",
            contextTitle: "release checklist",
        ),
        makeCBW005SessionSummary(
            sessionID: makeCBW005SessionID("55555555-5555-5555-5555-555555555555"),
            title: "Backend cleanup",
            preview: "Discuss retries",
            contextTitle: "Operations",
            searchText: "Earlier conversation mentioned RELEASE blockers in detail.",
        ),
        makeCBW005SessionSummary(
            sessionID: makeCBW005SessionID("44444444-4444-4444-4444-444444444444"),
            title: "Design sync",
            preview: "Discuss spacing",
            contextTitle: "UI",
        ),
    ]
}

func makeCBW005SessionSummary(
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

func makeCBW005LoadOnlyPersistence(_ persistence: AiChatSessionPersistenceSpy) -> AiChatSessionPersistenceClient {
    AiChatSessionPersistenceClient(
        listSessions: { _, _ in [] },
        loadSession: { id in try await persistence.loadSession(id) },
        saveSession: { _ in },
        deleteSession: { _ in },
    )
}

func makeCBW005MissingPersistence() -> AiChatSessionPersistenceClient {
    AiChatSessionPersistenceClient(
        loadSession: { _ in nil },
        saveSession: { _ in },
        deleteSession: { _ in },
    )
}

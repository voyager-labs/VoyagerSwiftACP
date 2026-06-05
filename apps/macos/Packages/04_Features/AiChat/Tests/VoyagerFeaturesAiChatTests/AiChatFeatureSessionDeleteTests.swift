import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW005 spec-owner suite 밖에 남긴 session delete/rename/cancellation 회귀 테스트.
// current processing delete, late snapshot callback, rename persistence 같은 session edge contract를 보존한다.

@MainActor
final class AiChatFeatureSessionDeleteTests: XCTestCase {
    /// session 삭제 실패가 row를 유지하고 list error를 표시하는지 검증
    func testDeleteSessionFailureLeavesRowAndSetsListError() async {
        let deletedSessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let deletedRow = makeDeleteTestSessionSummary(sessionID: deletedSessionID)

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [deletedRow], selectedSessionID: deletedSessionID),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in
                    throw AiChatSessionPersistenceClientError.applicationSupportDirectoryUnavailable
                },
            )
        }

        await store.send(.deleteSessionTapped(deletedSessionID))

        await store.receive(.sessionDeleteFailed(
            deletedSessionID,
            "That chat could not be deleted right now.",
        )) { state in
            state.sessionList.errorMessage = "That chat could not be deleted right now."
        }

        XCTAssertEqual(store.state.sessionList.allRows, [deletedRow])
        XCTAssertEqual(store.state.sessionList.rows, [deletedRow])
        XCTAssertEqual(store.state.sessionList.selectedSessionID, deletedSessionID)
    }

    /// sessions mode에서 현재 loaded session을 삭제해도 chat state가 유지되는지 검증
    func testDeleteCurrentLoadedSessionFromSessionsModeLeavesChatStateIntact() async {
        let activeSessionID = AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444"))
        let activeRow = makeDeleteTestSessionSummary(sessionID: activeSessionID, title: "Live chat")
        let transcript = [
            AiChatMessage(role: .user, content: "What changed?"),
            AiChatMessage(role: .assistant, content: "Here is the summary."),
        ]
        let currentContext = makeContextSnapshot(summary: "Current docs")
        let catalogRows = makeCatalogRows()

        let store = makeDeleteLoadedSessionStore(
            activeSessionID: activeSessionID,
            activeRow: activeRow,
            transcript: transcript,
            currentContext: currentContext,
            catalogRows: catalogRows,
        )

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
            state.sessionList.deletedSessionIDs = [activeSessionID]
        }

        assertLoadedSessionStateIntact(
            store.state,
            sessionID: activeSessionID,
            transcript: transcript,
            currentContext: currentContext,
            selectedModelHandle: catalogRows[0].handle,
        )
    }

    /// 삭제된 processing session에 대한 late snapshot callback이 row를 되살리지 않는지 검증
    func testLateSnapshotCallbacksDoNotReinsertDeletedProcessingSession() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("88888888-8888-8888-8888-888888888888"))
        let requestID = AiChatRequestID(rawValue: makeUUID("99999999-9999-9999-9999-999999999999"))
        let runID = AiChatRunID(rawValue: makeUUID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        let prompt = "Summarize the deleted session"
        let fixedMs: Int64 = 1_700_000_000_500
        let row = makeDeleteTestSessionSummary(sessionID: sessionID, title: prompt)
        let summaries = makeDeleteLateSummaries(sessionID: sessionID, prompt: prompt)
        let selectedRow = makeCatalogRows()[0]
        let request = makeDeleteTestRequest(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            selectedRow: selectedRow,
            prompt: prompt,
        )
        let lock = makeDeleteTestLock(request: request, selectedRow: selectedRow)
        let deletedIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [row], selectedSessionID: sessionID),
            sessionID: sessionID,
            executionPhase: .processing(lock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { id in deletedIDs.withValue { $0.append(id) } },
            )
        }

        await store.send(.deleteSessionTapped(sessionID)) { state in
            state.executionPhase = .cancelled(lock.recordingTerminal(
                at: fixedMs,
                failure: .cancelled,
                wasCancelled: true,
            ))
        }

        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.selectedSessionID = nil
            state.sessionList.deletedSessionIDs = [sessionID]
        }

        await store.send(.sessionSnapshotUpdated(summaries.start, requestID: requestID, runID: runID))
        await store.send(.sessionSnapshotSaved(summaries.final))
        await store.send(.sessionListLoaded([summaries.final]))

        assertProcessingSessionDeleted(store.state, sessionID: sessionID, deletedIDs: deletedIDs.value)
    }

    /// 현재 processing session 삭제 시 request를 먼저 cancel한 뒤 삭제하는지 검증
    func testDeleteCurrentProcessingSessionCancelsRequestBeforeDelete() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let row = makeDeleteTestSessionSummary(sessionID: sessionID, title: "Processing chat")
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let fixedMs: Int64 = 1_700_000_000_000
        let harness = makeDeleteProcessingHarness()

        let store = makeDeleteProcessingSessionStore(
            sessionID: sessionID,
            row: row,
            catalogRows: catalogRows,
            fixedMs: fixedMs,
            harness: harness,
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped)
        await waitUntil { harness.requestStarted.value }

        guard let request = harness.capturedRequest.value else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        await store.send(.deleteSessionTapped(sessionID)) { state in
            applyDeleteProcessingSessionState(&state, lock: lock, fixedMs: fixedMs)
        }

        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.deletedSessionIDs = [sessionID]
        }

        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Late final"),
            completedAtMs: fixedMs,
        ))))
        await store.finish()

        assertDeletedProcessingRequest(
            deletedIDs: harness.deletedIDs.value,
            sessionID: sessionID,
            requestCancelled: harness.requestCancelled.value,
            savedSnapshots: harness.savedSnapshots.value,
        )
    }

    // completed session 삭제 시 final snapshot save를 취소한 뒤 삭제하는지 검증
    // swiftlint:disable:next function_body_length
    func testDeleteCurrentCompletedSessionCancelsFinalSnapshotSaveBeforeDelete() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("dddddddd-dddd-dddd-dddd-dddddddddddd"))
        let requestID = AiChatRequestID(rawValue: makeUUID("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"))
        let runID = AiChatRunID(rawValue: makeUUID("ffffffff-ffff-ffff-ffff-ffffffffffff"))
        let prompt = "Delete after final response"
        let row = makeDeleteTestSessionSummary(sessionID: sessionID, title: prompt)
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let fixedMs: Int64 = 1_700_000_000_200
        let saveStarted = LockIsolated(false)
        let saveCancelled = LockIsolated(false)
        let completedSaves = LockIsolated<[AiChatSessionSnapshot]>([])
        let deletedIDs = LockIsolated<[AiChatSessionID]>([])
        let context = makeRequestContext(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            model: selectedHandle,
            selectedRow: catalogRows[0],
            promptSummary: prompt,
        )
        let request = AiChatRequest(
            context: context,
            messages: [AiChatMessage(role: .user, content: prompt)],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [row], selectedSessionID: sessionID),
            sessionID: sessionID,
            sessionStatus: .active,
            transcriptHistory: [AiChatMessage(role: .user, content: prompt)],
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: selectedHandle,
            executionPhase: .processing(lock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    saveStarted.setValue(true)
                    try await withTaskCancellationHandler {
                        while true {
                            try Task.checkCancellation()
                            try await Task.sleep(nanoseconds: 10_000_000)
                        }
                    } onCancel: {
                        saveCancelled.setValue(true)
                    }
                    completedSaves.withValue { $0.append(snapshot) }
                },
                deleteSession: { id in deletedIDs.withValue { $0.append(id) } },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Final answer"),
            completedAtMs: fixedMs,
        ))))
        await waitUntil { saveStarted.value }

        await store.send(.deleteSessionTapped(sessionID))

        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.selectedSessionID = nil
            state.sessionList.deletedSessionIDs = [sessionID]
        }
        await store.finish()

        XCTAssertEqual(deletedIDs.value, [sessionID])
        XCTAssertTrue(saveCancelled.value)
        XCTAssertTrue(completedSaves.value.isEmpty)
    }

    // processing session 삭제 시 request-start snapshot save를 취소한 뒤 삭제하는지 검증
    // swiftlint:disable:next function_body_length
    func testDeleteCurrentProcessingSessionCancelsRequestStartSnapshotBeforeDelete() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("cccccccc-cccc-cccc-cccc-cccccccccccc"))
        let row = makeDeleteTestSessionSummary(sessionID: sessionID, title: "Processing chat")
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let fixedMs: Int64 = 1_700_000_000_100
        let requestStarted = LockIsolated(false)
        let saveStarted = LockIsolated(false)
        let saveCancelled = LockIsolated(false)
        let capturedRequest = LockIsolated<AiChatRequest?>(nil)
        let deletedIDs = LockIsolated<[AiChatSessionID]>([])
        let completedSaves = LockIsolated<[AiChatSessionSnapshot]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [row], selectedSessionID: sessionID),
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            draftText: "Delete while start snapshot is saving",
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: selectedHandle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                capturedRequest.setValue(request)
                requestStarted.setValue(true)
                return AsyncStream { _ in }
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    saveStarted.setValue(true)
                    try await withTaskCancellationHandler {
                        while true {
                            try Task.checkCancellation()
                            try await Task.sleep(nanoseconds: 10_000_000)
                        }
                    } onCancel: {
                        saveCancelled.setValue(true)
                    }
                    completedSaves.withValue { $0.append(snapshot) }
                },
                deleteSession: { id in deletedIDs.withValue { $0.append(id) } },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { AIConnectionsFile.empty() },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped)
        await waitUntil { requestStarted.value && saveStarted.value }

        guard let request = capturedRequest.value else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        await store.send(.deleteSessionTapped(sessionID)) { state in
            state.lockedModelHandle = nil
            state.streamingAssistantDraft = nil
            state.executionPhase = .cancelled(lock.recordingTerminal(
                at: fixedMs,
                failure: .cancelled,
                wasCancelled: true,
            ))
        }

        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.selectedSessionID = nil
            state.sessionList.deletedSessionIDs = [sessionID]
        }
        await store.finish()

        XCTAssertEqual(deletedIDs.value, [sessionID])
        XCTAssertTrue(saveCancelled.value)
        XCTAssertTrue(completedSaves.value.isEmpty)
    }

    /// session rename 성공이 custom title을 저장하고 filtered rows를 갱신하는지 검증
    func testRenameSessionSuccessPersistsCustomTitleAndUpdatesFilteredRows() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555"))
        let originalRow = makeDeleteTestSessionSummary(sessionID: sessionID, title: "Original derived title")
        let snapshot = makeRenameTestSnapshot(sessionID: sessionID)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [originalRow], query: "renamed"),
            sessionID: sessionID,
            currentSessionCustomTitle: nil,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in id == sessionID ? snapshot : nil },
                saveSession: { snapshot in savedSnapshots.withValue { $0.append(snapshot) } },
                deleteSession: { _ in },
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

    /// 빈 title rename이 custom title을 지우고 derived title로 fallback하는지 검증
    func testRenameSessionBlankTitleClearsCustomTitleAndFallsBackToDerivedTitle() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("66666666-6666-6666-6666-666666666666"))
        let originalRow = makeDeleteTestSessionSummary(sessionID: sessionID, title: "Custom title")
        let snapshot = makeRenameTestSnapshot(sessionID: sessionID, customTitle: "Custom title")
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [originalRow]),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in id == sessionID ? snapshot : nil },
                saveSession: { snapshot in savedSnapshots.withValue { $0.append(snapshot) } },
                deleteSession: { _ in },
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

    /// session rename 실패가 editor를 열어 둔 채 list error를 표시하는지 검증
    func testRenameSessionFailureKeepsEditorOpenAndSetsListError() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("77777777-7777-7777-7777-777777777777"))
        let row = makeDeleteTestSessionSummary(sessionID: sessionID, title: "Original derived title")

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [row], renamingSessionID: sessionID, renameDraftText: "Rename fails"),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in throw AiChatSessionPersistenceClientError.applicationSupportDirectoryUnavailable },
                saveSession: { _ in },
                deleteSession: { _ in },
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

private struct DeleteProcessingHarness {
    let capturedRequest = LockIsolated<AiChatRequest?>(nil)
    let requestStarted = LockIsolated(false)
    let requestCancelled = LockIsolated(false)
    let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
    let deletedIDs = LockIsolated<[AiChatSessionID]>([])
}

private func makeDeleteProcessingHarness() -> DeleteProcessingHarness {
    DeleteProcessingHarness()
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

@MainActor
private func makeDeleteLoadedSessionStore(
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

private func makeDeleteLateSummaries(
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
private func makeDeleteProcessingSessionStore(
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

private func makeDeleteProcessingState(
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

private func makeDeleteExecutionClient(
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

private func assertLoadedSessionStateIntact(
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

private func makeDeleteTestRequest(
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

private func makeDeleteTestLock(
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

private func assertProcessingSessionDeleted(
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

private func applyDeleteProcessingSessionState(
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

private func assertDeletedProcessingRequest(
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

private func makeDeleteTestSessionSummary(
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
        status: status,
    )
}

private func makeRenameTestSnapshot(
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

private func makeRenamedSnapshot(
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

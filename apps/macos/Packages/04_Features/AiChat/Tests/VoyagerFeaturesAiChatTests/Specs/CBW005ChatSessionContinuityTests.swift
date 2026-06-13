import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class CBW005ChatSessionContinuityTests: XCTestCase {
    // MARK: - CBW-005-restore_chat_conversation_session

    /// CBW-005-restore_chat_conversation_session: 저장된 chat session을 transcript와 선택 상태로 복원한다.
    /// setup restore 경로가 이전 runtime lock을 지우고 durable snapshot을 active chat으로 승격하는지 검증합니다.
    /// - 검증 내용: restored transcript, selected model/thinking, idle execution phase, status text
    /// - 사전 조건: restoreSessionID와 persisted active session snapshot이 존재한다.
    /// - 기대 결과: 이전 processing state는 제거되고 저장된 session이 active 상태로 복원된다.
    func testRestoreChatConversationSessionHydratesTranscriptAndSelection() async {
        let catalogRows = makeCatalogRows()
        let targetSessionID = makeCBW005SessionID("55555555-5555-5555-5555-555555555555")
        let restoredSnapshot = makeCBW005Snapshot(
            sessionID: targetSessionID,
            transcriptHistory: restoredTranscript,
            model: catalogRows[1],
            selectedThinking: .effort(.minimal),
        )
        let store = makeRestoreHydrationStore(
            sessionID: targetSessionID,
            restoredSnapshot: restoredSnapshot,
            catalogRows: catalogRows,
        )
        let setupState = makeRestoreHydrationSetup(
            sessionID: targetSessionID,
            catalogRows: catalogRows,
        )
        await store.send(.setup(setupState)) { state in
            self.applyRestoringSetupState(&state, setup: setupState, catalogRows: catalogRows)
        }

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: restoredSnapshot),
            restoreFailure: nil,
        )) { state in
            self.applyRestoreHydrationOutcome(&state, snapshot: restoredSnapshot)
        }

        XCTAssertEqual(store.state.transcriptHistory, restoredSnapshot.transcriptHistory)
        XCTAssertEqual(store.state.selectedThinking, .effort(.minimal))
        XCTAssertEqual(store.state.sessionStatusText, "Restored session")
    }

    // MARK: - CBW-005-start_chat_conversation_session

    /// CBW-005-start_chat_conversation_session: New Chat은 durable 빈 session을 만들고 chat mode로 진입한다.
    /// 새 대화가 이전 transcript/model runtime을 비우고 저장 가능한 unselected snapshot을 생성하는지 검증합니다.
    /// - 검증 내용: sessionID 생성, transcript/runtime reset, durable snapshot 저장
    /// - 사전 조건: sessions mode에서 이전 선택과 draft가 남아 있다.
    /// - 기대 결과: 새 idle session이 선택되고 provider/model selection은 비워진다.
    func testStartChatConversationSessionCreatesDurableUnselectedDraft() async {
        let catalogRows = makeCatalogRows()
        let currentContext = makeContextSnapshot(summary: "Release docs")
        let newSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000000")
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let staleSessionID = makeCBW005SessionID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(
                rows: [makeCBW005SessionSummary(sessionID: staleSessionID)],
                errorMessage: "Previous error",
                selectedSessionID: staleSessionID,
            ),
            sessionStatus: .active,
            currentContext: currentContext,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "stale draft",
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: catalogRows[1].handle,
            selectedThinking: .effort(.high),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in savedSnapshots.withValue { $0.append(snapshot) } },
                deleteSession: { _ in },
            )
        }

        await store.send(.newChatTapped) { state in
            self.applyNewChatStartedState(&state, sessionID: newSessionID)
        }

        let expectedSnapshot = makeCBW005EmptySnapshot(sessionID: newSessionID, updatedAtMs: fixedTimestampMs)
        await store.receive(.newChatCreated(expectedSnapshot)) { state in
            self.applyNewChatCreatedState(&state, snapshot: expectedSnapshot)
        }

        XCTAssertEqual(savedSnapshots.value, [expectedSnapshot])
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.currentContext, currentContext)
    }

    // MARK: - CBW-005-continue_chat_conversation_session

    /// CBW-005-continue_chat_conversation_session: Sessions로 돌아가도 active chat data는 유지된다.
    /// Back to Sessions가 현재 transcript/draft/context/attachment를 삭제하지 않고 목록만 보여주는지 검증합니다.
    /// - 검증 내용: mode 전환, transcript와 draft 보존, added attachment 보존
    /// - 사전 조건: active chat에 transcript, draft, attachment가 있다.
    /// - 기대 결과: mode만 sessions로 바뀌고 대화 state는 계속 이어갈 수 있다.
    func testContinueChatConversationSessionPreservesActiveChatWhenReturningToList() async {
        let sessionID = makeCBW005SessionID("11111111-1111-1111-1111-111111111111")
        let selectedSessionID = makeCBW005SessionID("22222222-2222-2222-2222-222222222222")
        let attachment = makeCBW005Attachment(path: "/tmp/Screenshot.png")
        let transcript = restoredTranscript

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionList: .init(
                rows: [makeCBW005SessionSummary(sessionID: selectedSessionID)],
                query: "release",
                selectedSessionID: selectedSessionID,
            ),
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            addedAttachments: [attachment],
            transcriptHistory: transcript,
            draftText: "Draft reply",
        )) {
            AiChatFeature()
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
        }

        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.transcriptHistory, transcript)
        XCTAssertEqual(store.state.draftText, "Draft reply")
        XCTAssertEqual(store.state.addedAttachments, [attachment])
        XCTAssertEqual(store.state.sessionList.selectedSessionID, selectedSessionID)
    }

    // MARK: - CBW-005-open_chat_conversation_session

    /// CBW-005-open_chat_conversation_session: session row 선택은 저장 session을 열고 live context를 유지한다.
    /// 목록에서 기존 session을 열 때 persisted request context와 현재 FileManager context가 분리되는지 검증합니다.
    /// - 검증 내용: row selection, restore outcome, live current context preservation, persisted locked context hydration
    /// - 사전 조건: sessions list에 restore 가능한 row와 live current context가 있다.
    /// - 기대 결과: Chat View로 전환되고 transcript/lastRequestContext는 저장 snapshot에서 복원된다.
    func testOpenChatConversationSessionRestoresPersistedHistoryWithoutReplacingLiveContext() async {
        let catalogRows = makeCatalogRows()
        let targetSessionID = makeCBW005SessionID("34343434-3434-3434-3434-343434343434")
        let liveCurrentContext = makeContextSnapshot(summary: "Live FileManager selection")
        let restoredLockedContext = makeCBW005LockedContext(summary: "Restored request context")
        let restoredSnapshot = makeCBW005Snapshot(
            sessionID: targetSessionID,
            transcriptHistory: restoredTranscript,
            model: catalogRows[1],
            lastRequestContext: restoredLockedContext,
        )
        let store = makeOpenSessionStore(
            restoredSnapshot: restoredSnapshot,
            liveCurrentContext: liveCurrentContext,
            catalogRows: catalogRows,
        )

        await store.send(.sessionRowTapped(targetSessionID)) { state in
            self.applyOpeningSessionRowState(&state, sessionID: targetSessionID)
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: restoredSnapshot),
            restoreFailure: nil,
        )) { state in
            self.applyOpenedRestoredSessionState(
                &state,
                snapshot: restoredSnapshot,
                lockedContext: restoredLockedContext,
            )
        }

        XCTAssertEqual(store.state.currentContext, liveCurrentContext)
        XCTAssertEqual(store.state.lastRequestContext, restoredLockedContext)
        XCTAssertEqual(store.state.lastRequestContext?.currentContext.summary, "Restored request context")
    }

    // MARK: - CBW-005-show_chat_session_restore_failure

    /// CBW-005-show_chat_session_restore_failure: 복원 실패는 기존 chat을 승격하지 않고 목록 오류로 표시한다.
    /// 깨진 session row를 열 때 stale transcript가 active로 바뀌지 않는지 검증합니다.
    /// - 검증 내용: selected row clear, one-time restore error, 기존 active transcript 보존
    /// - 사전 조건: sessions mode에서 persistence load가 nil을 반환한다.
    /// - 기대 결과: mode는 sessions에 머물고 기존 active chat state는 유지된다.
    func testShowChatSessionRestoreFailureKeepsSessionsModeAndShowsError() async {
        let catalogRows = makeCatalogRows()
        let existingSessionID = makeCBW005SessionID("99999999-9999-9999-9999-999999999999")
        let requestedSessionID = makeCBW005SessionID("55555555-5555-5555-5555-555555555555")
        let staleTranscript = [AiChatMessage(role: .assistant, content: "already open chat")]
        let store = makeRestoreFailureStore(
            requestedSessionID: requestedSessionID,
            existingSessionID: existingSessionID,
            staleTranscript: staleTranscript,
            selectedModel: catalogRows[1].handle,
        )

        await store.send(.sessionRowTapped(requestedSessionID)) { state in
            self.applyRestoreFailureRowTappedState(&state, sessionID: requestedSessionID)
        }

        let fallbackSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000000")
        let fallbackSnapshot = makeCBW005Snapshot(
            sessionID: fallbackSessionID,
            transcriptHistory: [],
            status: .idle,
            model: AiChatStateSelection.makeCatalogRows(for: makeProviderModels())[1],
        )
        await store.receive(.restoreOutcome(
            requestedSessionID: requestedSessionID,
            .newSession(snapshot: fallbackSnapshot),
            restoreFailure: .missingRecord,
        )) { state in
            self.applyRestoreFailureListState(&state, message: "That chat is no longer available.")
        }

        XCTAssertEqual(store.state.mode, .sessions)
        XCTAssertEqual(store.state.sessionID, existingSessionID)
        XCTAssertEqual(store.state.transcriptHistory, staleTranscript)
        XCTAssertNil(store.state.restoreOutcome)
    }

    // MARK: - CBW-005-show_rebind_required_state

    /// CBW-005-show_rebind_required_state: context mismatch restore는 rebind-required recovery를 노출한다.
    /// rebind 상태가 transcript를 보존하고 submit을 막은 뒤 rebind CTA로 recovery를 지우는지 검증합니다.
    /// - 검증 내용: rebindRequired status, unavailable model handle, submit block, rebind CTA recovery clear
    /// - 사전 조건: persisted snapshot status가 rebindRequired이고 stale model을 가진다.
    /// - 기대 결과: transcript는 보존되고 사용자가 rebind를 선택하면 active 상태로 돌아온다.
    func testShowRebindRequiredStatePreservesTranscriptAndClearsOnRebind() async {
        let catalogRows = makeCatalogRows()
        let targetSessionID = makeCBW005SessionID("44444444-4444-4444-4444-444444444444")
        let staleHandle = AiModelHandle(provider: .anthropic, rawValue: "stale-model")
        let rebindSnapshot = makeCBW005Snapshot(
            sessionID: targetSessionID,
            transcriptHistory: [AiChatMessage(role: .user, content: "old")],
            status: .rebindRequired,
            provider: .anthropic,
            modelHandle: staleHandle,
        )
        let store = makeRebindRequiredStore(snapshot: rebindSnapshot)

        let setupState = AiChatSetupState(
            restoreSessionID: targetSessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: staleHandle,
            lockedModelHandle: staleHandle,
            lastExecutionFailure: nil,
        )
        await store.send(.setup(setupState)) { state in
            self.applyRestoringSetupState(&state, setup: setupState, catalogRows: catalogRows)
            state.selectedModelHandle = nil
            state.unavailableSelectedModelHandle = staleHandle
        }

        let normalizedSnapshot = makeCBW005Snapshot(
            sessionID: targetSessionID,
            transcriptHistory: rebindSnapshot.transcriptHistory,
            provider: .anthropic,
            modelHandle: staleHandle,
        )
        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .rebindRequired(snapshot: normalizedSnapshot),
            restoreFailure: .contextMismatch,
        )) { state in
            self.applyRebindRequiredState(&state, snapshot: normalizedSnapshot, staleHandle: staleHandle)
        }
        XCTAssertFalse(store.state.canSubmit)
        XCTAssertEqual(store.state.sessionStatusText, "Session needs rebind")

        await store.send(.rebindContextTapped) { state in
            state.sessionStatus = .active
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.unavailableSelectedModelHandle = nil
        }
        XCTAssertEqual(store.state.transcriptHistory, rebindSnapshot.transcriptHistory)
    }

    // MARK: - CBW-005-show_chat_session_list

    /// CBW-005-show_chat_session_list: Sessions view는 durable session summary를 불러와 표시한다.
    /// sessionsAppeared가 persistence list를 호출하고 rows/loading/error state를 갱신하는지 검증합니다.
    /// - 검증 내용: listSessions 호출 인자, loading state, loaded rows 반영
    /// - 사전 조건: persistence client가 두 개의 session summary를 반환한다.
    /// - 기대 결과: session list rows와 allRows가 같은 순서로 채워진다.
    func testShowChatSessionListLoadsDurableRows() async {
        let first = makeCBW005SessionSummary(
            sessionID: makeCBW005SessionID("11111111-1111-1111-1111-111111111111"),
            title: "Release notes follow-up",
        )
        let second = makeCBW005SessionSummary(
            sessionID: makeCBW005SessionID("22222222-2222-2222-2222-222222222222"),
            title: "Architecture review",
        )
        let listCalls = LockIsolated<[CBW005SessionListCall]>([])

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
                deleteSession: { _ in },
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

    // MARK: - CBW-005-search_chat_conversation_sessions

    /// CBW-005-search_chat_conversation_sessions: 검색어는 title/preview/context/transcript text를 필터링한다.
    /// Sessions view 검색이 원본 rows를 보존하면서 표시 rows만 deterministic하게 좁히는지 검증합니다.
    /// - 검증 내용: case-insensitive trimmed query, multiple searchable fields, allRows preservation
    /// - 사전 조건: title/preview/context/searchText별 match row와 non-match row가 있다.
    /// - 기대 결과: query가 저장되고 matching rows만 list에 남는다.
    func testSearchChatConversationSessionsFiltersRowsDeterministically() async {
        let rows = makeCBW005SearchRows()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionList: .init(allRows: rows),
        )) {
            AiChatFeature()
        }

        await store.send(.sessionSearchQueryChanged("  rElEaSe  ")) { state in
            state.sessionList.query = "  rElEaSe  "
            state.sessionList.rows = Array(rows.prefix(4))
        }

        XCTAssertEqual(store.state.sessionList.allRows, rows)
    }

    // MARK: - CBW-005-delete_chat_conversation_session

    /// CBW-005-delete_chat_conversation_session: session 삭제는 list와 filtered rows에서 같은 항목을 제거한다.
    /// delete action이 persistence delete를 호출하고 selected row를 정리하는지 검증합니다.
    /// - 검증 내용: deleteSession 호출, allRows removal, filtered rows refresh, selectedSessionID clear
    /// - 사전 조건: sessions list가 query와 selected deleted row를 가진다.
    /// - 기대 결과: 삭제된 session은 rows/allRows에서 사라지고 deletedSessionIDs에 기록된다.
    func testDeleteChatConversationSessionRemovesRowFromListAndFilteredRows() async {
        let deletedSessionID = makeCBW005SessionID("11111111-1111-1111-1111-111111111111")
        let keptSessionID = makeCBW005SessionID("22222222-2222-2222-2222-222222222222")
        let deletedRow = makeCBW005SessionSummary(sessionID: deletedSessionID, title: "Release notes follow-up")
        let keptRow = makeCBW005SessionSummary(
            sessionID: keptSessionID,
            title: "Architecture review",
            preview: "Backend design",
            contextTitle: "Backend",
        )
        let deletedIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(
                allRows: [deletedRow, keptRow],
                query: "release",
                selectedSessionID: deletedSessionID,
            ),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { id in deletedIDs.withValue { $0.append(id) } },
            )
        }

        await store.send(.deleteSessionTapped(deletedSessionID))
        await store.receive(.sessionDeleteSucceeded(deletedSessionID)) { state in
            state.sessionList.allRows = [keptRow]
            state.sessionList.rows = []
            state.sessionList.selectedSessionID = nil
            state.sessionList.deletedSessionIDs = [deletedSessionID]
        }

        XCTAssertEqual(deletedIDs.value, [deletedSessionID])
    }

    private var restoredTranscript: [AiChatMessage] {
        [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "Restored answer"),
        ]
    }

    private var fixedTimestampMs: Int64 {
        1_700_000_000_000
    }

    private func makeRestoreHydrationStore(
        sessionID: AiChatSessionID,
        restoredSnapshot: AiChatSessionSnapshot,
        catalogRows: [AiModelCatalogRow],
    ) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
        let staleLock = makeCBW005RequestLock(sessionID: sessionID, modelRow: catalogRows[1])
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in restoredSnapshot })
        return TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            sessionStatus: .restoring,
            currentContext: makeContextSnapshot(summary: "Current setup context"),
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.minimal),
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: .transportError,
            executionPhase: .processing(staleLock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = makeCBW005LoadOnlyPersistence(persistence)
        }
    }

    private func makeRestoreHydrationSetup(
        sessionID: AiChatSessionID,
        catalogRows: [AiModelCatalogRow],
    ) -> AiChatSetupState {
        AiChatSetupState(
            restoreSessionID: sessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: makeContextSnapshot(summary: "Current setup context"),
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.minimal),
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: .transportError,
        )
    }

    private func applyRestoreHydrationOutcome(
        _ state: inout AiChatFeature.State,
        snapshot: AiChatSessionSnapshot,
    ) {
        state.sessionID = snapshot.sessionID
        state.sessionStatus = .active
        state.transcriptHistory = snapshot.transcriptHistory
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .idle
        state.selectedModelHandle = snapshot.model
        state.selectedThinking = snapshot.selectedThinking
        state.restoreOutcome = .restored(snapshot: snapshot)
        state.restoreFailure = nil
    }

    private func makeOpenSessionStore(
        restoredSnapshot: AiChatSessionSnapshot,
        liveCurrentContext: AiChatCurrentContextSnapshot,
        catalogRows: [AiModelCatalogRow],
    ) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in restoredSnapshot })
        return TestStore(initialState: makeOpenSessionState(
            snapshot: restoredSnapshot,
            liveCurrentContext: liveCurrentContext,
            catalogRows: catalogRows,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = makeCBW005LoadOnlyPersistence(persistence)
        }
    }

    private func makeOpenSessionState(
        snapshot: AiChatSessionSnapshot,
        liveCurrentContext: AiChatCurrentContextSnapshot,
        catalogRows: [AiModelCatalogRow],
    ) -> AiChatFeature.State {
        AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(rows: [AiChatSessionSummary(snapshot: snapshot)]),
            currentContext: liveCurrentContext,
            currentContextFolderStructureModes: [
                AiChatCurrentContextFolderStructureKey(
                    source: .reference,
                    canonicalPath: "/tmp/StaleFolder",
                ): .includeSubfolders,
            ],
            addedAttachments: [makeCBW005Attachment(path: "/tmp/StaleLiveAttachment.txt")],
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[0].handle,
        )
    }

    private func applyOpeningSessionRowState(
        _ state: inout AiChatFeature.State,
        sessionID: AiChatSessionID,
    ) {
        state.mode = .sessions
        state.sessionList.selectedSessionID = sessionID
        state.sessionList.errorMessage = nil
        state.currentContextFolderStructureModes = [:]
        state.restoreSessionID = sessionID
    }

    private func applyOpenedRestoredSessionState(
        _ state: inout AiChatFeature.State,
        snapshot: AiChatSessionSnapshot,
        lockedContext: AiChatLockedRequestContextSnapshot,
    ) {
        applyRestoredSessionState(&state, snapshot: snapshot)
        state.lastRequestContext = lockedContext
        state.lastRequestContextModelHandle = snapshot.model
        state.addedAttachments = []
        state.currentContextFolderStructureModes = [:]
        state.mode = .chat
    }

    private func makeRestoreFailureStore(
        requestedSessionID: AiChatSessionID,
        existingSessionID: AiChatSessionID,
        staleTranscript: [AiChatMessage],
        selectedModel: AiModelHandle,
    ) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
        let brokenRow = makeCBW005SessionSummary(
            sessionID: requestedSessionID,
            title: "Broken session",
        )
        return TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(rows: [brokenRow]),
            sessionID: existingSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current"),
            transcriptHistory: staleTranscript,
            draftText: "Keep me",
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: selectedModel,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = makeCBW005MissingPersistence()
        }
    }

    private func applyRestoreFailureRowTappedState(
        _ state: inout AiChatFeature.State,
        sessionID: AiChatSessionID,
    ) {
        state.mode = .sessions
        state.sessionList.selectedSessionID = sessionID
        state.sessionList.errorMessage = nil
        state.restoreSessionID = sessionID
    }

    private func makeRebindRequiredStore(
        snapshot: AiChatSessionSnapshot,
    ) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in snapshot })
        return TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = makeCBW005LoadOnlyPersistence(persistence)
        }
    }

    private func applyNewChatStartedState(
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

    private func applyNewChatCreatedState(
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

    private func applyRestoredSessionState(
        _ state: inout AiChatFeature.State,
        snapshot: AiChatSessionSnapshot,
    ) {
        state.sessionID = snapshot.sessionID
        state.sessionStatus = .active
        state.currentSessionCustomTitle = snapshot.customTitle
        state.transcriptHistory = snapshot.transcriptHistory
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.lastRequestContext = snapshot.lastRequestContext
        state.executionPhase = .idle
        state.selectedModelHandle = snapshot.model
        state.selectedThinking = snapshot.selectedThinking
        state.unavailableSelectedModelHandle = nil
        state.restoreOutcome = .restored(snapshot: snapshot)
        state.restoreFailure = nil
        state.mode = .chat
        state.sessionList.errorMessage = nil
    }

    private func applyRestoringSetupState(
        _ state: inout AiChatFeature.State,
        setup: AiChatSetupState,
        catalogRows: [AiModelCatalogRow],
    ) {
        state.restoreSessionID = setup.restoreSessionID
        state.restoreOutcome = nil
        state.restoreFailure = nil
        state.sessionID = nil
        state.sessionStatus = .restoring
        state.currentContext = setup.currentContext
        state.transcriptHistory = setup.transcriptHistory
        state.draftText = setup.draftText
        state.catalogRows = catalogRows
        state.modelListState = .loaded(makeProviderModels())
        state.selectedModelHandle = setup.selectedModelHandle
        state.selectedThinking = setup.selectedThinking
        state.unavailableSelectedModelHandle = nil
        state.lockedModelHandle = setup.lockedModelHandle
        state.lastExecutionFailure = setup.lastExecutionFailure
        state.executionPhase = .idle
    }

    private func applyRestoreFailureListState(
        _ state: inout AiChatFeature.State,
        message: String,
    ) {
        state.sessionList.selectedSessionID = nil
        state.sessionList.errorMessage = message
    }

    private func applyRebindRequiredState(
        _ state: inout AiChatFeature.State,
        snapshot: AiChatSessionSnapshot,
        staleHandle: AiModelHandle,
    ) {
        state.sessionID = snapshot.sessionID
        state.sessionStatus = .rebindRequired
        state.transcriptHistory = snapshot.transcriptHistory
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.lastRequestContext = nil
        state.lastRequestContextModelHandle = nil
        state.executionPhase = .idle
        state.selectedModelHandle = nil
        state.selectedThinking = nil
        state.restoreOutcome = .rebindRequired(snapshot: snapshot)
        state.restoreFailure = .contextMismatch
        state.unavailableSelectedModelHandle = staleHandle
    }
}

private struct CBW005SessionListCall: Equatable {
    var limit: Int?
    var query: String?
}

private func makeCBW005SessionID(_ rawValue: String) -> AiChatSessionID {
    AiChatSessionID(rawValue: makeUUID(rawValue))
}

private func makeCBW005EmptySnapshot(
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

private func makeCBW005Snapshot(
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

private func makeCBW005LockedContext(summary: String) -> AiChatLockedRequestContextSnapshot {
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

private func makeCBW005RequestLock(
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

private func makeCBW005Attachment(path: String) -> AiChatAttachmentDraft {
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

private func makeCBW005SearchRows() -> [AiChatSessionSummary] {
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

private func makeCBW005SessionSummary(
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

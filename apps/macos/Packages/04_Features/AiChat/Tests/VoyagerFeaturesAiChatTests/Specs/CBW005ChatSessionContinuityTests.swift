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

    /// CBW-005-continue_chat_conversation_session: ContentPane History 열기는 active chat을 정리하지 않고 보존한다.
    /// AI Chat 페이지에서 목록을 열었다가 뒤로가면 직전 기존 채팅으로 즉시 복귀하는지 검증합니다.
    /// - 검증 내용: showSessionsTapped는 transcript/sessionID를 보존하고 returnToChatTapped가 같은 chat으로 복귀
    /// - 사전 조건: active chat에 transcript가 있다.
    /// - 기대 결과: mode만 sessions/chat으로 전환되고 대화 state는 유지된다.
    func testShowSessionsThenReturnPreservesExistingChat() async {
        let sessionID = makeCBW005SessionID("12121212-1212-1212-1212-121212121212")
        let transcript = restoredTranscript

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionList: .init(
                allRows: [makeCBW005SessionSummary(sessionID: sessionID, title: "Existing chat")],
                rows: [makeCBW005SessionSummary(sessionID: sessionID, title: "Existing chat")],
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            sessionStatus: .active,
            transcriptHistory: transcript,
            draftText: "Follow up",
        )) {
            AiChatFeature()
        }

        await store.send(.showSessionsTapped) { state in
            state.mode = .sessions
        }
        await store.send(.returnToChatTapped) { state in
            state.mode = .chat
            state.restoreOutcome = nil
            state.restoreFailure = nil
        }

        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.transcriptHistory, transcript)
        XCTAssertEqual(store.state.draftText, "Follow up")
    }

    /// CBW-005-continue_chat_conversation_session: ContentPane History 열기는 빈 new chat draft도 보존한다.
    /// 새 AI Chat 페이지에서 목록으로 갔다가 뒤로가면 직전 새 채팅 페이지로 돌아오는지 검증합니다.
    /// - 검증 내용: showSessionsTapped는 emptyDraftSessionID를 삭제하지 않고 returnToChatTapped가 같은 draft로 복귀
    /// - 사전 조건: untouched empty draft가 chat mode에 열려 있다.
    /// - 기대 결과: draft session은 삭제되지 않고 sessionID/emptyDraftSessionID가 유지된다.
    func testShowSessionsThenReturnPreservesNewChatDraft() async {
        let sessionID = makeCBW005SessionID("13131313-1313-1313-1313-131313131313")
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [makeCBW005SessionSummary(sessionID: sessionID, status: .idle)],
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                },
            )
        }

        await store.send(.showSessionsTapped) { state in
            state.mode = .sessions
        }
        await store.send(.returnToChatTapped) { state in
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.mode = .chat
        }

        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.emptyDraftSessionID, sessionID)
        XCTAssertEqual(deletedSessionIDs.value, [])
    }

    /// CBW-005-open_chat_conversation_session: 다른 row restore 중 뒤로가기는 진행 중인 restore를 취소하지 않는다.
    /// 목록에서 기존 session을 선택한 직후 return action이 이전 chat으로 되돌리는 회귀를 막습니다.
    /// - 검증 내용: pending restoreSessionID가 current session과 다르면 returnToChatTapped는 no-op
    /// - 사전 조건: A chat이 열려 있고 B session restore가 pending이다.
    /// - 기대 결과: sessions mode와 restore target이 유지된다.
    func testReturnToChatDoesNotCancelPendingDifferentSessionRestore() async {
        let currentSessionID = makeCBW005SessionID("14141414-1414-1414-1414-141414141414")
        let restoringSessionID = makeCBW005SessionID("15151515-1515-1515-1515-151515151515")

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: restoringSessionID,
            mode: .sessions,
            sessionList: .init(selectedSessionID: restoringSessionID),
            sessionID: currentSessionID,
            sessionStatus: .active,
            transcriptHistory: restoredTranscript,
        )) {
            AiChatFeature()
        }

        await store.send(.returnToChatTapped)

        XCTAssertEqual(store.state.mode, .sessions)
        XCTAssertEqual(store.state.sessionID, currentSessionID)
        XCTAssertEqual(store.state.restoreSessionID, restoringSessionID)
        XCTAssertEqual(store.state.sessionList.selectedSessionID, restoringSessionID)
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
            state.sessionList.hasLoadedRows = true
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

    // MARK: - CBW-005-show_chat_session_list

    /// CBW-005-show_chat_session_list: AiChat feature의 초기 mode는 sessions list에서 시작한다.
    /// AiChat feature의 초기 mode는 sessions list에서 시작한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: initial mode, empty session list state
    /// - 사전 조건: 새 AiChatFeature.State로 reducer를 생성한다.
    /// - 기대 결과: 초기 진입점은 sessions mode이고 session list는 비어 있는 기본 상태다.
    func testInitialModeDefaultsToSessions() {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        XCTAssertEqual(store.state.mode, AiChatMode.sessions)
        XCTAssertEqual(store.state.sessionList, .init())
    }

    // MARK: - CBW-005-start_chat_conversation_session

    /// CBW-005-start_chat_conversation_session: 선택 모델이 없어도 New Chat은 durable unselected draft snapshot을 저장한다.
    /// 선택 모델이 없어도 New Chat은 durable unselected draft snapshot을 저장한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: new session creation, unselected snapshot save, current context preservation
    /// - 사전 조건: sessions mode에서 selectedModelHandle이 nil인 상태로 new chat을 시작한다.
    /// - 기대 결과: 새 idle session snapshot이 저장되고 model selection 없이 chat mode로 진입한다.
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

    /// CBW-005-start_chat_conversation_session: New Chat은 이전 chat에 남아 있던 attachment와 folder mode를 초기화한다.
    /// New Chat은 이전 chat에 남아 있던 attachment와 folder mode를 초기화한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: addedAttachments reset, folder structure reset, new chat snapshot creation
    /// - 사전 조건: sessions mode에 stale attachment와 currentContextFolderStructureModes가 남아 있다.
    /// - 기대 결과: 새 chat draft는 깨끗한 attachment/context folder state로 시작한다.
    func testNewChatTappedClearsStaleAddedAttachments() async {
        let staleAttachment = makeNavigationAttachment(path: "/tmp/Stale.pdf")
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            currentContextFolderStructureModes: [
                makeNavigationFolderKey("/tmp/StaleFolder"): .includeSubfolders,
            ],
            addedAttachments: [staleAttachment],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_000))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in },
            )
        }

        await store.send(.newChatTapped) { state in
            applyNavigationNewChatStarted(&state, sessionID: newSessionID)
        }

        let expectedSnapshot = makeNavigationEmptySnapshot(sessionID: newSessionID)
        await store.receive(.newChatCreated(expectedSnapshot)) { state in
            applyNavigationNewChatCreated(&state, snapshot: expectedSnapshot)
        }
    }

    /// CBW-005-start_chat_conversation_session: 새 chat을 열어도 기존 in-flight request completion snapshot은 원래 session에 저장한다.
    /// 새 chat을 열어도 기존 in-flight request completion snapshot은 원래 session에 저장한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: new chat creation during processing, original completion persistence, unread session marking
    /// - 사전 조건: 기존 active session 요청이 진행 중인 상태에서 사용자가 new chat을 시작한다.
    /// - 기대 결과: 새 draft는 분리되어 열리고 기존 request final snapshot은 원래 session summary로 저장된다.
    func testNewChatTappedPreservesInFlightRequestAndSavesOriginalCompletion() async {
        let oldSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111331"))
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000002"))
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let fixedMs: Int64 = 1_700_000_001_331
        let stream = AiChatExecutionStreamDriver()
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
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
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
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Question before new chat")]
            state.lockedModelHandle = selectedHandle
            state.sessionList.unreadCompletedSessionIDs = []
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
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

        await store.send(.newChatTapped) { state in
            applySessionListNewChatStarted(&state, sessionID: newSessionID)
            state.executionPhase = .processing(lock)
        }

        let newChatSnapshot = makeSessionListEmptySnapshot(
            sessionID: newSessionID,
            updatedAtMs: fixedMs,
        )
        await store.receive(.newChatCreated(newChatSnapshot)) { state in
            applySessionListNewChatCreated(&state, snapshot: newChatSnapshot)
            state.executionPhase = .processing(lock)
        }

        let assistantMessage = AiChatMessage(role: .assistant, content: "Original request completed")
        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: assistantMessage,
            completedAtMs: fixedMs,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        let finalizedLock = lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .completed(finalizedLock)
        }

        let expectedOriginalSnapshot = AiChatSessionSnapshot(
            sessionID: oldSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Question before new chat"),
                assistantMessage,
            ],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        await store.receive(.sessionSnapshotSaved(AiChatSessionSummary(snapshot: expectedOriginalSnapshot))) { state in
            state.sessionList.replaceRow(AiChatSessionSummary(snapshot: expectedOriginalSnapshot))
            state.sessionList.unreadCompletedSessionIDs = [oldSessionID]
            state.sessionList.errorMessage = nil
        }

        await store.finish()
        XCTAssertEqual(store.state.sessionID, newSessionID)
        XCTAssertEqual(store.state.transcriptHistory, [])
        if case .processing = store.state.surfaceState {
            XCTFail("The new chat draft must not show the original request as processing")
        }
        XCTAssertFalse(store.state.isProcessing)
        XCTAssertTrue(savedSnapshots.value.contains(newChatSnapshot))
        XCTAssertTrue(savedSnapshots.value.contains(expectedOriginalSnapshot))
    }

    /// CBW-005-start_chat_conversation_session: rebind required recovery에서 시작한 New Chat도 durable unselected snapshot을
    /// 저장한다.
    /// rebind required recovery에서 시작한 New Chat도 durable unselected snapshot을 저장한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: rebind recovery path, unselected snapshot save, selection clear
    /// - 사전 조건: restoreFailure가 contextMismatch이고 sessionStatus가 rebindRequired다.
    /// - 기대 결과: 새 chat snapshot이 저장되고 이전 stale model selection은 제거된다.
    func testStartNewChatFromRebindTappedSavesDurableUnselectedSnapshot() async {
        let catalogRows = makeCatalogRows()
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            restoreFailure: .contextMismatch,
            sessionStatus: .rebindRequired,
            transcriptHistory: [AiChatMessage(role: .user, content: "old")],
            draftText: "follow up",
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[1].handle,
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

        await store.send(.startNewChatFromRebindTapped) { state in
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
    }

    // MARK: - CBW-005-continue_chat_conversation_session

    /// CBW-005-continue_chat_conversation_session: teardown은 processing draft를 정리하되 conversation history는 지우지 않는다.
    /// teardown은 processing draft를 정리하되 conversation history는 지우지 않는다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: processing teardown, transcript preservation, draft preservation, selection retention
    /// - 사전 조건: active chat가 processing lock과 partial assistant draft를 가진 상태다.
    /// - 기대 결과: streaming/runtime lock만 제거되고 기존 transcript와 draft는 이어갈 수 있게 남는다.
    func testTeardownRequestedStopsProcessingDraftWithoutClearingConversation() async {
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111122"))
        let requestID = AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000004"))
        let runID = AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000005"))
        let messages = [AiChatMessage(role: .user, content: "Keep this transcript")]
        let lock = makeTeardownProcessingLock(input: TeardownLockInput(
            sessionID: sessionID,
            requestIDs: (requestID: requestID, runID: runID),
            catalogRow: catalogRows[0],
            selectedModel: models[0],
            summary: summary,
            messages: messages,
        ))
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: messages,
            draftText: "Draft survives close",
            streamingAssistantDraft: "Partial response",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.medium),
            lockedModelHandle: catalogRows[0].handle,
            lastExecutionFailure: nil,
            executionPhase: .processing(lock),
        )) {
            AiChatFeature()
        }

        await store.send(.teardownRequested) { state in
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.executionPhase = .idle
        }

        XCTAssertEqual(store.state.transcriptHistory, messages)
        XCTAssertEqual(store.state.draftText, "Draft survives close")
        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[0].handle)
    }

    /// CBW-005-continue_chat_conversation_session: 아무 상호작용이 없는 empty new chat draft는 sessions 복귀 시 삭제한다.
    /// 아무 상호작용이 없는 empty new chat draft는 sessions 복귀 시 삭제한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: back-to-sessions cleanup, pending empty draft deletion, hidden draft rows
    /// - 사전 조건: idle empty draft session이 chat mode에 열려 있다.
    /// - 기대 결과: sessions로 돌아가면 empty draft session이 persistence에서 삭제된다.
    func testBackToSessionsDeletesUntouchedNewChatDraft() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let summary = makeCBW005SessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                },
            )
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
            state.pendingEmptyDraftDeletionSessionIDs = [sessionID]
            state.emptyDraftSessionID = nil
            state.sessionID = nil
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionList.selectedSessionID = nil
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.hiddenEmptyDraftSessionIDs, [sessionID])

        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.pendingEmptyDraftDeletionSessionIDs = []
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.deletedSessionIDs = [sessionID]
        }

        XCTAssertEqual(deletedSessionIDs.value, [sessionID])
    }

    /// CBW-005-continue_chat_conversation_session: 입력만 하고 보내지 않은 new chat draft도 sessions 복귀 시 삭제한다.
    /// 입력만 하고 보내지 않은 new chat draft도 sessions 복귀 시 삭제한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: typed-but-unsent draft deletion, pending deletion bookkeeping
    /// - 사전 조건: emptyDraftSessionID가 있는 idle draft에서 사용자가 text만 입력했다.
    /// - 기대 결과: submit되지 않은 draft session은 목록으로 돌아갈 때 제거된다.
    func testBackToSessionsDeletesNewChatDraftAfterTypingWithoutSending() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444"))
        let summary = makeCBW005SessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                },
            )
        }

        await store.send(.draftTextChanged("Do not keep unsent draft")) { state in
            state.draftText = "Do not keep unsent draft"
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
            state.pendingEmptyDraftDeletionSessionIDs = [sessionID]
            state.emptyDraftSessionID = nil
            state.sessionID = nil
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionList.selectedSessionID = nil
            state.sessionList.errorMessage = nil
        }

        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.pendingEmptyDraftDeletionSessionIDs = []
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.deletedSessionIDs = [sessionID]
        }

        XCTAssertEqual(deletedSessionIDs.value, [sessionID])
    }

    /// CBW-005-continue_chat_conversation_session: model selection만 한 idle draft도 sessions 복귀 시 삭제한다.
    /// model selection만 한 idle draft도 sessions 복귀 시 삭제한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: model-selected empty draft deletion, selectedSessionID clear
    /// - 사전 조건: idle new chat draft에서 model만 고르고 아직 어떤 메시지도 보내지 않았다.
    /// - 기대 결과: 대화가 시작되지 않은 draft는 sessions 복귀 시 삭제된다.
    func testBackToSessionsDeletesNewChatDraftAfterModelSelectionWithoutSending() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("66666666-6666-6666-6666-666666666666"))
        let model = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let summary = makeCBW005SessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
            selectedModelHandle: model,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                },
            )
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
            state.pendingEmptyDraftDeletionSessionIDs = [sessionID]
            state.emptyDraftSessionID = nil
            state.sessionID = nil
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionList.selectedSessionID = nil
            state.sessionList.errorMessage = nil
        }

        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.pendingEmptyDraftDeletionSessionIDs = []
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.deletedSessionIDs = [sessionID]
        }

        XCTAssertEqual(deletedSessionIDs.value, [sessionID])
    }

    /// CBW-005-continue_chat_conversation_session: empty draft 삭제 실패는 sessions 화면의 list error로 surfaced 된다.
    /// empty draft 삭제 실패는 sessions 화면의 list error로 surfaced 된다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: delete failure surface, errorMessage, row preservation after failed cleanup
    /// - 사전 조건: sessions 복귀 중 empty draft 삭제가 persistence error를 던진다.
    /// - 기대 결과: draft row는 유지되고 사용자는 sessions 화면에서 실패 메시지를 확인한다.
    func testBackToSessionsSurfacesEmptyDraftDeleteFailure() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555"))
        let summary = makeCBW005SessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                    throw AiChatSessionPersistenceClientError.applicationSupportDirectoryUnavailable
                },
            )
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
            state.pendingEmptyDraftDeletionSessionIDs = [sessionID]
            state.emptyDraftSessionID = nil
            state.sessionID = nil
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionList.selectedSessionID = nil
            state.sessionList.errorMessage = nil
        }

        await store.receive(.sessionDeleteFailed(sessionID, "That chat could not be deleted right now.")) { state in
            state.pendingEmptyDraftDeletionSessionIDs = []
            state.sessionList.errorMessage = "That chat could not be deleted right now."
        }

        XCTAssertEqual(deletedSessionIDs.value, [sessionID])
        XCTAssertEqual(store.state.sessionList.allRows, [summary])
    }

    // MARK: - CBW-005-show_chat_session_restore_failure

    /// CBW-005-show_chat_session_restore_failure: 누락된 session record restore는 오류 대신 새 session fallback으로 전환한다.
    /// 누락된 session record restore는 오류 대신 새 session fallback으로 전환한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: missing record fallback, new session snapshot outcome, stale runtime clear
    /// - 사전 조건: restoreSessionID가 주어졌지만 persistence load는 nil을 반환한다.
    /// - 기대 결과: 복원은 실패 메시지 대신 새로운 idle session으로 전환되고 기존 stale transcript는 제거된다.
    func testRestoreMissingRecordFallsBackToNewSessionWithoutError() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in nil })
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in try await persistence.loadSession(id) },
                saveSession: { _ in },
                deleteSession: { _ in },
            )
        }

        let staleTranscript = [AiChatMessage(role: .user, content: "stale")]
        await store.send(.setup(AiChatSetupState(
            restoreSessionID: targetSessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: staleTranscript,
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[1].handle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
        ))) { state in
            state.restoreSessionID = targetSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionID = nil
            state.sessionStatus = .restoring
            state.currentContext = summary
            state.transcriptHistory = staleTranscript
            state.draftText = "Draft"
            state.catalogRows = catalogRows
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = catalogRows[1].handle
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = catalogRows[1].handle
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        let fallbackSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let fallbackSnapshot = AiChatSessionSnapshot(
            sessionID: fallbackSessionID,
            status: .idle,
            provider: catalogRows[1].handle.provider,
            model: catalogRows[1].handle,
            selectedModelRow: catalogRows[1],
            transcriptHistory: [],
            updatedAtMs: 0,
        )

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .newSession(snapshot: fallbackSnapshot),
            restoreFailure: .missingRecord,
        )) { state in
            state.restoreOutcome = .newSession(snapshot: fallbackSnapshot)
            state.restoreFailure = .missingRecord
            state.sessionID = fallbackSessionID
            state.sessionStatus = .idle
            state.transcriptHistory = []
            state.draftText = "Draft"
            state.selectedModelHandle = catalogRows[1].handle
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertEqual(store.state.sessionStatusText, "Started new session")
        XCTAssertTrue(store.state.canSubmit)
        XCTAssertEqual(store.state.transcriptHistory, [])
        XCTAssertEqual(store.state.transcriptAutoScrollVersion, 0)
    }

    /// CBW-005-show_chat_session_restore_failure: 빈 catalog에서 missing record fallback이 unknown model selection을 만들지
    /// 않는다.
    /// 빈 catalog에서 missing record fallback이 unknown model selection을 만들지 않는다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: empty catalog fallback, no unknown selected model, canSubmit false
    /// - 사전 조건: restore 대상 record가 없고 현재 catalog도 비어 있다.
    /// - 기대 결과: 새 fallback session은 model 없이 시작하며 잘못된 selection display를 노출하지 않는다.
    func testRestoreMissingRecordWithEmptyCatalogDoesNotExposeUnknownModelSelection() async {
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("99999999-9999-9999-9999-999999999999"))
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in nil })
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in try await persistence.loadSession(id) },
                saveSession: { _ in },
                deleteSession: { _ in },
            )
        }

        await store.send(.setup(AiChatSetupState(
            restoreSessionID: targetSessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "Draft",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        ))) { state in
            state.restoreSessionID = targetSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionID = nil
            state.sessionStatus = .restoring
            state.currentContext = summary
            state.transcriptHistory = []
            state.draftText = "Draft"
            state.catalogRows = []
            state.modelListState = .empty
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        let fallbackSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let fallbackSnapshot = AiChatSessionSnapshot(
            sessionID: fallbackSessionID,
            status: .idle,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
            updatedAtMs: 0,
        )

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .newSession(snapshot: fallbackSnapshot),
            restoreFailure: .missingRecord,
        )) { state in
            state.restoreOutcome = .newSession(snapshot: fallbackSnapshot)
            state.restoreFailure = .missingRecord
            state.sessionID = fallbackSessionID
            state.sessionStatus = .idle
            state.transcriptHistory = []
            state.draftText = "Draft"
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.selectedModelDisplayModel)
        XCTAssertFalse(store.state.canSubmit)
        XCTAssertEqual(store.state.restoreFailure, .missingRecord)
        XCTAssertEqual(store.state.sessionStatus, .idle)
    }

    // MARK: - CBW-005-show_rebind_required_state

    /// CBW-005-show_rebind_required_state: rebind required 상태에서는 유효한 model selection이 있어도 submit을 막는다.
    /// rebind required 상태에서는 유효한 model selection이 있어도 submit을 막는다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: canSubmit false, chatInputDisplayModel.canSubmit false
    /// - 사전 조건: sessionStatus가 rebindRequired이고 catalog와 selected model 자체는 유효하다.
    /// - 기대 결과: 사용자는 rebind recovery를 마치기 전까지 follow-up submit을 실행할 수 없다.
    func testRebindRequiredBlocksSubmitEvenWhenSelectionIsOtherwiseValid() {
        let catalogRows = makeCatalogRows()
        let state = AiChatFeature.State(
            sessionStatus: .rebindRequired,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            transcriptHistory: [AiChatMessage(role: .user, content: "old")],
            draftText: "follow up",
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[1].handle,
        )

        XCTAssertFalse(state.canSubmit)
        XCTAssertFalse(state.chatInputDisplayModel.canSubmit)
    }

    // MARK: - CBW-005-show_chat_session_list

    /// CBW-005-show_chat_session_list: teardown은 session list의 in-flight list/rename/delete effect를 모두 취소한다.
    /// teardown은 session list의 in-flight list/rename/delete effect를 모두 취소한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: listSessions cancellation, rename cancellation, delete cancellation
    /// - 사전 조건: sessions 화면에서 list load, rename confirm, delete action이 동시에 진행 중이다.
    /// - 기대 결과: teardown 이후 관련 persistence effect가 모두 cancel되고 dangling effect가 남지 않는다.
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
                    makeCBW005SessionSummary(sessionID: renameSessionID, title: "Rename me"),
                    makeCBW005SessionSummary(sessionID: deleteSessionID, title: "Delete me"),
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

    /// CBW-005-show_chat_session_list: teardown은 아직 저장 중인 new chat draft snapshot effect를 취소한다.
    /// teardown은 아직 저장 중인 new chat draft snapshot effect를 취소한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: in-flight new chat save cancellation, selectedSessionID clear
    /// - 사전 조건: new chat snapshot save가 아직 완료되지 않은 상태다.
    /// - 기대 결과: teardown 이후 save task는 cancel되고 partial save side effect만 남는다.
    func testTeardownRequestedCancelsInFlightNewChatSave() async {
        await assertInFlightNewChatSaveCancelled(by: .teardown)
    }

    /// CBW-005-show_chat_session_list: reset도 진행 중인 new chat draft snapshot save effect를 취소한다.
    /// reset도 진행 중인 new chat draft snapshot save effect를 취소한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: reset cancellation of new chat save, state reset to idle draft-less surface
    /// - 사전 조건: new chat snapshot save가 시작된 직후 사용자가 reset을 누른다.
    /// - 기대 결과: save task는 cancel되고 state는 빈 draft 상태로 돌아간다.
    func testResetTappedCancelsInFlightNewChatSave() async {
        await assertInFlightNewChatSaveCancelled(by: .reset)
    }

    /// CBW-005-show_chat_session_list: session rename 성공은 custom title을 저장하고 filtered rows를 즉시 갱신한다.
    /// session rename 성공은 custom title을 저장하고 filtered rows를 즉시 갱신한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: rename persistence, summary replacement, filtered rows update, currentSessionCustomTitle
    /// - 사전 조건: sessions list에서 rename editor가 열려 있고 load/save persistence가 정상 동작한다.
    /// - 기대 결과: trimmed custom title이 저장되고 allRows와 filtered rows 모두 새 summary로 교체된다.
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

    /// CBW-005-show_chat_session_list: blank title rename은 custom title을 지우고 derived title로 되돌린다.
    /// blank title rename은 custom title을 지우고 derived title로 되돌린다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: blank rename normalization, customTitle nil, derived summary title
    /// - 사전 조건: 이미 custom title이 있는 session을 공백 title로 rename 한다.
    /// - 기대 결과: 저장된 snapshot의 customTitle은 nil이 되고 목록 title은 원래 derived prompt title로 복귀한다.
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

    /// CBW-005-show_chat_session_list: session rename 실패는 editor를 닫지 않고 list error만 노출한다.
    /// session rename 실패는 editor를 닫지 않고 list error만 노출한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: rename failure surface, renamingSessionID retention, renameDraftText retention
    /// - 사전 조건: rename confirm 시 persistence load가 오류를 던진다.
    /// - 기대 결과: 사용자는 draft text를 유지한 채 다시 시도할 수 있고 sessions list에는 실패 메시지가 남는다.
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

    // MARK: - CBW-005-delete_chat_conversation_session

    /// CBW-005-delete_chat_conversation_session: session 삭제 실패는 row를 유지하고 list error를 표시한다.
    /// session 삭제 실패는 row를 유지하고 list error를 표시한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: delete failure surface, row preservation, selected row retention
    /// - 사전 조건: sessions list에서 선택된 row 삭제가 persistence failure를 반환한다.
    /// - 기대 결과: 삭제된 row는 목록에 남고 사용자는 sessions 화면에서 오류를 확인한다.
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

    /// CBW-005-delete_chat_conversation_session: sessions mode에서 현재 loaded session을 삭제해도 active chat state 자체는 오염되지
    /// 않는다.
    /// sessions mode에서 현재 loaded session을 삭제해도 active chat state 자체는 오염되지 않는다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: list deletion of loaded session, transcript preservation, currentContext preservation
    /// - 사전 조건: 복원 완료된 active session이 sessions mode에서 선택된 상태다.
    /// - 기대 결과: 목록 row는 제거되지만 메모리에 유지된 chat transcript와 context는 손상되지 않는다.
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

    /// CBW-005-delete_chat_conversation_session: 삭제된 processing session으로부터 늦게 도착한 snapshot callback은 row를 되살리지 않는다.
    /// 삭제된 processing session으로부터 늦게 도착한 snapshot callback은 row를 되살리지 않는다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: late snapshot ignore after deletion, deletedSessionIDs guard, row non-reinsertion
    /// - 사전 조건: processing session 삭제 후 sessionSnapshotUpdated/sessionSnapshotSaved가 늦게 도착한다.
    /// - 기대 결과: 삭제된 session row는 다시 목록에 삽입되지 않는다.
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
        await store.send(.sessionListLoaded([summaries.final])) { state in
            state.sessionList.hasLoadedRows = true
        }

        assertProcessingSessionDeleted(store.state, sessionID: sessionID, deletedIDs: deletedIDs.value)
    }

    /// CBW-005-delete_chat_conversation_session: 현재 processing session 삭제는 request를 먼저 cancel한 뒤 삭제한다.
    /// 현재 processing session 삭제는 request를 먼저 cancel한 뒤 삭제한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: request cancellation, delete ordering, no late final persistence
    /// - 사전 조건: submit request가 진행 중인 session을 sessions list에서 삭제한다.
    /// - 기대 결과: request stream은 cancel되고 delete가 수행되며 late final 응답은 삭제된 session을 되살리지 않는다.
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

    /// CBW-005-delete_chat_conversation_session: completed session 삭제는 in-flight final snapshot save를 cancel한 뒤 삭제한다.
    /// completed session 삭제는 in-flight final snapshot save를 cancel한 뒤 삭제한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: final snapshot save cancellation, delete ordering, no completed save leakage
    /// - 사전 조건: assistant final 응답 후 saveSession이 아직 완료되지 않은 상태다.
    /// - 기대 결과: save task는 cancel되고 삭제만 성공하며 완료 snapshot은 저장되지 않는다.
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

    /// CBW-005-delete_chat_conversation_session: processing session 삭제는 request-start snapshot save도 cancel한다.
    /// processing session 삭제는 request-start snapshot save도 cancel한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: request-start snapshot save cancellation, delete ordering, no partial snapshot persistence
    /// - 사전 조건: submit 직후 request-start snapshot save가 진행 중인 session을 삭제한다.
    /// - 기대 결과: start snapshot save는 cancel되고 삭제만 완료된다.
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

    // MARK: - CBW-005-show_chat_session_list

    /// CBW-005-show_chat_session_list: Bucketing Groups Rows Using Content Pane Date Sections
    /// CBW-005 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testBucketingGroupsRowsUsingContentPaneDateSections() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = makeDate(year: 2026, month: 5, day: 25, calendar: calendar)

        let rows = makeBucketingTestRows(calendar: calendar, now: now)

        let displayModel = AiChatSessionsDisplayModel(
            rows: [rows.year, rows.previous30Days, rows.today, rows.month, rows.yesterday, rows.previous7Days],
            now: now,
            calendar: calendar,
        )

        assertBucketingSections(displayModel)
        assertBucketingTitles(displayModel)
        assertBucketingRowTitles(displayModel)
    }

    /// CBW-005-show_chat_session_list: Empty State Uses Exact Strings
    /// CBW-005 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testEmptyStateUsesExactStrings() {
        let displayModel = AiChatSessionsDisplayModel(rows: [], now: makeFixedDate(milliseconds: 1_700_000_000_000))

        XCTAssertTrue(displayModel.isEmpty)
        XCTAssertEqual(displayModel.title, "Sessions")
        XCTAssertEqual(displayModel.newChatTitle, "New Chat")
        XCTAssertEqual(displayModel.searchPlaceholder, "Search")
        XCTAssertEqual(displayModel.emptyTitle, "No sessions yet")
        XCTAssertEqual(displayModel.emptyDetail, "Start a new chat with the current context")
        XCTAssertTrue(displayModel.sections.isEmpty)
    }

    /// CBW-005-show_chat_session_list: Search Empty State Uses Exact Strings When Rows Are Filtered Out
    /// CBW-005 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testSearchEmptyStateUsesExactStringsWhenRowsAreFilteredOut() {
        let displayModel = AiChatSessionsDisplayModel(
            rows: [],
            now: makeFixedDate(milliseconds: 1_700_000_000_000),
            query: "  missing  ",
            totalRowCount: 2,
        )

        XCTAssertTrue(displayModel.isEmpty)
        XCTAssertEqual(displayModel.emptyTitle, "No matching sessions")
        XCTAssertEqual(displayModel.emptyDetail, "Try a different search term.")
        XCTAssertTrue(displayModel.sections.isEmpty)
    }

    /// CBW-005-show_chat_session_list: Row Activity States Prefer Processing Over Unread Completion
    /// CBW-005 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testRowActivityStatesPreferProcessingOverUnreadCompletion() {
        let now = makeFixedDate(milliseconds: 1_700_000_000_000)
        let processingID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111181"))
        let unreadID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111182"))
        let idleID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111183"))
        let processing = makeSessionSummary(
            sessionID: processingID,
            title: "Processing",
            updatedAtMs: milliseconds(for: now),
        )
        let unread = makeSessionSummary(sessionID: unreadID, title: "Unread", updatedAtMs: milliseconds(for: now))
        let idle = makeSessionSummary(sessionID: idleID, title: "Idle", updatedAtMs: milliseconds(for: now))

        let displayModel = AiChatSessionsDisplayModel(
            rows: [processing, unread, idle],
            now: now,
            processingSessionID: processingID,
            unreadCompletedSessionIDs: [processingID, unreadID],
        )
        let rows = displayModel.sections.flatMap(\.rows)

        XCTAssertEqual(rows.map(\.id), [processingID, unreadID, idleID])
        XCTAssertEqual(rows.map(\.activityState), [.processing, .unreadCompleted, .idle])
        XCTAssertNil(rows[0].detail)
        XCTAssertEqual(rows[1].detail, "Preview")
        XCTAssertEqual(rows[2].detail, "Preview")
    }

    /// CBW-005-show_chat_session_list: Hidden Empty Draft Rows Are Excluded From Sections
    /// CBW-005 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testHiddenEmptyDraftRowsAreExcludedFromSections() {
        let now = makeFixedDate(milliseconds: 1_700_000_000_000)
        let draftID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111184"))
        let visibleID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111185"))
        let draft = makeSessionSummary(sessionID: draftID, title: "New Chat", updatedAtMs: milliseconds(for: now))
        let visible = makeSessionSummary(
            sessionID: visibleID,
            title: "Visible prompt",
            updatedAtMs: milliseconds(for: now),
        )

        let displayModel = AiChatSessionsDisplayModel(
            rows: [draft, visible],
            now: now,
            totalRowCount: 2,
            hiddenSessionIDs: [draftID],
        )
        let rows = displayModel.sections.flatMap(\.rows)

        XCTAssertEqual(rows.map(\.id), [visibleID])
        XCTAssertEqual(rows.map(\.title), ["Visible prompt"])
    }

    /// CBW-005-show_chat_session_list: Search Query Still Uses No Sessions Copy When There Are No Saved Sessions
    /// CBW-005 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testSearchQueryStillUsesNoSessionsCopyWhenThereAreNoSavedSessions() {
        let displayModel = AiChatSessionsDisplayModel(
            rows: [],
            now: makeFixedDate(milliseconds: 1_700_000_000_000),
            query: "  missing  ",
            totalRowCount: 0,
        )

        XCTAssertTrue(displayModel.isEmpty)
        XCTAssertEqual(displayModel.emptyTitle, "No sessions yet")
        XCTAssertEqual(displayModel.emptyDetail, "Start a new chat with the current context")
        XCTAssertTrue(displayModel.sections.isEmpty)
    }

    /// back-to-sessions 후 같은 session 재진입과 off-chat final completion을 보존하는지 검증
    // MARK: - CBW-005-continue_chat_conversation_session

    /// CBW-005-continue_chat_conversation_session: In Flight Chat Continues From Session History And Updates Session
    /// Row
    /// CBW-005 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testInFlightChatContinuesFromSessionHistoryAndUpdatesSessionRow() async {
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111120"))
        let fixedMs: Int64 = 1_700_000_001_200

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionList: .init(selectedSessionID: sessionID, unreadCompletedSessionIDs: [sessionID]),
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello while browsing history",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { _, _ in
                    persistence.snapshots.map(AiChatSessionSummary.init(snapshot:))
                },
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }
        // store.exhaustivity = .off: session row 갱신과 unread 마킹만 관찰하고 내부 보조 액션 전부를 열거하지 않기 위함입니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello while browsing history")]
            state.lockedModelHandle = selectedHandle
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
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
        XCTAssertEqual(store.state.executionPhase, .processing(lock))
        XCTAssertEqual(store.state.sessionList.selectedSessionID, sessionID)
        XCTAssertEqual(store.state.sessionList.unreadCompletedSessionIDs, [])
        XCTAssertEqual(store.state.sessionList.allRows.first?.sessionID, sessionID)
        XCTAssertEqual(store.state.sessionList.allRows.first?.title, "Hello while browsing history")
        XCTAssertEqual(store.state.sessionList.allRows.first?.status, .active)

        let userMessage = AiChatMessage(role: .user, content: "Hello while browsing history")
        let expectedStartSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let expectedStartSummary = AiChatSessionSummary(snapshot: expectedStartSnapshot)
        XCTAssertEqual(expectedStartSummary.title, "Hello while browsing history")
        await store.receive(.sessionSnapshotUpdated(
            expectedStartSummary,
            requestID: lock.requestID,
            runID: lock.runID,
        )) { state in
            state.sessionList.allRows = [expectedStartSummary]
            state.sessionList.rows = [expectedStartSummary]
            state.sessionList.selectedSessionID = sessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.sessionList.errorMessage = nil
        }

        await store.send(.sessionsAppeared) { state in
            state.mode = .sessions
            state.sessionList.isLoading = true
            state.sessionList.errorMessage = nil
        }
        await store.receive(.sessionListLoaded([expectedStartSummary])) { state in
            state.sessionList.allRows = [expectedStartSummary]
            state.sessionList.rows = [expectedStartSummary]
            state.sessionList.isLoading = false
            state.sessionList.errorMessage = nil
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
        }
        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        await store.send(.sessionRowTapped(sessionID)) { state in
            state.mode = .chat
        }
        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
        }

        let assistantMessage = AiChatMessage(role: .assistant, content: "Still completed")
        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: assistantMessage,
            completedAtMs: fixedMs,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        let finalizedLock = lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = [userMessage, assistantMessage]
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = lock.context.requestContext
            state.lastRequestContextModelHandle = selectedHandle
            state.executionPhase = .completed(finalizedLock)
            state.transcriptAutoScrollVersion = 2
        }

        let expectedFinalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let expectedFinalSummary = AiChatSessionSummary(snapshot: expectedFinalSnapshot)
        await store.receive(.sessionSnapshotSaved(expectedFinalSummary)) { state in
            state.sessionList.allRows = [expectedFinalSummary]
            state.sessionList.rows = [expectedFinalSummary]
            state.sessionList.selectedSessionID = sessionID
            state.sessionList.unreadCompletedSessionIDs = [sessionID]
            state.sessionList.errorMessage = nil
        }

        await store.finish()
        XCTAssertEqual(persistence.snapshots, [expectedStartSnapshot, expectedFinalSnapshot])
    }

    // MARK: - CBW-005-restore_chat_conversation_session

    /// CBW-005-restore_chat_conversation_session: Restore Outcome From Superseded Session Is Ignored
    /// CBW-005 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testRestoreOutcomeFromSupersededSessionIsIgnored() async {
        let catalogRows = makeCatalogRows()
        let currentRestoreSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222"))
        let staleRestoreSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
        let currentTranscript = [AiChatMessage(role: .user, content: "current draft context")]
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: staleRestoreSessionID,
            status: .active,
            provider: catalogRows[1].handle.provider,
            model: catalogRows[1].handle,
            selectedModelRow: catalogRows[1],
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale restore")],
            updatedAtMs: 0,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: currentRestoreSessionID,
            sessionID: nil,
            sessionStatus: .restoring,
            currentContext: makeContextSnapshot(summary: "Current restore"),
            transcriptHistory: currentTranscript,
            draftText: "Current draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        }

        await store.send(.restoreOutcome(
            requestedSessionID: staleRestoreSessionID,
            .restored(snapshot: staleSnapshot),
            restoreFailure: nil,
        ))

        XCTAssertEqual(store.state.restoreSessionID, currentRestoreSessionID)
        XCTAssertNil(store.state.sessionID)
        XCTAssertEqual(store.state.sessionStatus, .restoring)
        XCTAssertEqual(store.state.transcriptHistory, currentTranscript)
        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[0].handle)
        XCTAssertNil(store.state.restoreOutcome)
        XCTAssertNil(store.state.restoreFailure)
    }

    /// CBW-005-restore_chat_conversation_session: Late Snapshot Saved Does Not Steal Selection During Session Restore
    /// CBW-005 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testLateSnapshotSavedDoesNotStealSelectionDuringSessionRestore() async {
        let catalogRows = makeCatalogRows()
        let activeSessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444"))
        let snapshots = makeLateSnapshotFixtures(
            catalogRows: catalogRows,
            activeSessionID: activeSessionID,
            targetSessionID: targetSessionID,
        )
        let store = makeLateSnapshotStore(
            catalogRows: catalogRows,
            activeSessionID: activeSessionID,
            targetSessionID: targetSessionID,
            activeSummary: snapshots.activeSummary,
            targetSummary: snapshots.targetSummary,
        )

        await store.send(AiChatAction.sessionSnapshotSaved(snapshots.activeSummary)) { state in
            state.sessionList.replaceRow(snapshots.activeSummary)
            state.sessionList.unreadCompletedSessionIDs.insert(activeSessionID)
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.sessionList.selectedSessionID, targetSessionID)

        await applyRestoredTargetSession(store: store, targetSessionID: targetSessionID, snapshot: snapshots.target)

        XCTAssertEqual(store.state.mode, AiChatMode.chat)
        XCTAssertEqual(store.state.sessionID, targetSessionID)
        XCTAssertEqual(store.state.sessionList.selectedSessionID, targetSessionID)
    }
}

// Legacy helper support from AiChatSessionDisplayModelTests.swift

private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    calendar: Calendar,
) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
}

private func milliseconds(for date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1000)
}

private func makeSessionSummary(
    sessionID: AiChatSessionID,
    title: String,
    updatedAtMs: Int64,
) -> AiChatSessionSummary {
    AiChatSessionSummary(
        sessionID: sessionID,
        title: title,
        preview: "Preview",
        messageCount: 2,
        contextTitle: "Context",
        provider: .openai,
        model: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
        createdAtMs: updatedAtMs,
        updatedAtMs: updatedAtMs,
        status: .active,
    )
}

private struct BucketingTestRows {
    let today: AiChatSessionSummary
    let yesterday: AiChatSessionSummary
    let previous7Days: AiChatSessionSummary
    let previous30Days: AiChatSessionSummary
    let month: AiChatSessionSummary
    let year: AiChatSessionSummary
}

private func makeBucketingTestRows(calendar: Calendar, now: Date) -> BucketingTestRows {
    BucketingTestRows(
        today: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111")),
            title: "Today session",
            updatedAtMs: milliseconds(for: now),
        ),
        yesterday: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222")),
            title: "Yesterday session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 5, day: 24, calendar: calendar)),
        ),
        previous7Days: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333")),
            title: "Previous 7 Days session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 5, day: 21, calendar: calendar)),
        ),
        previous30Days: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444")),
            title: "Previous 30 Days session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 5, day: 1, calendar: calendar)),
        ),
        month: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555")),
            title: "Month session",
            updatedAtMs: milliseconds(for: makeDate(year: 2026, month: 2, day: 1, calendar: calendar)),
        ),
        year: makeSessionSummary(
            sessionID: AiChatSessionID(rawValue: makeUUID("66666666-6666-6666-6666-666666666666")),
            title: "Year session",
            updatedAtMs: milliseconds(for: makeDate(year: 2024, month: 12, day: 1, calendar: calendar)),
        ),
    )
}

private func assertBucketingSections(_ displayModel: AiChatSessionsDisplayModel) {
    XCTAssertEqual(displayModel.sections.map(\.bucket), [
        .today,
        .yesterday,
        .previous7Days,
        .previous30Days,
        .month(2),
        .year(2024),
    ])
}

private func assertBucketingTitles(_ displayModel: AiChatSessionsDisplayModel) {
    XCTAssertEqual(displayModel.sections.map(\.title), [
        "Today",
        "Yesterday",
        "Previous 7 Days",
        "Previous 30 Days",
        "February",
        "2024",
    ])
}

private func assertBucketingRowTitles(_ displayModel: AiChatSessionsDisplayModel) {
    XCTAssertEqual(displayModel.sections.map { $0.rows.map(\.title) }, [
        ["Today session"],
        ["Yesterday session"],
        ["Previous 7 Days session"],
        ["Previous 30 Days session"],
        ["Month session"],
        ["Year session"],
    ])
}

// Legacy helper support from AiChatFeatureRestoreRaceTests.swift

private struct LateSnapshotFixtures {
    let active: AiChatSessionSnapshot
    let target: AiChatSessionSnapshot
    let activeSummary: AiChatSessionSummary
    let targetSummary: AiChatSessionSummary
}

private func makeLateSnapshotFixtures(
    catalogRows: [AiModelCatalogRow],
    activeSessionID: AiChatSessionID,
    targetSessionID: AiChatSessionID,
) -> LateSnapshotFixtures {
    let active = AiChatSessionSnapshot(
        sessionID: activeSessionID,
        status: .active,
        provider: catalogRows[0].handle.provider,
        model: catalogRows[0].handle,
        selectedModelRow: catalogRows[0],
        transcriptHistory: [
            AiChatMessage(role: .user, content: "Previous prompt"),
            AiChatMessage(role: .assistant, content: "Late final"),
        ],
        updatedAtMs: 2000,
    )
    let target = AiChatSessionSnapshot(
        sessionID: targetSessionID,
        status: .active,
        provider: catalogRows[1].handle.provider,
        model: catalogRows[1].handle,
        selectedModelRow: catalogRows[1],
        transcriptHistory: [AiChatMessage(role: .user, content: "Target session")],
        updatedAtMs: 1500,
    )
    return LateSnapshotFixtures(
        active: active,
        target: target,
        activeSummary: AiChatSessionSummary(snapshot: active),
        targetSummary: AiChatSessionSummary(snapshot: target),
    )
}

@MainActor
private func makeLateSnapshotStore(
    catalogRows: [AiModelCatalogRow],
    activeSessionID: AiChatSessionID,
    targetSessionID: AiChatSessionID,
    activeSummary: AiChatSessionSummary,
    targetSummary: AiChatSessionSummary,
) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
    TestStore(initialState: AiChatFeature.State(
        restoreSessionID: targetSessionID,
        mode: .sessions,
        sessionList: .init(
            allRows: [targetSummary, activeSummary],
            selectedSessionID: targetSessionID,
        ),
        sessionID: activeSessionID,
        sessionStatus: .active,
        catalogRows: catalogRows,
        modelListState: .loaded(makeProviderModels()),
        selectedModelHandle: catalogRows[0].handle,
    )) {
        AiChatFeature()
    }
}

@MainActor
private func applyRestoredTargetSession(
    store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
    targetSessionID: AiChatSessionID,
    snapshot: AiChatSessionSnapshot,
) async {
    await store.send(AiChatAction.restoreOutcome(
        requestedSessionID: targetSessionID,
        .restored(snapshot: snapshot),
        restoreFailure: nil,
    )) { state in
        state.sessionID = targetSessionID
        state.sessionStatus = .active
        state.currentSessionCustomTitle = snapshot.customTitle
        state.transcriptHistory = snapshot.transcriptHistory
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.lastRequestContext = snapshot.lastRequestContext
        state.lastRequestContextModelHandle = nil
        state.executionPhase = .idle
        state.selectedModelHandle = snapshot.model
        state.selectedThinking = snapshot.selectedThinking
        state.unavailableSelectedModelHandle = nil
        state.restoreOutcome = .restored(snapshot: snapshot)
        state.restoreFailure = nil
        state.mode = .chat
        state.sessionList.errorMessage = nil
    }
}

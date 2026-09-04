import AppKit
import ComposableArchitecture
import Foundation
import Perception
import SwiftUI
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class CBW005ChatSessionContinuityTests: XCTestCase {
    // MARK: - CBW-005-restore_chat_conversation_session

    /// CBW-005-restore_chat_conversation_session: centered와 full transcript 전환에서 mounted draft 입력을 유지한다.
    /// 실제 SwiftUI host가 layout presentation을 교체해도 non-empty draft의 NSTextView identity와 first responder가 보존되는지 검증합니다.
    /// - 검증 내용: centered→transcript→centered 전환마다 AttachmentDroppingTextView instance와 responder를 확인합니다.
    /// - 사전 조건: centered content가 있고 같은 chat session에서 non-empty draft를 편집 중입니다.
    /// - 기대 결과: transcript 유무만 바뀌며 동일 mounted input과 focus가 모든 전환에서 유지됩니다.
    func testRestoreChatConversationSessionKeepsMountedInputAcrossCenteredTranscriptTransitions() async throws {
        let wasPerceptionCheckingEnabled = isPerceptionCheckingEnabled
        isPerceptionCheckingEnabled = false
        defer { isPerceptionCheckingEnabled = wasPerceptionCheckingEnabled }

        let sessionID = makeCBW005SessionID("55555555-5555-5555-5555-555555555701")
        let store = Store<AiChatFeature.State, AiChatFeature.Action>(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            sessionStatus: .active,
            draftText: "Centered draft",
        )) {
            Reduce<AiChatFeature.State, AiChatFeature.Action> { state, action in
                guard case let .draftTextChanged(text) = action else { return .none }
                state.draftText = text
                state.transcriptHistory = text == "Transcript draft"
                    ? [AiChatMessage(role: .assistant, content: "Restored answer")]
                    : []
                return .none
            }
        }
        let hostingView = NSHostingView(rootView: WithPerceptionTracking {
            AiChatView(
                store: store,
                allowsAttachmentPicker: false,
                centeredEmptyContent: AnyView(Text("Centered content")),
            )
        })
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        await drainCBW005MainQueue()

        let centeredInput = try XCTUnwrap(hostingView.cbw005Descendant(
            ofType: AiChatInputTextView.AttachmentDroppingTextView.self,
        ))
        XCTAssertTrue(window.makeFirstResponder(centeredInput))

        store.send(.draftTextChanged("Transcript draft"))
        await drainCBW005MainQueue()
        hostingView.layoutSubtreeIfNeeded()
        await drainCBW005MainQueue()
        let transcriptInput = try XCTUnwrap(hostingView.cbw005Descendant(
            ofType: AiChatInputTextView.AttachmentDroppingTextView.self,
        ))

        XCTAssertIdentical(transcriptInput, centeredInput)
        XCTAssertIdentical(window.firstResponder, centeredInput)
        XCTAssertEqual(store.withState { $0.draftText }, "Transcript draft")

        store.send(.draftTextChanged("Centered draft restored"))
        await drainCBW005MainQueue()
        hostingView.layoutSubtreeIfNeeded()
        await drainCBW005MainQueue()
        let restoredCenteredInput = try XCTUnwrap(hostingView.cbw005Descendant(
            ofType: AiChatInputTextView.AttachmentDroppingTextView.self,
        ))

        XCTAssertIdentical(restoredCenteredInput, centeredInput)
        XCTAssertIdentical(window.firstResponder, centeredInput)
        XCTAssertEqual(store.withState { $0.draftText }, "Centered draft restored")
    }

    /// CBW-005-restore_chat_conversation_session: legacy message timestamp 누락과 explicit null을 nil로 복원한다.
    /// timestamp 필드 도입 전 저장 데이터와 null 데이터가 기존 transcript 의미를 유지하는지 검증합니다.
    /// - 검증 내용: source-compatible 기본값, missing key, explicit null, nil encoding key 정책을 확인합니다.
    /// - 사전 조건: role/content만 있는 legacy JSON과 createdAtMs가 null인 message JSON을 사용합니다.
    /// - 기대 결과: 모든 timestamp가 nil이고 nil encoding은 createdAtMs key를 생략합니다.
    func testRestoreChatConversationSessionDecodesMissingAndNullMessageTimestampsAsNil() throws {
        let sourceCompatibleMessage = AiChatMessage(role: .user, content: "Source compatible")
        let missingKeyData = Data(#"{"role":"assistant","content":"Legacy answer"}"#.utf8)
        let explicitNullData = Data(#"{"role":"user","content":"Null timestamp","createdAtMs":null}"#.utf8)

        let missingKeyMessage = try JSONDecoder().decode(AiChatMessage.self, from: missingKeyData)
        let explicitNullMessage = try JSONDecoder().decode(AiChatMessage.self, from: explicitNullData)
        let encodedNil = try JSONEncoder().encode(sourceCompatibleMessage)
        let encodedNilObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedNil) as? [String: Any],
        )

        XCTAssertNil(sourceCompatibleMessage.createdAtMs)
        XCTAssertNil(missingKeyMessage.createdAtMs)
        XCTAssertNil(explicitNullMessage.createdAtMs)
        XCTAssertEqual(Set(encodedNilObject.keys), Set(["role", "content"]))
        XCTAssertNil(encodedNilObject["createdAtMs"])
    }

    /// CBW-005-restore_chat_conversation_session: message timestamp 정수 경계는 Codable round-trip에서 보존된다.
    /// timestamp를 보정하거나 정규화하지 않고 저장된 millisecond 값을 그대로 복원하는지 검증합니다.
    /// - 검증 내용: nil, 일반 양수, 음수, Int64.max의 encode/decode 결과를 확인합니다.
    /// - 사전 조건: 각 timestamp 경계값을 가진 assistant message를 생성합니다.
    /// - 기대 결과: decoded message가 원본과 같고 createdAtMs 값이 손실되지 않습니다.
    func testRestoreChatConversationSessionRoundTripsMessageTimestampEdges() throws {
        let timestamps: [Int64?] = [nil, 1_700_000_000_000, -1, Int64.max]

        for timestamp in timestamps {
            let message = AiChatMessage(
                role: .assistant,
                content: "Timestamp edge",
                createdAtMs: timestamp,
            )
            let decoded = try JSONDecoder().decode(
                AiChatMessage.self,
                from: JSONEncoder().encode(message),
            )

            XCTAssertEqual(decoded, message)
            XCTAssertEqual(decoded.createdAtMs, timestamp)
        }
    }

    /// CBW-005-restore_chat_conversation_session: timestamp 필드 이전 snapshot은 transcript를 보존해 복원한다.
    /// 기존 session JSON이 새 message Codable 계약에서도 호환되는지 검증합니다.
    /// - 검증 내용: legacy snapshot decode 결과의 session identity와 전체 transcript를 확인합니다.
    /// - 사전 조건: transcript message에 createdAtMs key가 없는 기존 snapshot JSON을 사용합니다.
    /// - 기대 결과: 두 message의 role/content가 보존되고 timestamp는 모두 nil입니다.
    func testRestoreChatConversationSessionDecodesLegacySnapshotWithoutMessageTimestamps() throws {
        let legacySnapshotData = Data(
            #"""
            {
              "sessionID": {"rawValue": "55555555-5555-5555-5555-555555555555"},
              "status": "active",
              "transcriptHistory": [
                {"role": "user", "content": "Legacy question"},
                {"role": "assistant", "content": "Legacy answer"}
              ],
              "updatedAtMs": 1700000000000
            }
            """#.utf8,
        )

        let snapshot = try JSONDecoder().decode(AiChatSessionSnapshot.self, from: legacySnapshotData)

        XCTAssertEqual(snapshot.sessionID, makeCBW005SessionID("55555555-5555-5555-5555-555555555555"))
        XCTAssertEqual(snapshot.transcriptHistory, [
            AiChatMessage(role: .user, content: "Legacy question"),
            AiChatMessage(role: .assistant, content: "Legacy answer"),
        ])
        XCTAssertEqual(snapshot.transcriptHistory.map(\.createdAtMs), [nil, nil])
    }

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

    /// CBW-005-restore_chat_conversation_session: background activity는 matching owner에만 transient하게 남는다.
    /// 화면 밖 request status가 foreground transcript와 stream observability를 오염시키거나 snapshot JSON에 저장되지 않는지 검증합니다.
    /// - 검증 내용: background request/run/session identity, activity lock 갱신, foreground 불변, Codable snapshot 비변경을 확인합니다.
    /// - 사전 조건: foreground는 다른 session이고 backgroundExecutionPhases에 processing request owner가 있습니다.
    /// - 기대 결과: matching status만 background lock에 반영되고 session snapshot JSON에는 activity 정보가 없습니다.
    func testRestoreChatConversationSessionKeepsBackgroundActivityTransientAndIdentityScoped() async throws {
        let rows = makeCatalogRows()
        let backgroundSessionID = makeCBW005SessionID("55555555-5555-5555-5555-555555555601")
        let visibleSessionID = makeCBW005SessionID("55555555-5555-5555-5555-555555555602")
        let context = makeRequestContext(
            sessionID: backgroundSessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("66666666-6666-6666-6666-666666666601")),
            runID: AiChatRunID(rawValue: makeUUID("77777777-7777-7777-7777-777777777601")),
            model: rows[0].handle,
            selectedRow: rows[0],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(context: context, messages: []),
            selectedHandle: rows[0].handle,
            selectedRow: rows[0],
            assistantReplacementIndex: nil,
        )
        let snapshot = makeCBW005Snapshot(
            sessionID: backgroundSessionID,
            transcriptHistory: [AiChatMessage(role: .user, content: "Persisted")],
            model: rows[0],
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encodedBefore = try encoder.encode(snapshot)
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: visibleSessionID,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "Visible")],
            streamingAssistantDraft: "Visible draft",
            transcriptAutoScrollVersion: 9,
            executionPhase: .idle,
            backgroundExecutionPhases: [lock.requestID: .processing(lock)],
        )) {
            AiChatFeature()
        }
        let signal = AiChatExecutionActivitySignal(
            activityID: AiChatExecutionActivityID(rawValue: "background-search"),
            kind: .searching,
            phase: .began,
            evidence: .init(origin: .providerWire, providerEventType: "test.background.status"),
        )

        await store.send(.executionEvent(.status(context: context, signal: signal))) {
            $0.backgroundExecutionPhases[lock.requestID] = .processing(lock.recordingActivity(signal))
        }
        XCTAssertEqual(
            store.state.backgroundExecutionPhases[lock.requestID]?.lock?.activityState.selectedActivity,
            signal,
        )
        XCTAssertEqual(store.state.transcriptHistory, [AiChatMessage(role: .assistant, content: "Visible")])
        XCTAssertEqual(store.state.streamingAssistantDraft, "Visible draft")
        XCTAssertEqual(store.state.transcriptAutoScrollVersion, 9)
        XCTAssertEqual(store.state.backgroundExecutionPhases[lock.requestID]?.lock?.observabilitySummary.chunkCount, 0)

        let wrongSessionContext = makeRequestContext(
            sessionID: visibleSessionID,
            requestID: context.requestID,
            runID: context.runID,
            model: rows[0].handle,
            selectedRow: rows[0],
        )
        let afterMatchingStatus = store.state
        await store.send(.executionEvent(.status(context: wrongSessionContext, signal: signal)))
        XCTAssertEqual(store.state, afterMatchingStatus)

        let encodedAfter = try encoder.encode(snapshot)
        XCTAssertEqual(encodedAfter, encodedBefore)
        let json = try XCTUnwrap(String(data: encodedAfter, encoding: .utf8))
        XCTAssertFalse(json.contains("background-search"))
        XCTAssertFalse(json.contains("searching"))
    }

    /// CBW-005-restore_chat_conversation_session: 사용자가 다른 session을 선택하면 stale transcript 검색 상태를 초기화한다.
    /// session row 전환의 기존 restore 흐름을 유지하면서 이전 transcript query와 ordinal이 새 session으로 누출되지 않는지 검증합니다.
    /// - 검증 내용: 다른 session row 선택과 restore 완료 이후 transcript search state reset을 확인합니다.
    /// - 사전 조건: 현재 session에는 열린 검색과 2/2 match가 있고 history에는 다른 persisted session이 있습니다.
    /// - 기대 결과: 기존 session restore/navigation은 완료되고 transcript 검색 상태는 기본값으로 초기화됩니다.
    func testRestoreChatConversationSessionResetsStaleTranscriptSearchAfterUserTransition() async {
        let sourceSessionID = makeCBW005SessionID("55555555-5555-5555-5555-555555555551")
        let targetSessionID = makeCBW005SessionID("55555555-5555-5555-5555-555555555552")
        let targetRow = makeCBW005SessionSummary(sessionID: targetSessionID)
        let targetSnapshot = makeCBW005Snapshot(
            sessionID: targetSessionID,
            transcriptHistory: restoredTranscript,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionList: .init(allRows: [targetRow], rows: [targetRow]),
            sessionID: sourceSessionID,
            transcriptSearch: .init(
                isPresented: true,
                query: "stale",
                matchCount: 2,
                currentMatchOrdinal: 2,
                status: .matches,
            ),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient.loadSession = { _ in targetSnapshot }
        }
        // store.exhaustivity = .off: session 전환 seam의 transcript search reset만 단일 소유합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.sessionRowTapped(targetSessionID))
        await store.receive(\.restoreOutcome)

        XCTAssertEqual(store.state.transcriptSearch, .init())
        await store.finish()
    }

    /// CBW-005-restore_chat_conversation_session: current session route는 identity가 같으므로 transcript search를 보존한다.
    /// 동일 active session으로의 no-op route가 사용자의 local transcript search lifecycle을 지우지 않는지 검증합니다.
    /// - 검증 내용: current session route 이후 query, count, ordinal, presentation 상태 보존을 확인합니다.
    /// - 사전 조건: active chat identity와 route target이 같고 2/2 transcript search가 열려 있습니다.
    /// - 기대 결과: route presentation은 완료되지만 transcript search state는 변경되지 않습니다.
    func testCurrentSessionRoutePreservesTranscriptSearch() async {
        let sessionID = makeCBW005SessionID("55555555-5555-5555-5555-555555555553")
        let search = makeCBW005ActiveTranscriptSearch()
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            transcriptSearch: search,
        )) { AiChatFeature() }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.routeToChatSession(sessionID))

        XCTAssertEqual(store.state.transcriptSearch, search)
    }

    /// CBW-005-restore_chat_conversation_session: direct persisted route는 다른 session identity로 전환하기 전에 search를 초기화한다.
    /// 직접 route와 restore completion 사이에 이전 session 검색 상태가 target transcript로 누출되지 않는지 검증합니다.
    /// - 검증 내용: route 요청 직후와 restore outcome 이후 transcript search reset을 확인합니다.
    /// - 사전 조건: source chat에 2/2 검색이 열려 있고 다른 persisted target row와 snapshot이 존재합니다.
    /// - 기대 결과: target restore lifecycle은 유지되고 두 시점 모두 transcript search는 기본값입니다.
    func testDirectSessionRouteResetsTranscriptSearch() async {
        let sourceID = makeCBW005SessionID("55555555-5555-5555-5555-555555555554")
        let targetID = makeCBW005SessionID("55555555-5555-5555-5555-555555555555")
        let targetSnapshot = makeCBW005Snapshot(sessionID: targetID, transcriptHistory: restoredTranscript)
        let targetRow = makeCBW005SessionSummary(sessionID: targetID)
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionList: .init(allRows: [targetRow], rows: [targetRow]),
            sessionID: sourceID,
            transcriptSearch: makeCBW005ActiveTranscriptSearch(),
        )) { AiChatFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient.loadSession = { _ in targetSnapshot }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.routeToChatSession(targetID))
        XCTAssertEqual(store.state.transcriptSearch, .init())
        await store.receive(\.restoreOutcome)
        XCTAssertEqual(store.state.transcriptSearch, .init())
        await store.finish()
    }

    /// CBW-005-restore_chat_conversation_session: content-tab sessions route가 active identity를 바꾸면 search를 초기화한다.
    /// content-tab presentation이 sessionID를 직접 교체할 때도 row route와 동일한 검색 lifecycle 정책을 적용하는지 검증합니다.
    /// - 검증 내용: showSessionsForChat 이후 active session identity와 transcript search reset을 확인합니다.
    /// - 사전 조건: source chat에 열린 검색이 있고 content-tab target은 다른 session ID입니다.
    /// - 기대 결과: active identity는 target으로 바뀌고 이전 transcript search는 기본값으로 초기화됩니다.
    func testContentTabSessionsRouteResetsTranscriptSearchOnIdentityChange() async {
        let sourceID = makeCBW005SessionID("55555555-5555-5555-5555-555555555556")
        let targetID = makeCBW005SessionID("55555555-5555-5555-5555-555555555557")
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sourceID,
            transcriptSearch: makeCBW005ActiveTranscriptSearch(),
        )) { AiChatFeature() }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.showSessionsForChat(targetID))

        XCTAssertEqual(store.state.sessionID, targetID)
        XCTAssertEqual(store.state.transcriptSearch, .init())
    }

    /// CBW-005-restore_chat_conversation_session: accepted setup과 new-session restore만 실제 identity 변경 시 search를 초기화한다.
    /// setup no-op, setup identity 교체, accepted missing-record fallback의 reset 경계를 한 계약으로 검증합니다.
    /// - 검증 내용: 동일 setup 보존, 다른 setup reset, accepted new-session restore reset을 확인합니다.
    /// - 사전 조건: source 검색 상태와 서로 다른 setup target, restore target, fallback session ID가 준비되어 있습니다.
    /// - 기대 결과: 동일 identity에서는 검색이 보존되고 실제 setup/restore identity 교체에서만 기본값으로 초기화됩니다.
    func testSetupAndNewSessionRestoreResetTranscriptSearchOnlyForAcceptedIdentityChanges() async {
        let sourceID = makeCBW005SessionID("55555555-5555-5555-5555-555555555561")
        let setupTargetID = makeCBW005SessionID("55555555-5555-5555-5555-555555555562")
        let restoreTargetID = makeCBW005SessionID("55555555-5555-5555-5555-555555555563")
        let fallbackID = makeCBW005SessionID("55555555-5555-5555-5555-555555555564")
        let search = makeCBW005ActiveTranscriptSearch()
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sourceID,
            transcriptSearch: search,
        )) { AiChatFeature() }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.setup(.init(sessionID: sourceID, mode: .chat, sessionStatus: .active)))
        XCTAssertEqual(store.state.transcriptSearch, search)
        await store.send(.setup(.init(sessionID: setupTargetID, mode: .chat, sessionStatus: .active)))
        XCTAssertEqual(store.state.transcriptSearch, .init())

        let fallback = makeCBW005Snapshot(sessionID: fallbackID, transcriptHistory: [])
        let restoreStore = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: restoreTargetID,
            mode: .chat,
            sessionID: setupTargetID,
            sessionStatus: .restoring,
            transcriptSearch: makeCBW005ActiveTranscriptSearch(),
        )) { AiChatFeature() }
        restoreStore.exhaustivity = .off(showSkippedAssertions: false)

        await restoreStore.send(.restoreOutcome(
            requestedSessionID: restoreTargetID,
            .newSession(snapshot: fallback),
            restoreFailure: .missingRecord,
        ))
        XCTAssertEqual(restoreStore.state.sessionID, fallbackID)
        XCTAssertEqual(restoreStore.state.transcriptSearch, .init())
    }

    private func makeCBW005ActiveTranscriptSearch() -> AiChatTranscriptSearchState {
        .init(
            isPresented: true,
            query: "stale",
            matchCount: 2,
            currentMatchOrdinal: 2,
            status: .matches,
        )
    }

    // MARK: - CBW-005-start_chat_conversation_session

    /// CBW-005-start_chat_conversation_session: durable New Chat identity는 이전 transcript search를 초기화한다.
    /// 새 durable draft 생성과 persistence acknowledgment가 이전 session 검색 상태를 계승하지 않는지 검증합니다.
    /// - 검증 내용: New Chat 시작 직후와 newChatCreated 이후 transcript search reset을 확인합니다.
    /// - 사전 조건: 기존 active session에 열린 2/2 검색이 있고 새 draft 저장 client가 성공합니다.
    /// - 기대 결과: 새 session identity와 저장 완료 상태 모두 transcript search 기본값을 유지합니다.
    func testDurableNewChatResetsTranscriptSearch() async {
        let sourceID = makeCBW005SessionID("55555555-5555-5555-5555-555555555558")
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sourceID,
            transcriptSearch: makeCBW005ActiveTranscriptSearch(),
        )) { AiChatFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.newChatTapped)
        XCTAssertEqual(store.state.transcriptSearch, .init())
        await store.receive(\.newChatCreated)
        XCTAssertEqual(store.state.transcriptSearch, .init())
        await store.finish()
    }

    /// CBW-005-start_chat_conversation_session: transient New Chat identity도 이전 transcript search를 초기화한다.
    /// persistence 이전의 explicit transient identity 교체도 durable New Chat과 같은 검색 reset 정책을 따르는지 검증합니다.
    /// - 검증 내용: prepareTransientNewChat 이후 sessionID 교체와 transcript search reset을 확인합니다.
    /// - 사전 조건: source active session에 열린 검색이 있고 다른 explicit transient session ID가 주어집니다.
    /// - 기대 결과: active identity는 transient target으로 바뀌고 이전 검색 상태는 남지 않습니다.
    func testTransientNewChatResetsTranscriptSearch() async {
        let sourceID = makeCBW005SessionID("55555555-5555-5555-5555-555555555559")
        let targetID = makeCBW005SessionID("55555555-5555-5555-5555-555555555560")
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sourceID,
            transcriptSearch: makeCBW005ActiveTranscriptSearch(),
        )) { AiChatFeature() }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.prepareTransientNewChat(sessionID: targetID, seed: nil))

        XCTAssertEqual(store.state.sessionID, targetID)
        XCTAssertEqual(store.state.transcriptSearch, .init())
    }

    /// CBW-005-start_chat_conversation_session: 유효한 window-last 선택은 persisted default보다 우선한다.
    /// 새 대화 seed가 가장 최근 window 선택을 먼저 복원하는 precedence를 검증합니다.
    /// - 검증 내용: window-last model/thinking 우선 선택
    /// - 사전 조건: window와 persisted 후보가 모두 loaded catalog에서 유효하다.
    /// - 기대 결과: window 후보가 direct initialization seed로 반환된다.
    func testNewChatSelectionSeedPrefersValidWindowCandidateOverPersistedDefault() {
        let models = makeThinkingCapableProviderModels()
        let windowCandidate = AiChatNewChatSelectionCandidate(
            modelHandle: models[1].id,
            selectedThinking: .effort(.minimal),
        )
        let persistedCandidate = makePersistedSelectionCandidate(
            model: models[0],
            thinking: .effort("high"),
        )

        let seed = AiChatNewChatSelectionSeedResolver.resolve(
            windowLast: windowCandidate,
            persistedDefault: persistedCandidate,
            catalog: models,
        )

        XCTAssertEqual(seed, AiChatNewChatSelectionSeed(
            modelHandle: models[1].id,
            selectedThinking: .effort(.minimal),
        ))
    }

    /// CBW-005-start_chat_conversation_session: 무효한 window-last 선택은 유효한 persisted default로 fallback한다.
    /// catalog에서 사라진 window model이 저장 기본값까지 차단하지 않는지 검증합니다.
    /// - 검증 내용: invalid window 이후 persisted model/thinking 해석
    /// - 사전 조건: window model은 catalog에 없고 persisted 후보는 유효하다.
    /// - 기대 결과: persisted 후보가 direct initialization seed로 반환된다.
    func testNewChatSelectionSeedFallsBackFromInvalidWindowToValidPersistedDefault() {
        let models = makeThinkingCapableProviderModels()
        let windowCandidate = AiChatNewChatSelectionCandidate(
            modelHandle: makeUnresolvableModelHandle(),
            selectedThinking: .effort(.high),
        )
        let persistedCandidate = makePersistedSelectionCandidate(
            model: models[1],
            thinking: .effort("low"),
        )

        let seed = AiChatNewChatSelectionSeedResolver.resolve(
            windowLast: windowCandidate,
            persistedDefault: persistedCandidate,
            catalog: models,
        )

        XCTAssertEqual(seed, AiChatNewChatSelectionSeed(
            modelHandle: models[1].id,
            selectedThinking: .effort(.low),
        ))
    }

    /// CBW-005-start_chat_conversation_session: window-last가 없으면 유효한 persisted default를 사용한다.
    /// 새 window가 저장된 사용자의 기본 model/thinking intent를 복원하는지 검증합니다.
    /// - 검증 내용: nil window 이후 persisted 후보 선택
    /// - 사전 조건: window 후보는 없고 persisted 후보는 loaded catalog에서 유효하다.
    /// - 기대 결과: persisted 후보가 direct initialization seed로 반환된다.
    func testNewChatSelectionSeedUsesValidPersistedDefaultWhenWindowCandidateIsNil() {
        let models = makeThinkingCapableProviderModels()
        let persistedCandidate = makePersistedSelectionCandidate(
            model: models[0],
            thinking: .effort("medium"),
        )

        let seed = AiChatNewChatSelectionSeedResolver.resolve(
            windowLast: nil,
            persistedDefault: persistedCandidate,
            catalog: models,
        )

        XCTAssertEqual(seed, AiChatNewChatSelectionSeed(
            modelHandle: models[0].id,
            selectedThinking: .effort(.medium),
        ))
    }

    /// CBW-005-start_chat_conversation_session: window와 persisted model이 모두 무효면 runtime 선택을 만들지 않는다.
    /// stale 저장 intent가 catalog 밖 model을 runtime state로 승격하지 않는지 검증합니다.
    /// - 검증 내용: 두 후보의 model availability 검증
    /// - 사전 조건: window와 persisted model이 모두 loaded catalog에 없다.
    /// - 기대 결과: resolver는 nil을 반환한다.
    func testNewChatSelectionSeedReturnsNilWhenWindowAndPersistedCandidatesAreInvalid() {
        let models = makeThinkingCapableProviderModels()
        let windowCandidate = AiChatNewChatSelectionCandidate(
            modelHandle: makeUnresolvableModelHandle(),
            selectedThinking: .effort(.high),
        )
        let persistedCandidate = AiChatPersistedSelectionCandidate(
            providerRawValue: AiProvider.anthropic.rawValue,
            modelProviderRawValue: AiProvider.anthropic.rawValue,
            modelRawValue: "removed-model",
            thinking: .effort("minimal"),
        )

        let seed = AiChatNewChatSelectionSeedResolver.resolve(
            windowLast: windowCandidate,
            persistedDefault: persistedCandidate,
            catalog: models,
        )

        XCTAssertNil(seed)
    }

    /// CBW-005-start_chat_conversation_session: 유효한 model의 호환되지 않는 thinking은 provider default로 정규화한다.
    /// thinking 오류가 유효한 window model 자체를 fallback시키지 않는지 검증합니다.
    /// - 검증 내용: AiThinkingSelectionPolicy 기반 thinking normalization
    /// - 사전 조건: window model은 유효하지만 token budget thinking을 지원하지 않고 persisted 후보도 유효하다.
    /// - 기대 결과: window model과 nil thinking을 가진 seed가 반환된다.
    func testNewChatSelectionSeedKeepsValidWindowModelAndNormalizesInvalidThinkingToNil() {
        let models = makeThinkingCapableProviderModels()
        let windowCandidate = AiChatNewChatSelectionCandidate(
            modelHandle: models[0].id,
            selectedThinking: .tokenBudget(4096),
        )
        let persistedCandidate = makePersistedSelectionCandidate(
            model: models[1],
            thinking: .effort("low"),
        )

        let seed = AiChatNewChatSelectionSeedResolver.resolve(
            windowLast: windowCandidate,
            persistedDefault: persistedCandidate,
            catalog: models,
        )

        XCTAssertEqual(seed, AiChatNewChatSelectionSeed(
            modelHandle: models[0].id,
            selectedThinking: nil,
        ))
    }

    /// CBW-005-start_chat_conversation_session: unavailable window-last는 available persisted default로 fallback한다.
    /// 같은 handle이 catalog에 있어도 선택 불가능하면 window 우선순위를 얻지 못하는지 검증합니다.
    /// - 검증 내용: window availability 검증과 persisted fallback precedence
    /// - 사전 조건: window 후보 모델은 unavailable이고 persisted 후보 모델은 available입니다.
    /// - 기대 결과: persisted 모델과 normalized thinking이 new-chat seed로 반환됩니다.
    func testNewChatSelectionSeedFallsBackFromUnavailableWindowToAvailablePersistedDefault() {
        let models = makeThinkingCapableProviderModels()
        let unavailableWindowModel = AiProviderModel(
            id: models[0].id,
            provider: models[0].provider,
            rawModelID: models[0].rawModelID,
            displayName: models[0].displayName,
            providerDisplayName: models[0].providerDisplayName,
            thinkingCapability: models[0].thinkingCapability,
            supportsThinkingNone: models[0].supportsThinkingNone,
            unavailableReason: .init(message: "Model is temporarily unavailable."),
        )
        let windowCandidate = AiChatNewChatSelectionCandidate(
            modelHandle: unavailableWindowModel.id,
            selectedThinking: .effort(.high),
        )
        let persistedCandidate = makePersistedSelectionCandidate(
            model: models[1],
            thinking: .effort("low"),
        )

        let seed = AiChatNewChatSelectionSeedResolver.resolve(
            windowLast: windowCandidate,
            persistedDefault: persistedCandidate,
            catalog: [unavailableWindowModel, models[1]],
        )

        XCTAssertEqual(seed, AiChatNewChatSelectionSeed(
            modelHandle: models[1].id,
            selectedThinking: .effort(.low),
        ))
    }

    /// CBW-005-start_chat_conversation_session: unavailable persisted default는 new-chat seed가 되지 않는다.
    /// 저장된 handle의 존재만으로 선택 불가능한 모델이 새 draft에 복원되지 않는지 검증합니다.
    /// - 검증 내용: persisted candidate의 canonical availability 검증
    /// - 사전 조건: window 후보는 없고 persisted 후보와 같은 handle의 catalog 모델은 unavailable입니다.
    /// - 기대 결과: resolver는 nil을 반환하고 새 대화 선택을 만들지 않습니다.
    func testNewChatSelectionSeedRejectsUnavailablePersistedDefault() {
        let model = makeThinkingCapableProviderModels()[0]
        let unavailableModel = AiProviderModel(
            id: model.id,
            provider: model.provider,
            rawModelID: model.rawModelID,
            displayName: model.displayName,
            providerDisplayName: model.providerDisplayName,
            thinkingCapability: model.thinkingCapability,
            supportsThinkingNone: model.supportsThinkingNone,
            unavailableReason: .init(message: "Model is temporarily unavailable."),
        )
        let persistedCandidate = makePersistedSelectionCandidate(
            model: model,
            thinking: .effort("medium"),
        )

        let seed = AiChatNewChatSelectionSeedResolver.resolve(
            windowLast: nil,
            persistedDefault: persistedCandidate,
            catalog: [unavailableModel],
        )

        XCTAssertNil(seed)
    }

    /// CBW-005-start_chat_conversation_session: resolver 이후 stale unavailable seed도 적용 경계에서 거부한다.
    /// 비동기 seed resolution 뒤 catalog availability가 바뀌어도 새 runtime/snapshot에 승격되지 않는지 검증합니다.
    /// - 검증 내용: public new-chat seed action의 current-catalog 재검증
    /// - 사전 조건: seed handle과 같은 loaded model이 action 적용 시점에는 unavailable입니다.
    /// - 기대 결과: 새 chat은 unselected이며 저장 snapshot에도 provider/model/thinking이 없습니다.
    func testDurableNewChatRejectsStaleUnavailableSelectionSeed() async {
        let model = makeThinkingCapableProviderModels()[0]
        let unavailableModel = AiProviderModel(
            id: model.id,
            provider: model.provider,
            rawModelID: model.rawModelID,
            displayName: model.displayName,
            providerDisplayName: model.providerDisplayName,
            thinkingCapability: model.thinkingCapability,
            supportsThinkingNone: model.supportsThinkingNone,
            unavailableReason: .init(message: "Model is temporarily unavailable."),
        )
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: model.id,
            selectedThinking: .effort(.high),
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            catalogRows: [makeCatalogRows()[0]],
            modelListState: .loaded([unavailableModel]),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: stale seed의 runtime/persistence 차단만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.newChatTapped(seed: seed))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.selectedThinking)
        XCTAssertEqual(savedSnapshots.value.count, 1)
        XCTAssertNil(savedSnapshots.value.first?.provider)
        XCTAssertNil(savedSnapshots.value.first?.model)
        XCTAssertNil(savedSnapshots.value.first?.selectedThinking)
    }

    /// CBW-005-start_chat_conversation_session: durable New Chat은 known-disconnected provider seed를 제거한다.
    /// 연결 authority가 provider 부재를 확정하면 catalog 미완료 seed가 snapshot에 승격되지 않는지 검증합니다.
    /// - 검증 내용: generated session identity, unselected runtime/snapshot, save 1회
    /// - 사전 조건: OpenAI seed와 Anthropic만 포함한 known 연결 목록이 있습니다.
    /// - 기대 결과: 새 durable session은 유지되지만 model/thinking seed는 runtime과 snapshot에서 제거됩니다.
    func testDurableNewChatRejectsKnownDisconnectedProviderSelectionSeed() async {
        let selectedModel = makeThinkingCapableProviderModels()[0]
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: selectedModel.id,
            selectedThinking: .effort(.high),
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            modelListState: .loading,
            providerConnectionSnapshot: .known([.anthropic]),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs + 10))
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: known-disconnected durable seed의 제거와 snapshot 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.newChatTapped(seed: seed))
        await store.skipReceivedActions()

        let sessionID = try? XCTUnwrap(store.state.sessionID)
        XCTAssertEqual(store.state.mode, .chat)
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.selectedThinking)
        XCTAssertEqual(savedSnapshots.value.count, 1)
        XCTAssertEqual(savedSnapshots.value.first?.sessionID, sessionID)
        XCTAssertNil(savedSnapshots.value.first?.provider)
        XCTAssertNil(savedSnapshots.value.first?.model)
        XCTAssertNil(savedSnapshots.value.first?.selectedThinking)
    }

    /// CBW-005-start_chat_conversation_session: explicit-ID transient는 known-disconnected provider seed를 제거한다.
    /// transient identity와 provenance를 유지하면서 authoritative provider absence만 selection에 반영하는지 검증합니다.
    /// - 검증 내용: explicit ID, prepared marker, current provenance, unselected runtime, save 0회
    /// - 사전 조건: current provenance와 OpenAI seed, Anthropic만 포함한 known 연결 목록이 있습니다.
    /// - 기대 결과: transient는 명시 ID로 준비되고 seed는 제거되며 persistence는 호출되지 않습니다.
    func testExplicitIDTransientNewChatRejectsKnownDisconnectedProviderSelectionSeed() async {
        let selectedModel = makeThinkingCapableProviderModels()[0]
        let sessionID = makeCBW005SessionID("86868686-8686-8686-8686-868686868686")
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: selectedModel.id,
            selectedThinking: .effort(.high),
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            modelListState: .loading,
            providerConnectionSnapshot: .known([.anthropic]),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: known-disconnected transient seed와 zero-save 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        let provenance = store.state.newChatPreparationProvenance
        await store.send(.prepareTransientNewChatIfCurrent(
            sessionID: sessionID,
            provenance: provenance,
            seed: seed,
        ))

        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.preparedTransientSessionID, sessionID)
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.selectedThinking)
        XCTAssertNil(store.state.unavailableSelectedModelHandle)
        XCTAssertTrue(savedSnapshots.value.isEmpty)
    }

    /// CBW-005-start_chat_conversation_session: seed-only completion은 known-disconnected provider seed를 거부한다.
    /// touched transient의 payload와 identity를 보존하면서 authoritative provider absence를 no-op으로 처리하는지 검증합니다.
    /// - 검증 내용: 전체 state/provenance/context/attachment equality와 save 0회
    /// - 사전 조건: touched transient와 current provenance, OpenAI seed, Anthropic만 포함한 known 연결 목록이 있습니다.
    /// - 기대 결과: seed-only application은 전체 state를 변경하지 않고 persistence를 호출하지 않습니다.
    func testSeedOnlyCompletionRejectsKnownDisconnectedProviderSelectionSeed() async {
        let selectedModel = makeThinkingCapableProviderModels()[0]
        let sessionID = makeCBW005SessionID("87878787-8787-8787-8787-878787878787")
        let context = makeContextSnapshot(summary: "Known disconnected context")
        let attachment = makeCBW005Attachment(path: "/tmp/Known-disconnected.txt")
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: selectedModel.id,
            selectedThinking: .effort(.high),
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            preparedTransientSessionID: sessionID,
            currentContext: context,
            addedAttachments: [attachment],
            draftText: "Known disconnected draft",
            modelListState: .loading,
            providerConnectionSnapshot: .known([.anthropic]),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        let provenance = store.state.newChatPreparationProvenance
        let stateBeforeApplication = store.state

        await store.send(.applyNewChatSelectionSeedIfCurrent(
            provenance: provenance,
            seed: seed,
        ))

        XCTAssertEqual(store.state, stateBeforeApplication)
        XCTAssertEqual(store.state.newChatPreparationProvenance, provenance)
        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.currentContext, context)
        XCTAssertEqual(store.state.addedAttachments, [attachment])
        XCTAssertTrue(savedSnapshots.value.isEmpty)
    }

    /// CBW-005-start_chat_conversation_session: durable New Chat은 unknown catalog authority에서 resolved seed를 보존한다.
    /// loading과 selected-provider failure는 unavailable 확정이 아니므로 frozen seed를 durable snapshot에 유지하는지 검증합니다.
    /// - 검증 내용: loading/failure authority에서 runtime selection과 persisted snapshot seed 보존
    /// - 사전 조건: OpenAI resolved seed와 unresolved loading 또는 OpenAI failure + Anthropic success aggregate가 있습니다.
    /// - 기대 결과: 두 경우 모두 원래 model/thinking이 적용되고 snapshot은 한 번 저장됩니다.
    func testDurableNewChatPreservesResolvedSeedWhenCatalogAuthorityIsUnknown() async {
        let models = makeThinkingCapableProviderModels()
        let selectedModel = models[0]
        let otherProviderModel = models[1]
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: selectedModel.id,
            selectedThinking: .effort(.high),
        )
        let failure = AiModelListFailure(message: "OpenAI model list request failed.")
        let states = [
            AiChatFeature.State(
                mode: .sessions,
                catalogRows: makeCatalogRows(),
                modelListState: .loading,
                modelListProviderOrder: [.openai],
                modelListPendingProviders: [.openai],
                providerConnectionSnapshot: .unknown,
            ),
            AiChatFeature.State(
                mode: .sessions,
                catalogRows: makeCatalogRows(),
                modelListState: .loaded([otherProviderModel]),
                modelListFailedProviders: [.openai: failure],
                providerConnectionSnapshot: .unknown,
                availableModelsByProvider: [.openai: [], .anthropic: [otherProviderModel]],
            ),
        ]

        for (index, initialState) in states.enumerated() {
            let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
            let store = TestStore(initialState: initialState) {
                AiChatFeature()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs + Int64(index)))
                $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                }
            }
            // store.exhaustivity = .off: unknown authority별 durable seed와 snapshot 보존만 선별 검증합니다.
            store.exhaustivity = .off(showSkippedAssertions: false)

            await store.send(.newChatTapped(seed: seed))
            await store.skipReceivedActions()

            XCTAssertEqual(store.state.selectedModelHandle, seed.modelHandle, "scenario \(index)")
            XCTAssertEqual(store.state.selectedThinking, seed.selectedThinking, "scenario \(index)")
            XCTAssertEqual(savedSnapshots.value.count, 1, "scenario \(index)")
            XCTAssertEqual(savedSnapshots.value.first?.model, seed.modelHandle, "scenario \(index)")
            XCTAssertEqual(savedSnapshots.value.first?.selectedThinking, seed.selectedThinking, "scenario \(index)")
        }
    }

    /// CBW-005-start_chat_conversation_session: explicit-ID transient는 unknown catalog authority에서 resolved seed를 보존한다.
    /// loading과 selected-provider failure 중에도 explicit session identity와 zero-save semantics를 유지하는지 검증합니다.
    /// - 검증 내용: guarded transient의 seed, explicit ID, prepared marker, persistence 0회
    /// - 사전 조건: current provenance와 unresolved loading 또는 OpenAI failure + Anthropic success aggregate가 있습니다.
    /// - 기대 결과: 두 경우 모두 frozen seed가 적용되고 명시 ID로 transient가 준비됩니다.
    func testExplicitIDTransientNewChatPreservesResolvedSeedWhenCatalogAuthorityIsUnknown() async {
        let models = makeThinkingCapableProviderModels()
        let selectedModel = models[0]
        let otherProviderModel = models[1]
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: selectedModel.id,
            selectedThinking: .effort(.high),
        )
        let failure = AiModelListFailure(message: "OpenAI model list request failed.")
        let states = [
            AiChatFeature.State(
                mode: .sessions,
                catalogRows: makeCatalogRows(),
                modelListState: .loading,
                modelListProviderOrder: [.openai],
                modelListPendingProviders: [.openai],
                providerConnectionSnapshot: .unknown,
            ),
            AiChatFeature.State(
                mode: .sessions,
                catalogRows: makeCatalogRows(),
                modelListState: .loaded([otherProviderModel]),
                modelListFailedProviders: [.openai: failure],
                providerConnectionSnapshot: .unknown,
                availableModelsByProvider: [.openai: [], .anthropic: [otherProviderModel]],
            ),
        ]

        for (index, initialState) in states.enumerated() {
            let sessionID = AiChatSessionID(rawValue: makeUUID(
                index == 0
                    ? "84848484-8484-8484-8484-848484848480"
                    : "84848484-8484-8484-8484-848484848481",
            ))
            let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
            let store = TestStore(initialState: initialState) {
                AiChatFeature()
            } withDependencies: {
                $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                }
            }
            // store.exhaustivity = .off: unknown authority별 explicit-ID seed와 zero-save 경계만 선별 검증합니다.
            store.exhaustivity = .off(showSkippedAssertions: false)

            let provenance = store.state.newChatPreparationProvenance
            await store.send(.prepareTransientNewChatIfCurrent(
                sessionID: sessionID,
                provenance: provenance,
                seed: seed,
            ))

            XCTAssertEqual(store.state.sessionID, sessionID, "scenario \(index)")
            XCTAssertEqual(store.state.preparedTransientSessionID, sessionID, "scenario \(index)")
            XCTAssertEqual(store.state.selectedModelHandle, seed.modelHandle, "scenario \(index)")
            XCTAssertEqual(store.state.selectedThinking, seed.selectedThinking, "scenario \(index)")
            XCTAssertNil(store.state.emptyDraftSessionID, "scenario \(index)")
            XCTAssertTrue(savedSnapshots.value.isEmpty, "scenario \(index)")
        }
    }

    /// CBW-005-start_chat_conversation_session: seed-only completion은 unknown catalog authority에서 resolved seed를 보존한다.
    /// loading과 selected-provider failure 중에도 touched payload를 유지하며 frozen seed만 적용하는지 검증합니다.
    /// - 검증 내용: seed-only model/thinking 적용과 session/context/attachment/draft/provenance owner 보존
    /// - 사전 조건: touched transient와 unresolved loading 또는 OpenAI failure + Anthropic success aggregate가 있습니다.
    /// - 기대 결과: 두 경우 모두 payload와 identity는 유지되고 frozen seed가 적용되며 save는 없습니다.
    func testSeedOnlyCompletionPreservesResolvedSeedWhenCatalogAuthorityIsUnknown() async {
        let models = makeThinkingCapableProviderModels()
        let selectedModel = models[0]
        let otherProviderModel = models[1]
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: selectedModel.id,
            selectedThinking: .effort(.high),
        )
        let failure = AiModelListFailure(message: "OpenAI model list request failed.")
        let sessionID = makeCBW005SessionID("85858585-8585-8585-8585-858585858585")
        let context = makeContextSnapshot(summary: "Unknown authority context")
        let attachment = makeCBW005Attachment(path: "/tmp/Unknown-authority.txt")
        let states = [
            AiChatFeature.State(
                mode: .chat,
                sessionID: sessionID,
                currentContext: context,
                addedAttachments: [attachment],
                draftText: "Unknown authority draft",
                catalogRows: makeCatalogRows(),
                modelListState: .loading,
                modelListProviderOrder: [.openai],
                modelListPendingProviders: [.openai],
                providerConnectionSnapshot: .unknown,
            ),
            AiChatFeature.State(
                mode: .chat,
                sessionID: sessionID,
                currentContext: context,
                addedAttachments: [attachment],
                draftText: "Unknown authority draft",
                catalogRows: makeCatalogRows(),
                modelListState: .loaded([otherProviderModel]),
                modelListFailedProviders: [.openai: failure],
                providerConnectionSnapshot: .unknown,
                availableModelsByProvider: [.openai: [], .anthropic: [otherProviderModel]],
            ),
        ]

        for (index, initialState) in states.enumerated() {
            let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
            let store = TestStore(initialState: initialState) {
                AiChatFeature()
            } withDependencies: {
                $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                }
            }
            let provenance = store.state.newChatPreparationProvenance

            await store.send(.applyNewChatSelectionSeedIfCurrent(
                provenance: provenance,
                seed: seed,
            )) { state in
                state.selectedModelHandle = seed.modelHandle
                state.selectedThinking = seed.selectedThinking
            }

            XCTAssertEqual(store.state.sessionID, sessionID, "scenario \(index)")
            XCTAssertEqual(store.state.currentContext, context, "scenario \(index)")
            XCTAssertEqual(store.state.addedAttachments, [attachment], "scenario \(index)")
            XCTAssertEqual(store.state.draftText, "Unknown authority draft", "scenario \(index)")
            XCTAssertEqual(store.state.selectedModelHandle, seed.modelHandle, "scenario \(index)")
            XCTAssertEqual(store.state.selectedThinking, seed.selectedThinking, "scenario \(index)")
            XCTAssertNil(store.state.unavailableSelectedModelHandle, "scenario \(index)")
            XCTAssertTrue(savedSnapshots.value.isEmpty, "scenario \(index)")
        }
    }

    /// CBW-005-start_chat_conversation_session: 후보가 없으면 catalog의 default/recommended model도 자동 선택하지 않는다.
    /// catalog metadata가 명시적 사용자 선택 정책을 우회하지 않는지 검증합니다.
    /// - 검증 내용: no-candidate resolver 결과
    /// - 사전 조건: default/recommended row에 대응하는 loaded model catalog만 존재한다.
    /// - 기대 결과: resolver는 nil을 반환한다.
    func testNewChatSelectionSeedDoesNotAutoSelectCatalogModel() {
        let models = makeThinkingCapableProviderModels()

        let seed = AiChatNewChatSelectionSeedResolver.resolve(
            windowLast: nil,
            persistedDefault: nil,
            catalog: models,
        )

        XCTAssertNil(seed)
    }

    /// CBW-005-start_chat_conversation_session: durable New Chat은 seed 선택을 최초 snapshot과 runtime에 함께 적용한다.
    /// 새 대화를 저장할 때 선택 상태와 durable snapshot이 같은 model/thinking을 소유하는지 검증합니다.
    /// - 검증 내용: seeded state 초기화, selected model row 포함 snapshot 1회 저장
    /// - 사전 조건: loaded catalog에서 resolve된 seed와 deterministic persistence recorder가 있다.
    /// - 기대 결과: runtime과 저장 snapshot이 같은 seed를 가지며 save는 한 번 호출된다.
    func testDurableNewChatPersistsResolvedSelectionSeedOnce() async {
        let models = makeThinkingCapableProviderModels()
        let catalogRows = makeCatalogRows()
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: models[1].id,
            selectedThinking: .effort(.minimal),
        )
        let newSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000000")
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let expectedSnapshot = AiChatSessionSnapshot(
            sessionID: newSessionID,
            status: .idle,
            customTitle: nil,
            provider: seed.modelHandle.provider,
            model: seed.modelHandle,
            selectedModelRow: catalogRows[1],
            selectedThinking: seed.selectedThinking,
            transcriptHistory: [],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: fixedTimestampMs,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: seed와 persistence ownership만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.newChatTapped(seed: seed))
        await store.receive(.newChatCreated(expectedSnapshot))

        XCTAssertEqual(savedSnapshots.value, [expectedSnapshot])
        XCTAssertEqual(store.state.selectedModelHandle, seed.modelHandle)
        XCTAssertEqual(store.state.selectedThinking, seed.selectedThinking)
        XCTAssertNil(store.state.unavailableSelectedModelHandle)
    }

    /// CBW-005-start_chat_conversation_session: New Chat 저장 완료는 저장 중 변경된 최신 selection을 되돌리지 않는다.
    /// seed snapshot의 비동기 acknowledgment가 이후 사용자 model/thinking 선택보다 늦게 도착하는 경쟁을 검증합니다.
    /// - 검증 내용: `.newChatCreated`가 최신 runtime selection을 보존
    /// - 사전 조건: seed A snapshot 저장 중 같은 draft에서 selection B가 적용되어 있다.
    /// - 기대 결과: 저장 완료 후에도 model/thinking B가 유지된다.
    func testDurableNewChatSaveAcknowledgmentPreservesNewerRuntimeSelection() async {
        let models = makeThinkingCapableProviderModels()
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("68686868-6868-6868-6868-686868686868")
        let seededSnapshot = makeCBW005Snapshot(
            sessionID: sessionID,
            transcriptHistory: [],
            status: .idle,
            model: catalogRows[0],
            selectedThinking: .effort(.high),
        )
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: models[1].id,
            selectedThinking: .effort(.minimal),
        )) {
            AiChatFeature()
        }
        // store.exhaustivity = .off: save acknowledgment 이후 최신 selection 보존만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.newChatCreated(seededSnapshot))

        XCTAssertEqual(store.state.selectedModelHandle, models[1].id)
        XCTAssertEqual(store.state.selectedThinking, .effort(.minimal))
    }

    /// CBW-005-start_chat_conversation_session: explicit-ID transient New Chat은 첫 request-start까지 저장하지 않는다.
    /// Home placeholder identity와 seed가 preparation부터 최초 제출 persistence까지 유지되는지 검증합니다.
    /// - 검증 내용: explicit session ID와 seed 적용, preparation save 0회, 첫 submit request-start save 1회
    /// - 사전 조건: Home에서 만든 placeholder ID, loaded catalog, resolve된 seed가 있다.
    /// - 기대 결과: prepared transient와 최초 저장 snapshot이 같은 explicit ID를 사용하고 save는 정확히 한 번 호출된다.
    func testExplicitIDTransientNewChatPersistsOnceOnFirstRequestStart() async {
        let models = makeThinkingCapableProviderModels()
        let sessionID = makeCBW005SessionID("79797979-7979-7979-7979-797979797979")
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: models[0].id,
            selectedThinking: .effort(.high),
        )
        let stream = AiChatExecutionStreamDriver()
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(models),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: transient seed와 zero-save 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.prepareTransientNewChat(sessionID: sessionID, seed: seed))

        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.selectedModelHandle, seed.modelHandle)
        XCTAssertEqual(store.state.selectedThinking, seed.selectedThinking)
        XCTAssertEqual(store.state.preparedTransientSessionID, sessionID)
        XCTAssertNil(store.state.emptyDraftSessionID)
        XCTAssertTrue(savedSnapshots.value.isEmpty)

        await store.send(.draftTextChanged("Home question"))
        await store.send(.submitTapped)
        await resolvePendingRequestContext(store)
        await store.receive(\.sessionSnapshotUpdated)

        XCTAssertEqual(savedSnapshots.value.count, 1)
        XCTAssertEqual(savedSnapshots.value.first?.sessionID, sessionID)
        stream.finish()
    }

    /// CBW-005-start_chat_conversation_session: guarded explicit-ID transient는 stale unavailable seed를 거부한다.
    /// 비동기 seed resolution 뒤 catalog availability가 바뀐 application boundary를 검증합니다.
    /// - 검증 내용: current provenance 재검증 뒤 stale seed 거부, explicit ID와 prepared marker 보존, save 0회
    /// - 사전 조건: valid provenance와 seed handle이 unavailable인 loaded catalog가 있다.
    /// - 기대 결과: transient chat은 unselected이며 explicit ID로 준비되고 persistence는 호출되지 않는다.
    func testGuardedExplicitIDTransientNewChatRejectsStaleUnavailableSelectionSeed() async {
        let model = makeThinkingCapableProviderModels()[0]
        let unavailableModel = AiProviderModel(
            id: model.id,
            provider: model.provider,
            rawModelID: model.rawModelID,
            displayName: model.displayName,
            providerDisplayName: model.providerDisplayName,
            thinkingCapability: model.thinkingCapability,
            supportsThinkingNone: model.supportsThinkingNone,
            unavailableReason: .init(message: "Model is temporarily unavailable."),
        )
        let sessionID = makeCBW005SessionID("74747474-7474-7474-7474-747474747474")
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: model.id,
            selectedThinking: .effort(.high),
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            catalogRows: [makeCatalogRows()[0]],
            modelListState: .loaded([unavailableModel]),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: stale transient seed의 application boundary와 zero-save만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        let provenance = store.state.newChatPreparationProvenance
        await store.send(.prepareTransientNewChatIfCurrent(
            sessionID: sessionID,
            provenance: provenance,
            seed: seed,
        ))

        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.selectedThinking)
        XCTAssertEqual(store.state.preparedTransientSessionID, sessionID)
        XCTAssertNil(store.state.emptyDraftSessionID)
        XCTAssertTrue(savedSnapshots.value.isEmpty)
    }

    /// CBW-005-start_chat_conversation_session: seed-only completion은 stale unavailable seed를 거부한다.
    /// current provenance여도 비동기 resolution 뒤 unavailable이 된 seed가 runtime state로 승격되지 않는지 검증합니다.
    /// - 검증 내용: payload/identity/provenance 보존, model/thinking/unavailable presentation nil, save 0회
    /// - 사전 조건: touched transient와 current provenance, seed handle이 unavailable인 loaded catalog가 있다.
    /// - 기대 결과: seed-only application은 전체 state를 변경하지 않고 persistence를 호출하지 않는다.
    func testGuardedSeedOnlyCompletionRejectsStaleUnavailableSelectionSeed() async {
        let model = makeThinkingCapableProviderModels()[0]
        let unavailableModel = AiProviderModel(
            id: model.id,
            provider: model.provider,
            rawModelID: model.rawModelID,
            displayName: model.displayName,
            providerDisplayName: model.providerDisplayName,
            thinkingCapability: model.thinkingCapability,
            supportsThinkingNone: model.supportsThinkingNone,
            unavailableReason: .init(message: "Model is temporarily unavailable."),
        )
        let sessionID = makeCBW005SessionID("75757575-7575-7575-7575-757575757575")
        let context = makeContextSnapshot(summary: "Touched context")
        let attachment = makeCBW005Attachment(path: "/tmp/Touched.txt")
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: model.id,
            selectedThinking: .effort(.high),
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            currentContext: context,
            addedAttachments: [attachment],
            draftText: "Touched question",
            catalogRows: [makeCatalogRows()[0]],
            modelListState: .loaded([unavailableModel]),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        let provenance = store.state.newChatPreparationProvenance
        let stateBeforeApplication = store.state

        await store.send(.applyNewChatSelectionSeedIfCurrent(
            provenance: provenance,
            seed: seed,
        ))

        XCTAssertEqual(store.state, stateBeforeApplication)
        XCTAssertEqual(store.state.newChatPreparationProvenance, provenance)
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.selectedThinking)
        XCTAssertNil(store.state.unavailableSelectedModelHandle)
        XCTAssertTrue(savedSnapshots.value.isEmpty)
    }

    /// CBW-005-start_chat_conversation_session: seed-only completion은 touched transient payload와 identity를 보존한다.
    /// 비동기 seed 적용 뒤 첫 submit이 기존 transient ID로 request와 request-start snapshot을 한 번만 만드는지 검증합니다.
    /// - 검증 내용: draft/context/attachment/identity 보존, seed 선택 적용, execute/save 각 1회
    /// - 사전 조건: 사용자 payload가 있는 touched transient와 current provenance가 있다.
    /// - 기대 결과: seed-only completion은 선택만 갱신하고 첫 submit은 같은 ID로 정확히 한 번 시작·저장된다.
    func testGuardedSeedOnlyCompletionPreservesTouchedTransientAndSubmitsOnce() async {
        let fixture = makeGuardedSeedOnlyFixture()
        let store = fixture.store

        let staleProvenance = store.state.newChatPreparationProvenance
        await store.send(.selectedThinkingChanged(.effort(.low)))
        await store.send(.applyNewChatSelectionSeedIfCurrent(
            provenance: staleProvenance,
            seed: fixture.seed,
        ))
        assertGuardedSeedOnlyPayload(
            fixture,
            selectedModelHandle: fixture.models[0].id,
            selectedThinking: .effort(.low),
        )

        let provenance = store.state.newChatPreparationProvenance
        await store.send(.applyNewChatSelectionSeedIfCurrent(
            provenance: provenance,
            seed: fixture.seed,
        ))
        assertGuardedSeedOnlyPayload(
            fixture,
            selectedModelHandle: fixture.seed.modelHandle,
            selectedThinking: fixture.seed.selectedThinking,
        )
        XCTAssertTrue(fixture.savedSnapshots.value.isEmpty)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store)
        await store.receive(\.sessionSnapshotUpdated)

        XCTAssertEqual(fixture.stream.requests.count, 1)
        XCTAssertEqual(fixture.savedSnapshots.value.count, 1)
        XCTAssertEqual(fixture.savedSnapshots.value.first?.sessionID, fixture.sessionID)
        fixture.stream.finish()
    }

    private struct GuardedSeedOnlyFixture {
        let store: TestStore<AiChatFeature.State, AiChatFeature.Action>
        let models: [AiProviderModel]
        let sessionID: AiChatSessionID
        let context: AiChatCurrentContextSnapshot
        let attachment: AiChatAttachmentDraft
        let seed: AiChatNewChatSelectionSeed
        let stream: AiChatExecutionStreamDriver
        let savedSnapshots: LockIsolated<[AiChatSessionSnapshot]>
    }

    private func makeGuardedSeedOnlyFixture() -> GuardedSeedOnlyFixture {
        let models = makeThinkingCapableProviderModels()
        let sessionID = makeCBW005SessionID("77777777-7777-7777-7777-777777777777")
        let context = makeContextSnapshot(summary: "User context")
        let attachment = makeCBW005Attachment(path: "/tmp/User.txt")
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: models[1].id,
            selectedThinking: .effort(.low),
        )
        let stream = AiChatExecutionStreamDriver()
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            currentContext: context,
            addedAttachments: [attachment],
            draftText: "User question",
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(models),
            selectedModelHandle: models[0].id,
            selectedThinking: .effort(.high),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: seed-only payload 보존과 최초 request-start 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)
        return GuardedSeedOnlyFixture(
            store: store,
            models: models,
            sessionID: sessionID,
            context: context,
            attachment: attachment,
            seed: seed,
            stream: stream,
            savedSnapshots: savedSnapshots,
        )
    }

    private func assertGuardedSeedOnlyPayload(
        _ fixture: GuardedSeedOnlyFixture,
        selectedModelHandle: AiModelHandle?,
        selectedThinking: AiThinkingSelection?,
    ) {
        XCTAssertEqual(fixture.store.state.sessionID, fixture.sessionID)
        XCTAssertEqual(fixture.store.state.draftText, "User question")
        XCTAssertEqual(fixture.store.state.currentContext, fixture.context)
        XCTAssertEqual(fixture.store.state.addedAttachments, [fixture.attachment])
        XCTAssertEqual(fixture.store.state.selectedModelHandle, selectedModelHandle)
        XCTAssertEqual(fixture.store.state.selectedThinking, selectedThinking)
    }

    /// CBW-005-start_chat_conversation_session: queued transient seed action은 변경된 child provenance를 재검증한다.
    /// FileManager validation 이후 child action 적용 전에 사용자 입력이 바뀌는 race를 검증합니다.
    /// - 검증 내용: attachment mutation 뒤 late preparation action no-op, save 0회
    /// - 사전 조건: explicit Home session과 captured pristine provenance가 있다.
    /// - 기대 결과: attachment와 기존 selection/session이 유지되고 transient preparation은 실행되지 않는다.
    func testGuardedExplicitIDTransientNewChatIgnoresMutationBeforeChildApplication() async {
        let models = makeThinkingCapableProviderModels()
        let sessionID = makeCBW005SessionID("78787878-7878-7878-7878-787878787878")
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: models[0].id,
            selectedThinking: .effort(.high),
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(models),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: child action 적용 직전 provenance race만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        let provenance = store.state.newChatPreparationProvenance
        await store.send(.attachmentPickerSelection(sessionID, [URL(fileURLWithPath: "/tmp/queued-home.txt")]))
        XCTAssertEqual(store.state.addedAttachments.count, 1)

        await store.send(.prepareTransientNewChatIfCurrent(
            sessionID: sessionID,
            provenance: provenance,
            seed: seed,
        ))

        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.addedAttachments.count, 1)
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.preparedTransientSessionID)
        XCTAssertTrue(savedSnapshots.value.isEmpty)
    }

    /// CBW-005-start_chat_conversation_session: queued durable seed action은 session navigation provenance를 재검증한다.
    /// Parent validation 이후 Content history session이 바뀌는 race에서 unintended durable session 생성을 차단합니다.
    /// - 검증 내용: session navigation 뒤 guarded durable New Chat no-op, save 0회
    /// - 사전 조건: sessions mode의 기존 session과 captured provenance가 있다.
    /// - 기대 결과: navigation 대상 session/mode가 유지되고 새 session 생성과 persistence가 발생하지 않는다.
    func testGuardedDurableNewChatIgnoresSessionNavigationBeforeChildApplication() async {
        let models = makeThinkingCapableProviderModels()
        let originalSessionID = makeCBW005SessionID("76767676-7676-7676-7676-767676767676")
        let navigatedSessionID = makeCBW005SessionID("75757575-7575-7575-7575-757575757575")
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: models[0].id,
            selectedThinking: .effort(.high),
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(selectedSessionID: originalSessionID),
            sessionID: originalSessionID,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(models),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: durable child action 적용 직전 session provenance race만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        let provenance = store.state.newChatPreparationProvenance
        await store.send(.showSessionsForChat(navigatedSessionID))
        await store.send(.newChatTappedIfCurrent(provenance: provenance, seed: seed))

        XCTAssertEqual(store.state.sessionID, navigatedSessionID)
        XCTAssertEqual(store.state.sessionList.selectedSessionID, navigatedSessionID)
        XCTAssertEqual(store.state.mode, .sessions)
        XCTAssertTrue(savedSnapshots.value.isEmpty)
    }

    /// CBW-005-start_chat_conversation_session: context 포함 transient New Chat도 같은 seed를 저장 없이 표시한다.
    /// FileManager context 주입 경로가 seed나 transient provenance를 잃지 않는지 검증합니다.
    /// - 검증 내용: context+seed runtime 초기화, prepared transient marker, save 0회
    /// - 사전 조건: fresh context, loaded catalog, resolve된 seed가 있다.
    /// - 기대 결과: context와 seed가 함께 표시되고 persistence는 호출되지 않는다.
    func testTransientNewChatWithContextAppliesResolvedSelectionSeedWithoutSaving() async {
        let models = makeThinkingCapableProviderModels()
        let context = makeContextSnapshot(summary: "Seeded context")
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: models[1].id,
            selectedThinking: .effort(.low),
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(models),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: context 적용과 transient seed의 zero-save 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        let provenance = store.state.newChatPreparationProvenance
        await store.send(.prepareUnpersistedNewChatIfActive(
            context,
            provenance: provenance,
            seed: seed,
        ))

        XCTAssertEqual(store.state.currentContext, context)
        XCTAssertEqual(store.state.selectedModelHandle, seed.modelHandle)
        XCTAssertEqual(store.state.selectedThinking, seed.selectedThinking)
        XCTAssertEqual(store.state.preparedTransientSessionID, store.state.sessionID)
        XCTAssertTrue(savedSnapshots.value.isEmpty)
    }

    /// CBW-005-start_chat_conversation_session: stale provenance의 context transient 준비는 사용자 mutation을 지우지 않는다.
    /// Parent validation 이후 child action 적용 전 draft가 바뀌는 race를 검증합니다.
    /// - 검증 내용: stale context preparation no-op, draft/context/selection 보존, save 0회
    /// - 사전 조건: pristine provenance 캡처 뒤 사용자가 draft를 변경한다.
    /// - 기대 결과: transient session을 준비하지 않고 mutation 이전 context를 유지한다.
    func testGuardedContextTransientNewChatIgnoresDraftMutationBeforeApplication() async {
        let models = makeThinkingCapableProviderModels()
        let originalContext = makeContextSnapshot(summary: "Original context")
        let replacementContext = makeContextSnapshot(summary: "Replacement context")
        let seed = AiChatNewChatSelectionSeed(
            modelHandle: models[1].id,
            selectedThinking: .effort(.low),
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            currentContext: originalContext,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(models),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: child 적용 시점의 stale provenance no-op만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        let provenance = store.state.newChatPreparationProvenance
        await store.send(.draftTextChanged("User draft"))
        await store.send(.prepareUnpersistedNewChatIfActive(
            replacementContext,
            provenance: provenance,
            seed: seed,
        ))

        XCTAssertEqual(store.state.currentContext, originalContext)
        XCTAssertEqual(store.state.draftText, "User draft")
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.preparedTransientSessionID)
        XCTAssertTrue(savedSnapshots.value.isEmpty)
    }

    /// CBW-005-restore_chat_conversation_session: 성공한 restore는 현재 New Chat 후보보다 snapshot 선택을 우선한다.
    /// window/default 후보와 다른 저장 selection이 snapshot-first로 복원되는지 검증합니다.
    /// - 검증 내용: restored model/thinking이 기존 runtime 후보를 덮어씀
    /// - 사전 조건: runtime은 첫 model을 가리키고 저장 snapshot은 두 번째 model을 가진다.
    /// - 기대 결과: restore 완료 후 snapshot model/thinking이 유지된다.
    func testSuccessfulRestoreKeepsSnapshotSelectionWhenNewChatCandidateDiffers() async {
        let models = makeThinkingCapableProviderModels()
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("67676767-6767-6767-6767-676767676767")
        let restoredSnapshot = makeCBW005Snapshot(
            sessionID: sessionID,
            transcriptHistory: restoredTranscript,
            model: catalogRows[1],
            selectedThinking: .effort(.minimal),
        )
        let row = makeCBW005SessionSummary(sessionID: sessionID)
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [row], rows: [row]),
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: models[0].id,
            selectedThinking: .effort(.high),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient.loadSession = { _ in restoredSnapshot }
        }
        // store.exhaustivity = .off: restore 결과의 snapshot-first selection만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.sessionRowTapped(sessionID))
        await store.receive(\.restoreOutcome)

        XCTAssertEqual(store.state.selectedModelHandle, restoredSnapshot.model)
        XCTAssertEqual(store.state.selectedThinking, restoredSnapshot.selectedThinking)
        XCTAssertEqual(store.state.transcriptHistory, restoredSnapshot.transcriptHistory)
    }

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
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                },
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

    /// CBW-005-start_chat_conversation_session: Inspector New Chat은 입력 전까지 session을 저장하지 않는다.
    /// 빈 composer를 여는 동작만으로 history record를 만들거나 삭제 요청을 보내지 않는지 검증합니다.
    /// - 검증 내용: transient sessionID 준비, save/delete 미호출, history 전환
    /// - 사전 조건: sessions mode에서 inspector가 새 대화 composer를 요청한다.
    /// - 기대 결과: chat state는 준비되지만 persistence에는 기록이 생기지 않는다.
    func testPrepareUnpersistedNewChatDoesNotCreateOrDeleteSession() async {
        let newSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000000")
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(mode: .sessions)) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                },
            )
        }

        await store.send(.prepareUnpersistedNewChat) { state in
            self.applyNewChatStartedState(&state, sessionID: newSessionID)
            state.emptyDraftSessionID = nil
            state.preparedTransientSessionID = newSessionID
        }
        XCTAssertEqual(store.state.preparedTransientSessionID, newSessionID)
        XCTAssertTrue(store.state.isUntouchedPreparedTransientNewChat)
        XCTAssertTrue(savedSnapshots.value.isEmpty)

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
        }

        XCTAssertEqual(store.state.sessionID, newSessionID)
        XCTAssertNil(store.state.emptyDraftSessionID)
        XCTAssertTrue(savedSnapshots.value.isEmpty)
        XCTAssertTrue(deletedSessionIDs.value.isEmpty)
    }

    /// CBW-005-start_chat_conversation_session: 다른 session의 background 준비 작업은 transient marker를 무효화하지 않는다.
    /// 현재 transient session의 pending request만 idempotent New Chat 판정을 막는지 검증합니다.
    /// - 검증 내용: 다른 session pending 보존, 현재 session pending 차단
    /// - 사전 조건: untouched prepared transient session과 background pending request가 존재한다.
    /// - 기대 결과: 다른 session 작업은 허용되고 현재 session 작업만 untouched 판정을 해제한다.
    func testPreparedTransientQueryIgnoresBackgroundWorkForOtherSessions() {
        let transientSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000069")
        let otherSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000070")
        let models = makeProviderModels()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: makeUUID("00000000-0000-0000-0000-000000000071"),
            kind: .submit,
            sessionID: otherSessionID,
            selectedModel: models[0],
            selectedRow: nil,
            preparedRequest: AiChatPreparedRequest(
                prompt: "Other request",
                messages: [],
                persistenceTranscriptHistory: [],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 0,
                    excludedMessageCount: 0,
                    budget: 200_000,
                    truncationReason: nil,
                ),
            ),
        )
        var state = AiChatFeature.State(
            mode: .chat,
            sessionID: transientSessionID,
            preparedTransientSessionID: transientSessionID,
            backgroundPendingRequestStarts: [pendingRequest.resolutionID: pendingRequest],
        )

        XCTAssertTrue(state.isUntouchedPreparedTransientNewChat)

        state.backgroundPendingRequestStarts[pendingRequest.resolutionID]?.sessionID = transientSessionID
        XCTAssertFalse(state.isUntouchedPreparedTransientNewChat)
    }

    /// CBW-005-start_chat_conversation_session: setup과 durable New Chat은 transient provenance를 제거한다.
    /// transient composer identity가 restored/persisted session으로 누출되지 않는지 검증합니다.
    /// - 검증 내용: setup 및 durable New Chat 이후 marker 제거
    /// - 사전 조건: prepared transient session이 존재한다.
    /// - 기대 결과: 두 전이 모두 preparedTransientSessionID를 nil로 만든다.
    func testPreparedTransientMarkerClearsForSetupAndDurableNewChat() async {
        let existingSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000072")
        let store = TestStore(initialState: AiChatFeature.State(mode: .sessions)) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
        }
        // store.exhaustivity = .off: marker lifecycle과 session identity만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.prepareUnpersistedNewChat)
        XCTAssertNotNil(store.state.preparedTransientSessionID)
        await store.send(.draftTextChanged("Question"))
        XCTAssertNil(store.state.preparedTransientSessionID)

        await store.send(.prepareUnpersistedNewChat)
        await store.send(.setup(AiChatSetupState(
            sessionID: existingSessionID,
            mode: .chat,
            sessionStatus: .idle,
        )))
        XCTAssertNil(store.state.preparedTransientSessionID)

        await store.send(.prepareUnpersistedNewChat)
        XCTAssertNotNil(store.state.preparedTransientSessionID)
        await store.send(.newChatTapped)
        XCTAssertNil(store.state.preparedTransientSessionID)
        await store.skipReceivedActions()
    }

    /// CBW-005-start_chat_conversation_session: pending resolver 중 Inspector New Chat은 기존 request를 background로 이관한다.
    /// 늦게 완료된 resolver가 새 transient composer의 foreground state를 덮어쓰지 않는지 검증합니다.
    /// - 검증 내용: pending owner 이관, late resolution의 background 실행, 새 composer 보존
    /// - 사전 조건: 기존 session의 request context resolution이 pending 상태이다.
    /// - 기대 결과: 새 transient session은 untouched로 유지되고 기존 request만 background에서 시작한다.
    func testPrepareUnpersistedNewChatParksPendingResolverAndPreservesNewComposer() async {
        let catalogRows = makeCatalogRows()
        let currentSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000073")
        let transientSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000000")
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000000074")
        let userMessage = AiChatMessage(role: .user, content: "Pending transient switch")
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: currentSessionID,
            selectedModel: makeProviderModels()[0],
            selectedRow: catalogRows[0],
            selectedThinking: .effort(.minimal),
            customTitle: "Pending owner",
            preparedRequest: AiChatPreparedRequest(
                prompt: userMessage.content,
                messages: [userMessage],
                persistenceTranscriptHistory: [userMessage],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 200_000,
                    truncationReason: nil,
                ),
            ),
        )
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: currentSessionID,
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[0].handle,
            pendingRequestStart: pendingRequest,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatExecutionClient.execute = { _, _ in AsyncStream { $0.finish() } }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
        }
        // store.exhaustivity = .off: pending owner 이관과 새 transient foreground 보존만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.prepareUnpersistedNewChat)

        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(store.state.backgroundPendingRequestStarts[resolutionID], pendingRequest)
        XCTAssertEqual(store.state.sessionID, transientSessionID)
        XCTAssertEqual(store.state.preparedTransientSessionID, transientSessionID)
        XCTAssertTrue(store.state.isUntouchedPreparedTransientNewChat)

        await store.send(.requestContextResolved(resolutionID, AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.backgroundPendingRequestStarts[resolutionID])
        XCTAssertEqual(store.state.sessionID, transientSessionID)
        XCTAssertEqual(store.state.transcriptHistory, [])
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertEqual(store.state.preparedTransientSessionID, transientSessionID)
        XCTAssertTrue(store.state.isUntouchedPreparedTransientNewChat)
        guard case let .processing(lock) = store.state.backgroundExecutionPhases.values.first else {
            XCTFail("late resolver should start under the original background session owner")
            return
        }
        XCTAssertEqual(lock.context.sessionID, currentSessionID)
        XCTAssertEqual(lock.request.messages, [
            AiChatMessage(role: .user, content: userMessage.content, createdAtMs: fixedTimestampMs),
        ])
    }

    /// CBW-005-start_chat_conversation_session: model 선택은 prepared transient provenance를 영구 무효화한다.
    /// 빈 화면 형태가 유지돼도 사용자 model 선택 뒤 New Chat이 idempotent로 오인되지 않는지 검증합니다.
    /// - 검증 내용: selected model 적용과 marker 제거
    /// - 사전 조건: untouched prepared transient session과 사용 가능한 model이 있다.
    /// - 기대 결과: model 선택 후 marker가 nil이고 untouched query가 false이다.
    func testPreparedTransientMarkerInvalidatesAfterModelSelection() async {
        let catalogRows = makeCatalogRows()
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
        }
        // store.exhaustivity = .off: model mutation 뒤 provenance 상태만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.prepareUnpersistedNewChat)
        XCTAssertTrue(store.state.isUntouchedPreparedTransientNewChat)

        await store.send(.selectedModelChanged(catalogRows[0].handle))

        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[0].handle)
        XCTAssertNil(store.state.preparedTransientSessionID)
        XCTAssertFalse(store.state.isUntouchedPreparedTransientNewChat)
    }

    /// CBW-005-start_chat_conversation_session: attachment add 후 제거해도 transient provenance는 복구되지 않는다.
    /// composer가 다시 비어 보여도 이미 사용자 mutation이 있었음을 유지하는지 검증합니다.
    /// - 검증 내용: attachment add/remove 성공과 marker 영구 제거
    /// - 사전 조건: untouched prepared transient session이 있다.
    /// - 기대 결과: attachment 제거 후 빈 상태에서도 untouched query는 false이다.
    func testPreparedTransientMarkerStaysInvalidAfterAttachmentAddThenRemove() async throws {
        let attachmentURL = URL(filePath: "/tmp/Transient.txt")
        let store = TestStore(initialState: AiChatFeature.State(mode: .sessions)) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
        }
        // store.exhaustivity = .off: attachment mutation 뒤 provenance 상태만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.prepareUnpersistedNewChat)
        XCTAssertTrue(store.state.isUntouchedPreparedTransientNewChat)

        let attachmentSessionID = try XCTUnwrap(store.state.sessionID)
        await store.send(.attachmentPickerSelection(attachmentSessionID, [attachmentURL]))
        let attachmentID = try XCTUnwrap(store.state.addedAttachments.first?.id)
        XCTAssertNil(store.state.preparedTransientSessionID)

        await store.send(.removeAddedAttachment(attachmentID))

        XCTAssertTrue(store.state.addedAttachments.isEmpty)
        XCTAssertNil(store.state.preparedTransientSessionID)
        XCTAssertFalse(store.state.isUntouchedPreparedTransientNewChat)
    }

    /// CBW-005-start_chat_conversation_session: thinking과 folder mode 변경도 transient provenance를 무효화한다.
    /// draft text 외 사용자 설정 mutation이 untouched identity에 포함되는지 검증합니다.
    /// - 검증 내용: thinking 선택과 current-context folder mode 변경의 marker 제거
    /// - 사전 조건: 각 prepared transient state에 model 또는 folder context가 준비되어 있다.
    /// - 기대 결과: 두 mutation 모두 marker를 nil로 만든다.
    func testPreparedTransientMarkerInvalidatesAfterThinkingAndFolderModeChanges() async {
        let catalogRows = makeCatalogRows()
        let thinkingSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000075")
        let thinkingStore = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: thinkingSessionID,
            preparedTransientSessionID: thinkingSessionID,
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[0].handle,
        )) {
            AiChatFeature()
        }
        // store.exhaustivity = .off: thinking mutation 뒤 provenance 상태만 선별 검증합니다.
        thinkingStore.exhaustivity = .off(showSkippedAssertions: false)

        XCTAssertTrue(thinkingStore.state.isUntouchedPreparedTransientNewChat)
        await thinkingStore.send(.selectedThinkingChanged(.effort(.minimal)))
        XCTAssertNil(thinkingStore.state.preparedTransientSessionID)

        let folderPath = "/tmp/Projects"
        let folderSessionID = makeCBW005SessionID("00000000-0000-0000-0000-000000000076")
        let folderContext = makeContextSnapshot(
            references: [AiChatContextReference(
                kind: .folder,
                identifier: folderPath,
                title: "Projects",
                subtitle: folderPath,
                metadata: ["path": folderPath],
            )],
            items: [],
            attachments: [],
        )
        let folderStore = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: folderSessionID,
            preparedTransientSessionID: folderSessionID,
            currentContext: folderContext,
        )) {
            AiChatFeature()
        }
        // store.exhaustivity = .off: folder mode mutation 뒤 provenance 상태만 선별 검증합니다.
        folderStore.exhaustivity = .off(showSkippedAssertions: false)

        XCTAssertTrue(folderStore.state.isUntouchedPreparedTransientNewChat)
        await folderStore.send(.folderStructureModeChanged(.currentContext, .includeSubfolders))
        XCTAssertNil(folderStore.state.preparedTransientSessionID)
    }

    /// CBW-005-start_chat_conversation_session: fresh context를 적용하는 transient New Chat은 stale draft state를 먼저 비운다.
    /// 이전 attachment와 folder mode가 새 FileManager context를 필터링하거나 변형하지 않는지 검증합니다.
    /// - 검증 내용: overlapping item/reference 보존, stale attachment/mode 제거, 기본 folder mode 파생, save/delete 미호출
    /// - 사전 조건: stale attachment가 fresh item 경로와 겹치고 이전 folder mode가 남아 있다.
    /// - 기대 결과: fresh context 전체가 새 transient chat에 적용되고 persistence에는 기록이 생기지 않는다.
    func testPrepareUnpersistedNewChatWithContextClearsStaleDraftStateBeforeApplyingContext() async {
        let selectedPath = "/tmp/Selected.md"
        let freshFolderPath = "/tmp/FreshFolder"
        let staleFolderKey = makeNavigationFolderKey("/tmp/StaleFolder")
        let freshFolderKey = makeNavigationFolderKey(freshFolderPath)
        let freshContext = makeContextSnapshot(
            summary: "Fresh context",
            references: [AiChatContextReference(
                kind: .folder,
                identifier: freshFolderPath,
                title: "FreshFolder",
                subtitle: freshFolderPath,
                metadata: ["path": freshFolderPath],
            )],
            items: [AiChatContextItem(
                kind: .file,
                identifier: selectedPath,
                title: "Selected.md",
                subtitle: selectedPath,
                metadata: ["path": selectedPath],
            )],
            attachments: [],
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            currentContextFolderStructureModes: [staleFolderKey: .includeSubfolders],
            addedAttachments: [makeNavigationAttachment(path: selectedPath)],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: self.fixedTimestampMs))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                },
            )
        }
        // store.exhaustivity = .off: reset된 전체 chat state 대신 context 원자성과 persistence 경계만 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.prepareUnpersistedNewChatWithContext(freshContext))

        XCTAssertEqual(store.state.mode, .chat)
        XCTAssertEqual(store.state.preparedTransientSessionID, store.state.sessionID)
        XCTAssertTrue(store.state.isUntouchedPreparedTransientNewChat)
        XCTAssertTrue(store.state.addedAttachments.isEmpty)
        XCTAssertEqual(store.state.currentContext.summary, "Fresh context")
        XCTAssertEqual(store.state.currentContext.items.map(\.identifier), [selectedPath])
        XCTAssertEqual(store.state.currentContext.references.map(\.identifier), [freshFolderPath])
        XCTAssertNil(store.state.currentContextFolderStructureModes[staleFolderKey])
        XCTAssertEqual(store.state.currentContextFolderStructureModes, [freshFolderKey: .currentFolderOnly])
        XCTAssertTrue(savedSnapshots.value.isEmpty)
        XCTAssertTrue(deletedSessionIDs.value.isEmpty)
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
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
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

    /// CBW-005-open_chat_conversation_session: current chat route 복귀는 다른 session restore tracking을 먼저 정리한다.
    /// FileManager Back/Forward가 A chat route로 복귀할 때 B session restore가 늦게 도착해도 A chat을 덮지 않아야 합니다.
    /// - 검증 내용: routeToChatSession(current)는 pending restoreSessionID/selectedSessionID를 정리하고 stale restoreOutcome을 무시
    /// - 사전 조건: A chat이 열려 있고 B session restore가 pending이다.
    /// - 기대 결과: late B restoreOutcome 이후에도 A session과 transcript가 유지된다.
    func testRouteToCurrentChatCancelsPendingDifferentSessionRestore() async {
        let currentSessionID = makeCBW005SessionID("16161616-1616-1616-1616-161616161616")
        let restoringSessionID = makeCBW005SessionID("17171717-1717-1717-1717-171717171717")
        let staleSnapshot = makeCBW005Snapshot(
            sessionID: restoringSessionID,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale restore")],
        )

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: restoringSessionID,
            mode: .sessions,
            sessionList: .init(
                allRows: [makeCBW005SessionSummary(sessionID: restoringSessionID)],
                selectedSessionID: restoringSessionID,
            ),
            sessionID: currentSessionID,
            sessionStatus: .restoring,
            transcriptHistory: restoredTranscript,
        )) {
            AiChatFeature()
        }

        await store.send(.routeToChatSession(currentSessionID)) { state in
            state.restoreSessionID = nil
            state.sessionList.selectedSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionStatus = .active
            state.mode = .chat
        }

        await store.send(.restoreOutcome(
            requestedSessionID: restoringSessionID,
            .restored(snapshot: staleSnapshot),
            restoreFailure: nil,
        ))

        XCTAssertEqual(store.state.mode, .chat)
        XCTAssertEqual(store.state.sessionID, currentSessionID)
        XCTAssertEqual(store.state.transcriptHistory, restoredTranscript)
        XCTAssertNil(store.state.restoreSessionID)
        XCTAssertNil(store.state.sessionList.selectedSessionID)
    }

    /// CBW-005-restore_chat_conversation_session: 취소로 settled 된 same-ID restore의 late terminal은 무시한다.
    /// restoreSessionID가 provenance로 남아도 active restore status가 아니면 terminal이 semantic state를 바꾸지 않는지 검증합니다.
    /// - 검증 내용: return cancellation 뒤 same-ID restored outcome의 no-op 처리
    /// - 사전 조건: B restore가 진행 중이고 B chat으로 돌아오며 identity는 유지된다.
    /// - 기대 결과: status는 active로 정착하고 late B snapshot은 기존 transcript와 outcome을 바꾸지 않는다.
    func testLateSameIdentityRestoreOutcomeIsIgnoredAfterCancellationSettlesStatus() async {
        let sessionID = makeCBW005SessionID("25252525-2525-2525-2525-252525252525")
        let staleSnapshot = makeCBW005Snapshot(
            sessionID: sessionID,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "late restore")],
        )
        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .sessions,
            sessionList: .init(selectedSessionID: sessionID),
            sessionID: sessionID,
            sessionStatus: .restoring,
            transcriptHistory: restoredTranscript,
        )) {
            AiChatFeature()
        }

        await store.send(.returnToChatTapped) { state in
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionStatus = .active
            state.mode = .chat
        }
        await store.send(.restoreOutcome(
            requestedSessionID: sessionID,
            .restored(snapshot: staleSnapshot),
            restoreFailure: nil,
        ))

        XCTAssertEqual(store.state.restoreSessionID, sessionID)
        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.sessionStatus, .active)
        XCTAssertEqual(store.state.transcriptHistory, restoredTranscript)
        XCTAssertNil(store.state.restoreOutcome)
        await store.finish()
    }

    /// CBW-005-open_chat_conversation_session: current processing row 선택은 다른 restore를 supersede한다.
    /// A processing runtime이 authoritative한 동안 B restore를 취소하고 late B terminal을 차단하는지 검증합니다.
    /// - 검증 내용: current A row 선택의 B tracking/status 정리, restore cancellation, processing 보존
    /// - 사전 조건: A가 processing이고 sessions 화면에서 B restore가 진행 중이다.
    /// - 기대 결과: A가 chat으로 복귀하며 processing을 유지하고 late B outcome은 semantic state를 바꾸지 않는다.
    func testCurrentProcessingSessionRowSupersedesDifferentRestoreAndIgnoresLateTerminal() async {
        let catalogRows = makeCatalogRows()
        let currentSessionID = makeCBW005SessionID("26262626-2626-2626-2626-262626262626")
        let restoringSessionID = makeCBW005SessionID("27272727-2727-2727-2727-272727272727")
        let processingLock = makeCBW005RequestLock(sessionID: currentSessionID, modelRow: catalogRows[0])
        let staleSnapshot = makeCBW005Snapshot(
            sessionID: restoringSessionID,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "late B restore")],
        )
        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: restoringSessionID,
            mode: .sessions,
            sessionList: .init(
                allRows: [
                    makeCBW005SessionSummary(sessionID: currentSessionID),
                    makeCBW005SessionSummary(sessionID: restoringSessionID),
                ],
                selectedSessionID: restoringSessionID,
            ),
            sessionID: currentSessionID,
            sessionStatus: .restoring,
            transcriptHistory: restoredTranscript,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: catalogRows[0].handle,
            executionPhase: .processing(processingLock),
        )) {
            AiChatFeature()
        }

        await store.send(.sessionRowTapped(currentSessionID)) { state in
            state.sessionList.selectedSessionID = currentSessionID
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionStatus = .active
            state.mode = .chat
        }
        await store.send(.restoreOutcome(
            requestedSessionID: restoringSessionID,
            .restored(snapshot: staleSnapshot),
            restoreFailure: nil,
        ))

        XCTAssertEqual(store.state.sessionID, currentSessionID)
        XCTAssertEqual(store.state.sessionStatus, .active)
        XCTAssertEqual(store.state.transcriptHistory, restoredTranscript)
        XCTAssertEqual(store.state.executionPhase, .processing(processingLock))
        XCTAssertNil(store.state.restoreSessionID)
        XCTAssertEqual(store.state.sessionList.selectedSessionID, currentSessionID)
        await store.finish()
    }

    /// CBW-005-restore_chat_conversation_session: route/deferred restore는 effect 시작과 동시에 restoring을 소유한다.
    /// setup과 session row 외 진입 경로도 restore identity와 process status를 원자적으로 설정하는지 검증합니다.
    /// - 검증 내용: known list-row 및 deferred route의 즉시 `.restoring` 전이와 restored terminal `.active`
    /// - 사전 조건: persistence가 target snapshot을 반환하고 current chat 또는 deferred intent가 존재한다.
    /// - 기대 결과: effect가 시작된 send 경계는 restoring이고 terminal outcome 뒤 active로 정착한다.
    func testListAndDeferredRestoreStartsTruthfullySetRestoringUntilTerminal() async {
        let targetSessionID = makeCBW005SessionID("18181818-1818-1818-1818-181818181818")
        let currentSessionID = makeCBW005SessionID("19191919-1919-1919-1919-191919191919")
        let snapshot = makeCBW005Snapshot(
            sessionID: targetSessionID,
            transcriptHistory: restoredTranscript,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        func makeStore(_ state: AiChatFeature.State) -> TestStoreOf<AiChatFeature> {
            TestStore(initialState: state) { AiChatFeature() } withDependencies: {
                $0.uuid = .incrementing
                $0.aiChatSessionPersistenceClient.loadSession = { _ in snapshot }
            }
        }

        let listStore = makeStore(AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [summary]),
            sessionID: currentSessionID,
            sessionStatus: .active,
        ))
        // store.exhaustivity = .off: restore outcome의 세부 hydration보다 start/terminal status 경계를 검증한다.
        listStore.exhaustivity = .off
        await listStore.send(.routeToChatSession(targetSessionID)) { state in
            state.sessionList.selectedSessionID = targetSessionID
            state.restoreSessionID = targetSessionID
            state.sessionStatus = .restoring
        }
        await listStore.skipReceivedActions()
        await listStore.finish()
        XCTAssertEqual(listStore.state.sessionStatus, .active)

        let deferredStore = makeStore(AiChatFeature.State(
            deferredChatSessionRestoreID: targetSessionID,
            mode: .sessions,
            sessionList: .init(selectedSessionID: targetSessionID),
            sessionID: currentSessionID,
            sessionStatus: .active,
        ))
        // store.exhaustivity = .off: deferred restore outcome보다 start/terminal status 경계를 검증한다.
        deferredStore.exhaustivity = .off
        await deferredStore.send(.routeToChatSession(targetSessionID)) { state in
            state.deferredChatSessionRestoreID = nil
            state.restoreSessionID = targetSessionID
            state.sessionStatus = .restoring
        }
        await deferredStore.skipReceivedActions()
        await deferredStore.finish()
        XCTAssertEqual(deferredStore.state.sessionStatus, .active)
    }

    /// CBW-005-restore_chat_conversation_session: restore 취소는 stale restoring 상태를 남기지 않는다.
    /// History로 돌아가 restore effect를 취소할 때 현재 durable chat의 settled 상태를 복구하는지 검증합니다.
    /// - 검증 내용: backToSessions cancellation의 restore tracking 정리와 sessionStatus 정상화
    /// - 사전 조건: active session을 보유한 채 다른 session restore가 진행 중이다.
    /// - 기대 결과: restore ID는 정리되고 기존 session status는 active로 정착한다.
    func testBackToSessionsCancellationClearsRestoringStatus() async {
        let currentSessionID = makeCBW005SessionID("20202020-2020-2020-2020-202020202020")
        let restoringSessionID = makeCBW005SessionID("21212121-2121-2121-2121-212121212121")
        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: restoringSessionID,
            mode: .sessions,
            sessionList: .init(selectedSessionID: restoringSessionID),
            sessionID: currentSessionID,
            sessionStatus: .restoring,
        )) {
            AiChatFeature()
        }

        await store.send(.backToSessionsTapped) { state in
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionStatus = .active
        }
        await store.finish()
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

    /// CBW-005-show_chat_session_list: Inspector session row는 rest에서 clear이고 Home과 같은 hover feedback을 사용한다.
    /// session 목록을 탐색할 때 지속 배경 없이 pointer가 있는 row만 기존 Home interaction token으로 강조하는지 검증합니다.
    /// - 검증 내용: row modifier의 local hover state, shared fill, control radius, continuous style, 0.14초 ease-out
    /// - 사전 조건: 일반 row와 rename row가 같은 sessionRow 경계를 사용하고 기존 navigation/activity/actions sibling 구조가 존재한다.
    /// - 기대 결과: rest fill은 clear이고 hover 시 shared token으로 전환되며 기존 sibling target 구조는 별도 회귀 테스트로 보존된다.
    func testSessionRowsUseHomeHoverBackgroundContract() throws {
        let source = try String(contentsOf: aiChatSessionsViewSourceURL, encoding: .utf8)
        XCTAssertTrue(source
            .contains(
                "sessionRow(row)\n                                        .modifier(AiChatSessionRowHoverEffect())",
            ))

        let hoverEffect = try sourceSection(
            in: source,
            from: "private struct AiChatSessionRowHoverEffect",
            to: "private struct AiChatProcessingRowTextEffect",
        )

        XCTAssertTrue(hoverEffect.contains("@Environment(\\.colorScheme)"))
        XCTAssertTrue(hoverEffect.contains("@State private var isHovered = false"))
        XCTAssertTrue(hoverEffect.contains("VoyagerDS.Radius.control, style: .continuous"))
        XCTAssertTrue(hoverEffect.contains("isHovered ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear"))
        XCTAssertTrue(hoverEffect.contains(".animation(.easeOut(duration: 0.14), value: isHovered)"))
        XCTAssertTrue(hoverEffect.contains(".onHover { isHovered = $0 }"))
    }

    /// CBW-005-show_chat_session_list: session row의 navigation 영역은 카드 padding을 포함하고 보조 target과 분리된다.
    /// 실제 source 구조가 Button semantics를 유지하면서 빈 행 영역까지 hit target으로 확장되는지 검증합니다.
    /// - 검증 내용: max-width label, row text와 Spacer, 내부 padding, Rectangle content shape, sibling activity/menu
    /// - 사전 조건: display row는 rename row가 아닌 일반 session row이다.
    /// - 기대 결과: navigation Button이 남은 행 폭을 소유하고 activity와 actions menu는 Button 뒤의 독립 sibling이다.
    func testSessionRowNavigationOwnsVisiblePaddingAndKeepsSiblingTargets() throws {
        let source = try String(contentsOf: aiChatSessionsViewSourceURL, encoding: .utf8)
        let displayRow = try sourceSection(
            in: source,
            from: "    private func displayRow",
            to: "    @ViewBuilder\n    private func rowActivityIndicator",
        )

        XCTAssertTrue(displayRow.contains("Button {"))
        XCTAssertTrue(displayRow.contains("rowText(row)\n                    Spacer(minLength: 0)"))
        XCTAssertTrue(displayRow.contains(".padding(.leading, 10)"))
        XCTAssertTrue(displayRow.contains(".padding(.vertical, 8)"))
        XCTAssertTrue(displayRow.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(displayRow.contains(".contentShape(Rectangle())"))
        XCTAssertFalse(displayRow.contains(".onTapGesture"))

        let buttonIndex = try XCTUnwrap(displayRow.range(of: "Button {")?.lowerBound)
        let activityIndex = try XCTUnwrap(displayRow.range(of: "rowActivityIndicator(row)")?.lowerBound)
        let actionsIndex = try XCTUnwrap(displayRow.range(of: "AiChatSessionActionsMenuButton(")?.lowerBound)
        XCTAssertLessThan(buttonIndex, activityIndex)
        XCTAssertLessThan(activityIndex, actionsIndex)
        XCTAssertTrue(displayRow.contains(".padding(.trailing, 10)"))
    }

    /// CBW-005-show_chat_session_list: actions menu는 명시적인 button 접근성 metadata와 focus ring을 제공한다.
    /// NSHostingView가 representable의 실제 makeNSView를 실행해 만든 AppKit button 계약을 검증합니다.
    /// - 검증 내용: accessibility label, button role, focus ring, actions button 단일 AppKit target
    /// - 사전 조건: 일반 session row의 actions representable을 24pt frame으로 host한다.
    /// - 기대 결과: VoiceOver가 목적과 role을 읽고 keyboard focus indication이 억제되지 않는다.
    func testSessionActionsMenuButtonExposesAccessibilityAndFocusRing() throws {
        _ = NSApplication.shared
        let hostedView = NSHostingView(rootView: AiChatSessionActionsMenuButton(
            onRename: {},
            onDelete: {},
        ).frame(width: 24, height: 24))
        hostedView.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        hostedView.layoutSubtreeIfNeeded()

        let button = try XCTUnwrap(firstSubview(of: NSButton.self, in: hostedView))
        XCTAssertEqual(button.accessibilityLabel(), "Session actions")
        XCTAssertEqual(button.accessibilityRole(), .button)
        XCTAssertNotEqual(button.focusRingType, .none)
    }

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
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { limit, query in
                    listCalls.withValue { $0.append(.init(limit: limit, query: query)) }
                    return [first, second]
                },
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }

        await store.send(.sessionsAppeared) { state in
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
                saveSession: { snapshot in snapshot },
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

    /// CBW-005-delete_chat_conversation_session: 삭제된 세션의 foreground 요청은 cancelled terminal을 한 번 기록한다.
    /// requestPrepared가 turnSubmitted를 남긴 뒤 세션 삭제가 correlation을 소비하므로 늦은 terminal callback 전에
    /// cancelled 결과를 확정해야 합니다.
    /// - 검증 내용: 삭제 시 cancelled result 1회와 이후 late final callback의 무시를 확인합니다.
    /// - 사전 조건: 표시 중 세션의 processing lock에 requestPrepared correlation이 있습니다.
    /// - 기대 결과: submitted 1회, cancelled result 1회, success/failure result 0회입니다.
    func testDeleteSessionWithSubmittedForegroundRequestRecordsCancelledTerminal() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("33333333-3333-3333-3333-333333333331")
        let context = makeRequestContext(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("44444444-4444-4444-4444-444444444431")),
            runID: AiChatRunID(rawValue: makeUUID("55555555-5555-5555-5555-555555555531")),
            model: catalogRows[0].handle,
            selectedRow: catalogRows[0],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(context: context, messages: []),
            selectedHandle: catalogRows[0].handle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let metrics = LockIsolated<[AiChatProductMetric]>([])
        let store = makeDeleteSessionMetricStore(
            initialState: AiChatFeature.State(
                sessionID: sessionID,
                sessionStatus: .active,
                currentContext: makeContextSnapshot(),
                catalogRows: catalogRows,
                selectedModelHandle: catalogRows[0].handle,
                executionPhase: .processing(lock),
            ),
            metrics: metrics,
            milliseconds: 1_700_000_000_261,
        )
        // store.exhaustivity = .off: 삭제 경로의 metric 상관관계만 단일 소유합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.executionEvent(.requestPrepared(context: context))) { state in
            state.productMetricOperations[context.requestID] = AiChatProductMetricOperation(
                runID: context.runID,
                operationID: makeUUID("00000000-0000-0000-0000-000000000000"),
            )
        }
        await store.send(.deleteSessionTapped(sessionID))
        await store.receive(.sessionDeleteSucceeded(sessionID))
        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: context,
            assistantMessage: AiChatMessage(role: .assistant, content: "late"),
            completedAtMs: 1_700_000_000_261,
        ))))

        assertSingleSubmittedCancelledMetric(metrics.value)
    }

    /// CBW-005-delete_chat_conversation_session: 백그라운드 세션 삭제도 해당 correlation의 cancelled를 남긴다.
    /// 다른 세션을 표시하는 동안 background execution phase의 요청이 삭제되면 그 correlation만 소비해야 합니다.
    /// - 검증 내용: background lock 삭제 시 cancelled result 1회와 표시 세션 무영향을 확인합니다.
    /// - 사전 조건: backgroundExecutionPhases에 삭제 대상 세션의 processing lock이 있습니다.
    /// - 기대 결과: submitted 1회, cancelled result 1회이고 표시 세션에는 이벤트가 없습니다.
    func testDeleteSessionWithBackgroundRequestRecordsCancelledTerminal() async {
        let catalogRows = makeCatalogRows()
        let visibleSessionID = makeCBW005SessionID("33333333-3333-3333-3333-333333333332")
        let deletedSessionID = makeCBW005SessionID("33333333-3333-3333-3333-333333333333")
        let context = makeRequestContext(
            sessionID: deletedSessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("44444444-4444-4444-4444-444444444432")),
            runID: AiChatRunID(rawValue: makeUUID("55555555-5555-5555-5555-555555555532")),
            model: catalogRows[0].handle,
            selectedRow: catalogRows[0],
        )
        let backgroundLock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(context: context, messages: []),
            selectedHandle: catalogRows[0].handle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        var initialState = AiChatFeature.State(
            sessionID: visibleSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            executionPhase: .idle,
        )
        initialState.backgroundExecutionPhases[context.requestID] = .processing(backgroundLock)
        let metrics = LockIsolated<[AiChatProductMetric]>([])
        let store = makeDeleteSessionMetricStore(
            initialState: initialState,
            metrics: metrics,
            milliseconds: 1_700_000_000_262,
        )
        // store.exhaustivity = .off: background correlation 소비만 단일 소유합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.executionEvent(.requestPrepared(context: context))) { state in
            state.productMetricOperations[context.requestID] = AiChatProductMetricOperation(
                runID: context.runID,
                operationID: makeUUID("00000000-0000-0000-0000-000000000000"),
            )
        }
        await store.send(.deleteSessionTapped(deletedSessionID))
        await store.receive(.sessionDeleteSucceeded(deletedSessionID))

        assertSingleSubmittedCancelledMetric(metrics.value)
    }

    private func makeDeleteSessionMetricStore(
        initialState: AiChatFeature.State,
        metrics: LockIsolated<[AiChatProductMetric]>,
        milliseconds: Int64,
    ) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
        TestStore(initialState: initialState) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: milliseconds))
            $0.aiChatProductMetricsClient = AiChatProductMetricsClient { metric in
                metrics.withValue { $0.append(metric) }
            }
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }
    }

    private func assertSingleSubmittedCancelledMetric(_ recorded: [AiChatProductMetric]) {
        XCTAssertEqual(recorded.count(where: { if case .turnSubmitted = $0 { true } else { false } }), 1)
        XCTAssertEqual(
            recorded
                .count(where: {
                    if case let .turnResult(_, interaction, result, _) = $0 {
                        interaction == .generateContextualChatResponse && result == .cancelled
                    } else { false }
                }),
            1,
        )
        XCTAssertEqual(recorded.count(where: { if case .turnResult = $0 { true } else { false } }), 1)
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
        state.sessionStatus = .restoring
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
        state.sessionStatus = .restoring
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

    private func makePersistedSelectionCandidate(
        model: AiProviderModel,
        thinking: AiChatPersistedThinkingSelection,
    ) -> AiChatPersistedSelectionCandidate {
        AiChatPersistedSelectionCandidate(
            providerRawValue: model.provider.rawValue,
            modelProviderRawValue: model.provider.rawValue,
            modelRawValue: model.rawModelID,
            thinking: thinking,
        )
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
        state.sessionStatus = .active
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
                    return snapshot
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
                saveSession: { snapshot in snapshot },
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

    /// CBW-005-continue_chat_conversation_session: offscreen completion은 foreground next-turn draft/context/selection을
    /// 보존한다.
    /// 다른 session의 background 응답이 도착해도 현재 composer의 다음 메시지 준비 상태를 덮어쓰지 않는지 검증합니다.
    /// - 검증 내용: foreground draft/current context/attachment/model/thinking과 background owner terminal 전환을 확인합니다.
    /// - 사전 조건: session A request는 background processing이고 foreground session B에는 편집 중인 next-turn state가 있습니다.
    /// - 기대 결과: A만 completed owner로 전환되고 B의 composer state는 byte-for-byte 동일하게 유지됩니다.
    func testOffscreenCompletionPreservesForegroundNextTurnComposerState() {
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let backgroundSessionID = makeCBW005SessionID("50505050-5050-5050-5050-505050505635")
        let foregroundSessionID = makeCBW005SessionID("60606060-6060-6060-6060-606060606635")
        let nextContext = makeContextSnapshot(summary: "Foreground next context")
        let nextAttachment = makeCBW005Attachment(path: "/tmp/NextTurn.txt")
        let requestContext = makeRequestContext(
            sessionID: backgroundSessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("70707070-7070-7070-7070-707070707635")),
            runID: AiChatRunID(rawValue: makeUUID("80808080-8080-8080-8080-808080808635")),
            model: catalogRows[0].handle,
            selectedRow: catalogRows[0],
        )
        let request = AiChatRequest(
            context: requestContext,
            messages: [AiChatMessage(role: .user, content: "Background prompt")],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: catalogRows[0].handle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        var state = AiChatFeature.State(
            sessionID: foregroundSessionID,
            sessionStatus: .active,
            currentContext: nextContext,
            addedAttachments: [nextAttachment],
            draftText: "Foreground next draft",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[1].handle,
            selectedThinking: .effort(.minimal),
            backgroundExecutionPhases: [lock.requestID: .processing(lock)],
        )
        let feature = AiChatFeature()

        _ = withDependencies {
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_006_352))
        } operation: {
            feature.handleExecutionEvent(
                .final(response: AiChatResponse(
                    context: requestContext,
                    assistantMessage: AiChatMessage(role: .assistant, content: "Background answer"),
                    completedAtMs: 1_700_000_006_352,
                )),
                state: &state,
            )
        }

        XCTAssertEqual(state.sessionID, foregroundSessionID)
        XCTAssertEqual(state.currentContext, nextContext)
        XCTAssertEqual(state.addedAttachments, [nextAttachment])
        XCTAssertEqual(state.draftText, "Foreground next draft")
        XCTAssertEqual(state.selectedModelHandle, catalogRows[1].handle)
        XCTAssertEqual(state.selectedThinking, .effort(.minimal))
        guard case let .completed(completedLock) = state.backgroundExecutionPhases[lock.requestID] else {
            return XCTFail("Expected background completion owner")
        }
        XCTAssertEqual(completedLock.context, lock.context)
        XCTAssertEqual(completedLock.request, lock.request)
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
            currentSessionCustomTitle: "Renamed original",
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
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                },
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
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Question before new chat", createdAtMs: fixedMs),
            ]
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
            customTitle: "Renamed original",
        )

        await store.send(.newChatTapped) { state in
            applySessionListNewChatStarted(&state, sessionID: newSessionID)
            state.backgroundExecutionPhases[lock.requestID] = .processing(lock)
        }

        let newChatSnapshot = makeSessionListEmptySnapshot(
            sessionID: newSessionID,
            updatedAtMs: fixedMs,
        )
        await store.receive(.newChatCreated(newChatSnapshot)) { state in
            applySessionListNewChatCreated(&state, snapshot: newChatSnapshot)
            state.backgroundExecutionPhases[lock.requestID] = .processing(lock)
        }

        await store.send(.selectedModelChanged(selectedHandle)) { state in
            state.selectedModelHandle = selectedHandle
            state.unavailableSelectedModelHandle = nil
        }
        await store.send(.draftTextChanged("Question in new chat")) { state in
            state.draftText = "Question in new chat"
        }
        XCTAssertTrue(store.state.canSubmit)
        XCTAssertTrue(store.state.chatInputDisplayModel.canSubmit)
        XCTAssertEqual(store.state.backgroundExecutionPhases[lock.requestID], .processing(lock))

        let assistantMessage = AiChatMessage(
            role: .assistant, content: "Original request completed", createdAtMs: fixedMs,
        )
        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: assistantMessage,
            completedAtMs: fixedMs,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        let finalizedLock = lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        let expectedOriginalSnapshot = AiChatSessionSnapshot(
            sessionID: oldSessionID,
            status: .active,
            customTitle: "Renamed original",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Question before new chat", createdAtMs: fixedMs),
                assistantMessage,
            ],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let finalizedLockWithSnapshot = finalizedLock.recordingFinalSnapshot(expectedOriginalSnapshot)
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.backgroundExecutionPhases[finalizedLock.requestID] = .completed(finalizedLockWithSnapshot)
        }

        await store.receive(.sessionSnapshotSaved(
            AiChatSessionSummary(snapshot: expectedOriginalSnapshot),
            snapshot: expectedOriginalSnapshot,
            requestID: finalizedLockWithSnapshot.requestID,
            runID: finalizedLockWithSnapshot.runID,
        )) { state in
            state.backgroundExecutionPhases[finalizedLock.requestID] = nil
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

    func testBackgroundFinalStoresPersistenceTranscriptInsteadOfTruncatedRequestMessages() async {
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = makeCBW005SessionID("14141414-1414-1414-1414-141414141414")
        let fixedMs: Int64 = 1_700_000_001_414
        let olderUser = AiChatMessage(role: .user, content: "Older user kept for persistence")
        let olderAssistant = AiChatMessage(role: .assistant, content: "Older assistant kept for persistence")
        let latestUser = AiChatMessage(role: .user, content: "Latest user sent to provider")
        let assistantMessage = AiChatMessage(
            role: .assistant, content: "Background final answer", createdAtMs: fixedMs,
        )
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("14141414-1414-1414-1414-141414141415")),
                runID: AiChatRunID(rawValue: makeUUID("14141414-1414-1414-1414-141414141416")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [latestUser],
        )
        let lock = AiChatRequestLock(
            kind: .submit,
            requestID: request.context.requestID,
            runID: request.context.runID,
            context: request.context,
            request: request,
            selectedModelHandle: selectedHandle,
            selectedModelRow: catalogRows[0],
            assistantReplacementIndex: nil,
            persistenceTranscriptHistory: [olderUser, olderAssistant, latestUser],
            customTitle: "Persist full transcript",
            historyTruncation: AiChatHistoryTruncationMetadata(
                includedMessageCount: 1,
                excludedMessageCount: 2,
                budget: 24000,
                truncationReason: .characterBudgetExceeded,
            ),
            observabilitySummary: AiChatRequestObservabilitySummary(submittedAtMs: fixedMs),
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: makeCBW005SessionID("15151515-1515-1515-1515-151515151515"),
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            backgroundExecutionPhases: [lock.requestID: .processing(lock)],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { _, _ in [] },
                loadSession: { id in try await persistence.loadSession(id) },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }
        store.exhaustivity = Exhaustivity.off(showSkippedAssertions: false)

        let response = AiChatResponse(
            context: request.context,
            assistantMessage: assistantMessage,
            completedAtMs: fixedMs,
        )
        let expectedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Persist full transcript",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [olderUser, olderAssistant, latestUser, assistantMessage],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let finalizedLock = lock.recordingTerminal(
            at: fixedMs,
            failure: AiChatExecutionFailure?.none,
            wasCancelled: false,
        )
        .recordingFinalSnapshot(expectedSnapshot)

        await store.send(AiChatAction.executionEvent(.final(response: response))) { state in
            state.backgroundExecutionPhases[lock.requestID] = AiChatExecutionPhase.completed(finalizedLock)
        }
        XCTAssertEqual(persistence.snapshots.count, 1)
        guard let persistedSnapshot = persistence.snapshots.first else {
            XCTFail("Expected background final snapshot to be saved")
            return
        }
        XCTAssertEqual(persistedSnapshot.transcriptHistory, [
            olderUser,
            olderAssistant,
            latestUser,
            assistantMessage,
        ])
        XCTAssertEqual(persistedSnapshot.lastRequestID, lock.requestID)
        XCTAssertEqual(persistedSnapshot.lastRunID, lock.runID)
        XCTAssertEqual(persistedSnapshot.customTitle, "Persist full transcript")
    }

    func testVisibleFinalStoresFinalSnapshotOnCompletedOwner() async {
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = makeCBW005SessionID("13131313-1313-1313-1313-131313131313")
        let fixedMs: Int64 = 1_700_000_001_313
        let userMessage = AiChatMessage(role: .user, content: "Question before visible final")
        let assistantMessage = AiChatMessage(
            role: .assistant, content: "Visible final answer", createdAtMs: fixedMs,
        )
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("13131313-1313-1313-1313-131313131314")),
                runID: AiChatRunID(rawValue: makeUUID("13131313-1313-1313-1313-131313131315")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
                selectedModel: makeProviderModels()[0],
            ),
            messages: [userMessage],
        )
        let processingLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let finalizedLock = processingLock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        let expectedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: nil,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let finalizedLockWithSnapshot = finalizedLock.recordingFinalSnapshot(expectedSnapshot)
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [userMessage],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: selectedHandle,
            executionPhase: .processing(processingLock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: TimeInterval(fixedMs) / 1000))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }

        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: processingLock.context,
            assistantMessage: assistantMessage,
            completedAtMs: fixedMs,
        )))) { state in
            state.transcriptHistory = [userMessage, assistantMessage]
            state.lockedModelHandle = nil
            state.lastRequestContext = processingLock.context.requestContext
            state.lastRequestContextModelHandle = selectedHandle
            state.executionPhase = .completed(finalizedLockWithSnapshot)
            state.transcriptAutoScrollVersion += 1
        }

        await store.receive(.sessionSnapshotSaved(
            AiChatSessionSummary(snapshot: expectedSnapshot),
            snapshot: expectedSnapshot,
            requestID: finalizedLockWithSnapshot.requestID,
            runID: finalizedLockWithSnapshot.runID,
        )) { state in
            state.executionPhase = .completed(finalizedLockWithSnapshot.clearingFinalSnapshot())
            state.sessionList.replaceRow(AiChatSessionSummary(snapshot: expectedSnapshot))
            state.sessionList.selectedSessionID = sessionID
            state.sessionList.unreadCompletedSessionIDs = [sessionID]
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(persistence.snapshots, [expectedSnapshot])
        XCTAssertNil(store.state.executionPhase.lock?.finalSnapshot)
        await store.finish()
    }

    /// CBW-005: final snapshot 저장 중 변경한 모델과 Thinking을 저장 완료 후에도 유지한다.
    /// - 검증 내용: 저장 시작 snapshot보다 최신인 runtime selection 보존
    /// - 사전 조건: final snapshot 저장이 완료되기 전에 모델과 Thinking을 변경한다.
    /// - 기대 결과: 저장 완료는 transcript를 반영하되 최신 모델과 Thinking을 덮어쓰지 않는다.
    func testFinalSnapshotSaveCompletionPreservesNewerRuntimeSelection() async {
        let catalogRows = makeCatalogRows()
        let persistedHandle = catalogRows[0].handle
        let newerHandle = catalogRows[1].handle
        let sessionID = makeCBW005SessionID("13131313-1313-1313-1313-131313131323")
        let fixedMs: Int64 = 1_700_000_001_323
        let userMessage = AiChatMessage(role: .user, content: "Question before delayed save")
        let assistantMessage = AiChatMessage(role: .assistant, content: "Delayed final answer")
        let normalizedAssistantMessage = AiChatMessage(
            role: .assistant, content: "Delayed final answer", createdAtMs: fixedMs,
        )
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("13131313-1313-1313-1313-131313131324")),
                runID: AiChatRunID(rawValue: makeUUID("13131313-1313-1313-1313-131313131325")),
                model: persistedHandle,
                selectedRow: catalogRows[0],
                selectedModel: makeProviderModels()[0],
            ),
            messages: [userMessage],
        )
        let processingLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: persistedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let finalizedLock = processingLock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        let expectedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: nil,
            provider: persistedHandle.provider,
            model: persistedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, normalizedAssistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let finalizedLockWithSnapshot = finalizedLock.recordingFinalSnapshot(expectedSnapshot)
        let saveStarted = AsyncStream<Void>.makeStream()
        let resumeSave = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            sessionStatus: .active,
            transcriptHistory: [userMessage],
            catalogRows: catalogRows,
            selectedModelHandle: persistedHandle,
            lockedModelHandle: persistedHandle,
            executionPhase: .processing(processingLock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: TimeInterval(fixedMs) / 1000))
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                saveStarted.continuation.yield()
                var iterator = resumeSave.stream.makeAsyncIterator()
                _ = await iterator.next()
                return snapshot
            }
        }
        // 저장 gate 전후의 selection과 completion projection만 선별 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: processingLock.context,
            assistantMessage: assistantMessage,
            completedAtMs: fixedMs,
        ))))
        var saveStartedIterator = saveStarted.stream.makeAsyncIterator()
        _ = await saveStartedIterator.next()

        await store.send(.selectedModelChanged(newerHandle))
        await store.send(.selectedThinkingChanged(.effort(.low)))
        resumeSave.continuation.yield()
        await store.receive(.sessionSnapshotSaved(
            AiChatSessionSummary(snapshot: expectedSnapshot),
            snapshot: expectedSnapshot,
            requestID: finalizedLockWithSnapshot.requestID,
            runID: finalizedLockWithSnapshot.runID,
        )) { state in
            state.executionPhase = .completed(finalizedLockWithSnapshot.clearingFinalSnapshot())
            state.sessionList.replaceRow(AiChatSessionSummary(snapshot: expectedSnapshot))
            state.sessionList.selectedSessionID = sessionID
            state.sessionList.errorMessage = nil
        }
        await store.finish()

        XCTAssertEqual(store.state.selectedModelHandle, newerHandle)
        XCTAssertEqual(store.state.selectedThinking, .effort(.low))
        XCTAssertEqual(store.state.transcriptHistory, [userMessage, normalizedAssistantMessage])
    }

    /// CBW-005: background final 저장 중 원래 session으로 돌아와 변경한 selection을 유지한다.
    /// - 검증 내용: offscreen save baseline과 promoted final owner의 최신 runtime selection 보존
    /// - 사전 조건: session A 저장이 지연된 동안 session B에서 A로 복귀해 모델과 Thinking을 변경한다.
    /// - 기대 결과: A의 저장 완료는 최신 selection을 덮어쓰지 않고 final transcript만 반영한다.
    func testBackgroundFinalSaveCompletionPreservesSelectionChangedAfterReturningToSession() async {
        let catalogRows = makeCatalogRows()
        let persistedHandle = catalogRows[0].handle
        let newerHandle = catalogRows[1].handle
        let sessionID = makeCBW005SessionID("13131313-1313-1313-1313-131313131333")
        let otherSessionID = makeCBW005SessionID("13131313-1313-1313-1313-131313131334")
        let fixedMs: Int64 = 1_700_000_001_333
        let userMessage = AiChatMessage(role: .user, content: "Background question")
        let assistantMessage = AiChatMessage(role: .assistant, content: "Background final answer")
        let normalizedAssistantMessage = AiChatMessage(
            role: .assistant, content: "Background final answer", createdAtMs: fixedMs,
        )
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("13131313-1313-1313-1313-131313131335")),
                runID: AiChatRunID(rawValue: makeUUID("13131313-1313-1313-1313-131313131336")),
                model: persistedHandle,
                selectedRow: catalogRows[0],
                selectedModel: makeProviderModels()[0],
            ),
            messages: [userMessage],
        )
        let processingLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: persistedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: nil,
            provider: persistedHandle.provider,
            model: persistedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: fixedMs - 1,
        )
        let saveStarted = AsyncStream<Void>.makeStream()
        let resumeSave = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionList: .init(
                allRows: [AiChatSessionSummary(snapshot: staleSnapshot)],
                rows: [AiChatSessionSummary(snapshot: staleSnapshot)],
            ),
            sessionID: otherSessionID,
            sessionStatus: .active,
            transcriptHistory: [AiChatMessage(role: .user, content: "Other session")],
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: persistedHandle,
            backgroundExecutionPhases: [processingLock.requestID: .processing(processingLock)],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: TimeInterval(fixedMs) / 1000))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { requestedSessionID in
                    requestedSessionID == sessionID ? staleSnapshot : nil
                },
                saveSession: { snapshot in
                    saveStarted.continuation.yield()
                    var iterator = resumeSave.stream.makeAsyncIterator()
                    _ = await iterator.next()
                    return snapshot
                },
                deleteSession: { _ in },
            )
        }
        // background final, restore promotion, selection mutation, save completion 순서만 선별 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: processingLock.context,
            assistantMessage: assistantMessage,
            completedAtMs: fixedMs,
        ))))
        var saveStartedIterator = saveStarted.stream.makeAsyncIterator()
        _ = await saveStartedIterator.next()

        await store.send(.routeToChatSession(sessionID))
        await store.skipReceivedActions()
        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.transcriptHistory, [userMessage, normalizedAssistantMessage])

        await store.send(.selectedModelChanged(newerHandle))
        await store.send(.selectedThinkingChanged(.effort(.low)))
        resumeSave.continuation.yield()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.selectedModelHandle, newerHandle)
        XCTAssertEqual(store.state.selectedThinking, .effort(.low))
        XCTAssertEqual(store.state.transcriptHistory, [userMessage, normalizedAssistantMessage])
    }

    func testRequestStartPreservesPreviousCompletedOwnerForCancellation() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = makeCBW005SessionID("15151515-1515-1515-1515-151515151515")
        let oldUserMessage = AiChatMessage(role: .user, content: "Old question")
        let oldAssistantMessage = AiChatMessage(role: .assistant, content: "Old answer")
        let oldRequest = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("15151515-1515-1515-1515-151515151516")),
                runID: AiChatRunID(rawValue: makeUUID("15151515-1515-1515-1515-151515151517")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
                selectedModel: makeProviderModels()[0],
            ),
            messages: [oldUserMessage],
        )
        let oldFinalizedLock = makeRequestLock(
            kind: .submit,
            request: oldRequest,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        .recordingTerminal(at: 1_700_000_001_515, failure: nil, wasCancelled: false)
        let oldSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: nil,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [oldUserMessage, oldAssistantMessage],
            lastRequestID: oldFinalizedLock.requestID,
            lastRunID: oldFinalizedLock.runID,
            lastRequestContext: oldFinalizedLock.context.requestContext,
            updatedAtMs: 1_700_000_001_515,
        )
        let oldOwnerLock = oldFinalizedLock.recordingFinalSnapshot(oldSnapshot)
        let resolutionID = makeUUID("15151515-1515-1515-1515-151515151518")
        let newUserMessage = AiChatMessage(role: .user, content: "New question")
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: makeProviderModels()[0],
            selectedRow: catalogRows[0],
            preparedRequest: AiChatPreparedRequest(
                prompt: newUserMessage.content,
                messages: [newUserMessage],
                persistenceTranscriptHistory: nil,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )
        let store: TestStore<AiChatFeature.State, AiChatAction> = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            transcriptHistory: [oldUserMessage, oldAssistantMessage],
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            pendingRequestStart: pendingRequest,
            executionPhase: .completed(oldOwnerLock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_001.600))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in AsyncStream { $0.finish() } }
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.requestContextResolved(resolutionID, AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.backgroundExecutionPhases[oldOwnerLock.requestID], .completed(oldOwnerLock))
        if case .processing = store.state.executionPhase {
        } else {
            XCTFail("new request should start processing after context resolution")
        }
        await store.finish()
    }

    func testRequestStartPreservesDifferentSessionCompletedOwnerForCancellation() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let oldSessionID = makeCBW005SessionID("17171717-1717-1717-1717-171717171717")
        let newSessionID = makeCBW005SessionID("18181818-1818-1818-1818-181818181818")
        let oldUserMessage = AiChatMessage(role: .user, content: "Old cross-session question")
        let oldAssistantMessage = AiChatMessage(role: .assistant, content: "Old cross-session answer")
        let oldRequest = AiChatRequest(
            context: makeRequestContext(
                sessionID: oldSessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("17171717-1717-1717-1717-171717171718")),
                runID: AiChatRunID(rawValue: makeUUID("17171717-1717-1717-1717-171717171719")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
                selectedModel: makeProviderModels()[0],
            ),
            messages: [oldUserMessage],
        )
        let oldFinalizedLock = makeRequestLock(
            kind: .submit,
            request: oldRequest,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        .recordingTerminal(at: 1_700_000_001_717, failure: nil, wasCancelled: false)
        let oldSnapshot = AiChatSessionSnapshot(
            sessionID: oldSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [oldUserMessage, oldAssistantMessage],
            lastRequestID: oldFinalizedLock.requestID,
            lastRunID: oldFinalizedLock.runID,
            lastRequestContext: oldFinalizedLock.context.requestContext,
            updatedAtMs: 1_700_000_001_717,
        )
        let oldOwnerLock = oldFinalizedLock.recordingFinalSnapshot(oldSnapshot)
        let resolutionID = makeUUID("18181818-1818-1818-1818-181818181819")
        let newUserMessage = AiChatMessage(role: .user, content: "New session question")
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: newSessionID,
            selectedModel: makeProviderModels()[0],
            selectedRow: catalogRows[0],
            preparedRequest: AiChatPreparedRequest(
                prompt: newUserMessage.content,
                messages: [newUserMessage],
                persistenceTranscriptHistory: [newUserMessage],
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )
        let store: TestStore<AiChatFeature.State, AiChatAction> = TestStore(initialState: AiChatFeature.State(
            sessionID: newSessionID,
            sessionStatus: .active,
            transcriptHistory: [],
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            pendingRequestStart: pendingRequest,
            executionPhase: .completed(oldOwnerLock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_001.800))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in AsyncStream { $0.finish() } }
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.requestContextResolved(resolutionID, AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.backgroundExecutionPhases[oldOwnerLock.requestID], .completed(oldOwnerLock))
        if case let .processing(lock) = store.state.executionPhase {
            XCTAssertEqual(lock.context.sessionID, newSessionID)
        } else {
            XCTFail("new session request should start processing after context resolution")
        }
        await store.finish()
    }

    func testSavedCompletedOwnerIsNotPreservedBeforeNextRequestStart() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = makeCBW005SessionID("16161616-1616-1616-1616-161616161616")
        let oldUserMessage = AiChatMessage(role: .user, content: "Saved old question")
        let oldAssistantMessage = AiChatMessage(role: .assistant, content: "Saved old answer")
        let oldRequest = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("16161616-1616-1616-1616-161616161617")),
                runID: AiChatRunID(rawValue: makeUUID("16161616-1616-1616-1616-161616161618")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
                selectedModel: makeProviderModels()[0],
            ),
            messages: [oldUserMessage],
        )
        let oldFinalizedLock = makeRequestLock(
            kind: .submit,
            request: oldRequest,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        .recordingTerminal(at: 1_700_000_001_616, failure: nil, wasCancelled: false)
        let oldSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [oldUserMessage, oldAssistantMessage],
            lastRequestID: oldFinalizedLock.requestID,
            lastRunID: oldFinalizedLock.runID,
            lastRequestContext: oldFinalizedLock.context.requestContext,
            updatedAtMs: 1_700_000_001_616,
        )
        let oldOwnerLock = oldFinalizedLock.recordingFinalSnapshot(oldSnapshot)
        let savedOwnerLock = oldOwnerLock.clearingFinalSnapshot()
        let resolutionID = makeUUID("16161616-1616-1616-1616-161616161619")
        let newUserMessage = AiChatMessage(role: .user, content: "New question after saved final")
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: makeProviderModels()[0],
            selectedRow: catalogRows[0],
            preparedRequest: AiChatPreparedRequest(
                prompt: newUserMessage.content,
                messages: [newUserMessage],
                persistenceTranscriptHistory: nil,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )
        let store: TestStore<AiChatFeature.State, AiChatAction> = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            transcriptHistory: oldSnapshot.transcriptHistory,
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            pendingRequestStart: pendingRequest,
            executionPhase: .completed(oldOwnerLock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_001.700))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in AsyncStream { $0.finish() } }
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.sessionSnapshotSaved(
            AiChatSessionSummary(snapshot: oldSnapshot),
            snapshot: oldSnapshot,
            requestID: oldOwnerLock.requestID,
            runID: oldOwnerLock.runID,
        ))
        XCTAssertEqual(store.state.executionPhase, .completed(savedOwnerLock))

        await store.send(.requestContextResolved(resolutionID, AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.backgroundExecutionPhases[oldOwnerLock.requestID])
        if case .processing = store.state.executionPhase {
        } else {
            XCTFail("new request should start processing after context resolution")
        }
        await store.finish()
    }

    func testPersistenceRecoveryRetryUsesFinalSnapshotStoredOnRequestLock() async {
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = makeCBW005SessionID("14141414-1414-1414-1414-141414141414")
        let fixedMs: Int64 = 1_700_000_001_414
        let userMessage = AiChatMessage(role: .user, content: "Question before background failure")
        let assistantMessage = AiChatMessage(role: .assistant, content: "Recovered final answer")
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("14141414-1414-1414-1414-141414141415")),
                runID: AiChatRunID(rawValue: makeUUID("14141414-1414-1414-1414-141414141416")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [userMessage],
        )
        let finalizedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        .recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: nil,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let recoveryLock = finalizedLock.recordingFinalSnapshot(finalSnapshot)
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [userMessage],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .unknown,
            executionPhase: .persistenceRecovery(recoveryLock, .unknown),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }

        await store.send(.errorRecoveryTapped)

        await store.receive(.persistenceRecoverySucceeded(recoveryLock)) { state in
            state.lastExecutionFailure = nil
            state.executionPhase = .completed(recoveryLock.clearingFinalSnapshot())
        }

        XCTAssertEqual(persistence.snapshots, [finalSnapshot])
        XCTAssertNil(store.state.executionPhase.lock?.finalSnapshot)
        await store.finish()
    }

    func testRenameSessionRefreshesBackgroundFinalSnapshotCustomTitle() async {
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = makeCBW005SessionID("15151515-1515-1515-1515-151515151515")
        let fixedMs: Int64 = 1_700_000_001_515
        let userMessage = AiChatMessage(role: .user, content: "Rename while background final pending")
        let assistantMessage = AiChatMessage(role: .assistant, content: "Final answer after rename")
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("15151515-1515-1515-1515-151515151516")),
                runID: AiChatRunID(rawValue: makeUUID("15151515-1515-1515-1515-151515151517")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [userMessage],
        )
        let finalizedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
            customTitle: nil,
        )
        .recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: nil,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let finalLock = finalizedLock.recordingFinalSnapshot(finalSnapshot)
        let renamedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Renamed while pending",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: fixedMs - 1,
        )
        let renamedSummary = AiChatSessionSummary(snapshot: renamedSnapshot)
        let renamedFinalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Renamed while pending",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let renamedFinalLock = finalizedLock
            .recordingFinalSnapshot(finalSnapshot)
            .recordingCustomTitle("Renamed while pending")

        let store = TestStore(initialState: AiChatFeature.State(
            sessionList: .init(allRows: [AiChatSessionSummary(snapshot: finalSnapshot)]),
            sessionID: makeCBW005SessionID("15151515-1515-1515-1515-151515151518"),
            sessionStatus: .idle,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            backgroundExecutionPhases: [
                finalizedLock.requestID: AiChatExecutionPhase.completed(finalLock),
            ],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { requestedSessionID in
                    requestedSessionID == sessionID ? renamedSnapshot : nil
                },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }

        await store.send(.sessionRenameSucceeded(renamedSummary, customTitle: "Renamed while pending")) { state in
            state.sessionList.replaceRow(renamedSummary)
            state.backgroundExecutionPhases[finalizedLock.requestID] = AiChatExecutionPhase.completed(renamedFinalLock)
            state.sessionList.errorMessage = nil
        }

        await store.send(.persistenceFailed(finalLock, .unknown)) { state in
            state.backgroundExecutionPhases[finalizedLock.requestID] = AiChatExecutionPhase.persistenceRecovery(
                renamedFinalLock,
                .unknown,
            )
        }

        await store.send(.routeToChatSession(sessionID)) { state in
            state.sessionList.selectedSessionID = sessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.restoreSessionID = sessionID
            state.sessionStatus = .restoring
            state.mode = .sessions
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: sessionID,
            .restored(snapshot: renamedSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = sessionID
            state.sessionStatus = .active
            state.currentSessionCustomTitle = renamedFinalSnapshot.customTitle
            state.transcriptHistory = renamedFinalSnapshot.transcriptHistory
            state.transcriptAutoScrollVersion += 1
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = renamedFinalSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = renamedFinalSnapshot.model
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = AiChatExecutionPhase.persistenceRecovery(renamedFinalLock, .unknown)
            state.backgroundExecutionPhases[finalizedLock.requestID] = nil
            state.selectedModelHandle = renamedFinalSnapshot.model
            state.selectedThinking = renamedFinalSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: renamedSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        await store.send(.errorRecoveryTapped)
        await store.receive(.persistenceRecoverySucceeded(renamedFinalLock)) { state in
            state.lastExecutionFailure = nil
            state.executionPhase = AiChatExecutionPhase.completed(renamedFinalLock)
        }

        XCTAssertEqual(persistence.snapshots, [renamedFinalSnapshot])
        await store.finish()
    }

    func testBackgroundPersistenceRecoveryFollowUpsUpdateBackgroundOwner() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("18181818-1818-1818-1818-181818181818")
        let selectedHandle = catalogRows[0].handle
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("18181818-1818-1818-1818-181818181819")),
                runID: AiChatRunID(rawValue: makeUUID("18181818-1818-1818-1818-181818181820")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [AiChatMessage(role: .user, content: "Retry background")],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let otherSessionID = makeCBW005SessionID("19191919-1919-1919-1919-191919191919")

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: otherSessionID,
            sessionStatus: .idle,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            backgroundExecutionPhases: [
                lock.requestID: AiChatExecutionPhase.persistenceRecovery(lock, .unknown),
            ],
        )) {
            AiChatFeature()
        }

        await store.send(.persistenceRecoveryRetryFailed(lock, .network)) { state in
            state.backgroundExecutionPhases[lock.requestID] = .persistenceRecovery(lock, .network)
        }
        await store.send(.persistenceRecoverySucceeded(lock)) { state in
            state.backgroundExecutionPhases[lock.requestID] = .completed(lock)
        }
        await store.finish()
    }

    func testNewChatTappedMovesPersistenceRecoveryOwnerToBackground() async {
        let catalogRows = makeCatalogRows()
        let sourceSessionID = makeCBW005SessionID("18181818-1818-1818-1818-181818181818")
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let selectedHandle = catalogRows[0].handle
        let userMessage = AiChatMessage(role: .user, content: "Source recovery pending")
        let assistantMessage = AiChatMessage(role: .assistant, content: "Final answer before retry")
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sourceSessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("18181818-1818-1818-1818-181818181819")),
                runID: AiChatRunID(rawValue: makeUUID("18181818-1818-1818-1818-18181818181a")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [userMessage],
        )
        let finalizedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        .recordingTerminal(at: 1_700_000_001_818, failure: nil, wasCancelled: false)
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: sourceSessionID,
            status: .active,
            customTitle: "Recovered Source",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: 1_700_000_001_818,
        )
        let ownerLock = finalizedLock.recordingFinalSnapshot(finalSnapshot)

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionID: sourceSessionID,
            sessionStatus: .active,
            transcriptHistory: [userMessage],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .persistenceRecovery(ownerLock, .unknown),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_001_818))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }

        await store.send(.newChatTapped) { state in
            applySessionListNewChatStarted(&state, sessionID: newSessionID)
            state.backgroundExecutionPhases[ownerLock.requestID] = .persistenceRecovery(ownerLock, .unknown)
        }

        let newChatSnapshot = makeSessionListEmptySnapshot(
            sessionID: newSessionID,
            updatedAtMs: 1_700_000_001_818,
        )
        await store.receive(.newChatCreated(newChatSnapshot)) { state in
            applySessionListNewChatCreated(&state, snapshot: newChatSnapshot)
            state.backgroundExecutionPhases[ownerLock.requestID] = .persistenceRecovery(ownerLock, .unknown)
        }

        XCTAssertEqual(
            store.state.backgroundExecutionPhases[ownerLock.requestID],
            .persistenceRecovery(ownerLock, .unknown),
        )
        await store.finish()
    }

    func testRouteToChatSessionMovesCompletedFinalOwnerToBackground() async {
        let catalogRows = makeCatalogRows()
        let sourceSessionID = makeCBW005SessionID("16161616-1616-1616-1616-161616161616")
        let targetSessionID = makeCBW005SessionID("17171717-1717-1717-1717-171717171717")
        let selectedHandle = catalogRows[0].handle
        let userMessage = AiChatMessage(role: .user, content: "Source final pending")
        let assistantMessage = AiChatMessage(role: .assistant, content: "Final answer")
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sourceSessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("16161616-1616-1616-1616-161616161617")),
                runID: AiChatRunID(rawValue: makeUUID("16161616-1616-1616-1616-161616161618")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [userMessage],
        )
        let finalizedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        .recordingTerminal(at: 1_700_000_001_616, failure: nil, wasCancelled: false)
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: sourceSessionID,
            status: .active,
            customTitle: nil,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: 1_700_000_001_616,
        )
        let ownerLock = finalizedLock.recordingFinalSnapshot(finalSnapshot)
        let targetSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            customTitle: "Target",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Target question")],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_700_000_001_700,
        )
        let targetSummary = AiChatSessionSummary(snapshot: targetSnapshot)

        let store = TestStore(initialState: AiChatFeature.State(
            sessionList: .init(allRows: [targetSummary], rows: [targetSummary]),
            sessionID: sourceSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [userMessage],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .completed(ownerLock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { requestedSessionID in
                    requestedSessionID == targetSessionID ? targetSnapshot : nil
                },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }

        await store.send(.routeToChatSession(targetSessionID)) { state in
            state.backgroundExecutionPhases[ownerLock.requestID] = .completed(ownerLock)
            state.executionPhase = .idle
            state.lockedModelHandle = nil
            state.streamingAssistantDraft = nil
            state.currentContextFolderStructureModes = [:]
            state.sessionList.selectedSessionID = targetSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.restoreSessionID = targetSessionID
            state.sessionStatus = .restoring
            state.mode = .sessions
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: targetSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.currentSessionCustomTitle = targetSnapshot.customTitle
            state.transcriptHistory = targetSnapshot.transcriptHistory
            state.lastExecutionFailure = nil
            state.lastRequestContext = targetSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = nil
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.selectedModelHandle = targetSnapshot.model
            state.selectedThinking = targetSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: targetSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }
        XCTAssertEqual(store.state.backgroundExecutionPhases[ownerLock.requestID], .completed(ownerLock))
        await store.finish()
    }

    func testRouteToChatSessionPromotesFinalSnapshotToVisibleTranscript() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("18181818-1818-1818-1818-181818181818")
        let selectedHandle = catalogRows[0].handle
        let userMessage = AiChatMessage(role: .user, content: "Restore source final pending")
        let assistantMessage = AiChatMessage(role: .assistant, content: "Restored final answer")
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("18181818-1818-1818-1818-181818181819")),
                runID: AiChatRunID(rawValue: makeUUID("18181818-1818-1818-1818-18181818181A")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [userMessage],
        )
        let finalizedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        .recordingTerminal(at: 1_700_000_001_818, failure: nil, wasCancelled: false)
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Final title",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: 1_700_000_001_818,
        )
        let ownerLock = finalizedLock.recordingFinalSnapshot(finalSnapshot)
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Stale title",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_700_000_001_700,
        )
        let staleSummary = AiChatSessionSummary(snapshot: staleSnapshot)

        let store = TestStore(initialState: AiChatFeature.State(
            sessionList: .init(allRows: [staleSummary], rows: [staleSummary]),
            sessionID: makeCBW005SessionID("19191919-1919-1919-1919-191919191919"),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .user, content: "Other session")],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            backgroundExecutionPhases: [ownerLock.requestID: .completed(ownerLock)],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { requestedSessionID in
                    requestedSessionID == sessionID ? staleSnapshot : nil
                },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }

        await store.send(.routeToChatSession(sessionID)) { state in
            state.sessionList.selectedSessionID = sessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.restoreSessionID = sessionID
            state.sessionStatus = .restoring
            state.mode = .sessions
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: sessionID,
            .restored(snapshot: staleSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = sessionID
            state.sessionStatus = .active
            state.currentSessionCustomTitle = finalSnapshot.customTitle
            state.transcriptHistory = finalSnapshot.transcriptHistory
            state.transcriptAutoScrollVersion += 1
            state.lastExecutionFailure = nil
            state.lastRequestContext = finalSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = finalSnapshot.model
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = .completed(ownerLock)
            state.backgroundExecutionPhases[ownerLock.requestID] = nil
            state.selectedModelHandle = finalSnapshot.model
            state.selectedThinking = finalSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: staleSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        XCTAssertNil(store.state.backgroundExecutionPhases[ownerLock.requestID])
        XCTAssertEqual(store.state.transcriptHistory, finalSnapshot.transcriptHistory)
        XCTAssertEqual(store.state.currentSessionCustomTitle, "Final title")
        await store.finish()
    }

    func testRouteToChatSessionKeepsPersistedSnapshotForSavedCompletedOwner() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("2B2B2B2B-2B2B-2B2B-2B2B-2B2B2B2B2B2B")
        let selectedHandle = catalogRows[0].handle
        let userMessage = AiChatMessage(role: .user, content: "Saved completed restore")
        let assistantMessage = AiChatMessage(role: .assistant, content: "Already saved answer")
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("2B2B2B2B-2B2B-2B2B-2B2B-2B2B2B2B2B2C")),
                runID: AiChatRunID(rawValue: makeUUID("2B2B2B2B-2B2B-2B2B-2B2B-2B2B2B2B2B2D")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [userMessage],
        )
        let finalizedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
            persistenceTranscriptHistory: [userMessage],
        )
        .recordingTerminal(at: 1_700_000_002_525, failure: nil, wasCancelled: false)
        let persistedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Persisted final title",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: 1_700_000_002_525,
        )
        let savedCompletedLock = finalizedLock
            .recordingFinalSnapshot(persistedSnapshot)
            .clearingFinalSnapshot()
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Stale loaded title",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: 1_700_000_002_500,
        )
        let staleSummary = AiChatSessionSummary(snapshot: staleSnapshot)

        let store = TestStore(initialState: AiChatFeature.State(
            sessionList: .init(allRows: [staleSummary], rows: [staleSummary]),
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: staleSnapshot.transcriptHistory,
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .completed(savedCompletedLock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { requestedSessionID in
                    requestedSessionID == sessionID ? persistedSnapshot : nil
                },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }

        await store.send(.sessionRowTapped(sessionID)) { state in
            self.applyOpeningSessionRowState(&state, sessionID: sessionID)
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: sessionID,
            .restored(snapshot: persistedSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = sessionID
            state.sessionStatus = .active
            state.currentSessionCustomTitle = persistedSnapshot.customTitle
            state.transcriptHistory = persistedSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = persistedSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = persistedSnapshot.model
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = .completed(savedCompletedLock)
            state.selectedModelHandle = persistedSnapshot.model
            state.selectedThinking = persistedSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: persistedSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        XCTAssertNil(store.state.executionPhase.lock?.finalSnapshot)
        XCTAssertEqual(store.state.transcriptHistory, persistedSnapshot.transcriptHistory)
        XCTAssertEqual(store.state.currentSessionCustomTitle, "Persisted final title")
        await store.finish()
    }

    func testRouteToChatSessionPreservesCurrentCompletedOwnerForSameSession() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("2A2A2A2A-2A2A-2A2A-2A2A-2A2A2A2A2A2A")
        let selectedHandle = catalogRows[0].handle
        let userMessage = AiChatMessage(role: .user, content: "Restore current final pending")
        let assistantMessage = AiChatMessage(role: .assistant, content: "Current final answer")
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("2A2A2A2A-2A2A-2A2A-2A2A-2A2A2A2A2A2B")),
                runID: AiChatRunID(rawValue: makeUUID("2A2A2A2A-2A2A-2A2A-2A2A-2A2A2A2A2A2C")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [userMessage],
        )
        let finalizedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        .recordingTerminal(at: 1_700_000_002_424, failure: nil, wasCancelled: false)
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Current final title",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: finalizedLock.requestID,
            lastRunID: finalizedLock.runID,
            lastRequestContext: finalizedLock.context.requestContext,
            updatedAtMs: 1_700_000_002_424,
        )
        let ownerLock = finalizedLock.recordingFinalSnapshot(finalSnapshot)
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Stale same-session title",
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_700_000_002_300,
        )
        let staleSummary = AiChatSessionSummary(snapshot: staleSnapshot)

        let store = TestStore(initialState: AiChatFeature.State(
            sessionList: .init(allRows: [staleSummary], rows: [staleSummary]),
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: staleSnapshot.transcriptHistory,
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .completed(ownerLock),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { requestedSessionID in
                    requestedSessionID == sessionID ? staleSnapshot : nil
                },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }

        await store.send(.sessionRowTapped(sessionID)) { state in
            self.applyOpeningSessionRowState(&state, sessionID: sessionID)
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: sessionID,
            .restored(snapshot: staleSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = sessionID
            state.sessionStatus = .active
            state.currentSessionCustomTitle = finalSnapshot.customTitle
            state.transcriptHistory = finalSnapshot.transcriptHistory
            state.transcriptAutoScrollVersion += 1
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = finalSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = finalSnapshot.model
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = .completed(ownerLock)
            state.selectedModelHandle = finalSnapshot.model
            state.selectedThinking = finalSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: staleSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.executionPhase.lock?.finalSnapshot, finalSnapshot)
        XCTAssertEqual(store.state.transcriptHistory, finalSnapshot.transcriptHistory)
        await store.finish()
    }

    func testRouteToChatSessionPromotesProcessingOwnerBeforeCompletedOwner() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("21212121-2121-2121-2121-212121212121")
        let selectedHandle = catalogRows[0].handle
        let completedUserMessage = AiChatMessage(role: .user, content: "Previous request")
        let completedAssistantMessage = AiChatMessage(role: .assistant, content: "Previous final")
        let completedRequest = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("21212121-2121-2121-2121-212121212122")),
                runID: AiChatRunID(rawValue: makeUUID("21212121-2121-2121-2121-212121212123")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [completedUserMessage],
        )
        let completedLock = makeRequestLock(
            kind: .submit,
            request: completedRequest,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        .recordingTerminal(at: 1_700_000_002_121, failure: nil, wasCancelled: false)
        .recordingFinalSnapshot(AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [completedUserMessage, completedAssistantMessage],
            lastRequestID: AiChatRequestID(rawValue: makeUUID("21212121-2121-2121-2121-212121212122")),
            lastRunID: AiChatRunID(rawValue: makeUUID("21212121-2121-2121-2121-212121212123")),
            lastRequestContext: completedRequest.context.requestContext,
            updatedAtMs: 1_700_000_002_121,
        ))

        let processingPreviousMessage = AiChatMessage(role: .assistant, content: "Preserved previous context")
        let processingUserMessage = AiChatMessage(role: .user, content: "Current request")
        let processingTranscriptHistory = [processingPreviousMessage, processingUserMessage]
        let processingRequest = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("21212121-2121-2121-2121-212121212124")),
                runID: AiChatRunID(rawValue: makeUUID("21212121-2121-2121-2121-212121212125")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [processingUserMessage],
        )
        let processingLock = makeRequestLock(
            kind: .submit,
            request: processingRequest,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
            persistenceTranscriptHistory: processingTranscriptHistory,
        )
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [completedUserMessage],
            updatedAtMs: 1_700_000_002_000,
        )
        let staleSummary = AiChatSessionSummary(snapshot: staleSnapshot)

        let store = TestStore(initialState: AiChatFeature.State(
            sessionList: .init(allRows: [staleSummary], rows: [staleSummary]),
            sessionID: makeCBW005SessionID("22222222-2222-2222-2222-222222222222"),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .user, content: "Other session")],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            backgroundExecutionPhases: [
                completedLock.requestID: .completed(completedLock),
                processingLock.requestID: .processing(processingLock),
            ],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { requestedSessionID in
                    requestedSessionID == sessionID ? staleSnapshot : nil
                },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }

        await store.send(.routeToChatSession(sessionID)) { state in
            state.sessionList.selectedSessionID = sessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.restoreSessionID = sessionID
            state.sessionStatus = .restoring
            state.mode = .sessions
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: sessionID,
            .restored(snapshot: staleSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = sessionID
            state.sessionStatus = .active
            state.currentSessionCustomTitle = staleSnapshot.customTitle
            state.transcriptHistory = processingTranscriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = processingRequest.context.requestContext
            state.lastRequestContextModelHandle = processingRequest.context.model
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.transcriptAutoScrollVersion += 1
            state.executionPhase = .processing(processingLock)
            state.backgroundExecutionPhases[processingLock.requestID] = nil
            state.selectedModelHandle = processingRequest.context.model
            state.selectedThinking = processingLock.context.selectedThinking
            state.restoreOutcome = .restored(snapshot: staleSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.executionPhase, .processing(processingLock))
        XCTAssertEqual(store.state.transcriptHistory, processingTranscriptHistory)
        XCTAssertEqual(store.state.lastRequestContext, processingRequest.context.requestContext)
        XCTAssertEqual(store.state.backgroundExecutionPhases[completedLock.requestID], .completed(completedLock))
        await store.finish()
    }

    func testRouteToChatSessionPromotesFailedOwnerWithRequestTranscript() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("23232323-2323-2323-2323-232323232323")
        let selectedHandle = catalogRows[0].handle
        let failedUserMessage = AiChatMessage(role: .user, content: "Failed request prompt")
        let failedRequest = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("23232323-2323-2323-2323-232323232324")),
                runID: AiChatRunID(rawValue: makeUUID("23232323-2323-2323-2323-232323232325")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [failedUserMessage],
        )
        let failedLock = makeRequestLock(
            kind: .submit,
            request: failedRequest,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        .recordingTerminal(at: 1_700_000_002_323, failure: .unknown, wasCancelled: false)
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [],
            updatedAtMs: 1_700_000_002_000,
        )
        let staleSummary = AiChatSessionSummary(snapshot: staleSnapshot)

        let store = TestStore(initialState: AiChatFeature.State(
            sessionList: .init(allRows: [staleSummary], rows: [staleSummary]),
            sessionID: makeCBW005SessionID("24242424-2424-2424-2424-242424242424"),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .user, content: "Other session")],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            backgroundExecutionPhases: [failedLock.requestID: .failed(failedLock, .unknown)],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { requestedSessionID in
                    requestedSessionID == sessionID ? staleSnapshot : nil
                },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }

        await store.send(.routeToChatSession(sessionID)) { state in
            state.sessionList.selectedSessionID = sessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.restoreSessionID = sessionID
            state.sessionStatus = .restoring
            state.mode = .sessions
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: sessionID,
            .restored(snapshot: staleSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = sessionID
            state.sessionStatus = .active
            state.currentSessionCustomTitle = staleSnapshot.customTitle
            state.transcriptHistory = failedRequest.messages
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = failedRequest.context.requestContext
            state.lastRequestContextModelHandle = failedRequest.context.model
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.transcriptAutoScrollVersion += 1
            state.executionPhase = .failed(failedLock, .unknown)
            state.backgroundExecutionPhases[failedLock.requestID] = nil
            state.selectedModelHandle = failedRequest.context.model
            state.selectedThinking = failedLock.context.selectedThinking
            state.restoreOutcome = .restored(snapshot: staleSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.executionPhase, .failed(failedLock, .unknown))
        XCTAssertEqual(store.state.transcriptHistory, failedRequest.messages)
        XCTAssertEqual(store.state.lastRequestContext, failedRequest.context.requestContext)
        await store.finish()
    }

    func testRouteToChatSessionPromotesBackgroundExecutionPhaseToVisible() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("11111111-2222-3333-4444-555555555555")
        let requestID = AiChatRequestID(rawValue: makeUUID("11111111-2222-3333-4444-555555555556"))
        let runID = AiChatRunID(rawValue: makeUUID("11111111-2222-3333-4444-555555555557"))
        let requestContext = makeRequestContext(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            model: catalogRows[0].handle,
            selectedRow: catalogRows[0],
            selectedModel: makeProviderModels()[0],
            promptSummary: "Background request",
        )
        let request = AiChatRequest(
            context: requestContext,
            messages: [AiChatMessage(role: .user, content: "Background question")],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: catalogRows[0].handle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(
                allRows: [makeCBW005SessionSummary(sessionID: sessionID, title: "Background chat")],
                rows: [makeCBW005SessionSummary(sessionID: sessionID, title: "Background chat")],
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            transcriptHistory: [AiChatMessage(role: .user, content: "Background question")],
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[0].handle,
            executionPhase: .idle,
            backgroundExecutionPhases: [lock.requestID: .processing(lock)],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(makeFixedDate(milliseconds: fixedTimestampMs))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.routeToChatSession(sessionID)) { state in
            state.executionPhase = .processing(lock)
            state.backgroundExecutionPhases = [:]
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.mode = .chat
        }

        await store.send(.executionEvent(.delta(context: requestContext, text: "partial")))

        XCTAssertEqual(store.state.streamingAssistantDraft, "partial")
        XCTAssertEqual(store.state.backgroundExecutionPhases, [:])
        await store.finish()
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
                    return snapshot
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
                saveSession: { snapshot in snapshot },
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
                saveSession: { snapshot in snapshot },
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
                saveSession: { snapshot in snapshot },
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
                saveSession: { snapshot in snapshot },
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
                saveSession: { snapshot in snapshot },
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

    func testSetupParksPendingResolverForDifferentSessionBeforeSwitching() async {
        let catalogRows = makeCatalogRows()
        let currentSessionID = AiChatSessionID(rawValue: makeUUID("aaaaaaaa-7777-8888-9999-000000000001"))
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("bbbbbbbb-7777-8888-9999-000000000001"))
        let resolutionID = makeUUID("cccccccc-7777-8888-9999-000000000001")
        let userMessage = AiChatMessage(role: .user, content: "Pending setup question")
        let frozenThinking = AiThinkingSelection.effort(.minimal)
        let frozenTitle = "Frozen pending title"
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: currentSessionID,
            selectedModel: makeProviderModels()[0],
            selectedRow: catalogRows[0],
            selectedThinking: frozenThinking,
            customTitle: frozenTitle,
            preparedRequest: AiChatPreparedRequest(
                prompt: userMessage.content,
                messages: [userMessage],
                persistenceTranscriptHistory: nil,
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 200_000,
                    truncationReason: nil,
                ),
            ),
        )
        let setupState = AiChatSetupState(
            restoreSessionID: nil,
            sessionID: targetSessionID,
            sessionStatus: .idle,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: currentSessionID,
            currentSessionCustomTitle: frozenTitle,
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.high),
            pendingRequestStart: pendingRequest,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_002.800))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in AsyncStream { $0.finish() } }
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.setup(setupState)) { state in
            state.emptyDraftSessionID = nil
            state.currentSessionCustomTitle = nil
            state.pendingRequestStart = nil
            state.backgroundPendingRequestStarts[resolutionID] = pendingRequest
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionID = targetSessionID
            state.sessionStatus = .idle
            state.currentContext = setupState.currentContext
            state.lastRequestContext = nil
            state.lastRequestContextModelHandle = nil
            state.transcriptHistory = []
            state.draftText = ""
            state.streamingAssistantDraft = nil
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.catalogRows = catalogRows
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = catalogRows[0].handle
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(store.state.backgroundPendingRequestStarts[resolutionID], pendingRequest)

        await store.send(.requestContextResolved(resolutionID, AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.backgroundPendingRequestStarts[resolutionID])
        XCTAssertEqual(store.state.sessionID, targetSessionID)
        XCTAssertEqual(store.state.transcriptHistory, [])
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertEqual(store.state.backgroundExecutionPhases.count, 1)
        if case let .processing(lock) = store.state.backgroundExecutionPhases.values.first {
            XCTAssertEqual(lock.context.sessionID, currentSessionID)
            XCTAssertEqual(lock.request.messages, [
                AiChatMessage(role: .user, content: userMessage.content, createdAtMs: 1_700_000_002_800),
            ])
            XCTAssertEqual(lock.context.selectedThinking, frozenThinking)
            XCTAssertEqual(lock.customTitle, frozenTitle)
        } else {
            XCTFail("background pending resolver should start as a background processing owner")
        }
    }

    func testParkedPendingResolverStartsInBackgroundWhenForegroundIsBusy() async {
        let catalogRows = makeCatalogRows()
        let providerModels = makeProviderModels()
        let sessionID = AiChatSessionID(rawValue: makeUUID("aaaaaaa0-7777-8888-9999-000000000001"))
        let parkedResolutionID = makeUUID("bbbbbbb0-7777-8888-9999-000000000001")
        let currentResolutionID = makeUUID("ccccccc0-7777-8888-9999-000000000001")
        let parkedMessage = AiChatMessage(role: .user, content: "Parked question")
        let currentMessage = AiChatMessage(role: .user, content: "Current question")
        let parkedRequest = AiChatPendingRequestStart(
            resolutionID: parkedResolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: providerModels[0],
            selectedRow: catalogRows[0],
            selectedThinking: .effort(.minimal),
            customTitle: "Parked title",
            preparedRequest: AiChatPreparedRequest(
                prompt: parkedMessage.content,
                messages: [parkedMessage],
                persistenceTranscriptHistory: [parkedMessage],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 200_000,
                    truncationReason: nil,
                ),
            ),
        )
        let currentPendingRequest = AiChatPendingRequestStart(
            resolutionID: currentResolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: providerModels[0],
            selectedRow: catalogRows[0],
            preparedRequest: AiChatPreparedRequest(
                prompt: currentMessage.content,
                messages: [currentMessage],
                persistenceTranscriptHistory: [currentMessage],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 200_000,
                    truncationReason: nil,
                ),
            ),
        )

        let store: TestStore<AiChatFeature.State, AiChatAction> = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(providerModels),
            selectedModelHandle: catalogRows[0].handle,
            pendingRequestStart: currentPendingRequest,
            backgroundPendingRequestStarts: [parkedResolutionID: parkedRequest],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatExecutionClient = AiChatExecutionClient { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.aiChatContextPartResolverClient = .init { _ in
                AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: [])
            }
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { _, _ in [] },
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
            )
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_003.000))
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.requestContextResolved(parkedResolutionID, AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.pendingRequestStart, currentPendingRequest)
        XCTAssertNil(store.state.backgroundPendingRequestStarts[parkedResolutionID])
        XCTAssertEqual(store.state.transcriptHistory, [])
        XCTAssertEqual(store.state.backgroundExecutionPhases.count, 1)
        if case let .processing(lock) = store.state.backgroundExecutionPhases.values.first {
            XCTAssertEqual(lock.context.sessionID, sessionID)
            XCTAssertEqual(lock.request.messages, [
                AiChatMessage(role: .user, content: parkedMessage.content, createdAtMs: 1_700_000_003_000),
            ])
            XCTAssertEqual(lock.context.selectedThinking, AiThinkingSelection.effort(.minimal))
            XCTAssertEqual(lock.customTitle, "Parked title")
        } else {
            XCTFail("parked resolver should start as a background owner while foreground is busy")
        }
    }

    func testSameSessionParkedPendingRequestBlocksSubmit() {
        let catalogRows = makeCatalogRows()
        let providerModels = makeProviderModels()
        let sessionID = AiChatSessionID(rawValue: makeUUID("ddddddd0-7777-8888-9999-000000000001"))
        let resolutionID = makeUUID("eeeeeee0-7777-8888-9999-000000000001")
        let message = AiChatMessage(role: .user, content: "parked")
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: providerModels[0],
            selectedRow: catalogRows[0],
            preparedRequest: AiChatPreparedRequest(
                prompt: message.content,
                messages: [message],
                persistenceTranscriptHistory: [message],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 200_000,
                    truncationReason: nil,
                ),
            ),
        )
        let state = AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            draftText: "second request",
            catalogRows: catalogRows,
            modelListState: .loaded(providerModels),
            selectedModelHandle: catalogRows[0].handle,
            backgroundPendingRequestStarts: [resolutionID: pendingRequest],
        )

        XCTAssertFalse(state.canSubmit)
        XCTAssertFalse(state.chatInputDisplayModel.canSubmit)
    }

    /// CBW-005-continue_chat_conversation_session: A→B→A 복귀 시 parked pending을 다시 잠금·Stop owner로 표시한다.
    /// resolver 완료 전에 원 session으로 돌아오면 background slot의 pending도 현재 composer lifecycle로 취급되는지 검증합니다.
    /// - 검증 내용: pending park, 복귀 후 composer 잠금/Stop, cancel ownership, 원 prompt 보존을 확인합니다.
    /// - 사전 조건: session A submit이 pending인 동안 B로 이동한 뒤 같은 A setup으로 복귀합니다.
    /// - 기대 결과: A composer는 잠기고 Stop이 활성화되며 cancel은 parked resolution만 제거하고 draft를 보존합니다.
    func testReturningToSessionWithParkedPendingRestoresStopAndCancelOwnership() async {
        let catalogRows = makeCatalogRows()
        let models = makeProviderModels()
        let sessionA = AiChatSessionID(rawValue: makeUUID("12121212-7777-8888-9999-000000000635"))
        let sessionB = AiChatSessionID(rawValue: makeUUID("13131313-7777-8888-9999-000000000635"))
        let resolutionID = makeUUID("14141414-7777-8888-9999-000000000635")
        let originalPrompt = "Original parked prompt"
        let pending = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: sessionA,
            selectedModel: models[0],
            selectedRow: catalogRows[0],
            selectedThinking: .effort(.medium),
            preparedRequest: AiChatPreparedRequest(
                prompt: originalPrompt,
                messages: [AiChatMessage(role: .user, content: originalPrompt)],
                persistenceTranscriptHistory: [AiChatMessage(role: .user, content: originalPrompt)],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 200_000,
                    truncationReason: nil,
                ),
            ),
        )
        let setupB = AiChatSetupState(
            restoreSessionID: nil,
            sessionID: sessionB,
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )
        let setupA = AiChatSetupState(
            restoreSessionID: nil,
            sessionID: sessionA,
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: originalPrompt,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionA,
            sessionStatus: .active,
            draftText: originalPrompt,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.medium),
            pendingRequestStart: pending,
        )) {
            AiChatFeature()
        }
        // store.exhaustivity = .off: session 전환 뒤 parked pending presentation과 cancel 결과만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.setup(setupB))
        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(store.state.backgroundPendingRequestStarts[resolutionID], pending)

        await store.send(.setup(setupA))
        XCTAssertEqual(store.state.sessionID, sessionA)
        XCTAssertEqual(store.state.backgroundPendingRequestStarts[resolutionID], pending)
        XCTAssertEqual(store.state.draftText, originalPrompt)
        XCTAssertTrue(store.state.chatInputDisplayModel.isComposerEditingDisabled)
        XCTAssertFalse(store.state.chatInputDisplayModel.isSubmitVisible)
        XCTAssertTrue(store.state.chatInputDisplayModel.isStopVisible)
        XCTAssertTrue(store.state.chatInputDisplayModel.canStop)

        await store.send(.cancelTapped)
        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertNil(store.state.backgroundPendingRequestStarts[resolutionID])
        XCTAssertEqual(store.state.draftText, originalPrompt)
        XCTAssertFalse(store.state.chatInputDisplayModel.isStopVisible)
    }

    /// CBW-005-continue_chat_conversation_session: A attachment completion은 전환된 B resolver 입력에 포함되지 않는다.
    /// session 전환 뒤 늦게 도착한 local attachment가 B의 다음 provider request source로 누출되지 않는지 검증합니다.
    /// - 검증 내용: A picker 시작, B setup, stale result, B request resolver input attachment 목록을 확인합니다.
    /// - 사전 조건: A에서 picker를 연 뒤 B로 전환하고 A file result가 늦게 도착합니다.
    /// - 기대 결과: B draft/context는 유지되고 B pending resolver input에는 attachment가 없습니다.
    func testPreviousSessionAttachmentResultDoesNotEnterCurrentRequestPayload() async throws {
        let catalogRows = makeCatalogRows()
        let models = makeProviderModels()
        let sessionA = AiChatSessionID(rawValue: makeUUID("17171717-7777-8888-9999-000000000635"))
        let sessionB = AiChatSessionID(rawValue: makeUUID("18181818-7777-8888-9999-000000000635"))
        let setupB = AiChatSetupState(
            restoreSessionID: nil,
            sessionID: sessionB,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "B request context"),
            transcriptHistory: [],
            draftText: "B prompt",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionA,
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_006_355))
        }
        // store.exhaustivity = .off: A/B owner 전환과 resolver input만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.attachmentPickerTapped)
        await store.receive(.delegate(.requestAttachmentPicker(sessionA)))
        await store.send(.setup(setupB))
        await store.send(.attachmentPickerSelection(sessionA, [URL(fileURLWithPath: "/tmp/A-only.txt")]))
        await store.send(.submitTapped)

        let pending = try XCTUnwrap(store.state.pendingRequestStart)
        let resolverInput = AiChatFeature().makeRequestContextResolverInput(for: pending, state: store.state)
        XCTAssertEqual(pending.sessionID, sessionB)
        XCTAssertEqual(pending.preparedRequest.prompt, "B prompt")
        XCTAssertEqual(resolverInput.currentContext.summary, "B request context")
        XCTAssertTrue(resolverInput.attachments.isEmpty)
        XCTAssertTrue(store.state.addedAttachments.isEmpty)
    }

    /// CBW-005-continue_chat_conversation_session: 빈 rows의 다른 session lock은 현재 composer를 잠그지 않는다.
    /// foreground phase가 stale하더라도 현재 보이는 session identity와 다르면 독립 session 입력을 계속 허용하는지 검증합니다.
    /// - 검증 내용: empty rows와 mismatched non-nil lock에서 submit 가능 여부와 processing affordance를 확인합니다.
    /// - 사전 조건: 현재 session에는 valid model과 non-empty draft가 있고 다른 session lock이 foreground phase에 남아 있습니다.
    /// - 기대 결과: 현재 submit은 활성화되고 stop 및 streaming processing projection은 표시되지 않습니다.
    func testForegroundProcessingDifferentSessionDoesNotBlockSubmitWhenRowsAreEmpty() {
        let catalogRows = makeCatalogRows()
        let providerModels = makeProviderModels()
        let processingSessionID = AiChatSessionID(rawValue: makeUUID("33333330-7777-8888-9999-000000000001"))
        let visibleSessionID = AiChatSessionID(rawValue: makeUUID("44444440-7777-8888-9999-000000000001"))
        let message = AiChatMessage(role: .user, content: "foreground processing")
        let requestID = AiChatRequestID(rawValue: makeUUID("55555550-7777-8888-9999-000000000001"))
        let runID = AiChatRunID(rawValue: makeUUID("66666660-7777-8888-9999-000000000001"))
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: processingSessionID,
                requestID: requestID,
                runID: runID,
                model: providerModels[0].id,
                selectedRow: catalogRows[0],
            ),
            messages: [message],
        )
        let lock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: request.context,
            request: request,
            selectedModelHandle: providerModels[0].id,
            selectedModelRow: catalogRows[0],
            assistantReplacementIndex: nil,
            persistenceTranscriptHistory: [message],
            historyTruncation: .init(
                includedMessageCount: 1,
                excludedMessageCount: 0,
                budget: 200_000,
                truncationReason: nil,
            ),
        )
        let state = AiChatFeature.State(
            mode: .chat,
            sessionList: .init(rows: [], selectedSessionID: visibleSessionID),
            sessionID: visibleSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            draftText: "new visible request",
            catalogRows: catalogRows,
            modelListState: .loaded(providerModels),
            selectedModelHandle: catalogRows[0].handle,
            executionPhase: .processing(lock),
        )

        XCTAssertTrue(state.sessionList.rows.isEmpty)
        XCTAssertTrue(state.canSubmit)
        XCTAssertTrue(state.chatInputDisplayModel.canSubmit)
        XCTAssertTrue(state.chatInputDisplayModel.isSubmitVisible)
        XCTAssertFalse(state.chatInputDisplayModel.isStopVisible)
        XCTAssertNil(state.streamingAssistantDisplayModel)
        XCTAssertEqual(
            AiChatViewPresentation.resolve(state: state, hasCenteredEmptyContent: true),
            .centeredEmpty,
        )
    }

    func testSameSessionBackgroundProcessingRequestBlocksSubmit() {
        let catalogRows = makeCatalogRows()
        let providerModels = makeProviderModels()
        let sessionID = AiChatSessionID(rawValue: makeUUID("fffffff0-7777-8888-9999-000000000001"))
        let message = AiChatMessage(role: .user, content: "background")
        let requestID = AiChatRequestID(rawValue: makeUUID("11111110-7777-8888-9999-000000000001"))
        let runID = AiChatRunID(rawValue: makeUUID("22222220-7777-8888-9999-000000000001"))
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: requestID,
                runID: runID,
                model: providerModels[0].id,
                selectedRow: catalogRows[0],
            ),
            messages: [message],
        )
        let lock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: request.context,
            request: request,
            selectedModelHandle: providerModels[0].id,
            selectedModelRow: catalogRows[0],
            assistantReplacementIndex: nil,
            persistenceTranscriptHistory: [message],
            historyTruncation: .init(
                includedMessageCount: 1,
                excludedMessageCount: 0,
                budget: 200_000,
                truncationReason: nil,
            ),
        )
        let state = AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            draftText: "second request",
            catalogRows: catalogRows,
            modelListState: .loaded(providerModels),
            selectedModelHandle: catalogRows[0].handle,
            backgroundExecutionPhases: [requestID: .processing(lock)],
        )

        XCTAssertFalse(state.canSubmit)
        XCTAssertFalse(state.chatInputDisplayModel.canSubmit)
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
                saveSession: { snapshot in snapshot },
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
                saveSession: { snapshot in snapshot },
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
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                },
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
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                },
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
                saveSession: { snapshot in snapshot },
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
                saveSession: { snapshot in snapshot },
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

    func testBackgroundRequestStartSnapshotUpdatedRefreshesSessionRow() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("aaaaaaaa-2222-3333-4444-555555555555"))
        let visibleSessionID = AiChatSessionID(rawValue: makeUUID("bbbbbbbb-2222-3333-4444-555555555555"))
        let requestID = AiChatRequestID(rawValue: makeUUID("cccccccc-2222-3333-4444-555555555555"))
        let runID = AiChatRunID(rawValue: makeUUID("dddddddd-2222-3333-4444-555555555555"))
        let catalogRows = makeCatalogRows()
        let request = makeDeleteTestRequest(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            selectedRow: catalogRows[0],
            prompt: "Background row refresh",
        )
        let lock = makeDeleteTestLock(request: request, selectedRow: catalogRows[0])
        let summary = makeDeleteTestSessionSummary(
            sessionID: sessionID,
            title: "Background row refresh",
            updatedAtMs: 1_700_000_010_000,
            status: .active,
        )
        let visibleSummary = makeDeleteTestSessionSummary(
            sessionID: visibleSessionID,
            title: "Visible session",
            updatedAtMs: 1_700_000_000_000,
            status: .idle,
        )

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionList: .init(allRows: [visibleSummary], selectedSessionID: visibleSessionID),
            sessionID: visibleSessionID,
            sessionStatus: .idle,
            executionPhase: .idle,
            backgroundExecutionPhases: [requestID: .processing(lock)],
        )) {
            AiChatFeature()
        }

        await store.send(AiChatAction.sessionSnapshotUpdated(summary, requestID: requestID, runID: runID)) { state in
            state.sessionList.allRows = [summary, visibleSummary]
            state.sessionList.rows = [summary, visibleSummary]
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.sessionList.selectedSessionID, visibleSessionID)
        XCTAssertEqual(store.state.backgroundExecutionPhases[requestID], AiChatExecutionPhase.processing(lock))
    }

    /// CBW-005-delete_chat_conversation_session: 삭제된 processing session으로부터 늦게 도착한 snapshot callback은 row를 되살리지 않는다.
    /// 삭제된 processing session으로부터 늦게 도착한 snapshot callback은 row를 되살리지 않는다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: late snapshot ignore after deletion, deletedSessionIDs guard, row non-reinsertion
    /// - 사전 조건: processing session 삭제 후 sessionSnapshotUpdated/sessionSnapshotSaved가 늦게 도착한다.
    /// - 기대 결과: 삭제된 session row는 다시 목록에 삽입되지 않는다.
    func testDeletedSessionSnapshotSavedCleansMatchingOwnersWithoutReinsertingRow() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("89898989-8989-8989-8989-898989898989")
        let lock = makeCBW005RequestLock(sessionID: sessionID, modelRow: catalogRows[0])
        let snapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .completed,
            customTitle: "Deleted session",
            provider: catalogRows[0].handle.provider,
            model: catalogRows[0].handle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Deleted")],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            updatedAtMs: 1_700_000_000_500,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)
        let completedLock = lock.recordingFinalSnapshot(snapshot)
        var state = AiChatFeature.State()
        state.executionPhase = .completed(completedLock)
        state.backgroundExecutionPhases[lock.requestID] = .completed(completedLock)
        state.sessionList.deletedSessionIDs = [sessionID]
        let store = TestStore(initialState: state) {
            AiChatFeature()
        }

        await store.send(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: lock.requestID,
            runID: lock.runID,
        )) { state in
            state.backgroundExecutionPhases[lock.requestID] = nil
            state.executionPhase = .completed(completedLock.clearingFinalSnapshot())
        }

        XCTAssertTrue(store.state.sessionList.allRows.isEmpty)
        XCTAssertTrue(store.state.sessionList.deletedSessionIDs.contains(sessionID))
        XCTAssertNil(store.state.backgroundExecutionPhases[lock.requestID])
        XCTAssertNil(store.state.executionPhase.lock?.finalSnapshot)
    }

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
                saveSession: { snapshot in snapshot },
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

    func testDeleteSessionCancelsPendingRequestContextResolutionBeforeDelete() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("aaaaaaaa-1111-2222-3333-444444444444"))
        let resolutionID = makeUUID("bbbbbbbb-1111-2222-3333-444444444444")
        let requestID = AiChatRequestID(rawValue: makeUUID("cccccccc-1111-2222-3333-444444444444"))
        let runID = AiChatRunID(rawValue: makeUUID("dddddddd-1111-2222-3333-444444444444"))
        let prompt = "Pending resolver delete"
        let row = makeDeleteTestSessionSummary(sessionID: sessionID, title: prompt)
        let catalogRows = makeCatalogRows()
        let providerModels = makeProviderModels()
        let request = makeDeleteTestRequest(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            selectedRow: catalogRows[0],
            prompt: prompt,
        )
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: providerModels[0],
            selectedRow: catalogRows[0],
            preparedRequest: AiChatPreparedRequest(
                prompt: prompt,
                messages: request.messages,
                persistenceTranscriptHistory: nil,
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: request.messages.count,
                    excludedMessageCount: 0,
                    budget: 200_000,
                    truncationReason: nil,
                ),
            ),
        )
        let deletedIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [row], selectedSessionID: sessionID),
            sessionID: sessionID,
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(providerModels),
            pendingRequestStart: pendingRequest,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in snapshot },
                deleteSession: { id in deletedIDs.withValue { $0.append(id) } },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.deleteSessionTapped(sessionID)) { state in
            state.pendingRequestStart = nil
        }
        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.selectedSessionID = nil
            state.sessionList.deletedSessionIDs = [sessionID]
        }
        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))
        await store.finish()

        XCTAssertEqual(deletedIDs.value, [sessionID])
        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(store.state.executionPhase, .idle)
    }

    func testDeleteInactiveBackgroundSessionCancelsRequestBeforeDelete() async {
        let activeSessionID = AiChatSessionID(rawValue: makeUUID("aaaaaaaa-5555-6666-7777-888888888888"))
        let deletedSessionID = AiChatSessionID(rawValue: makeUUID("bbbbbbbb-5555-6666-7777-888888888888"))
        let requestID = AiChatRequestID(rawValue: makeUUID("cccccccc-5555-6666-7777-888888888888"))
        let runID = AiChatRunID(rawValue: makeUUID("dddddddd-5555-6666-7777-888888888888"))
        let prompt = "Inactive background delete"
        let catalogRows = makeCatalogRows()
        let request = makeDeleteTestRequest(
            sessionID: deletedSessionID,
            requestID: requestID,
            runID: runID,
            selectedRow: catalogRows[0],
            prompt: prompt,
        )
        let lock = makeDeleteTestLock(request: request, selectedRow: catalogRows[0])
        let deletedRow = makeDeleteTestSessionSummary(sessionID: deletedSessionID, title: prompt)
        let activeRow = makeDeleteTestSessionSummary(sessionID: activeSessionID, title: "Active chat")
        let deletedIDs = LockIsolated<[AiChatSessionID]>([])
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [deletedRow, activeRow], selectedSessionID: deletedSessionID),
            sessionID: activeSessionID,
            sessionStatus: .active,
            backgroundExecutionPhases: [lock.requestID: .processing(lock)],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                },
                deleteSession: { id in deletedIDs.withValue { $0.append(id) } },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.deleteSessionTapped(deletedSessionID)) { state in
            state.backgroundExecutionPhases = [:]
        }
        await store.receive(.sessionDeleteSucceeded(deletedSessionID)) { state in
            state.sessionList.allRows = [activeRow]
            state.sessionList.rows = [activeRow]
            state.sessionList.selectedSessionID = nil
            state.sessionList.deletedSessionIDs = [deletedSessionID]
        }
        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Late final"),
            completedAtMs: 1_700_000_000_000,
        ))))
        await store.finish()

        XCTAssertEqual(deletedIDs.value, [deletedSessionID])
        XCTAssertEqual(store.state.backgroundExecutionPhases, [:])
        XCTAssertTrue(savedSnapshots.value.isEmpty)
        XCTAssertFalse(store.state.sessionList.allRows.contains { $0.sessionID == deletedSessionID })
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
                    return snapshot
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
                    return snapshot
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
        XCTAssertEqual(displayModel.title, "Chat History")
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
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello while browsing history", createdAtMs: fixedMs),
            ]
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

        let userMessage = AiChatMessage(
            role: .user, content: "Hello while browsing history", createdAtMs: fixedMs,
        )
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
            snapshot: expectedStartSnapshot,
            requestID: lock.requestID,
            runID: lock.runID,
        )) { state in
            state.sessionList.allRows = [expectedStartSummary]
            state.sessionList.rows = [expectedStartSummary]
            state.sessionList.selectedSessionID = sessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.sessionList.errorMessage = nil
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
        }
        await store.send(.sessionsAppeared) { state in
            state.sessionList.isLoading = true
            state.sessionList.errorMessage = nil
        }
        await store.receive(.sessionListLoaded([expectedStartSummary])) { state in
            state.sessionList.allRows = [expectedStartSummary]
            state.sessionList.rows = [expectedStartSummary]
            state.sessionList.isLoading = false
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        await store.send(.sessionRowTapped(sessionID)) { state in
            state.mode = .chat
        }
        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
        }

        let assistantMessage = AiChatMessage(
            role: .assistant, content: "Still completed", createdAtMs: fixedMs,
        )
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
        await store.receive(.sessionSnapshotSaved(
            expectedFinalSummary,
            snapshot: expectedFinalSnapshot,
            requestID: finalizedLock.requestID,
            runID: finalizedLock.runID,
        )) { state in
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
    func testSessionSummaryMergeResultSeparatesRowAcceptanceFromPayloadPermission() {
        let sessionID = makeCBW005SessionID("12121212-1212-1212-1212-121212121212")
        let otherSessionID = makeCBW005SessionID("13131313-1313-1313-1313-131313131313")
        let current = makeSessionSummary(sessionID: sessionID, title: "Current", updatedAtMs: 100)
        let conflicting = makeSessionSummary(sessionID: sessionID, title: "Conflicting", updatedAtMs: 100)
        let newer = makeSessionSummary(sessionID: sessionID, title: "Newer", updatedAtMs: 200)
        let older = makeSessionSummary(sessionID: sessionID, title: "Older", updatedAtMs: 50)
        let inserted = makeSessionSummary(sessionID: otherSessionID, title: "Inserted", updatedAtMs: 100)
        var sessionList = AiChatSessionListState(allRows: [current])

        let unchangedResult = sessionList.replaceRowIfNewer(current)
        XCTAssertEqual(unchangedResult, .unchanged)
        XCTAssertTrue(unchangedResult.acceptsRow)
        XCTAssertFalse(unchangedResult.permitsSnapshotPayload)

        XCTAssertEqual(sessionList.replaceRowIfNewer(conflicting), .rejected)
        XCTAssertEqual(sessionList.replaceRowIfNewer(newer), .merged)
        XCTAssertEqual(sessionList.replaceRowIfNewer(older), .rejected)
        XCTAssertEqual(sessionList.replaceRowIfNewer(inserted), .merged)

        sessionList.removeRow(sessionID: otherSessionID)
        XCTAssertEqual(sessionList.replaceRowIfNewer(inserted), .rejected)
    }

    func testEqualSummaryMatchingCompletedOwnerAppliesStatusTitleAndTransientCleanup() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("14141414-1414-1414-1414-141414141414")
        let lock = makeCBW005RequestLock(sessionID: sessionID, modelRow: catalogRows[0])
        let expectedTranscript = [
            AiChatMessage(role: .user, content: "Question"),
            AiChatMessage(role: .assistant, content: "Answer"),
        ]
        let snapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Saved title",
            provider: catalogRows[0].handle.provider,
            model: catalogRows[0].handle,
            selectedModelRow: catalogRows[0],
            selectedThinking: .effort(.low),
            transcriptHistory: expectedTranscript,
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: 1_234_567_890_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)
        let completedLock = lock.recordingFinalSnapshot(snapshot)
        var state = AiChatFeature.State()
        state.sessionID = sessionID
        state.mode = .chat
        state.sessionStatus = .failed
        state.currentSessionCustomTitle = "Stale title"
        state.transcriptHistory = expectedTranscript
        state.streamingAssistantDraft = "Stale draft"
        state.catalogRows = catalogRows
        state.lockedModelHandle = catalogRows[0].handle
        state.lastRequestContext = snapshot.lastRequestContext
        state.lastRequestContextModelHandle = catalogRows[0].handle
        state.selectedModelHandle = catalogRows[0].handle
        state.selectedThinking = .effort(.low)
        state.executionPhase = .completed(completedLock)
        state.sessionList = AiChatSessionListState(allRows: [summary])
        let store = TestStore(initialState: state) {
            AiChatFeature()
        }
        store.exhaustivity = .off

        await store.send(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: lock.requestID,
            runID: lock.runID,
        ))
        await store.finish()

        XCTAssertEqual(store.state.transcriptHistory, expectedTranscript)
        XCTAssertEqual(store.state.selectedThinking, .effort(.low))
        XCTAssertEqual(store.state.sessionStatus, .active)
        XCTAssertEqual(store.state.currentSessionCustomTitle, "Saved title")
        XCTAssertNil(store.state.streamingAssistantDraft)
        XCTAssertNil(store.state.lockedModelHandle)
        XCTAssertEqual(store.state.executionPhase, .completed(completedLock.clearingFinalSnapshot()))
        XCTAssertEqual(store.state.sessionList.allRows, [summary])
    }

    func testNewerSummaryAppliesStatusTitleAndTransientCleanupWithoutOwner() async {
        let catalogRows = makeCatalogRows()
        let sessionID = makeCBW005SessionID("15151515-1515-1515-1515-151515151515")
        let transcript = [
            AiChatMessage(role: .user, content: "Question"),
            AiChatMessage(role: .assistant, content: "Answer"),
        ]
        let snapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .completed,
            customTitle: "Newer title",
            provider: catalogRows[0].handle.provider,
            model: catalogRows[0].handle,
            selectedModelRow: catalogRows[0],
            selectedThinking: .effort(.low),
            transcriptHistory: transcript,
            updatedAtMs: 2000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)
        let olderSummary = AiChatSessionSummary(
            sessionID: summary.sessionID,
            title: summary.title,
            preview: summary.preview,
            messageCount: summary.messageCount,
            contextTitle: summary.contextTitle,
            searchText: summary.searchText,
            provider: summary.provider,
            model: summary.model,
            createdAtMs: 1000,
            updatedAtMs: 1000,
            status: .active,
        )
        var state = AiChatFeature.State()
        state.sessionID = sessionID
        state.mode = .chat
        state.sessionStatus = .failed
        state.currentSessionCustomTitle = "Stale title"
        state.transcriptHistory = transcript
        state.streamingAssistantDraft = "Stale draft"
        state.catalogRows = catalogRows
        state.lockedModelHandle = catalogRows[0].handle
        state.selectedModelHandle = catalogRows[0].handle
        state.selectedThinking = .effort(.low)
        state.sessionList = AiChatSessionListState(allRows: [olderSummary])
        let store = TestStore(initialState: state) {
            AiChatFeature()
        }
        store.exhaustivity = .off

        await store.send(.sessionSnapshotSaved(summary, snapshot: snapshot))
        await store.finish()

        XCTAssertEqual(store.state.sessionStatus, .completed)
        XCTAssertEqual(store.state.currentSessionCustomTitle, "Newer title")
        XCTAssertNil(store.state.streamingAssistantDraft)
        XCTAssertNil(store.state.lockedModelHandle)
        XCTAssertEqual(store.state.sessionList.allRows, [summary])
    }

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

    private var aiChatSessionsViewSourceURL: URL {
        var packageRoot = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 {
            packageRoot.deleteLastPathComponent()
        }
        return packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("VoyagerFeaturesAiChat")
            .appendingPathComponent("Ui")
            .appendingPathComponent("AiChatSessionsView.swift")
    }

    private func sourceSection(in source: String, from start: String, to end: String) throws -> String {
        let startIndex = try XCTUnwrap(source.range(of: start)?.lowerBound)
        let endIndex = try XCTUnwrap(source.range(of: end, range: startIndex ..< source.endIndex)?.lowerBound)
        return String(source[startIndex ..< endIndex])
    }

    private func firstSubview<View: NSView>(of _: View.Type, in root: NSView) -> View? {
        if let root = root as? View {
            return root
        }
        for subview in root.subviews {
            if let match = firstSubview(of: View.self, in: subview) {
                return match
            }
        }
        return nil
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
        sessionStatus: .restoring,
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

private extension NSView {
    func cbw005Descendant<ViewType: NSView>(ofType type: ViewType.Type) -> ViewType? {
        if let matched = self as? ViewType {
            return matched
        }
        for subview in subviews {
            if let matched = subview.cbw005Descendant(ofType: type) {
                return matched
            }
        }
        return nil
    }
}

private func drainCBW005MainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}
